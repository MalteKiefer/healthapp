import { useState, useEffect } from 'react';
import { useTranslation } from 'react-i18next';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { useForm } from 'react-hook-form';
import { ProfileSelector } from '../components/ProfileSelector';
import { useDateFormat } from '../hooks/useDateLocale';
import { ConfirmDelete } from '../components/ConfirmDelete';
import { useProfiles } from '../hooks/useProfiles';
import { diaryApi, EVENT_TYPES, type DiaryEvent } from '../api/diary';

const TIMELINE_ICON = (
  <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
    <circle cx="12" cy="12" r="10" /><polyline points="12 6 12 12 16 14" />
  </svg>
);

function severityColor(sev?: number): string {
  if (!sev) return '';
  if (sev >= 8) return 'status-critical';
  if (sev >= 6) return 'status-abnormal';
  if (sev >= 4) return 'status-borderline';
  return 'status-normal';
}

export function Diary() {
  const { t } = useTranslation();
  const { fmt, relative } = useDateFormat();
  const { data: profilesData } = useProfiles();
  const profiles = profilesData || [];
  const [selectedProfile, setSelectedProfile] = useState('');
  const [showForm, setShowForm] = useState(false);
  const [deleteTarget, setDeleteTarget] = useState<string | null>(null);
  const [editTarget, setEditTarget] = useState<DiaryEvent | null>(null);
  const queryClient = useQueryClient();

  const profileId = selectedProfile || profiles[0]?.id || '';

  const { data, isLoading } = useQuery({
    queryKey: ['diary', profileId],
    queryFn: () => diaryApi.list(profileId, { limit: 50 }),
    enabled: !!profileId,
  });

  const createMutation = useMutation({
    mutationFn: (event: Partial<DiaryEvent>) => diaryApi.create(profileId, event),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['diary', profileId] });
      setShowForm(false);
      reset();
    },
  });

  const updateMutation = useMutation({
    mutationFn: ({ id, data }: { id: string; data: Partial<DiaryEvent> }) =>
      diaryApi.update(profileId, id, data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['diary', profileId] });
      setEditTarget(null);
      editReset();
    },
  });

  const deleteMutation = useMutation({
    mutationFn: (id: string) => diaryApi.delete(profileId, id),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['diary', profileId] }),
  });

  const { register, handleSubmit, reset } = useForm<Partial<DiaryEvent>>();
  const { register: editRegister, handleSubmit: editHandleSubmit, reset: editReset } = useForm<Partial<DiaryEvent>>();

  useEffect(() => {
    if (editTarget) {
      editReset({
        title: editTarget.title,
        event_type: editTarget.event_type,
        started_at: editTarget.started_at ? editTarget.started_at.slice(0, 16) : '',
        severity: editTarget.severity,
        description: editTarget.description,
        location: editTarget.location,
      });
    }
  }, [editTarget, editReset]);
  const items = data?.items || [];

  return (
    <div className="page">
      <div className="page-header">
        <h2>{t('nav.diary')}</h2>
        <div className="page-actions">
          <ProfileSelector selectedId={profileId} onSelect={setSelectedProfile} />
          <button className="btn btn-add" onClick={() => setShowForm(!showForm)}>
            + {t('common.add')}
          </button>
        </div>
      </div>

      {showForm && (
        <div className="modal-overlay" onClick={() => setShowForm(false)}>
          <div className="modal" onClick={(e) => e.stopPropagation()}>
            <div className="modal-header">
              <h3>{t('diary.new_entry')}</h3>
              <button className="btn-icon-sm" onClick={() => setShowForm(false)} aria-label={t('common.close')}>×</button>
            </div>
            <form id="diary-create-form" onSubmit={handleSubmit((data) => {
              const cleaned: Record<string, unknown> = { ...data };
              // Convert datetime-local to ISO and clean empty/NaN values
              cleaned.started_at = data.started_at ? new Date(data.started_at).toISOString() : new Date().toISOString();
              if (typeof cleaned.severity === 'number' && isNaN(cleaned.severity as number)) delete cleaned.severity;
              if (cleaned.severity === '' || cleaned.severity === undefined) delete cleaned.severity;
              if (!cleaned.description) delete cleaned.description;
              if (!cleaned.location) delete cleaned.location;
              createMutation.mutate(cleaned as Partial<DiaryEvent>);
            })}>
              <div className="modal-body">
                <div className="form-row">
                  <div className="form-group">
                    <label>{t('diary.title_label')} *</label>
                    <input type="text" {...register('title')} required />
                  </div>
                  <div className="form-group">
                    <label>{t('diary.type_label')} *</label>
                    <select {...register('event_type')} required>
                      {EVENT_TYPES.map((et) => (
                        <option key={et} value={et}>{t('diary.event_' + et)}</option>
                      ))}
                    </select>
                  </div>
                </div>
                <div className="form-row">
                  <div className="form-group">
                    <label>{t('common.date')}</label>
                    <input type="datetime-local" {...register('started_at')} />
                  </div>
                  <div className="form-group">
                    <label>{t('diary.severity')}</label>
                    <input type="number" min="1" max="10" {...register('severity', { valueAsNumber: true })} />
                  </div>
                </div>
                <div className="form-group">
                  <label>{t('diary.description')}</label>
                  <textarea rows={3} {...register('description')} />
                </div>
                <div className="form-group">
                  <label>{t('diary.location')}</label>
                  <input type="text" {...register('location')} />
                </div>
              </div>
              <div className="modal-footer">
                <button type="submit" className="btn btn-add" disabled={createMutation.isPending}>
                  {t('common.save')}
                </button>
                <button type="button" className="btn btn-secondary" onClick={() => setShowForm(false)}>
                  {t('common.cancel')}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      <div className="card">
        {isLoading ? (
          <p>{t('common.loading')}</p>
        ) : items.length === 0 ? (
          <p className="text-muted">{t('common.no_data')}</p>
        ) : (
          <div className="timeline">
            {items.map((event) => (
              <div key={event.id} className="timeline-item">
                <div className="timeline-icon">
                  {TIMELINE_ICON}
                </div>
                <div
                  className="timeline-content"
                  style={{ cursor: 'pointer' }}
                  onClick={() => setEditTarget(event)}
                  onKeyDown={(e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); setEditTarget(event); } }}
                  role="button"
                  tabIndex={0}
                >
                  <div className="timeline-header">
                    <span className="timeline-title">{event.title}</span>
                    <span className="timeline-date">
                      {fmt(event.started_at, 'dd. MMM yyyy, HH:mm')}
                      {' · '}
                      {relative(event.started_at)}
                    </span>
                  </div>
                  <div className="timeline-meta">
                    <span className="badge badge-info">
                      {t('diary.event_' + event.event_type)}
                    </span>
                    {event.severity && (
                      <span className={`badge ${severityColor(event.severity)}`}>
                        {t('diary.severity_short')}: {event.severity}/10
                      </span>
                    )}
                  </div>
                  {event.description && (
                    <p className="timeline-desc">{event.description}</p>
                  )}
                  {event.location && (
                    <p className="timeline-location">{event.location}</p>
                  )}
                </div>
                <button
                  className="btn-icon-sm"
                  onClick={() => setDeleteTarget(event.id)}
                  title={t('common.delete')}
                  aria-label={t('common.delete')}
                >
                  ×
                </button>
              </div>
            ))}
          </div>
        )}
      </div>

      {editTarget && (
        <div className="modal-overlay" onClick={() => setEditTarget(null)}>
          <div className="modal" onClick={(e) => e.stopPropagation()}>
            <div className="modal-header">
              <h3>{t('diary.edit')}</h3>
              <button className="btn-icon-sm" onClick={() => setEditTarget(null)} aria-label={t('common.close')}>×</button>
            </div>
            <form onSubmit={editHandleSubmit((data) => updateMutation.mutate({ id: editTarget.id, data }))}>
              <div className="form-row">
                <div className="form-group">
                  <label>{t('diary.title_label')} *</label>
                  <input type="text" {...editRegister('title')} required />
                </div>
                <div className="form-group">
                  <label>{t('diary.type_label')} *</label>
                  <select {...editRegister('event_type')} required>
                    {EVENT_TYPES.map((et) => (
                      <option key={et} value={et}>{t('diary.event_' + et)}</option>
                    ))}
                  </select>
                </div>
              </div>
              <div className="form-row">
                <div className="form-group">
                  <label>{t('common.date')}</label>
                  <input type="datetime-local" {...editRegister('started_at')} />
                </div>
                <div className="form-group">
                  <label>{t('diary.severity')}</label>
                  <input type="number" min="1" max="10" {...editRegister('severity', { valueAsNumber: true })} />
                </div>
              </div>
              <div className="form-group">
                <label>{t('diary.description')}</label>
                <textarea rows={3} {...editRegister('description')} />
              </div>
              <div className="form-group">
                <label>{t('diary.location')}</label>
                <input type="text" {...editRegister('location')} />
              </div>
              <div className="form-actions">
                <button type="submit" className="btn btn-add" disabled={updateMutation.isPending}>
                  {t('common.save')}
                </button>
                <button type="button" className="btn btn-secondary" onClick={() => setEditTarget(null)}>
                  {t('common.cancel')}
                </button>
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
