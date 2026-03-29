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

  const enabled = config?.enabled ?? false;

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
        </>
      )}
    </div>
  );
}
