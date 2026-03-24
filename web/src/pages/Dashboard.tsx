import { useTranslation } from 'react-i18next';

export function Dashboard() {
  const { t } = useTranslation();

  return (
    <div className="page">
      <h2>{t('nav.dashboard')}</h2>
      <div className="dashboard-grid">
        <div className="card">
          <h3>{t('vitals.title')}</h3>
          <p>{t('common.no_data')}</p>
        </div>
        <div className="card">
          <h3>{t('nav.tasks')}</h3>
          <p>{t('common.no_data')}</p>
        </div>
        <div className="card">
          <h3>{t('nav.appointments')}</h3>
          <p>{t('common.no_data')}</p>
        </div>
        <div className="card">
          <h3>{t('nav.medications')}</h3>
          <p>{t('common.no_data')}</p>
        </div>
      </div>
    </div>
  );
}
