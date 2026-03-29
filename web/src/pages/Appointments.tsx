import { useState, useEffect } from 'react';
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
  const [editTarget, setEditTarget] = useState<Appointment | null>(null);
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

  const updateMutation = useMutation({
    mutationFn: ({ id, data }: { id: string; data: Partial<Appointment> }) =>
      appointmentsApi.update(profileId, id, data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['appointments', profileId] });
      setEditTarget(null);
      editReset();
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
  const { register: editRegister, handleSubmit: editHandleSubmit, reset: editReset } = useForm<Partial<Appointment>>();

  useEffect(() => {
    if (editTarget) {
      editReset({
        title: editTarget.title,
        appointment_type: editTarget.appointment_type,
        scheduled_at: editTarget.scheduled_at ? editTarget.scheduled_at.slice(0, 16) : '',
        duration_minutes: editTarget.duration_minutes,
        location: editTarget.location,
        preparation_notes: editTarget.preparation_notes,
      });
    }
  }, [editTarget, editReset]);

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
            {t('appointments.upcoming_only')}
          </label>
          <button className="btn btn-add" onClick={() => setShowForm(!showForm)}>
            + {t('common.add')}
          </button>
        </div>
      </div>

      {showForm && (
        <div className="modal-overlay" onClick={() => setShowForm(false)}>
          <div className="modal" onClick={(e) => e.stopPropagation()}>
            <div className="modal-header">
              <h3>{t('appointments.add')}</h3>
              <button className="btn-icon-sm" onClick={() => setShowForm(false)}>×</button>
            </div>
            <form id="appt-create-form" onSubmit={handleSubmit((data) => createMutation.mutate(data))}>
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
              const dateLabel = isToday(date) ? t('appointments.today') : isTomorrow(date) ? t('appointments.tomorrow')
                : isPast(date) ? t('appointments.past') : date < addDays(new Date(), 7) ? t('appointments.this_week') : '';

              return (
                <div key={appt.id} className={`appt-item ${isPast(date) ? 'appt-past' : ''}`}>
                  <div className="appt-date">
                    <div className="appt-day">{fmt(date, 'dd')}</div>
                    <div className="appt-month">{fmt(date, 'MMM')}</div>
                    <div className="appt-time">{fmt(date, 'HH:mm')}</div>
                  </div>
                  <div className="appt-info" style={{ cursor: 'pointer' }} onClick={() => setEditTarget(appt)}>
                    <div className="appt-title">{appt.title}</div>
                    <div className="appt-type">{t('appointments.type_' + appt.appointment_type)}</div>
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
                        {t('appointments.complete')}
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

      {editTarget && (
        <div className="modal-overlay" onClick={() => setEditTarget(null)}>
          <div className="modal" onClick={(e) => e.stopPropagation()}>
            <div className="modal-header">
              <h3>{t('appointments.edit')}</h3>
              <button className="btn-icon-sm" onClick={() => setEditTarget(null)}>×</button>
            </div>
            <form onSubmit={editHandleSubmit((data) => updateMutation.mutate({ id: editTarget.id, data }))}>
              <div className="form-row">
                <div className="form-group">
                  <label>{t('common.title')} *</label>
                  <input type="text" {...editRegister('title')} required />
                </div>
                <div className="form-group">
                  <label>{t('common.type')} *</label>
                  <select {...editRegister('appointment_type')} required>
                    {TYPES.map((type) => <option key={type} value={type}>{t('appointments.type_' + type)}</option>)}
                  </select>
                </div>
              </div>
              <div className="form-row">
                <div className="form-group">
                  <label>{t('vitals.date_time')} *</label>
                  <input type="datetime-local" {...editRegister('scheduled_at')} required />
                </div>
                <div className="form-group">
                  <label>{t('appointments.duration')}</label>
                  <input type="number" {...editRegister('duration_minutes', { valueAsNumber: true })} />
                </div>
              </div>
              <div className="form-group">
                <label>{t('appointments.location')}</label>
                <input type="text" {...editRegister('location')} />
              </div>
              <div className="form-group">
                <label>{t('appointments.preparation')}</label>
                <textarea rows={2} {...editRegister('preparation_notes')} />
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
