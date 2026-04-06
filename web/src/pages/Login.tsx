import { useState } from 'react';
import { useNavigate, Link } from 'react-router-dom';
import { useTranslation } from 'react-i18next';
import { useAuthStore } from '../store/auth';
import { api, ApiError } from '../api/client';
import {
  deriveAuthHash, derivePEK, setPEK,
  importPrivateKeyEncrypted, setIdentityPrivateKey,
  generateIdentityKeyPair, exportPublicKey, exportPrivateKeyEncrypted,
} from '../crypto';

interface LoginResponse {
  expires_at?: number;
  user_id: string;
  role?: string;
  requires_totp?: boolean;
  pek_salt?: string;
  challenge_token?: string;
  identity_privkey_enc?: string;
  signing_privkey_enc?: string;
}

export function Login() {
  const { t } = useTranslation();
  const navigate = useNavigate();
  const { login } = useAuthStore();

  const [email, setEmail] = useState('');
  const [passphrase, setPassphrase] = useState('');
  const [totpCode, setTotpCode] = useState('');
  const [needs2FA, setNeeds2FA] = useState(false);
  const [userId, setUserId] = useState('');
  const [challengeToken, setChallengeToken] = useState('');
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);

  const handleLogin = async (e: React.FormEvent) => {
    e.preventDefault();
    setError('');
    setLoading(true);

    try {
      // Step 1: Get salts for this user (embedded in login response)
      // For the initial login, we derive auth_hash client-side
      // In production, we'd first fetch salts, then derive
      const authHash = await deriveAuthHash(passphrase, email);

      const res = await api.post<LoginResponse>('/api/v1/auth/login', {
        email,
        auth_hash: authHash,
      });

      if (res.requires_totp) {
        setNeeds2FA(true);
        setUserId(res.user_id);
        setChallengeToken(res.challenge_token || '');
        // Store pek_salt for after 2FA verification
        if (res.pek_salt) localStorage.setItem('_pek_salt_tmp', res.pek_salt);
        setLoading(false);
        return;
      }

      if (res.pek_salt) {
        const pekKey = await derivePEK(passphrase, res.pek_salt);
        setPEK(pekKey);
        // Unwrap the identity ECDH private key. If decryption fails (legacy
        // users whose stored PEK salt doesn't match the one used to encrypt
        // the key), regenerate the keypair and update the server.
        if (res.identity_privkey_enc) {
          try {
            const idPriv = await importPrivateKeyEncrypted(res.identity_privkey_enc, pekKey);
            setIdentityPrivateKey(idPriv);
          } catch {
            console.warn('Identity key decrypt failed — regenerating keypair');
            try {
              const kp = await generateIdentityKeyPair();
              const pub = await exportPublicKey(kp.publicKey);
              const privEnc = await exportPrivateKeyEncrypted(kp.privateKey, pekKey);
              await api.patch('/api/v1/users/me/keys', {
                identity_pubkey: pub,
                identity_privkey_enc: privEnc,
              });
              setIdentityPrivateKey(kp.privateKey);
            } catch (regenErr) {
              console.warn('Identity key regen failed:', regenErr);
            }
          }
        }
      }
      login(res.user_id, res.role || 'user', email);
      navigate('/');
    } catch (err) {
      if (err instanceof ApiError) {
        setError(err.code === 'invalid_credentials' ? t('auth.invalid_credentials') : err.code);
      } else {
        setError(t('auth.connection_error'));
      }
    } finally {
      setLoading(false);
    }
  };

  const handle2FA = async (e: React.FormEvent) => {
    e.preventDefault();
    setError('');
    setLoading(true);

    try {
      const res = await api.post<LoginResponse>('/api/v1/auth/login/2fa', {
        user_id: userId,
        code: totpCode,
        challenge_token: challengeToken,
      });

      // Derive PEK with passphrase still in memory
      const pekSalt = localStorage.getItem('_pek_salt_tmp') || res.pek_salt;
      if (pekSalt && passphrase) {
        const pekKey = await derivePEK(passphrase, pekSalt);
        setPEK(pekKey);
        if (res.identity_privkey_enc) {
          try {
            const idPriv = await importPrivateKeyEncrypted(res.identity_privkey_enc, pekKey);
            setIdentityPrivateKey(idPriv);
          } catch {
            console.warn('Identity key decrypt failed (2FA) — regenerating');
            try {
              const kp = await generateIdentityKeyPair();
              const pub = await exportPublicKey(kp.publicKey);
              const privEnc = await exportPrivateKeyEncrypted(kp.privateKey, pekKey);
              await api.patch('/api/v1/users/me/keys', {
                identity_pubkey: pub,
                identity_privkey_enc: privEnc,
              });
              setIdentityPrivateKey(kp.privateKey);
            } catch (regenErr) {
              console.warn('Identity key regen failed:', regenErr);
            }
          }
        }
      }
      localStorage.removeItem('_pek_salt_tmp');
      login(res.user_id, res.role || 'user', email);
      navigate('/');
    } catch (err) {
      if (err instanceof ApiError) {
        setError(err.code === 'invalid_totp_code' ? t('auth.invalid_totp') : err.code);
      }
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="auth-page">
      <div className="auth-card">
        <h1>{t('app.name')}</h1>
        <p className="auth-tagline">{t('app.tagline')}</p>

        {error && <div className="alert alert-error">{error}</div>}

        {!needs2FA ? (
          <form onSubmit={handleLogin}>
            <div className="form-group">
              <label htmlFor="email">{t('auth.email')}</label>
              <input
                id="email"
                type="email"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                required
                autoComplete="email"
              />
            </div>
            <div className="form-group">
              <label htmlFor="passphrase">{t('auth.passphrase')}</label>
              <input
                id="passphrase"
                type="password"
                value={passphrase}
                onChange={(e) => setPassphrase(e.target.value)}
                required
                autoComplete="current-password"
              />
            </div>
            <button type="submit" className="btn btn-primary" disabled={loading}>
              {loading ? t('common.loading') : t('auth.login')}
            </button>
          </form>
        ) : (
          <form onSubmit={handle2FA}>
            <div className="form-group">
              <label htmlFor="totp">{t('auth.totp_code')}</label>
              <input
                id="totp"
                type="text"
                inputMode="numeric"
                pattern="[0-9]{6}"
                maxLength={6}
                value={totpCode}
                onChange={(e) => setTotpCode(e.target.value)}
                required
                autoComplete="one-time-code"
              />
            </div>
            <button type="submit" className="btn btn-primary" disabled={loading}>
              {loading ? t('common.loading') : t('auth.submit')}
            </button>
          </form>
        )}
        <p className="auth-tagline" style={{ marginTop: 16, marginBottom: 0 }}>
          {t('auth.no_account')} <Link to="/register" className="card-link">{t('auth.register')}</Link>
        </p>
        <p className="auth-tagline" style={{ marginTop: 8, marginBottom: 0 }}>
          <Link to="/recovery" className="card-link">{t('auth.forgot_passphrase')}</Link>
        </p>
      </div>
    </div>
  );
}
