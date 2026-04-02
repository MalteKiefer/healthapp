import { memo, useEffect, useState } from 'react';
import { useTranslation } from 'react-i18next';

type SyncStatus = 'online' | 'offline' | 'syncing';

function SyncIndicatorInner() {
  const { t } = useTranslation();
  const [status, setStatus] = useState<SyncStatus>(navigator.onLine ? 'online' : 'offline');

  useEffect(() => {
    const handleOnline = () => setStatus('online');
    const handleOffline = () => setStatus('offline');

    window.addEventListener('online', handleOnline);
    window.addEventListener('offline', handleOffline);

    return () => {
      window.removeEventListener('online', handleOnline);
      window.removeEventListener('offline', handleOffline);
    };
  }, []);

  if (status === 'online') return null; // Don't show when online

  return (
    <div className={`sync-indicator sync-${status}`}>
      <span className="sync-dot" />
      <span className="sync-text">
        {status === 'offline' && t('sync.offline')}
        {status === 'syncing' && t('sync.syncing')}
      </span>
    </div>
  );
}

export const SyncIndicator = memo(SyncIndicatorInner);
