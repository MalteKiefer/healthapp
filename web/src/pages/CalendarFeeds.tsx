import { useState } from 'react';
import { useTranslation } from 'react-i18next';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { useForm } from 'react-hook-form';
import { ConfirmDelete } from '../components/ConfirmDelete';
import { useDateFormat } from '../hooks/useDateLocale';
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

interface EditFeedForm {
  name: string;
  include_appointments: boolean;
  include_tasks: boolean;
  include_vaccinations: boolean;
  include_medications: boolean;
  verbose_mode: boolean;
}

export function CalendarFeeds() {
  const { t } = useTranslation();
  const { fmt } = useDateFormat();
  const [showForm, setShowForm] = useState(false);
  const [newFeedUrl, setNewFeedUrl] = useState<string | null>(null);
  const [deleteTarget, setDeleteTarget] = useState<string | null>(null);
  const [editingFeed, setEditingFeed] = useState<CalendarFeed | null>(null);
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

  const updateMutation = useMutation({
    mutationFn: ({ id, data }: { id: string; data: Partial<EditFeedForm> }) =>
      api.patch(`/api/v1/calendar/feeds/${id}`, data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['calendar-feeds'] });
      setEditingFeed(null);
    },
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

  const {
    register: registerEdit,
    handleSubmit: handleEditSubmit,
    reset: resetEdit,
  } = useForm<EditFeedForm>();

  const handleOpenEdit = (feed: CalendarFeed) => {
    setEditingFeed(feed);
    resetEdit({
      name: feed.name,
      include_appointments: feed.include_appointments,
      include_tasks: feed.include_tasks,
      include_vaccinations: feed.include_vaccinations,
      include_medications: feed.include_medications,
      verbose_mode: feed.verbose_mode,
    });
  };

  const items = data?.items || [];

  return (
    <div className="page">
      <div className="page-header">
        <h2>{t('nav.calendar_feeds')}</h2>
        <button className="btn btn-add" onClick={() => setShowForm(!showForm)}>{t('calendar.new_feed')}</button>
      </div>

      {newFeedUrl && (
        <div className="card" style={{ borderLeft: '4px solid var(--color-success)', marginBottom: 16 }}>
          <h3>{t('calendar.feed_created')}</h3>
          <p style={{ fontSize: 13 }}>{t('calendar.copy_url_hint')}</p>
          <div className="feed-url-box">
            <code className="feed-url">{newFeedUrl}</code>
            <button className="btn-sm" onClick={() => { navigator.clipboard.writeText(newFeedUrl); }}>{t('common.copy')}</button>
          </div>
          <p className="text-muted" style={{ fontSize: 12, marginTop: 8 }}>
            {t('calendar.url_shown_once')}
          </p>
          <button className="btn btn-secondary" onClick={() => setNewFeedUrl(null)} style={{ marginTop: 8 }}>{t('common.dismiss')}</button>
        </div>
      )}

      {showForm && (
        <div className="modal-overlay" onClick={() => setShowForm(false)}>
          <div className="modal" onClick={(e) => e.stopPropagation()}>
            <div className="modal-header">
              <h3>{t('calendar.create_feed')}</h3>
              <button className="btn-icon-sm" onClick={() => setShowForm(false)}>×</button>
            </div>
            <form id="feed-create-form" onSubmit={handleSubmit((data) => createMutation.mutate(data))}>
              <div className="modal-body">
                <div className="form-group">
                  <label>{t('calendar.feed_name')} *</label>
                  <input type="text" {...register('name')} required placeholder={t('calendar.feed_name_placeholder')} />
                </div>
                <div className="form-group">
                  <label>{t('calendar.include')}</label>
                  <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
                    <label className="toggle-label"><input type="checkbox" {...register('include_appointments')} /> {t('nav.appointments')}</label>
                    <label className="toggle-label"><input type="checkbox" {...register('include_tasks')} /> {t('calendar.task_due_dates')}</label>
                    <label className="toggle-label"><input type="checkbox" {...register('include_vaccinations')} /> {t('calendar.vaccination_reminders')}</label>
                    <label className="toggle-label"><input type="checkbox" {...register('include_medications')} /> {t('calendar.medication_reminders')}</label>
                  </div>
                </div>
                <div className="form-group">
                  <label className="toggle-label">
                    <input type="checkbox" {...register('verbose_mode')} />
                    {t('calendar.verbose_titles')}
                  </label>
                  <p className="text-muted" style={{ fontSize: 11, marginTop: 4 }}>
                    {t('calendar.verbose_warning')}
                  </p>
                </div>
              </div>
              <div className="modal-footer">
                <button type="submit" className="btn btn-add" disabled={createMutation.isPending}>{t('common.save')}</button>
                <button type="button" className="btn btn-secondary" onClick={() => setShowForm(false)}>{t('common.cancel')}</button>
              </div>
            </form>
          </div>
        </div>
      )}

      <div className="card">
        <h3>{t('calendar.active_feeds')}</h3>
        {isLoading ? <p>{t('common.loading')}</p> : items.length === 0 ? (
          <p className="text-muted">{t('calendar.no_feeds')}</p>
        ) : (
          <div className="med-list">
            {items.map((feed) => (
              <div key={feed.id} className="med-item" style={{ cursor: 'pointer' }} onClick={() => handleOpenEdit(feed)}>
                <div className="med-info">
                  <div className="med-name">{feed.name}</div>
                  <div className="med-details">
                    {[
                      feed.include_appointments && t('calendar.detail_appointments'),
                      feed.include_tasks && t('calendar.detail_tasks'),
                      feed.include_vaccinations && t('calendar.detail_vaccinations'),
                      feed.include_medications && t('calendar.detail_medications'),
                    ].filter(Boolean).join(', ')}
                    {feed.verbose_mode && ` · ${t('calendar.detail_verbose')}`}
                  </div>
                  {feed.last_polled_at && (
                    <div className="med-meta">{t('calendar.last_polled')}: {fmt(feed.last_polled_at, 'dd. MMM, HH:mm')}</div>
                  )}
                </div>
                <div className="med-actions">
                  <button className="btn-sm" onClick={(e) => { e.stopPropagation(); handleOpenEdit(feed); }}>{t('common.edit')}</button>
                  <button className="btn-sm" onClick={(e) => { e.stopPropagation(); setDeleteTarget(feed.id); }}>{t('common.delete')}</button>
                </div>
              </div>
            ))}
          </div>
        )}
      </div>

      {editingFeed && (
        <div className="modal-overlay" onClick={() => setEditingFeed(null)}>
          <div className="modal" onClick={(e) => e.stopPropagation()}>
            <div className="modal-header">
              <h3>{t('calendar.edit_feed')}</h3>
              <button className="btn-icon-sm" onClick={() => setEditingFeed(null)}>&times;</button>
            </div>
            <form id="feed-edit-form" onSubmit={handleEditSubmit((formData) => updateMutation.mutate({ id: editingFeed.id, data: formData }))}>
              <div className="modal-body">
                <div className="form-group">
                  <label>{t('calendar.feed_name')} *</label>
                  <input type="text" {...registerEdit('name')} required placeholder={t('calendar.feed_name_placeholder')} />
                </div>
                <div className="form-group">
                  <label>{t('calendar.include')}</label>
                  <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
                    <label className="toggle-label"><input type="checkbox" {...registerEdit('include_appointments')} /> {t('nav.appointments')}</label>
                    <label className="toggle-label"><input type="checkbox" {...registerEdit('include_tasks')} /> {t('calendar.task_due_dates')}</label>
                    <label className="toggle-label"><input type="checkbox" {...registerEdit('include_vaccinations')} /> {t('calendar.vaccination_reminders')}</label>
                    <label className="toggle-label"><input type="checkbox" {...registerEdit('include_medications')} /> {t('calendar.medication_reminders')}</label>
                  </div>
                </div>
                <div className="form-group">
                  <label className="toggle-label">
                    <input type="checkbox" {...registerEdit('verbose_mode')} />
                    {t('calendar.verbose_titles')}
                  </label>
                  <p className="text-muted" style={{ fontSize: 11, marginTop: 4 }}>
                    {t('calendar.verbose_warning')}
                  </p>
                </div>
              </div>
              <div className="modal-footer">
                <button type="submit" className="btn btn-add" disabled={updateMutation.isPending}>{t('common.save')}</button>
                <button type="button" className="btn btn-secondary" onClick={() => setEditingFeed(null)}>{t('common.cancel')}</button>
              </div>
            </form>
          </div>
        </div>
      )}

      <ConfirmDelete
        open={!!deleteTarget}
        onConfirm={() => { deleteMutation.mutate(deleteTarget!); setDeleteTarget(null); }}
        onCancel={() => setDeleteTarget(null)}
        pending={deleteMutation.isPending}
      />
    </div>
  );
}
