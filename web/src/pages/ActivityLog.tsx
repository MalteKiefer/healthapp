import { useState } from 'react';
import { useTranslation } from 'react-i18next';
import { useQuery } from '@tanstack/react-query';
import { ProfileSelector } from '../components/ProfileSelector';
import { useProfiles } from '../hooks/useProfiles';
import { api } from '../api/client';

interface ActivityEntry {
  id: string;
  action: string;
  resource: string;
  details?: string;
  created_at: string;
}

interface ActivityResponse {
  items: ActivityEntry[];
  total?: number;
}

const PAGE_SIZE = 25;

export function ActivityLog() {
  const { t } = useTranslation();
  const { data: profilesData } = useProfiles();
  const profiles = profilesData || [];
  const [selectedProfile, setSelectedProfile] = useState('');
  const [offset, setOffset] = useState(0);

  const profileId = selectedProfile || profiles[0]?.id || '';

  const { data, isLoading } = useQuery({
    queryKey: ['activity', profileId, offset],
    queryFn: () =>
      api.get<ActivityResponse>(
        `/api/v1/profiles/${profileId}/activity?offset=${offset}&limit=${PAGE_SIZE}`,
      ),
    enabled: !!profileId,
  });

  const items = data?.items || [];
  const total = data?.total ?? 0;
  const hasNext = items.length === PAGE_SIZE || offset + PAGE_SIZE < total;
  const hasPrev = offset > 0;

  return (
    <div className="page">
      <div className="page-header">
        <h2>{t('activity.title')}</h2>
        <ProfileSelector
          selectedId={selectedProfile || profiles[0]?.id}
          onSelect={(id) => {
            setSelectedProfile(id);
            setOffset(0);
          }}
        />
      </div>

      {isLoading ? (
        <p>{t('common.loading')}</p>
      ) : !profileId ? (
        <p className="text-muted">{t('common.no_profiles')}</p>
      ) : items.length === 0 && offset === 0 ? (
        <p className="text-muted">{t('activity.no_entries')}</p>
      ) : (
        <>
          <div style={{ overflowX: 'auto' }}>
            <table style={{ width: '100%', borderCollapse: 'collapse' }}>
              <thead>
                <tr>
                  <th style={thStyle}>{t('common.date')}</th>
                  <th style={thStyle}>{t('activity.action')}</th>
                  <th style={thStyle}>{t('activity.resource')}</th>
                  <th style={thStyle}>{t('activity.details')}</th>
                </tr>
              </thead>
              <tbody>
                {items.map((entry) => (
                  <tr key={entry.id}>
                    <td style={tdStyle}>
                      {new Date(entry.created_at).toLocaleString()}
                    </td>
                    <td style={tdStyle}>{entry.action}</td>
                    <td style={tdStyle}>{entry.resource}</td>
                    <td style={tdStyle}>{entry.details || '-'}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>

          <div
            style={{
              display: 'flex',
              justifyContent: 'space-between',
              alignItems: 'center',
              marginTop: 16,
            }}
          >
            <button
              className="btn btn-secondary"
              disabled={!hasPrev}
              onClick={() => setOffset((o) => Math.max(0, o - PAGE_SIZE))}
            >
              {t('activity.prev')}
            </button>
            <span className="text-muted" style={{ fontSize: 13 }}>
              {t('activity.showing', {
                from: offset + 1,
                to: offset + items.length,
              })}
            </span>
            <button
              className="btn btn-secondary"
              disabled={!hasNext}
              onClick={() => setOffset((o) => o + PAGE_SIZE)}
            >
              {t('activity.next')}
            </button>
          </div>
        </>
      )}
    </div>
  );
}

const thStyle: React.CSSProperties = {
  textAlign: 'left',
  padding: '8px 12px',
  borderBottom: '2px solid var(--color-border, #e2e8f0)',
  fontSize: 13,
  fontWeight: 600,
};

const tdStyle: React.CSSProperties = {
  padding: '8px 12px',
  borderBottom: '1px solid var(--color-border, #e2e8f0)',
  fontSize: 14,
};
