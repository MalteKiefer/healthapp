import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { useTranslation } from 'react-i18next';
import { useAuthStore } from '../store/auth';
import { api, ApiError } from '../api/client';

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
      // TODO: derive auth_hash from passphrase using Argon2id (WebCrypto)
      // For now, send passphrase directly (will be replaced with client-side hashing)
      const res = await api.post<LoginResponse>('/api/v1/auth/login', {
        email,
        auth_hash: passphrase,
      });

      if (res.requires_totp) {
        setNeeds2FA(true);
        setUserId(res.user_id);
        setLoading(false);
        return;
      }

      if (res.access_token && res.refresh_token) {
        login(res.access_token, res.refresh_token, res.user_id, 'user');
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
      </div>
    </div>
  );
}
