import { useState } from 'react';
import { useNavigate, Link } from 'react-router-dom';
import { useTranslation } from 'react-i18next';
import { api, ApiError } from '../api/client';

export function Recovery() {
  const { t } = useTranslation();
  const navigate = useNavigate();

  const [email, setEmail] = useState('');
  const [recoveryCode, setRecoveryCode] = useState('');
  const [error, setError] = useState('');
  const [success, setSuccess] = useState(false);
  const [loading, setLoading] = useState(false);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError('');
    setSuccess(false);
    setLoading(true);

    try {
      await api.post('/api/v1/auth/recovery', {
        email,
        recovery_code: recoveryCode,
      });

      setSuccess(true);
      setTimeout(() => navigate('/login'), 2000);
    } catch (err) {
      if (err instanceof ApiError) {
        setError(t('recovery.invalid'));
      } else {
        setError(t('recovery.connection_error'));
      }
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="auth-page">
      <div className="auth-card">
        <h1>{t('recovery.title')}</h1>
        <p className="auth-tagline">{t('recovery.description')}</p>

        {error && <div className="alert alert-error">{error}</div>}
        {success && <div className="alert alert-success">{t('recovery.success')}</div>}

        {!success && (
          <form onSubmit={handleSubmit}>
            <div className="form-group">
              <label htmlFor="recovery-email">{t('auth.email')}</label>
              <input
                id="recovery-email"
                type="email"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                required
                autoComplete="email"
              />
            </div>
            <div className="form-group">
              <label htmlFor="recovery-code">{t('recovery.code')}</label>
              <input
                id="recovery-code"
                type="text"
                value={recoveryCode}
                onChange={(e) => setRecoveryCode(e.target.value)}
                required
                autoComplete="off"
              />
            </div>
            <button type="submit" className="btn btn-primary" disabled={loading}>
              {loading ? t('common.loading') : t('recovery.submit')}
            </button>
          </form>
        )}

        <p className="auth-tagline" style={{ marginTop: 16, marginBottom: 0 }}>
          <Link to="/login" className="card-link">{t('recovery.back_to_login')}</Link>
        </p>
      </div>
    </div>
  );
}
