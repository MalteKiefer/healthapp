import { useTranslation } from 'react-i18next';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { api } from '../api/client';
import { useAuthStore } from '../store/auth';

interface SystemHealth {
  database: { pool_size: number; idle: number; total: number };
  redis: { status: string; db_size: number };
  version: string;
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
  checksum_sha256: string;
}

export function Admin() {
  const { t } = useTranslation();
  const { role } = useAuthStore();
  const queryClient = useQueryClient();

  const { data: system } = useQuery({
    queryKey: ['admin-system'],
    queryFn: () => api.get<SystemHealth>('/api/v1/admin/system'),
    enabled: role === 'admin',
  });

  const { data: users } = useQuery({
    queryKey: ['admin-users'],
    queryFn: () => api.get<{ items: UserInfo[] }>('/api/v1/admin/users'),
    enabled: role === 'admin',
  });

  const { data: backups } = useQuery({
    queryKey: ['admin-backups'],
    queryFn: () => api.get<{ items: BackupInfo[] }>('/api/v1/admin/backups'),
    enabled: role === 'admin',
  });

  const { data: storage } = useQuery({
    queryKey: ['admin-storage'],
    queryFn: () => api.get<{ total_used_bytes: number; total_quota_bytes: number; user_count: number }>('/api/v1/admin/storage'),
    enabled: role === 'admin',
  });

  const disableUser = useMutation({
    mutationFn: (id: string) => api.post(`/api/v1/admin/users/${id}/disable`),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['admin-users'] }),
  });

  const enableUser = useMutation({
    mutationFn: (id: string) => api.post(`/api/v1/admin/users/${id}/enable`),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['admin-users'] }),
  });

  if (role !== 'admin') {
    return <div className="page"><h2>Access Denied</h2><p>Administrator privileges required.</p></div>;
  }

  const formatBytes = (bytes: number) => {
    if (bytes < 1048576) return `${(bytes / 1024).toFixed(0)} KB`;
    if (bytes < 1073741824) return `${(bytes / 1048576).toFixed(1)} MB`;
    return `${(bytes / 1073741824).toFixed(2)} GB`;
  };

  return (
    <div className="page">
      <h2>{t('nav.admin')}</h2>

      {/* System Health */}
      <div className="dashboard-grid" style={{ marginBottom: 16 }}>
        <div className="card">
          <h3>System</h3>
          <div className="dash-list">
            <div className="dash-item"><span>Version</span><span className="dash-meta">{system?.version || '—'}</span></div>
            <div className="dash-item"><span>Database</span><span className="dash-meta badge badge-active">Connected</span></div>
            <div className="dash-item"><span>Redis</span><span className="dash-meta badge badge-active">{system?.redis?.status || 'OK'}</span></div>
            <div className="dash-item"><span>DB Pool</span><span className="dash-meta">{system?.database?.total || 0} connections</span></div>
          </div>
        </div>

        <div className="card">
          <h3>Storage</h3>
          <div className="dash-list">
            <div className="dash-item"><span>Total Used</span><span className="dash-meta">{formatBytes(storage?.total_used_bytes || 0)}</span></div>
            <div className="dash-item"><span>Users</span><span className="dash-meta">{storage?.user_count || 0}</span></div>
          </div>
        </div>

        <div className="card">
          <h3>Backups</h3>
          {backups?.items && backups.items.length > 0 ? (
            <div className="dash-list">
              <div className="dash-item"><span>Latest</span><span className="dash-meta">{new Date(backups.items[0].backed_up_at).toLocaleString()}</span></div>
              <div className="dash-item"><span>Size</span><span className="dash-meta">{formatBytes(backups.items[0].file_size_bytes)}</span></div>
            </div>
          ) : (
            <p className="text-muted">No backups recorded</p>
          )}
        </div>
      </div>

      {/* Users */}
      <div className="card">
        <h3>Users</h3>
        {users?.items && users.items.length > 0 ? (
          <div className="table-scroll">
            <table className="data-table">
              <thead><tr><th>Email</th><th>Name</th><th>Role</th><th>Storage</th><th>Status</th><th>Actions</th></tr></thead>
              <tbody>
                {users.items.map((u) => (
                  <tr key={u.id}>
                    <td>{u.email}</td>
                    <td>{u.display_name}</td>
                    <td><span className={`badge ${u.role === 'admin' ? 'badge-scheduled' : 'badge-info'}`}>{u.role}</span></td>
                    <td>{u.used_bytes != null ? formatBytes(u.used_bytes) : '—'}</td>
                    <td><span className={`badge ${u.is_disabled ? 'badge-missed' : 'badge-active'}`}>{u.is_disabled ? 'Disabled' : 'Active'}</span></td>
                    <td>
                      {u.is_disabled ? (
                        <button className="btn-sm" onClick={() => enableUser.mutate(u.id)}>Enable</button>
                      ) : (
                        <button className="btn-sm" onClick={() => disableUser.mutate(u.id)}>Disable</button>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        ) : (
          <p className="text-muted">{t('common.no_data')}</p>
        )}
      </div>
    </div>
  );
}
