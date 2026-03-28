import { useState } from 'react';
import { useTranslation } from 'react-i18next';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { useForm } from 'react-hook-form';
import { isPast, isToday, isTomorrow, addDays } from 'date-fns';
import { ProfileSelector } from '../components/ProfileSelector';
import { useDateFormat } from '../hooks/useDateLocale';
import { ConfirmDelete } from '../components/ConfirmDelete';
import { useProfiles } from '../hooks/useProfiles';
import { appointmentsApi, type Appointment } from '../api/appointments';

const TYPES = [
  'examination', 'surgery', 'vaccination', 'follow_up', 'lab',
  'specialist', 'general_practice', 'therapy', 'other',
];

export function Appointments() {
  const { t } = useTranslation();
  const { fmt } = useDateFormat();
  const { data: profilesData } = useProfiles();
  const profiles = profilesData || [];
  const [selectedProfile, setSelectedProfile] = useState('');
  const [showUpcoming, setShowUpcoming] = useState(true);
  const [showForm, setShowForm] = useState(false);
  const [deleteTarget, setDeleteTarget] = useState<string | null>(null);
  const queryClient = useQueryClient();

  const profileId = selectedProfile || profiles[0]?.id || '';

  const { data, isLoading } = useQuery({
    queryKey: ['appointments', profileId, showUpcoming],
    queryFn: () => showUpcoming ? appointmentsApi.upcoming(profileId) : appointmentsApi.list(profileId),
    enabled: !!profileId,
  });

  const createMutation = useMutation({
    mutationFn: (appt: Partial<Appointment>) => appointmentsApi.create(profileId, appt),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['appointments', profileId] });
      setShowForm(false);
      reset();
    },
  });

  const completeMutation = useMutation({
    mutationFn: (id: string) => appointmentsApi.complete(profileId, id),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['appointments', profileId] }),
  });

  const deleteMutation = useMutation({
    mutationFn: (id: string) => appointmentsApi.delete(profileId, id),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['appointments', profileId] }),
  });

  const { register, handleSubmit, reset } = useForm<Partial<Appointment>>();

  const items = data?.items || [];

  return (
    <div className="page">
      <div className="page-header">
        <h2>{t('nav.appointments')}</h2>
        <div className="page-actions">
          <ProfileSelector selectedId={profileId} onSelect={setSelectedProfile} />
          <label className="toggle-label">
            <input
              type="checkbox"
              checked={showUpcoming}
              onChange={(e) => setShowUpcoming(e.target.checked)}
            />
            Upcoming only
          </label>
          <button className="btn btn-add" onClick={() => setShowForm(!showForm)}>
            + {t('common.add')}
          </button>
        </div>
      </div>

      {showForm && (
        <div className="card form-card">
          <h3>{t('appointments.add')}</h3>
          <form onSubmit={handleSubmit((data) => createMutation.mutate(data))}>
            <div className="form-row">
              <div className="form-group">
                <label>{t('common.title')} *</label>
                <input type="text" {...register('title')} required />
              </div>
              <div className="form-group">
                <label>{t('common.type')} *</label>
                <select {...register('appointment_type')} required>
                  {TYPES.map((type) => <option key={type} value={type}>{t('appointments.type_' + type)}</option>)}
                </select>
              </div>
            </div>
            <div className="form-row">
              <div className="form-group">
                <label>{t('vitals.date_time')} *</label>
                <input type="datetime-local" {...register('scheduled_at')} required />
              </div>
              <div className="form-group">
                <label>{t('appointments.duration')}</label>
                <input type="number" {...register('duration_minutes', { valueAsNumber: true })} />
              </div>
            </div>
            <div className="form-group">
              <label>{t('appointments.location')}</label>
              <input type="text" {...register('location')} />
            </div>
            <div className="form-group">
              <label>{t('appointments.preparation')}</label>
              <textarea rows={2} {...register('preparation_notes')} placeholder="e.g. Arrive fasting" />
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
          <div className="appt-list">
            {items.map((appt) => {
              const date = new Date(appt.scheduled_at);
              const dateLabel = isToday(date) ? 'Today' : isTomorrow(date) ? 'Tomorrow'
                : isPast(date) ? 'Past' : date < addDays(new Date(), 7) ? 'This week' : '';

              return (
                <div key={appt.id} className={`appt-item ${isPast(date) ? 'appt-past' : ''}`}>
                  <div className="appt-date">
                    <div className="appt-day">{fmt(date, 'dd')}</div>
                    <div className="appt-month">{fmt(date, 'MMM')}</div>
                    <div className="appt-time">{fmt(date, 'HH:mm')}</div>
                  </div>
                  <div className="appt-info">
                    <div className="appt-title">{appt.title}</div>
                    <div className="appt-type">{appt.appointment_type.replace(/_/g, ' ')}</div>
                    {appt.location && <div className="appt-location">{appt.location}</div>}
                    {dateLabel && <span className="badge badge-info">{dateLabel}</span>}
                  </div>
                  <div className="appt-actions">
                    <span className={`badge badge-${appt.status}`}>{appt.status}</span>
                    {appt.status === 'scheduled' && (
                      <button
                        className="btn-sm"
                        onClick={() => completeMutation.mutate(appt.id)}
                      >
                        Complete
                      </button>
                    )}
                    <button
                      className="btn-icon-sm"
                      onClick={() => setDeleteTarget(appt.id)}
                      title={t('common.delete')}
                    >×</button>
                  </div>
                </div>
              );
            })}
          </div>
        )}
      </div>

      <ConfirmDelete
        open={!!deleteTarget}
        onConfirm={() => { deleteMutation.mutate(deleteTarget!); setDeleteTarget(null); }}
        onCancel={() => setDeleteTarget(null)}
        pending={deleteMutation.isPending}
      />
    </div>
  );
}
