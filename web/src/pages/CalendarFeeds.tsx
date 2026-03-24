import { useState } from 'react';
import { useTranslation } from 'react-i18next';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { useForm } from 'react-hook-form';
import { format } from 'date-fns';
import { api } from '../api/client';

interface CalendarFeed {
  id: string;
  name: string;
  profile_ids: string[];
  include_appointments: boolean;
  include_tasks: boolean;
  include_vaccinations: boolean;
  include_medications: boolean;
  include_labs: boolean;
  verbose_mode: boolean;
  last_polled_at?: string;
  created_at: string;
}

interface FeedWithToken extends CalendarFeed {
  token: string;
  url: string;
}

export function CalendarFeeds() {
  const { t } = useTranslation();
  const [showForm, setShowForm] = useState(false);
  const [copiedId, setCopiedId] = useState<string | null>(null);
  const [newFeedUrl, setNewFeedUrl] = useState<string | null>(null);
  const queryClient = useQueryClient();

  const { data, isLoading } = useQuery({
    queryKey: ['calendar-feeds'],
    queryFn: () => api.get<{ items: CalendarFeed[] }>('/api/v1/calendar/feeds'),
  });

  const createMutation = useMutation({
    mutationFn: (feed: Partial<CalendarFeed>) =>
      api.post<FeedWithToken>('/api/v1/calendar/feeds', feed),
    onSuccess: (data) => {
      queryClient.invalidateQueries({ queryKey: ['calendar-feeds'] });
      setNewFeedUrl(data.url);
      setShowForm(false);
      reset();
    },
  });

  const deleteMutation = useMutation({
    mutationFn: (id: string) => api.delete(`/api/v1/calendar/feeds/${id}`),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['calendar-feeds'] }),
  });

  const { register, handleSubmit, reset } = useForm<{
    name: string;
    include_appointments: boolean;
    include_tasks: boolean;
    include_vaccinations: boolean;
    include_medications: boolean;
    verbose_mode: boolean;
  }>({
    defaultValues: {
      include_appointments: true,
      include_tasks: true,
      include_vaccinations: true,
      include_medications: false,
      verbose_mode: false,
    },
  });

  const copyUrl = async (url: string, id: string) => {
    await navigator.clipboard.writeText(url);
    setCopiedId(id);
    setTimeout(() => setCopiedId(null), 2000);
  };

  const items = data?.items || [];

  return (
    <div className="page">
      <div className="page-header">
        <h2>Calendar Feeds</h2>
        <button className="btn btn-add" onClick={() => setShowForm(!showForm)}>+ New Feed</button>
      </div>

      {newFeedUrl && (
        <div className="card" style={{ borderLeft: '4px solid var(--color-success)', marginBottom: 16 }}>
          <h3>Feed Created</h3>
          <p style={{ fontSize: 13 }}>Copy this URL into your calendar app's "Subscribe to calendar" function:</p>
          <div className="feed-url-box">
            <code className="feed-url">{newFeedUrl}</code>
            <button className="btn-sm" onClick={() => { navigator.clipboard.writeText(newFeedUrl); }}>Copy</button>
          </div>
          <p className="text-muted" style={{ fontSize: 12, marginTop: 8 }}>
            This URL is shown once. You can regenerate it later from feed settings.
          </p>
          <button className="btn btn-secondary" onClick={() => setNewFeedUrl(null)} style={{ marginTop: 8 }}>Dismiss</button>
        </div>
      )}

      {showForm && (
        <div className="card form-card">
          <h3>Create Calendar Feed</h3>
          <form onSubmit={handleSubmit((data) => createMutation.mutate(data))}>
            <div className="form-group">
              <label>Feed Name *</label>
              <input type="text" {...register('name')} required placeholder="e.g. Family Health Calendar" />
            </div>
            <div className="form-group">
              <label>Include</label>
              <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
                <label className="toggle-label"><input type="checkbox" {...register('include_appointments')} /> Appointments</label>
                <label className="toggle-label"><input type="checkbox" {...register('include_tasks')} /> Task due dates</label>
                <label className="toggle-label"><input type="checkbox" {...register('include_vaccinations')} /> Vaccination reminders</label>
                <label className="toggle-label"><input type="checkbox" {...register('include_medications')} /> Medication reminders</label>
              </div>
            </div>
            <div className="form-group">
              <label className="toggle-label">
                <input type="checkbox" {...register('verbose_mode')} />
                Verbose titles (show actual names instead of "Medical Appointment")
              </label>
              <p className="text-muted" style={{ fontSize: 11, marginTop: 4 }}>
                If enabled, appointment details and medication names will be visible to your calendar provider.
              </p>
            </div>
            <div className="form-actions">
              <button type="submit" className="btn btn-add" disabled={createMutation.isPending}>{t('common.save')}</button>
              <button type="button" className="btn btn-secondary" onClick={() => setShowForm(false)}>{t('common.cancel')}</button>
            </div>
          </form>
        </div>
      )}

      <div className="card">
        <h3>Active Feeds</h3>
        {isLoading ? <p>{t('common.loading')}</p> : items.length === 0 ? (
          <p className="text-muted">No calendar feeds configured. Create one to subscribe in your calendar app.</p>
        ) : (
          <div className="med-list">
            {items.map((feed) => (
              <div key={feed.id} className="med-item">
                <div className="med-info">
                  <div className="med-name">{feed.name}</div>
                  <div className="med-details">
                    {[
                      feed.include_appointments && 'appointments',
                      feed.include_tasks && 'tasks',
                      feed.include_vaccinations && 'vaccinations',
                      feed.include_medications && 'medications',
                    ].filter(Boolean).join(', ')}
                    {feed.verbose_mode && ' · verbose'}
                  </div>
                  {feed.last_polled_at && (
                    <div className="med-meta">Last polled: {format(new Date(feed.last_polled_at), 'MMM d, HH:mm')}</div>
                  )}
                </div>
                <div className="med-actions">
                  <button className="btn-sm" onClick={() => deleteMutation.mutate(feed.id)}>Delete</button>
                </div>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}
