import { useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { formatDistanceToNow } from 'date-fns';
import { api } from '../api/client';

interface Notification {
  id: string;
  type: string;
  title: string;
  body?: string;
  read_at?: string;
  created_at: string;
}

interface NotificationListResponse {
  items: Notification[];
  total: number;
}

const TYPE_ICONS: Record<string, string> = {
  vaccination_due: '💉',
  lab_result_abnormal: '⚗',
  emergency_access_request: '🚨',
  session_new: '🔑',
  storage_quota_warning: '💾',
  family_invite: '👨‍👩‍👧',
  key_rotation_required: '🔄',
  export_ready: '📦',
  backup_failed: '⚠',
};

export function NotificationBell() {
  const [open, setOpen] = useState(false);
  const queryClient = useQueryClient();

  const { data } = useQuery({
    queryKey: ['notifications'],
    queryFn: () => api.get<NotificationListResponse>('/api/v1/notifications?limit=20'),
    refetchInterval: 60000, // Poll every minute
  });

  const markAllRead = useMutation({
    mutationFn: () => api.post('/api/v1/notifications/read-all'),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['notifications'] }),
  });

  const markRead = useMutation({
    mutationFn: (id: string) => api.post(`/api/v1/notifications/${id}/read`),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['notifications'] }),
  });

  const items = data?.items || [];
  const unreadCount = items.filter((n) => !n.read_at).length;

  return (
    <div className="notif-container">
      <button
        className="notif-bell"
        onClick={() => setOpen(!open)}
        aria-label={`Notifications${unreadCount > 0 ? ` (${unreadCount} unread)` : ''}`}
      >
        🔔
        {unreadCount > 0 && <span className="notif-badge">{unreadCount}</span>}
      </button>

      {open && (
        <div className="notif-dropdown">
          <div className="notif-header">
            <span className="notif-title">Notifications</span>
            {unreadCount > 0 && (
              <button className="notif-mark-all" onClick={() => markAllRead.mutate()}>
                Mark all read
              </button>
            )}
          </div>

          {items.length === 0 ? (
            <div className="notif-empty">No notifications</div>
          ) : (
            <div className="notif-list">
              {items.map((n) => (
                <div
                  key={n.id}
                  className={`notif-item ${n.read_at ? 'notif-read' : 'notif-unread'}`}
                  onClick={() => !n.read_at && markRead.mutate(n.id)}
                >
                  <span className="notif-icon">{TYPE_ICONS[n.type] || '📌'}</span>
                  <div className="notif-content">
                    <div className="notif-item-title">{n.title}</div>
                    {n.body && <div className="notif-body">{n.body}</div>}
                    <div className="notif-time">
                      {formatDistanceToNow(new Date(n.created_at), { addSuffix: true })}
                    </div>
                  </div>
                  {!n.read_at && <span className="notif-dot" />}
                </div>
              ))}
            </div>
          )}
        </div>
      )}
    </div>
  );
}
