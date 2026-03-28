import { useState } from 'react';
import { useTranslation } from 'react-i18next';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { useForm } from 'react-hook-form';
import { format, formatDistanceToNow } from 'date-fns';
import { ProfileSelector } from '../components/ProfileSelector';
import { useProfiles } from '../hooks/useProfiles';
import { diaryApi, EVENT_TYPES, type DiaryEvent } from '../api/diary';

const EVENT_ICONS: Record<string, string> = {
  accident: '🚑', illness: '🤒', surgery: '🏥', hospital_stay: '🛏',
  emergency: '🚨', doctor_visit: '👨‍⚕', vaccination: '💉',
  medication_change: '💊', symptom: '📋', other: '📝',
};

function severityColor(sev?: number): string {
  if (!sev) return '';
  if (sev >= 8) return 'status-critical';
  if (sev >= 6) return 'status-abnormal';
  if (sev >= 4) return 'status-borderline';
  return 'status-normal';
}

export function Diary() {
  const { t } = useTranslation();
  const { data: profilesData } = useProfiles();
  const profiles = profilesData || [];
  const [selectedProfile, setSelectedProfile] = useState('');
  const [showForm, setShowForm] = useState(false);
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

  const deleteMutation = useMutation({
    mutationFn: (id: string) => diaryApi.delete(profileId, id),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['diary', profileId] }),
  });

  const { register, handleSubmit, reset } = useForm<Partial<DiaryEvent>>();
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
        <div className="card form-card">
          <h3>New Diary Entry</h3>
          <form onSubmit={handleSubmit((data) => {
            createMutation.mutate({
              ...data,
              started_at: data.started_at || new Date().toISOString(),
            });
          })}>
            <div className="form-row">
              <div className="form-group">
                <label>Title *</label>
                <input type="text" {...register('title')} required />
              </div>
              <div className="form-group">
                <label>Type *</label>
                <select {...register('event_type')} required>
                  {EVENT_TYPES.map((t) => (
                    <option key={t} value={t}>{EVENT_ICONS[t]} {t.replace(/_/g, ' ')}</option>
                  ))}
                </select>
              </div>
            </div>
            <div className="form-row">
              <div className="form-group">
                <label>Date</label>
                <input type="datetime-local" {...register('started_at')} />
              </div>
              <div className="form-group">
                <label>Severity (1-10)</label>
                <input type="number" min="1" max="10" {...register('severity', { valueAsNumber: true })} />
              </div>
            </div>
            <div className="form-group">
              <label>Description</label>
              <textarea rows={3} {...register('description')} />
            </div>
            <div className="form-group">
              <label>Location</label>
              <input type="text" {...register('location')} />
            </div>
            <div className="form-actions">
              <button type="submit" className="btn btn-add" disabled={createMutation.isPending}>
                {t('common.save')}
              </button>
              <button type="button" className="btn btn-secondary" onClick={() => setShowForm(false)}>
                {t('common.cancel')}
              </button>
            </div>
          </form>
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
                  {EVENT_ICONS[event.event_type] || '📝'}
                </div>
                <div className="timeline-content">
                  <div className="timeline-header">
                    <span className="timeline-title">{event.title}</span>
                    <span className="timeline-date">
                      {format(new Date(event.started_at), 'MMM d, yyyy HH:mm')}
                      {' · '}
                      {formatDistanceToNow(new Date(event.started_at), { addSuffix: true })}
                    </span>
                  </div>
                  <div className="timeline-meta">
                    <span className="badge badge-info">
                      {event.event_type.replace(/_/g, ' ')}
                    </span>
                    {event.severity && (
                      <span className={`badge ${severityColor(event.severity)}`}>
                        Severity: {event.severity}/10
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
                  onClick={() => deleteMutation.mutate(event.id)}
                  title={t('common.delete')}
                >
                  ×
                </button>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}
