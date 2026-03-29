import { useState, useCallback } from 'react';
import { useTranslation } from 'react-i18next';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { api } from '../api/client';
import { useAuthStore } from '../store/auth';
import { useDateFormat } from '../hooks/useDateLocale';
import { ConfirmDelete } from '../components/ConfirmDelete';

/* ── Response types ─────────────────────────────────────── */

interface SystemHealth {
  version: string;
  database: { pool_size: number; idle: number; total: number; total_conns: number; max_conns: number };
  redis: { status: string; db_size: number };
  registration_mode: string;
}

interface StorageStats {
  total_used_bytes: number;
  total_quota_bytes: number;
  user_count: number;
}

interface UserInfo {
  id: string;
  email: string;
  display_name: string;
  role: string;
  is_disabled: boolean;
  created_at: string;
  used_bytes?: number;
  quota_bytes?: number;
}

interface BackupInfo {
  id: string;
  backed_up_at: string;
  file_size_bytes: number;
  encrypted: boolean;
  checksum_sha256: string;
}

interface InviteInfo {
  token: string;
  email?: string;
  note?: string;
  created_at: string;
}

interface AuditEntry {
  id: string;
  user_id?: string;
  action: string;
  resource: string;
  resource_id?: string;
  ip_address?: string;
  metadata?: Record<string, unknown>;
  created_at: string;
}

/* ── Helpers ────────────────────────────────────────────── */

type AdminTab = 'overview' | 'users' | 'invites' | 'backups' | 'audit' | 'settings';

function formatBytes(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1048576) return `${(bytes / 1024).toFixed(0)} KB`;
  if (bytes < 1073741824) return `${(bytes / 1048576).toFixed(1)} MB`;
  return `${(bytes / 1073741824).toFixed(2)} GB`;
}

function maskToken(token: string): string {
  if (token.length <= 8) return token;
  return token.slice(0, 4) + '****' + token.slice(-4);
}

/* ── Icons (inline SVG, monochrome, stroke-based) ─────── */

function IconShield(): React.ReactNode {
  return (
    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
      <path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z" />
    </svg>
  );
}

function IconMail(): React.ReactNode {
  return (
    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
      <rect x="2" y="4" width="20" height="16" rx="2" />
      <path d="M22 7l-10 7L2 7" />
    </svg>
  );
}

function IconDatabase(): React.ReactNode {
  return (
    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
      <ellipse cx="12" cy="5" rx="9" ry="3" />
      <path d="M21 12c0 1.66-4.03 3-9 3s-9-1.34-9-3" />
      <path d="M3 5v14c0 1.66 4.03 3 9 3s9-1.34 9-3V5" />
    </svg>
  );
}

function IconClipboard(): React.ReactNode {
  return (
    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
      <path d="M16 4h2a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2h2" />
      <rect x="8" y="2" width="8" height="4" rx="1" ry="1" />
    </svg>
  );
}

function IconRefresh(): React.ReactNode {
  return (
    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
      <polyline points="23 4 23 10 17 10" />
      <path d="M20.49 15a9 9 0 1 1-2.12-9.36L23 10" />
    </svg>
  );
}

function IconPlus(): React.ReactNode {
  return (
    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <line x1="12" y1="5" x2="12" y2="19" />
      <line x1="5" y1="12" x2="19" y2="12" />
    </svg>
  );
}

function IconCheck(): React.ReactNode {
  return (
    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <polyline points="20 6 9 17 4 12" />
    </svg>
  );
}

function IconLock(): React.ReactNode {
  return (
    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
      <rect x="3" y="11" width="18" height="11" rx="2" ry="2" />
      <path d="M7 11V7a5 5 0 0 1 10 0v4" />
    </svg>
  );
}

function IconUnlock(): React.ReactNode {
  return (
    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
      <rect x="3" y="11" width="18" height="11" rx="2" ry="2" />
      <path d="M7 11V7a5 5 0 0 1 9.9-1" />
    </svg>
  );
}

function IconGear(): React.ReactNode {
  return (
    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
      <circle cx="12" cy="12" r="3" />
      <path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 0 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 0 1-2.83-2.83l.06-.06A1.65 1.65 0 0 0 4.68 15a1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 0 1 2.83-2.83l.06.06A1.65 1.65 0 0 0 9 4.68a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 0 1 2.83 2.83l-.06.06A1.65 1.65 0 0 0 19.4 9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z" />
    </svg>
  );
}

/* ── Main component ─────────────────────────────────────── */

export function Admin() {
  const { t } = useTranslation();
  const { role, userId } = useAuthStore();
  const { fmt, relative } = useDateFormat();
  const queryClient = useQueryClient();

  const [tab, setTab] = useState<AdminTab>('overview');

  /* ── Delete confirmation state ── */
  const [deleteTarget, setDeleteTarget] = useState<{ type: 'user' | 'invite'; id: string } | null>(null);

  /* ── Queries ── */
  const isAdmin = role === 'admin';

  const { data: system } = useQuery({
    queryKey: ['admin-system'],
    queryFn: () => api.get<SystemHealth>('/api/v1/admin/system'),
    enabled: isAdmin,
  });

  const { data: storage } = useQuery({
    queryKey: ['admin-storage'],
    queryFn: () => api.get<StorageStats>('/api/v1/admin/storage'),
    enabled: isAdmin,
  });

  const { data: users } = useQuery({
    queryKey: ['admin-users'],
    queryFn: () => api.get<{ items: UserInfo[] }>('/api/v1/admin/users'),
    enabled: isAdmin && (tab === 'overview' || tab === 'users'),
  });

  const { data: backups } = useQuery({
    queryKey: ['admin-backups'],
    queryFn: () => api.get<{ items: BackupInfo[] }>('/api/v1/admin/backups'),
    enabled: isAdmin && (tab === 'overview' || tab === 'backups'),
  });

  const { data: invites } = useQuery({
    queryKey: ['admin-invites'],
    queryFn: () => api.get<{ items: InviteInfo[] }>('/api/v1/admin/invites'),
    enabled: isAdmin && tab === 'invites',
  });

  const [auditOffset, setAuditOffset] = useState(0);
  const auditLimit = 50;

  const { data: auditLog, isFetching: auditFetching } = useQuery({
    queryKey: ['admin-audit', auditOffset],
    queryFn: () =>
      api.get<{ items: AuditEntry[] }>(
        `/api/v1/admin/audit-log?limit=${auditLimit}&offset=${auditOffset}`,
      ),
    enabled: isAdmin && tab === 'audit',
  });

  /* ── Mutations ── */
  const disableUser = useMutation({
    mutationFn: (id: string) => api.post(`/api/v1/admin/users/${id}/disable`),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['admin-users'] }),
  });

  const enableUser = useMutation({
    mutationFn: (id: string) => api.post(`/api/v1/admin/users/${id}/enable`),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['admin-users'] }),
  });

  const deleteUser = useMutation({
    mutationFn: (id: string) => api.delete(`/api/v1/admin/users/${id}`),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['admin-users'] });
      queryClient.invalidateQueries({ queryKey: ['admin-storage'] });
    },
  });

  const revokeSessions = useMutation({
    mutationFn: (id: string) => api.delete(`/api/v1/admin/users/${id}/sessions`),
  });

  const [quotaEditing, setQuotaEditing] = useState<string | null>(null);
  const [quotaValue, setQuotaValue] = useState('');

  const setQuota = useMutation({
    mutationFn: ({ id, quota_bytes }: { id: string; quota_bytes: number }) =>
      api.patch(`/api/v1/admin/users/${id}/quota`, { quota_bytes }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['admin-users'] });
      setQuotaEditing(null);
    },
  });

  const createInvite = useMutation({
    mutationFn: (body: { email?: string; note?: string }) =>
      api.post('/api/v1/admin/invites', body),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['admin-invites'] }),
  });

  const deleteInvite = useMutation({
    mutationFn: (token: string) => api.delete(`/api/v1/admin/invites/${token}`),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['admin-invites'] }),
  });

  const triggerBackup = useMutation({
    mutationFn: () => api.post('/api/v1/admin/backups/trigger'),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['admin-backups'] }),
  });

  /* ── Settings state ── */
  const [settingsRegMode, setSettingsRegMode] = useState<string>(system?.registration_mode ?? 'open');
  const [settingsQuotaMb, setSettingsQuotaMb] = useState('');
  const [settingsMinPassLen, setSettingsMinPassLen] = useState('');
  const [settingsRequireUpper, setSettingsRequireUpper] = useState(false);
  const [settingsRequireLower, setSettingsRequireLower] = useState(false);
  const [settingsRequireNumber, setSettingsRequireNumber] = useState(false);
  const [settingsRequireSymbol, setSettingsRequireSymbol] = useState(false);
  const [settingsSaved, setSettingsSaved] = useState(false);

  // Sync registration mode from server when data arrives
  const currentRegMode = system?.registration_mode ?? 'open';

  const saveSettings = useMutation({
    mutationFn: (settings: Record<string, string>) =>
      api.patch('/api/v1/admin/settings', { settings }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['admin-system'] });
      queryClient.invalidateQueries({ queryKey: ['auth-policy'] });
      setSettingsSaved(true);
      setTimeout(() => setSettingsSaved(false), 3000);
    },
  });

  const handleSaveSettings = useCallback(() => {
    const settings: Record<string, string> = {};
    if (settingsRegMode !== currentRegMode) {
      settings.registration_mode = settingsRegMode;
    }
    if (settingsQuotaMb.trim() !== '') {
      settings.default_quota_mb = settingsQuotaMb.trim();
    }
    if (settingsMinPassLen.trim() !== '') {
      const val = parseInt(settingsMinPassLen.trim(), 10);
      if (!isNaN(val) && val >= 8) {
        settings.min_passphrase_length = String(val);
      }
    }
    if (settingsRequireUpper) settings.require_uppercase = 'true';
    if (settingsRequireLower) settings.require_lowercase = 'true';
    if (settingsRequireNumber) settings.require_numbers = 'true';
    if (settingsRequireSymbol) settings.require_symbols = 'true';
    if (!settingsRequireUpper) settings.require_uppercase = 'false';
    if (!settingsRequireLower) settings.require_lowercase = 'false';
    if (!settingsRequireNumber) settings.require_numbers = 'false';
    if (!settingsRequireSymbol) settings.require_symbols = 'false';
    if (Object.keys(settings).length > 0) {
      saveSettings.mutate(settings);
    }
  }, [settingsRegMode, currentRegMode, settingsQuotaMb, settingsMinPassLen, settingsRequireUpper, settingsRequireLower, settingsRequireNumber, settingsRequireSymbol, saveSettings]);

  /* ── Invite form state ── */
  const [showInviteForm, setShowInviteForm] = useState(false);
  const [inviteEmail, setInviteEmail] = useState('');
  const [inviteNote, setInviteNote] = useState('');

  const handleCreateInvite = useCallback(() => {
    createInvite.mutate(
      {
        email: inviteEmail.trim() || undefined,
        note: inviteNote.trim() || undefined,
      },
      {
        onSuccess: () => {
          setInviteEmail('');
          setInviteNote('');
          setShowInviteForm(false);
        },
      },
    );
  }, [createInvite, inviteEmail, inviteNote]);

  /* ── Delete confirmation handler ── */
  const handleConfirmDelete = useCallback(() => {
    if (!deleteTarget) return;
    if (deleteTarget.type === 'user') {
      deleteUser.mutate(deleteTarget.id, { onSettled: () => setDeleteTarget(null) });
    } else {
      deleteInvite.mutate(deleteTarget.id, { onSettled: () => setDeleteTarget(null) });
    }
  }, [deleteTarget, deleteUser, deleteInvite]);

  /* ── Access guard ── */
  if (!isAdmin) {
    return (
      <div className="page">
        <h2>{t('admin.access_denied')}</h2>
        <p>{t('admin.access_denied_message')}</p>
      </div>
    );
  }

  /* ── Storage percent ── */
  const storagePercent =
    storage && storage.total_quota_bytes > 0
      ? Math.min(100, Math.round((storage.total_used_bytes / storage.total_quota_bytes) * 100))
      : 0;

  const latestBackup = backups?.items?.[0] ?? null;

  /* ── Tab definitions ── */
  const tabs: { key: AdminTab; label: string }[] = [
    { key: 'overview', label: t('admin.tab_overview') },
    { key: 'users', label: t('admin.tab_users') },
    { key: 'invites', label: t('admin.tab_invites') },
    { key: 'backups', label: t('admin.tab_backups') },
    { key: 'audit', label: t('admin.tab_audit') },
    { key: 'settings', label: t('admin.tab_settings') },
  ];

  /* ── Render ── */
  return (
    <div className="page">
      <h2>{t('admin.title')}</h2>

      {/* Tab bar */}
      <div className="admin-tabs">
        {tabs.map((tb) => (
          <button
            key={tb.key}
            className={`admin-tab${tab === tb.key ? ' active' : ''}`}
            onClick={() => setTab(tb.key)}
          >
            {tb.label}
          </button>
        ))}
      </div>

      {/* Overview */}
      {tab === 'overview' && (
        <>
          <div className="dashboard-grid" style={{ marginBottom: 16 }}>
            {/* System health */}
            <div className="card">
              <h3 style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
                <IconShield /> {t('admin.system_health')}
              </h3>
              <div className="dash-list">
                <div className="dash-item">
                  <span>{t('admin.version')}</span>
                  <span className="dash-meta">{system?.version || '\u2014'}</span>
                </div>
                <div className="dash-item">
                  <span>{t('admin.database')}</span>
                  <span className="dash-meta badge badge-active">{t('admin.connected')}</span>
                </div>
                <div className="dash-item">
                  <span>{t('admin.redis')}</span>
                  <span className="dash-meta badge badge-active">
                    {system?.redis?.status || 'OK'}
                  </span>
                </div>
                <div className="dash-item">
                  <span>{t('admin.db_pool')}</span>
                  <span className="dash-meta">
                    {t('admin.connections', { count: system?.database?.total_conns ?? system?.database?.total ?? 0 })}
                  </span>
                </div>
                <div className="dash-item">
                  <span>{t('admin.registration')}</span>
                  <span className="dash-meta">
                    <span className={`badge ${system?.registration_mode === 'open' ? 'badge-active' : system?.registration_mode === 'closed' ? 'badge-missed' : 'badge-scheduled'}`}>
                      {system?.registration_mode === 'open' ? t('admin.reg_open') : system?.registration_mode === 'closed' ? t('admin.reg_closed') : t('admin.reg_invite')}
                    </span>
                  </span>
                </div>
              </div>
            </div>

            {/* Storage */}
            <div className="card">
              <h3 style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
                <IconDatabase /> {t('admin.storage_overview')}
              </h3>
              <div className="dash-list">
                <div className="dash-item">
                  <span>{t('admin.total_used')}</span>
                  <span className="dash-meta">{formatBytes(storage?.total_used_bytes ?? 0)}</span>
                </div>
                <div className="dash-item">
                  <span>{t('admin.total_quota')}</span>
                  <span className="dash-meta">{formatBytes(storage?.total_quota_bytes ?? 0)}</span>
                </div>
                <div className="dash-item">
                  <span>{t('admin.user_count')}</span>
                  <span className="dash-meta">{storage?.user_count ?? 0}</span>
                </div>
              </div>
              {storage && storage.total_quota_bytes > 0 && (
                <div className="storage-bar" style={{ marginTop: 8 }}>
                  <div className="storage-fill" style={{ width: `${storagePercent}%` }} />
                </div>
              )}
            </div>

            {/* Latest backup */}
            <div className="card">
              <h3 style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
                <IconClipboard /> {t('admin.latest_backup')}
              </h3>
              {latestBackup ? (
                <div className="dash-list">
                  <div className="dash-item">
                    <span>{t('common.date')}</span>
                    <span className="dash-meta">
                      {fmt(latestBackup.backed_up_at, 'PPp')}
                    </span>
                  </div>
                  <div className="dash-item">
                    <span>{t('admin.size')}</span>
                    <span className="dash-meta">
                      {formatBytes(latestBackup.file_size_bytes)}
                    </span>
                  </div>
                  <div className="dash-item">
                    <span>{t('admin.encrypted')}</span>
                    <span className="dash-meta">
                      {latestBackup.encrypted ? t('admin.yes') : t('admin.no')}
                    </span>
                  </div>
                </div>
              ) : (
                <p className="text-muted">{t('admin.no_backups')}</p>
              )}
            </div>
          </div>
        </>
      )}

      {/* Users */}
      {tab === 'users' && (
        <div>
          {users?.items && users.items.length > 0 ? (
            <div className="admin-user-list">
              {users.items.map((u) => {
                const usagePercent = u.used_bytes != null && u.quota_bytes ? Math.min(100, Math.round(u.used_bytes / u.quota_bytes * 100)) : 0;
                const isSelf = u.id === userId;
                const adminCount = users.items.filter((x) => x.role === 'admin' && !x.is_disabled).length;
                const isLastAdmin = u.role === 'admin' && adminCount <= 1;
                return (
                  <div key={u.id} className={`card admin-user-card${u.is_disabled ? ' admin-user-disabled' : ''}`}>
                    <div className="admin-user-header">
                      <div className="admin-user-avatar">{(u.display_name || u.email).charAt(0).toUpperCase()}</div>
                      <div className="admin-user-info">
                        <div className="admin-user-name">
                          {u.display_name || u.email.split('@')[0]}
                          <span className={`badge ${u.role === 'admin' ? 'badge-scheduled' : 'badge-inactive'}`} style={{ marginLeft: 8 }}>{u.role}</span>
                          {u.is_disabled && <span className="badge badge-missed" style={{ marginLeft: 4 }}>{t('admin.disabled')}</span>}
                        </div>
                        <div className="admin-user-email">{u.email}</div>
                      </div>
                    </div>

                    {/* Storage bar */}
                    {u.quota_bytes != null && u.quota_bytes > 0 && (
                      <div style={{ marginTop: 12 }}>
                        <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: 12, color: 'var(--color-text-secondary)', marginBottom: 4 }}>
                          <span>{t('admin.storage_used')}</span>
                          <span>{formatBytes(u.used_bytes || 0)} / {formatBytes(u.quota_bytes)}</span>
                        </div>
                        <div className="storage-bar"><div className="storage-fill" style={{ width: `${usagePercent}%` }} /></div>
                      </div>
                    )}

                    {/* Actions */}
                    <div className="admin-user-actions">
                      {!isSelf && !isLastAdmin && (
                        u.is_disabled ? (
                          <button className="btn-sm" onClick={() => enableUser.mutate(u.id)} disabled={enableUser.isPending}>
                            <IconUnlock /> {t('admin.enable')}
                          </button>
                        ) : (
                          <button className="btn-sm" onClick={() => disableUser.mutate(u.id)} disabled={disableUser.isPending}>
                            <IconLock /> {t('admin.disable')}
                          </button>
                        )
                      )}
                      {!isSelf && (
                        <button className="btn-sm" onClick={() => revokeSessions.mutate(u.id)} disabled={revokeSessions.isPending} title={t('admin.revoke_sessions')}>
                          <IconRefresh /> {t('admin.revoke_sessions')}
                        </button>
                      )}
                      {quotaEditing === u.id ? (
                        <span style={{ display: 'inline-flex', gap: 4, alignItems: 'center' }}>
                          <input type="number" style={{ width: 80, padding: '4px 8px', fontSize: 13, borderRadius: 6, border: '1px solid var(--color-border)' }} value={quotaValue} onChange={(e) => setQuotaValue(e.target.value)} placeholder="MB" min={0} />
                          <button className="btn-sm" onClick={() => { const mb = parseInt(quotaValue, 10); if (!isNaN(mb) && mb >= 0) setQuota.mutate({ id: u.id, quota_bytes: mb * 1048576 }); }} disabled={setQuota.isPending}><IconCheck /></button>
                          <button className="btn-sm" onClick={() => setQuotaEditing(null)}>&times;</button>
                        </span>
                      ) : (
                        <button className="btn-sm" onClick={() => { setQuotaEditing(u.id); setQuotaValue(u.quota_bytes != null ? String(Math.round(u.quota_bytes / 1048576)) : ''); }} title={t('admin.set_quota')}>
                          {t('admin.quota')}
                        </button>
                      )}
                      {!isSelf && !isLastAdmin && (
                        <button className="btn-sm" style={{ color: 'var(--color-danger)' }} onClick={() => setDeleteTarget({ type: 'user', id: u.id })} title={t('common.delete')}>
                          {t('common.delete')}
                        </button>
                      )}
                      {isSelf && <span className="badge badge-info" style={{ fontSize: 11 }}>{t('settings.current_session')}</span>}
                    </div>
                  </div>
                );
              })}
            </div>
          ) : (
            <div className="card"><p className="text-muted">{t('common.no_data')}</p></div>
          )}
        </div>
      )}

      {/* Invites */}
      {tab === 'invites' && (
        <div className="card">
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 12 }}>
            <h3 style={{ display: 'flex', alignItems: 'center', gap: 6, margin: 0 }}>
              <IconMail /> {t('admin.tab_invites')}
            </h3>
            <button
              className="btn btn-add"
              onClick={() => setShowInviteForm((v) => !v)}
            >
              <IconPlus /> {t('admin.create_invite')}
            </button>
          </div>

          {/* Inline invite form */}
          {showInviteForm && (
            <div style={{ marginBottom: 16, padding: 12, background: 'var(--color-bg-subtle)', borderRadius: 8 }}>
              <div className="form-row">
                <div className="form-group">
                  <label>{t('admin.invite_email')}</label>
                  <input
                    type="email"
                    className="form-input"
                    value={inviteEmail}
                    onChange={(e) => setInviteEmail(e.target.value)}
                    placeholder={t('admin.invite_email_placeholder')}
                  />
                </div>
                <div className="form-group">
                  <label>{t('admin.invite_note')}</label>
                  <input
                    type="text"
                    className="form-input"
                    value={inviteNote}
                    onChange={(e) => setInviteNote(e.target.value)}
                    placeholder={t('admin.invite_note_placeholder')}
                  />
                </div>
              </div>
              <div className="form-actions">
                <button
                  className="btn btn-secondary"
                  onClick={() => {
                    setShowInviteForm(false);
                    setInviteEmail('');
                    setInviteNote('');
                  }}
                >
                  {t('common.cancel')}
                </button>
                <button
                  className="btn"
                  onClick={handleCreateInvite}
                  disabled={createInvite.isPending}
                >
                  {createInvite.isPending ? t('common.loading') : t('admin.create_invite')}
                </button>
              </div>
            </div>
          )}

          {invites?.items && invites.items.length > 0 ? (
            <div className="table-scroll">
              <table className="data-table">
                <thead>
                  <tr>
                    <th>{t('admin.email')}</th>
                    <th>{t('admin.invite_note')}</th>
                    <th>{t('admin.created')}</th>
                    <th>{t('admin.token')}</th>
                    <th>{t('common.actions')}</th>
                  </tr>
                </thead>
                <tbody>
                  {invites.items.map((inv) => (
                    <tr key={inv.token}>
                      <td>{inv.email || '\u2014'}</td>
                      <td>{inv.note || '\u2014'}</td>
                      <td title={fmt(inv.created_at, 'PPp')}>{relative(inv.created_at)}</td>
                      <td>
                        <code style={{ fontSize: 12 }}>{maskToken(inv.token)}</code>
                      </td>
                      <td>
                        <button
                          className="btn-sm btn-danger"
                          onClick={() => setDeleteTarget({ type: 'invite', id: inv.token })}
                        >
                          {t('common.delete')}
                        </button>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          ) : (
            <p className="text-muted">{t('admin.no_invites')}</p>
          )}
        </div>
      )}

      {/* Backups */}
      {tab === 'backups' && (
        <div className="card">
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 12 }}>
            <h3 style={{ display: 'flex', alignItems: 'center', gap: 6, margin: 0 }}>
              <IconClipboard /> {t('admin.tab_backups')}
            </h3>
            <button
              className="btn btn-add"
              onClick={() => triggerBackup.mutate()}
              disabled={triggerBackup.isPending}
            >
              {triggerBackup.isPending ? (
                <>{t('admin.backup_pending')}</>
              ) : triggerBackup.isSuccess ? (
                <><IconCheck /> {t('admin.backup_triggered')}</>
              ) : (
                <><IconRefresh /> {t('admin.trigger_backup')}</>
              )}
            </button>
          </div>

          {backups?.items && backups.items.length > 0 ? (
            <div className="table-scroll">
              <table className="data-table">
                <thead>
                  <tr>
                    <th>{t('common.date')}</th>
                    <th>{t('admin.size')}</th>
                    <th>{t('admin.encrypted')}</th>
                    <th>{t('admin.checksum')}</th>
                  </tr>
                </thead>
                <tbody>
                  {backups.items.map((b) => (
                    <tr key={b.id}>
                      <td title={fmt(b.backed_up_at, 'PPp')}>{relative(b.backed_up_at)}</td>
                      <td>{formatBytes(b.file_size_bytes)}</td>
                      <td>
                        <span className={`badge ${b.encrypted ? 'badge-active' : 'badge-inactive'}`}>
                          {b.encrypted ? t('admin.yes') : t('admin.no')}
                        </span>
                      </td>
                      <td>
                        <code style={{ fontSize: 12 }}>
                          {b.checksum_sha256 ? b.checksum_sha256.slice(0, 16) + '\u2026' : '\u2014'}
                        </code>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          ) : (
            <p className="text-muted">{t('admin.no_backups')}</p>
          )}
        </div>
      )}

      {/* Audit Log */}
      {tab === 'audit' && (
        <div className="card">
          <h3 style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
            <IconClipboard /> {t('admin.tab_audit')}
          </h3>
          {auditLog?.items && auditLog.items.length > 0 ? (
            <>
              <div className="table-scroll" style={{ maxHeight: 520, overflowY: 'auto' }}>
                <table className="data-table">
                  <thead>
                    <tr>
                      <th>{t('admin.timestamp')}</th>
                      <th>{t('admin.user')}</th>
                      <th>{t('admin.action')}</th>
                      <th>{t('admin.details')}</th>
                      <th>{t('admin.ip')}</th>
                    </tr>
                  </thead>
                  <tbody>
                    {auditLog.items.map((entry) => (
                      <tr key={entry.id}>
                        <td title={fmt(entry.created_at, 'dd. MMM yyyy, HH:mm')}>
                          {relative(entry.created_at)}
                        </td>
                        <td>{entry.user_id?.slice(0, 8) || '\u2014'}</td>
                        <td>
                          <code style={{ fontSize: 12 }}>{entry.action}</code>
                        </td>
                        <td style={{ maxWidth: 240, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                          {entry.resource}{entry.resource_id ? ` (${entry.resource_id.slice(0, 8)})` : ''}
                        </td>
                        <td>{entry.ip_address || '\u2014'}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>

              {/* Pagination */}
              <div style={{ display: 'flex', justifyContent: 'space-between', marginTop: 12 }}>
                <button
                  className="btn btn-secondary btn-sm"
                  onClick={() => setAuditOffset((o) => Math.max(0, o - auditLimit))}
                  disabled={auditOffset === 0 || auditFetching}
                >
                  {t('common.back')}
                </button>
                <span className="text-muted" style={{ fontSize: 13, alignSelf: 'center' }}>
                  {t('admin.showing_entries', {
                    from: auditOffset + 1,
                    to: auditOffset + (auditLog.items.length),
                  })}
                </span>
                <button
                  className="btn btn-secondary btn-sm"
                  onClick={() => setAuditOffset((o) => o + auditLimit)}
                  disabled={auditLog.items.length < auditLimit || auditFetching}
                >
                  {t('admin.load_more')}
                </button>
              </div>
            </>
          ) : (
            <p className="text-muted">{t('admin.no_audit_entries')}</p>
          )}
        </div>
      )}

      {/* Settings */}
      {tab === 'settings' && (
        <div>
          {/* Registration Mode */}
          <div className="card settings-section" style={{ marginBottom: 16 }}>
            <div className="security-header" style={{ marginBottom: 16 }}>
              <div className="security-icon"><IconGear /></div>
              <div>
                <div className="security-title">{t('admin.registration_mode')}</div>
                <div className="text-muted" style={{ fontSize: 13 }}>{t('admin.registration_desc')}</div>
              </div>
            </div>
            <div>
              <div className="toggle-switch">
                <div>
                  <div className="toggle-switch-label">{t('admin.reg_mode_open')}</div>
                  <div className="toggle-switch-desc">{t('admin.reg_open_desc')}</div>
                </div>
                <input type="checkbox" checked={settingsRegMode === 'open'} onChange={() => setSettingsRegMode('open')} />
              </div>
              <div className="toggle-switch">
                <div>
                  <div className="toggle-switch-label">{t('admin.reg_mode_invite')}</div>
                  <div className="toggle-switch-desc">{t('admin.reg_invite_desc')}</div>
                </div>
                <input type="checkbox" checked={settingsRegMode === 'invite_only'} onChange={() => setSettingsRegMode('invite_only')} />
              </div>
              <div className="toggle-switch">
                <div>
                  <div className="toggle-switch-label">{t('admin.reg_mode_closed')}</div>
                  <div className="toggle-switch-desc">{t('admin.reg_closed_desc')}</div>
                </div>
                <input type="checkbox" checked={settingsRegMode === 'closed'} onChange={() => setSettingsRegMode('closed')} />
              </div>
            </div>
          </div>

          {/* Password Policy */}
          <div className="card settings-section" style={{ marginBottom: 16 }}>
            <div className="security-header" style={{ marginBottom: 16 }}>
              <div className="security-icon"><IconShield /></div>
              <div>
                <div className="security-title">{t('admin.password_policy')}</div>
                <div className="text-muted" style={{ fontSize: 13 }}>{t('admin.password_policy_desc')}</div>
              </div>
            </div>
            <div className="settings-form-row">
              <label>{t('admin.min_passphrase_length')}</label>
              <input
                type="number"
                value={settingsMinPassLen}
                onChange={(e) => setSettingsMinPassLen(e.target.value)}
                placeholder="12"
                min={8}
                max={128}
              />
            </div>
            <div className="toggle-switch">
              <div>
                <div className="toggle-switch-label">{t('admin.require_uppercase')}</div>
                <div className="toggle-switch-desc">{t('admin.require_uppercase_desc')}</div>
              </div>
              <input type="checkbox" checked={settingsRequireUpper} onChange={(e) => setSettingsRequireUpper(e.target.checked)} />
            </div>
            <div className="toggle-switch">
              <div>
                <div className="toggle-switch-label">{t('admin.require_lowercase')}</div>
                <div className="toggle-switch-desc">{t('admin.require_lowercase_desc')}</div>
              </div>
              <input type="checkbox" checked={settingsRequireLower} onChange={(e) => setSettingsRequireLower(e.target.checked)} />
            </div>
            <div className="toggle-switch">
              <div>
                <div className="toggle-switch-label">{t('admin.require_numbers')}</div>
                <div className="toggle-switch-desc">{t('admin.require_numbers_desc')}</div>
              </div>
              <input type="checkbox" checked={settingsRequireNumber} onChange={(e) => setSettingsRequireNumber(e.target.checked)} />
            </div>
            <div className="toggle-switch">
              <div>
                <div className="toggle-switch-label">{t('admin.require_symbols')}</div>
                <div className="toggle-switch-desc">{t('admin.require_symbols_desc')}</div>
              </div>
              <input type="checkbox" checked={settingsRequireSymbol} onChange={(e) => setSettingsRequireSymbol(e.target.checked)} />
            </div>
          </div>

          {/* Default Storage Quota */}
          <div className="card settings-section" style={{ marginBottom: 16 }}>
            <div className="security-header" style={{ marginBottom: 16 }}>
              <div className="security-icon"><IconDatabase /></div>
              <div>
                <div className="security-title">{t('admin.default_quota')}</div>
                <div className="text-muted" style={{ fontSize: 13 }}>{t('admin.storage_desc')}</div>
              </div>
            </div>
            <div className="settings-form-row">
              <label>{t('admin.default_quota')}</label>
              <input
                type="number"
                value={settingsQuotaMb}
                onChange={(e) => setSettingsQuotaMb(e.target.value)}
                placeholder="512"
                min={0}
              />
              <span className="settings-unit">MB</span>
            </div>
          </div>

          {/* Instance Info */}
          <div className="card settings-section" style={{ marginBottom: 16 }}>
            <div className="security-header" style={{ marginBottom: 16 }}>
              <div className="security-icon"><IconShield /></div>
              <div>
                <div className="security-title">{t('admin.instance_settings')}</div>
                <div className="text-muted" style={{ fontSize: 13 }}>{t('admin.instance_desc')}</div>
              </div>
            </div>
            <div className="dash-list">
              <div className="dash-item">
                <span>{t('admin.version')}</span>
                <span className="dash-meta">{system?.version || '\u2014'}</span>
              </div>
              <div className="dash-item">
                <span>{t('admin.registration_mode')}</span>
                <span className="dash-meta">
                  <span className={`badge ${currentRegMode === 'open' ? 'badge-active' : currentRegMode === 'closed' ? 'badge-missed' : 'badge-scheduled'}`}>
                    {currentRegMode === 'open' ? t('admin.reg_mode_open') : currentRegMode === 'closed' ? t('admin.reg_mode_closed') : t('admin.reg_mode_invite')}
                  </span>
                </span>
              </div>
              <div className="dash-item">
                <span>{t('admin.user_count')}</span>
                <span className="dash-meta">{storage?.user_count ?? 0}</span>
              </div>
              <div className="dash-item">
                <span>{t('admin.database')}</span>
                <span className="dash-meta badge badge-active">{t('admin.connected')}</span>
              </div>
            </div>
          </div>

          {/* Save button */}
          <div style={{ display: 'flex', gap: 12, alignItems: 'center' }}>
            <button
              className="btn btn-add"
              onClick={handleSaveSettings}
              disabled={saveSettings.isPending}
            >
              {saveSettings.isPending ? t('common.loading') : t('admin.save_settings')}
            </button>
            {settingsSaved && (
              <span className="badge badge-active" style={{ fontSize: 13 }}>
                <IconCheck /> {t('common.save')}
              </span>
            )}
          </div>
        </div>
      )}

      {/* Confirm delete modal */}
      <ConfirmDelete
        open={deleteTarget !== null}
        title={
          deleteTarget?.type === 'user'
            ? t('admin.delete_user_title')
            : t('admin.delete_invite_title')
        }
        message={
          deleteTarget?.type === 'user'
            ? t('admin.delete_user_message')
            : t('admin.delete_invite_message')
        }
        onConfirm={handleConfirmDelete}
        onCancel={() => setDeleteTarget(null)}
        pending={deleteUser.isPending || deleteInvite.isPending}
      />
    </div>
  );
}
