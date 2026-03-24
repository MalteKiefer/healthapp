import { useEffect, useState } from 'react';

type SyncStatus = 'online' | 'offline' | 'syncing';

export function SyncIndicator() {
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
        {status === 'offline' && 'Offline — changes will sync when reconnected'}
        {status === 'syncing' && 'Syncing...'}
      </span>
    </div>
  );
}
