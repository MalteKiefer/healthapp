import { useState } from 'react';
import { useNavigate, Link } from 'react-router-dom';
import { useTranslation } from 'react-i18next';
import { useAuthStore } from '../store/auth';
import { api, ApiError } from '../api/client';
import { deriveAuthHash, derivePEK, setPEK } from '../crypto';

interface LoginResponse {
  access_token?: string;
  refresh_token?: string;
  expires_at?: number;
  user_id: string;
  requires_totp?: boolean;
  pek_salt?: string;
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
        setLoading(false);
        return;
      }

      if (res.access_token && res.refresh_token) {
        // Derive PEK and store in memory for this session
        if (res.pek_salt) {
          const pekKey = await derivePEK(passphrase, res.pek_salt);
          setPEK(pekKey);
        }
        login(res.access_token, res.refresh_token, res.user_id, 'user', email);
        navigate('/');
      }
    } catch (err) {
      if (err instanceof ApiError) {
        setError(err.code === 'invalid_credentials' ? 'Invalid email or passphrase' : err.code);
      } else {
        setError('Connection error');
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
      });

      if (res.access_token && res.refresh_token) {
        login(res.access_token, res.refresh_token, res.user_id, 'user');
        navigate('/');
      }
    } catch (err) {
      if (err instanceof ApiError) {
        setError(err.code);
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
          Don&apos;t have an account? <Link to="/register" className="card-link">{t('auth.register')}</Link>
        </p>
      </div>
    </div>
  );
}
