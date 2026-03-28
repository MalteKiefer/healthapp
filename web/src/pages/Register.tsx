import { useState } from 'react';
import { useNavigate, Link } from 'react-router-dom';
import { useTranslation } from 'react-i18next';
import { api, ApiError } from '../api/client';
import {
  deriveAuthHash,
  derivePEK,
  setPEK,
  generateIdentityKeyPair,
  exportPublicKey,
  exportPrivateKeyEncrypted,
  generateRecoveryCodes,
  bytesToBase64,
} from '../crypto';
import { useAuthStore } from '../store/auth';

interface RegisterInitResponse {
  pek_salt: string;
  auth_salt: string;
}

interface RegisterCompleteResponse {
  id: string;
  email: string;
}

interface LoginResponse {
  access_token: string;
  refresh_token: string;
  expires_at: number;
  user_id: string;
  pek_salt?: string;
}

export function Register() {
  const { t } = useTranslation();
  const navigate = useNavigate();
  const { login } = useAuthStore();

  const [step, setStep] = useState<'form' | 'recovery'>('form');
  const [email, setEmail] = useState('');
  const [displayName, setDisplayName] = useState('');
  const [passphrase, setPassphrase] = useState('');
  const [passphraseConfirm, setPassphraseConfirm] = useState('');
  const [recoveryCodes, setRecoveryCodes] = useState<string[]>([]);
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);
  const [copiedCodes, setCopiedCodes] = useState(false);

  // Stored between steps
  const [registeredEmail, setRegisteredEmail] = useState('');
  const [registeredAuthHash, setRegisteredAuthHash] = useState('');

  const handleRegister = async (e: React.FormEvent) => {
    e.preventDefault();
    setError('');

    if (passphrase !== passphraseConfirm) {
      setError('Passphrases do not match');
      return;
    }

    if (passphrase.length < 12) {
      setError('Passphrase must be at least 12 characters');
      return;
    }

    setLoading(true);

    try {
      // Step 1: Get salts from server
      const salts = await api.post<RegisterInitResponse>('/api/v1/auth/register', {
        email,
      });

      // Step 2: Derive keys client-side
      // PEK uses server-provided salt, auth_hash uses deterministic email-based salt
      const pekKey = await derivePEK(passphrase, salts.pek_salt);
      const authHash = await deriveAuthHash(passphrase, email);

      // Step 3: Generate identity keypair (ECDH P-256)
      const identityKeyPair = await generateIdentityKeyPair();
      const identityPubkey = await exportPublicKey(identityKeyPair.publicKey);
      const identityPrivkeyEnc = await exportPrivateKeyEncrypted(identityKeyPair.privateKey, pekKey);

      // Step 4: Generate signing keypair (reuse ECDH for now)
      const signingKeyPair = await generateIdentityKeyPair();
      const signingPubkey = await exportPublicKey(signingKeyPair.publicKey);
      const signingPrivkeyEnc = await exportPrivateKeyEncrypted(signingKeyPair.privateKey, pekKey);

      // Step 5: Generate recovery codes and hash them
      const codes = generateRecoveryCodes(10);
      const encoder = new TextEncoder();
      const codeHashes: string[] = [];
      for (const code of codes) {
        const raw = code.replace(/-/g, '');
        const hashBuffer = await crypto.subtle.digest('SHA-256', encoder.encode(raw));
        codeHashes.push(bytesToBase64(new Uint8Array(hashBuffer)));
      }

      // Step 6: Complete registration
      await api.post<RegisterCompleteResponse>('/api/v1/auth/register/complete', {
        email,
        display_name: displayName || email.split('@')[0],
        auth_hash: authHash,
        identity_pubkey: identityPubkey,
        identity_privkey_enc: identityPrivkeyEnc,
        signing_pubkey: signingPubkey,
        signing_privkey_enc: signingPrivkeyEnc,
        recovery_code_hashes: codeHashes,
      });

      // Show recovery codes
      setRecoveryCodes(codes);
      setRegisteredEmail(email);
      setRegisteredAuthHash(authHash);
      setPEK(pekKey);
      setStep('recovery');
    } catch (err) {
      if (err instanceof ApiError) {
        if (err.code === 'email_already_registered') {
          setError('This email is already registered');
        } else {
          setError(err.code);
        }
      } else {
        setError('Connection error');
      }
    } finally {
      setLoading(false);
    }
  };

  const handleCopyCodes = () => {
    const text = recoveryCodes.join('\n');
    navigator.clipboard.writeText(text);
    setCopiedCodes(true);
  };

  const handleContinue = async () => {
    setLoading(true);
    try {
      // Auto-login after registration
      const res = await api.post<LoginResponse>('/api/v1/auth/login', {
        email: registeredEmail,
        auth_hash: registeredAuthHash,
      });

      if (res.access_token && res.refresh_token) {
        login(res.access_token, res.refresh_token, res.user_id, 'user');
        navigate('/');
      }
    } catch {
      // Login failed, redirect to login page
      navigate('/login');
    } finally {
      setLoading(false);
    }
  };

  if (step === 'recovery') {
    return (
      <div className="onboarding-page">
        <div className="onboarding-card">
          <h1>Recovery Codes</h1>
          <div className="alert alert-warning" style={{ marginBottom: 20 }}>
            Save these codes in a safe place. They are the <strong>only way</strong> to recover your account if you lose your passphrase.
          </div>
          <div className="recovery-grid" style={{ marginBottom: 20 }}>
            {recoveryCodes.map((code, i) => (
              <div className="recovery-code" key={i}>{code}</div>
            ))}
          </div>
          <div className="form-actions">
            <button className="btn-secondary" onClick={handleCopyCodes} style={{ flex: 1, padding: '10px 16px' }}>
              {copiedCodes ? 'Copied!' : 'Copy to Clipboard'}
            </button>
            <button
              className="btn-add"
              onClick={handleContinue}
              disabled={loading}
              style={{ flex: 1, padding: '10px 16px' }}
            >
              {loading ? 'Logging in...' : 'Continue'}
            </button>
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="auth-page">
      <div className="auth-card">
        <h1>{t('app.name')}</h1>
        <p className="auth-tagline">{t('auth.register')}</p>

        {error && <div className="alert alert-error">{error}</div>}

        <form onSubmit={handleRegister}>
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
            <label htmlFor="displayName">Display Name</label>
            <input
              id="displayName"
              type="text"
              value={displayName}
              onChange={(e) => setDisplayName(e.target.value)}
              placeholder={email.split('@')[0] || 'Optional'}
              autoComplete="name"
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
              minLength={12}
              autoComplete="new-password"
            />
            <small className="text-muted" style={{ display: 'block', marginTop: 4 }}>
              {t('auth.passphrase_warning')}
            </small>
          </div>
          <div className="form-group">
            <label htmlFor="passphraseConfirm">Confirm Passphrase</label>
            <input
              id="passphraseConfirm"
              type="password"
              value={passphraseConfirm}
              onChange={(e) => setPassphraseConfirm(e.target.value)}
              required
              minLength={12}
              autoComplete="new-password"
            />
          </div>
          <button type="submit" className="btn btn-primary" disabled={loading}>
            {loading ? t('common.loading') : t('auth.register')}
          </button>
        </form>

        <p className="auth-tagline" style={{ marginTop: 16, marginBottom: 0 }}>
          Already have an account? <Link to="/login" className="card-link">{t('auth.login')}</Link>
        </p>
      </div>
    </div>
  );
}
