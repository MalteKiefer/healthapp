import { useState, useEffect } from 'react';
import { useTranslation } from 'react-i18next';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { ProfileSelector } from '../components/ProfileSelector';
import { useProfiles } from '../hooks/useProfiles';
import { useAuthStore } from '../store/auth';
import { api, ApiError } from '../api/client';

interface EmergencyConfig {
  id?: string;
  profile_id: string;
  enabled: boolean;
  emergency_contact_user_id?: string;
  wait_hours: number;
  data_fields: string[];
  message?: string | null;
  created_at?: string;
  updated_at?: string;
}

interface PendingRequest {
  id: string;
  profile_id: string;
  requester_id: string;
  requested_at: string;
  status: string;
}

interface EmergencyCard {
  token: string;
  url: string;
}

const DATA_FIELD_KEYS = [
  'blood_type',
  'allergies',
  'medications',
  'diagnoses',
  'contacts',
] as const;

const DEFAULT_WAIT_HOURS = 48;
const DEFAULT_DATA_FIELDS = ['blood_type', 'allergies', 'medications', 'diagnoses', 'contacts'];

export function EmergencyAccess() {
  const { t } = useTranslation();
  const { data: profilesData } = useProfiles();
  const profiles = profilesData || [];
  const [selectedProfile, setSelectedProfile] = useState('');
  const [dataFields, setDataFields] = useState<string[]>(DEFAULT_DATA_FIELDS);
  const [waitHours, setWaitHours] = useState(DEFAULT_WAIT_HOURS);
  const [message, setMessage] = useState('');
  const queryClient = useQueryClient();
  const userId = useAuthStore((s) => s.userId);

  const profileId = selectedProfile || profiles[0]?.id || '';

  const { data: config, isLoading } = useQuery({
    queryKey: ['emergency-access', profileId],
    queryFn: async () => {
      try {
        return await api.get<EmergencyConfig>(`/api/v1/profiles/${profileId}/emergency-access`);
      } catch (err) {
        if (err instanceof ApiError && err.status === 404) {
          // No config row means disabled
          return { profile_id: profileId, enabled: false, wait_hours: DEFAULT_WAIT_HOURS, data_fields: DEFAULT_DATA_FIELDS } as EmergencyConfig;
        }
        throw err;
      }
    },
    enabled: !!profileId,
  });

  useEffect(() => {
    if (config) {
      setDataFields(config.data_fields?.length ? config.data_fields : DEFAULT_DATA_FIELDS);
      setWaitHours(config.wait_hours ?? DEFAULT_WAIT_HOURS);
      setMessage(config.message || '');
    }
  }, [config]);

  const saveMutation = useMutation({
    mutationFn: (body: {
      emergency_contact_user_id: string;
      wait_hours: number;
      data_fields: string[];
      message: string;
    }) => api.post(`/api/v1/profiles/${profileId}/emergency-access`, body),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['emergency-access', profileId] });
    },
  });

  const disableMutation = useMutation({
    mutationFn: () => api.delete(`/api/v1/profiles/${profileId}/emergency-access`),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['emergency-access', profileId] });
    },
  });

  const enabled = config?.enabled ?? false;

  const { data: pendingData } = useQuery({
    queryKey: ['emergency-pending'],
    queryFn: () => api.get<{ items: PendingRequest[] }>('/api/v1/emergency/pending'),
  });

  const pendingRequests = pendingData?.items || [];

  const { data: cardData } = useQuery({
    queryKey: ['emergency-card', profileId],
    queryFn: () => api.get<EmergencyCard>(`/api/v1/profiles/${profileId}/emergency-card`),
    enabled: !!profileId && enabled,
  });

  const [cardUrlCopied, setCardUrlCopied] = useState(false);

  const approveMutation = useMutation({
    mutationFn: (requestId: string) => api.post(`/api/v1/emergency/approve/${requestId}`),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['emergency-pending'] });
    },
  });

  const denyMutation = useMutation({
    mutationFn: (requestId: string) => api.post(`/api/v1/emergency/deny/${requestId}`),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['emergency-pending'] });
    },
  });

  const handleCopyCardUrl = () => {
    if (cardData?.url) {
      navigator.clipboard.writeText(cardData.url);
      setCardUrlCopied(true);
      setTimeout(() => setCardUrlCopied(false), 2000);
    }
  };

  const toggleDataField = (key: string) => {
    setDataFields((prev) =>
      prev.includes(key) ? prev.filter((k) => k !== key) : [...prev, key],
    );
  };

  const handleSave = () => {
    saveMutation.mutate({
      emergency_contact_user_id: userId || '',
      wait_hours: waitHours,
      data_fields: dataFields,
      message: message,
    });
  };

  const handleDisable = () => {
    disableMutation.mutate();
  };

  return (
    <div className="page">
      <div className="page-header">
        <h2>{t('emergency.title')}</h2>
        <ProfileSelector selectedId={selectedProfile || profiles[0]?.id} onSelect={setSelectedProfile} />
      </div>

      <p className="text-muted" style={{ marginBottom: 16 }}>{t('emergency.description')}</p>

      {isLoading ? (
        <p>{t('common.loading')}</p>
      ) : !profileId ? (
        <p className="text-muted">{t('common.no_profiles')}</p>
      ) : (
        <>
          {/* Status badge */}
          <div className="card" style={{ marginBottom: 16 }}>
            <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
                <span
                  style={{
                    padding: '4px 12px',
                    borderRadius: 12,
                    fontSize: 13,
                    fontWeight: 600,
                    background: enabled ? 'var(--color-success, #22c55e)' : 'var(--color-muted, #94a3b8)',
                    color: '#fff',
                  }}
                >
                  {enabled ? t('emergency.enabled') : t('emergency.disabled')}
                </span>
              </div>
              {enabled ? (
                <button
                  className="btn btn-secondary"
                  onClick={handleDisable}
                  disabled={disableMutation.isPending}
                >
                  {t('emergency.disable')}
                </button>
              ) : (
                <button
                  className="btn btn-add"
                  onClick={handleSave}
                  disabled={saveMutation.isPending}
                >
                  {t('emergency.enable')}
                </button>
              )}
            </div>
          </div>

          {/* Shared data checkboxes */}
          <div className="card" style={{ marginBottom: 16 }}>
            <h3>{t('emergency.shared_data')}</h3>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 8, marginTop: 8 }}>
              {DATA_FIELD_KEYS.map((key) => (
                <label key={key} className="toggle-label" style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                  <input
                    type="checkbox"
                    checked={dataFields.includes(key)}
                    onChange={() => toggleDataField(key)}
                  />
                  {t(`emergency.include_${key}`)}
                </label>
              ))}
            </div>
          </div>

          {/* Wait hours */}
          <div className="card" style={{ marginBottom: 16 }}>
            <h3>{t('emergency.wait_hours')}</h3>
            <p className="text-muted" style={{ fontSize: 12, marginBottom: 8 }}>
              {t('emergency.wait_hours_hint')}
            </p>
            <input
              type="number"
              min={0}
              max={168}
              value={waitHours}
              onChange={(e) => setWaitHours(Math.max(0, Math.min(168, parseInt(e.target.value) || 0)))}
              style={{ maxWidth: 120 }}
            />
          </div>

          {/* Message */}
          <div className="card" style={{ marginBottom: 16 }}>
            <h3>{t('emergency.message')}</h3>
            <p className="text-muted" style={{ fontSize: 12, marginBottom: 8 }}>
              {t('emergency.message_hint')}
            </p>
            <textarea
              value={message}
              onChange={(e) => setMessage(e.target.value)}
              rows={3}
              style={{ width: '100%', resize: 'vertical' }}
            />
          </div>

          {/* Save */}
          <button
            className="btn btn-add"
            onClick={handleSave}
            disabled={saveMutation.isPending}
          >
            {saveMutation.isPending ? t('common.loading') : t('emergency.save')}
          </button>

          {/* Emergency Card URL */}
          {enabled && cardData?.url && (
            <div className="card" style={{ marginTop: 16 }}>
              <h3>{t('emergency.card_url')}</h3>
              <p className="text-muted" style={{ fontSize: 12, marginBottom: 8 }}>
                {t('emergency.card_hint')}
              </p>
              <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                <input
                  type="text"
                  readOnly
                  value={cardData.url}
                  style={{ flex: 1, fontFamily: 'monospace', fontSize: 13 }}
                  onClick={(e) => (e.target as HTMLInputElement).select()}
                />
                <button className="btn btn-secondary" onClick={handleCopyCardUrl}>
                  {cardUrlCopied ? t('common.copied') : t('common.copy')}
                </button>
              </div>
            </div>
          )}

          {/* Pending Requests */}
          <div className="card" style={{ marginTop: 16 }}>
            <h3>{t('emergency.pending_requests')}</h3>
            {pendingRequests.length === 0 ? (
              <p className="text-muted" style={{ marginTop: 8 }}>{t('emergency.no_pending')}</p>
            ) : (
              <div style={{ display: 'flex', flexDirection: 'column', gap: 12, marginTop: 12 }}>
                {pendingRequests.map((req) => (
                  <div
                    key={req.id}
                    className="card"
                    style={{
                      display: 'flex',
                      alignItems: 'center',
                      justifyContent: 'space-between',
                      padding: 12,
                    }}
                  >
                    <div>
                      <div style={{ fontWeight: 500 }}>
                        {t('emergency.requester')}: {req.requester_id}
                      </div>
                      <div className="text-muted" style={{ fontSize: 12 }}>
                        {t('emergency.requested_at')}: {new Date(req.requested_at).toLocaleString()}
                      </div>
                    </div>
                    <div style={{ display: 'flex', gap: 8 }}>
                      <button
                        className="btn"
                        style={{ background: 'var(--color-success, #22c55e)', color: '#fff' }}
                        onClick={() => approveMutation.mutate(req.id)}
                        disabled={approveMutation.isPending}
                      >
                        {t('emergency.approve')}
                      </button>
                      <button
                        className="btn"
                        style={{ background: 'var(--color-danger, #ef4444)', color: '#fff' }}
                        onClick={() => denyMutation.mutate(req.id)}
                        disabled={denyMutation.isPending}
                      >
                        {t('emergency.deny')}
                      </button>
                    </div>
                  </div>
                ))}
              </div>
            )}
          </div>
        </>
      )}
    </div>
  );
}
