import { useState, useEffect } from 'react';
import { useTranslation } from 'react-i18next';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { ProfileSelector } from '../components/ProfileSelector';
import { ConfirmDelete } from '../components/ConfirmDelete';
import { useProfiles } from '../hooks/useProfiles';
import { useDateFormat } from '../hooks/useDateLocale';
import { api } from '../api/client';
import { medicationsApi } from '../api/medications';

interface Share {
  share_id: string;
  label: string;
  expires_at: string;
  revoked_at?: string | null;
  created_at: string;
  active: boolean;
}

interface CreateShareResponse {
  share_id: string;
  share_url: string;
  expires_at: string;
}

type ExpiryDuration = '1h' | '24h' | '7d' | '30d';

const DURATION_TO_HOURS: Record<ExpiryDuration, number> = {
  '1h': 1,
  '24h': 24,
  '7d': 168,
  '30d': 720,
};

function toUrlSafeBase64(bytes: Uint8Array): string {
  let binary = '';
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

/** Generate a random 256-bit AES key and return as CryptoKey + URL-safe base64 */
async function generateTempKey(): Promise<{ key: CryptoKey; base64: string }> {
  const key = await crypto.subtle.generateKey(
    { name: 'AES-GCM', length: 256 },
    true,
    ['encrypt'],
  );
  const raw = await crypto.subtle.exportKey('raw', key);
  return { key, base64: toUrlSafeBase64(new Uint8Array(raw)) };
}

/** Encrypt a JSON payload with AES-GCM, return base64(IV + ciphertext) */
async function encryptPayload(data: unknown, key: CryptoKey): Promise<string> {
  const plaintext = new TextEncoder().encode(JSON.stringify(data));
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const ciphertext = await crypto.subtle.encrypt(
    { name: 'AES-GCM', iv, tagLength: 128 },
    key,
    plaintext,
  );
  // Concatenate IV + ciphertext
  const combined = new Uint8Array(iv.length + ciphertext.byteLength);
  combined.set(iv);
  combined.set(new Uint8Array(ciphertext), iv.length);
  let binary = '';
  for (const b of combined) binary += String.fromCharCode(b);
  return btoa(binary);
}

/** Fetch health data for a profile and return a summary object */
async function gatherHealthData(profileId: string): Promise<Record<string, unknown>> {
  const [meds, allergies, diagnoses, vitals, contacts] = await Promise.allSettled([
    medicationsApi.list(profileId).then((data) => ({
      items: (data.items || []).filter((m: { ended_at?: string | null }) => !m.ended_at || new Date(m.ended_at) > new Date()),
    })),
    api.get<{ items: unknown[] }>(`/api/v1/profiles/${profileId}/allergies`),
    api.get<{ items: unknown[] }>(`/api/v1/profiles/${profileId}/diagnoses`),
    api.get<{ items: unknown[] }>(`/api/v1/profiles/${profileId}/vitals?limit=10`),
    api.get<{ items: unknown[] }>(`/api/v1/profiles/${profileId}/contacts`),
  ]);
  const get = (r: PromiseSettledResult<{ items: unknown[] }>) =>
    r.status === 'fulfilled' ? r.value.items : [];
  return {
    medications: get(meds),
    allergies: get(allergies),
    diagnoses: get(diagnoses),
    vitals: get(vitals),
    contacts: get(contacts),
    generated_at: new Date().toISOString(),
  };
}

export function DoctorShares() {
  const { t } = useTranslation();
  const { fmt, relative } = useDateFormat();
  const { data: profilesData } = useProfiles();
  const profiles = profilesData || [];
  const [selectedProfile, setSelectedProfile] = useState('');
  const [showCreateModal, setShowCreateModal] = useState(false);
  const [showLinkModal, setShowLinkModal] = useState(false);
  const [shareUrl, setShareUrl] = useState('');
  const [copied, setCopied] = useState(false);
  const [revokeTarget, setRevokeTarget] = useState<string | null>(null);
  const queryClient = useQueryClient();
  const profileId = selectedProfile || profiles[0]?.id || '';

  useEffect(() => {
    if (!selectedProfile && profiles.length > 0) {
      setSelectedProfile(profiles[0].id);
    }
  }, [profiles, selectedProfile]);

  const { data, isLoading } = useQuery({
    queryKey: ['shares', profileId],
    queryFn: () => api.get<{ items: Share[] }>(`/api/v1/profiles/${profileId}/shares`),
    enabled: !!profileId,
  });

  const createMutation = useMutation({
    mutationFn: async (duration: ExpiryDuration) => {
      const { key, base64: tempKeyBase64 } = await generateTempKey();
      const healthData = await gatherHealthData(profileId);
      const encryptedData = await encryptPayload(healthData, key);
      const resp = await api.post<CreateShareResponse>(`/api/v1/profiles/${profileId}/share`, {
        encrypted_data: encryptedData,
        expires_in_hours: DURATION_TO_HOURS[duration],
        label: '',
      });
      return { resp, tempKey: tempKeyBase64 };
    },
    onSuccess: ({ resp, tempKey }) => {
      queryClient.invalidateQueries({ queryKey: ['shares', profileId] });
      setShareUrl(`${resp.share_url}#${tempKey}`);
      setShowCreateModal(false);
      setShowLinkModal(true);
    },
  });

  const revokeMutation = useMutation({
    mutationFn: (shareId: string) =>
      api.delete(`/api/v1/profiles/${profileId}/share/${shareId}`),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['shares', profileId] });
    },
  });

  const items = data?.items || [];

  const getStatus = (share: Share): 'active' | 'expired' | 'revoked' => {
    if (share.revoked_at) return 'revoked';
    if (!share.active) return 'expired';
    return 'active';
  };

  const handleCopy = () => {
    navigator.clipboard.writeText(shareUrl);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  return (
    <div className="page">
      <div className="page-header">
        <h2>{t('shares.title')}</h2>
        <div style={{ display: 'flex', gap: 12, alignItems: 'center' }}>
          <ProfileSelector selectedId={profileId} onSelect={setSelectedProfile} />
          <button
            className="btn btn-add"
            onClick={() => setShowCreateModal(true)}
            disabled={!profileId}
          >
            {t('shares.create')}
          </button>
        </div>
      </div>

      {/* Create Share Modal */}
      {showCreateModal && (
        <div className="modal-overlay" onClick={() => setShowCreateModal(false)}>
          <div className="modal" onClick={(e) => e.stopPropagation()}>
            <div className="modal-header">
              <h3>{t('shares.create')}</h3>
              <button className="btn-icon-sm" onClick={() => setShowCreateModal(false)}>
                &times;
              </button>
            </div>
            <div className="modal-body">
              <div className="form-group">
                <label>{t('shares.expiry')}</label>
                <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
                  {(['1h', '24h', '7d', '30d'] as ExpiryDuration[]).map((dur) => (
                    <button
                      key={dur}
                      className="btn btn-secondary"
                      style={{ textAlign: 'left' }}
                      disabled={createMutation.isPending}
                      onClick={() => createMutation.mutate(dur)}
                    >
                      {t(`shares.${dur}`)}
                    </button>
                  ))}
                </div>
              </div>
            </div>
            <div className="modal-footer">
              <button
                className="btn btn-secondary"
                onClick={() => setShowCreateModal(false)}
              >
                {t('common.cancel')}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Share Link Modal */}
      {showLinkModal && (
        <div className="modal-overlay" onClick={() => setShowLinkModal(false)}>
          <div className="modal" onClick={(e) => e.stopPropagation()}>
            <div className="modal-header">
              <h3>{t('shares.share_created')}</h3>
              <button className="btn-icon-sm" onClick={() => setShowLinkModal(false)}>
                &times;
              </button>
            </div>
            <div className="modal-body">
              <div className="feed-url-box">
                <code className="feed-url" style={{ wordBreak: 'break-all' }}>
                  {shareUrl}
                </code>
                <button className="btn-sm" onClick={handleCopy}>
                  {copied ? t('shares.link_copied') : t('shares.copy_link')}
                </button>
              </div>
              <p className="text-muted" style={{ fontSize: 12, marginTop: 8 }}>
                {t('shares.link_hint')}
              </p>
            </div>
            <div className="modal-footer">
              <button
                className="btn btn-secondary"
                onClick={() => setShowLinkModal(false)}
              >
                {t('common.close')}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Shares List */}
      <div className="card">
        {isLoading ? (
          <p>{t('common.loading')}</p>
        ) : items.length === 0 ? (
          <p className="text-muted">{t('shares.no_shares')}</p>
        ) : (
          <div className="med-list">
            {items.map((share) => {
              const status = getStatus(share);
              const dimmed = status !== 'active';

              return (
                <div
                  key={share.share_id}
                  className="med-item"
                  style={dimmed ? { opacity: 0.5 } : undefined}
                >
                  <div className="med-info">
                    <div className="med-name">
                      <span
                        className={`badge badge-${status === 'active' ? 'success' : status === 'expired' ? 'warning' : 'danger'}`}
                        style={{
                          display: 'inline-block',
                          padding: '2px 8px',
                          borderRadius: 4,
                          fontSize: 11,
                          fontWeight: 600,
                          marginRight: 8,
                          background:
                            status === 'active'
                              ? 'var(--color-success)'
                              : status === 'expired'
                                ? 'var(--color-warning, #e6a817)'
                                : 'var(--color-danger)',
                          color: '#fff',
                        }}
                      >
                        {t(`shares.${status}`)}
                      </span>
                      {share.label || fmt(share.created_at, 'dd. MMM yyyy, HH:mm')}
                    </div>
                    <div className="med-details">
                      {status === 'active'
                        ? `${t('shares.expiry')}: ${relative(share.expires_at)}`
                        : status === 'expired'
                          ? t('shares.expired')
                          : t('shares.revoked')}
                    </div>
                  </div>
                  <div className="med-actions">
                    {status === 'active' && (
                      <button
                        className="btn-sm"
                        onClick={() => setRevokeTarget(share.share_id)}
                      >
                        {t('shares.revoke')}
                      </button>
                    )}
                  </div>
                </div>
              );
            })}
          </div>
        )}
      </div>

      <ConfirmDelete
        open={!!revokeTarget}
        title={t('shares.revoke_title')}
        message={t('shares.revoke_message')}
        onConfirm={() => {
          revokeMutation.mutate(revokeTarget!);
          setRevokeTarget(null);
        }}
        onCancel={() => setRevokeTarget(null)}
        pending={revokeMutation.isPending}
      />
    </div>
  );
}
