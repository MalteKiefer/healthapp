import { useState, useEffect } from 'react';
import { useTranslation } from 'react-i18next';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { useForm } from 'react-hook-form';
import { isPast, isToday, isTomorrow, addDays } from 'date-fns';
import { ProfileSelector } from '../components/ProfileSelector';
import { useDateFormat } from '../hooks/useDateLocale';
import { ContactPicker } from '../components/ContactPicker';
import { ConfirmDelete } from '../components/ConfirmDelete';
import { useProfiles } from '../hooks/useProfiles';
import { appointmentsApi, type Appointment } from '../api/appointments';
import { api } from '../api/client';

interface Contact { id: string; name: string; specialty?: string; facility?: string; address?: string; street?: string; postal_code?: string; city?: string; country?: string }

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
  const [sortCol, setSortCol] = useState<string>('scheduled_at');
  const [sortDir, setSortDir] = useState<'asc'|'desc'>('desc');
  const queryClient = useQueryClient();

  const profileId = selectedProfile || profiles[0]?.id || '';

  const { data, isLoading } = useQuery({
    queryKey: ['appointments', profileId, showUpcoming],
    queryFn: () => showUpcoming ? appointmentsApi.upcoming(profileId) : appointmentsApi.list(profileId),
    enabled: !!profileId,
  });

  const { data: contactsData } = useQuery({
    queryKey: ['contacts', profileId],
    queryFn: () => api.get<{ items: Contact[] }>(`/api/v1/profiles/${profileId}/contacts`),
    enabled: !!profileId,
  });
  const contacts = contactsData?.items || [];

  const cleanAppt = (appt: Partial<Appointment>) => {
    const cleaned = { ...appt };
    if (!cleaned.doctor_id) delete cleaned.doctor_id;
    if (!cleaned.location) delete cleaned.location;
    if (!cleaned.preparation_notes) delete cleaned.preparation_notes;
    if (!cleaned.duration_minutes) delete cleaned.duration_minutes;
    // datetime-local gives "2026-04-01T10:00" — backend needs full ISO 8601
    if (cleaned.scheduled_at && !cleaned.scheduled_at.includes('Z') && !cleaned.scheduled_at.includes('+')) {
      cleaned.scheduled_at = new Date(cleaned.scheduled_at).toISOString();
    }
    return cleaned;
  };

  const createMutation = useMutation({
    mutationFn: (appt: Partial<Appointment>) => appointmentsApi.create(profileId, cleanAppt(appt)),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['appointments', profileId] });
      setShowForm(false);
      reset();
      setDoctorDisplay('');
    },
  });

  const updateMutation = useMutation({
    mutationFn: ({ id, data }: { id: string; data: Partial<Appointment> }) =>
      appointmentsApi.update(profileId, id, cleanAppt(data)),
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

  const { register, handleSubmit, reset, setValue } = useForm<Partial<Appointment>>();
  const { register: editRegister, handleSubmit: editHandleSubmit, reset: editReset, setValue: editSetValue } = useForm<Partial<Appointment>>();
  const [doctorDisplay, setDoctorDisplay] = useState('');
  const [editDoctorDisplay, setEditDoctorDisplay] = useState('');

  useEffect(() => {
    if (editTarget) {
      editReset({
        title: editTarget.title,
        appointment_type: editTarget.appointment_type,
        scheduled_at: editTarget.scheduled_at ? editTarget.scheduled_at.slice(0, 16) : '',
        duration_minutes: editTarget.duration_minutes,
        doctor_id: editTarget.doctor_id,
        location: editTarget.location,
        preparation_notes: editTarget.preparation_notes,
      });
      const doc = contacts.find((c) => c.id === editTarget.doctor_id);
      setEditDoctorDisplay(doc ? (doc.specialty ? `${doc.name} — ${doc.specialty}` : doc.name) : '');
    }
  }, [editTarget, editReset, contacts]);

  const items = data?.items || [];

  const sortedItems = [...items].sort((a, b) => {
    const aVal = (a as unknown as Record<string,unknown>)[sortCol];
    const bVal = (b as unknown as Record<string,unknown>)[sortCol];
    if (aVal == null && bVal == null) return 0;
    if (aVal == null) return 1;
    if (bVal == null) return -1;
    const cmp = typeof aVal === 'string' ? aVal.localeCompare(bVal as string) : (aVal as number) - (bVal as number);
    return sortDir === 'asc' ? cmp : -cmp;
  });

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
              <button className="modal-close" onClick={() => setShowForm(false)}>&times;</button>
            </div>
            <div className="modal-body">
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
                <div className="form-row">
                  <ContactPicker
                    profileId={profileId}
                    value={doctorDisplay}
                    onChange={(name, contact) => {
                      setDoctorDisplay(name);
                      setValue('doctor_id', contact?.id || '');
                      if (contact?.address) setValue('location', contact.address);
                    }}
                    label={t('appointments.doctor')}
                  />
                  <div className="form-group">
                    <label>{t('appointments.location')}</label>
                    <input type="text" {...register('location')} />
                  </div>
                </div>
                <div className="form-group">
                  <label>{t('appointments.preparation')}</label>
                  <textarea rows={2} {...register('preparation_notes')} placeholder={t('appointments.preparation_placeholder')} />
                </div>
              </form>
            </div>
            <div className="modal-footer">
              <button type="button" className="btn btn-secondary" onClick={() => setShowForm(false)}>
                {t('common.cancel')}
              </button>
              <button type="submit" form="appt-create-form" className="btn btn-add" disabled={createMutation.isPending}>
                {t('common.save')}
              </button>
            </div>
          </div>
        </div>
      )}

      <div className="card">
        {isLoading ? (
          <p>{t('common.loading')}</p>
        ) : items.length === 0 ? (
          <p className="text-muted">{t('common.no_data')}</p>
        ) : (
          <>
          <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 12 }}>
            <label style={{ fontSize: 14 }}>{t('common.sort_by')}:</label>
            <select value={sortCol} onChange={(e) => setSortCol(e.target.value)} style={{ fontSize: 14 }}>
              <option value="scheduled_at">{t('common.date')}</option>
              <option value="title">{t('common.title')}</option>
              <option value="appointment_type">{t('common.type')}</option>
            </select>
            <button className="btn-icon-sm" onClick={() => setSortDir(d => d === 'asc' ? 'desc' : 'asc')} title={sortDir === 'asc' ? 'Descending' : 'Ascending'}>
              {sortDir === 'asc' ? '\u2191' : '\u2193'}
            </button>
          </div>
          <div className="appt-list">
            {sortedItems.map((appt) => {
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
                  <div
                    className="appt-info"
                    style={{ cursor: 'pointer' }}
                    onClick={() => setEditTarget(appt)}
                    onKeyDown={(e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); setEditTarget(appt); } }}
                    role="button"
                    tabIndex={0}
                  >
                    <div className="appt-title">{appt.title}</div>
                    <div className="appt-type">{t('appointments.type_' + appt.appointment_type)}</div>
                    {appt.doctor_id && (() => { const doc = contacts.find(c => c.id === appt.doctor_id); return doc ? <div className="appt-location">{doc.name}{doc.specialty ? ` — ${doc.specialty}` : ''}</div> : null; })()}
                    {appt.location && <div className="appt-location">{appt.location}</div>}
                    {dateLabel && <span className="badge badge-info">{dateLabel}</span>}
                  </div>
                  <div className="appt-actions">
                    <span className={`badge badge-${appt.status}`}>{t('appointments.status_' + appt.status)}</span>
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
          </>
        )}
      </div>

      {editTarget && (
        <div className="modal-overlay" onClick={() => setEditTarget(null)}>
          <div className="modal" onClick={(e) => e.stopPropagation()}>
            <div className="modal-header">
              <h3>{t('appointments.edit')}</h3>
              <button className="modal-close" onClick={() => setEditTarget(null)}>&times;</button>
            </div>
            <div className="modal-body">
              <form id="appt-edit-form" onSubmit={editHandleSubmit((data) => updateMutation.mutate({ id: editTarget.id, data }))}>
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
                <div className="form-row">
                  <ContactPicker
                    profileId={profileId}
                    value={editDoctorDisplay}
                    onChange={(name, contact) => {
                      setEditDoctorDisplay(name);
                      editSetValue('doctor_id', contact?.id || '');
                      if (contact?.address) editSetValue('location', contact.address);
                    }}
                    label={t('appointments.doctor')}
                  />
                  <div className="form-group">
                    <label>{t('appointments.location')}</label>
                    <input type="text" {...editRegister('location')} />
                  </div>
                </div>
                <div className="form-group">
                  <label>{t('appointments.preparation')}</label>
                  <textarea rows={2} {...editRegister('preparation_notes')} />
                </div>
              </form>
            </div>
            <div className="modal-footer">
              <button type="button" className="btn btn-secondary" onClick={() => setEditTarget(null)}>
                {t('common.cancel')}
              </button>
              <button type="submit" form="appt-edit-form" className="btn btn-add" disabled={updateMutation.isPending}>
                {t('common.save')}
              </button>
            </div>
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
