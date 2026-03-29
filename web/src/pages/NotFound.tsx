import { Link } from 'react-router-dom';
import { useTranslation } from 'react-i18next';

export function NotFound() {
  const { t } = useTranslation();
  return (
    <div className="auth-page">
      <div className="auth-card" style={{ textAlign: 'center' }}>
        <h1 style={{ fontSize: 64, marginBottom: 8 }}>404</h1>
        <p className="auth-tagline">{t('common.not_found')}</p>
        <Link to="/" className="btn btn-add" style={{ display: 'inline-block', width: 'auto', marginTop: 16 }}>
          {t('common.go_to_dashboard')}
        </Link>
      </div>
    </div>
  );
}
