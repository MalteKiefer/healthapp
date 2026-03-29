import { useState } from 'react';
import { useTranslation } from 'react-i18next';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { useForm } from 'react-hook-form';
import { useDateFormat } from '../hooks/useDateLocale';
import { ProfileSelector } from '../components/ProfileSelector';
import { ConfirmDelete } from '../components/ConfirmDelete';
import { useProfiles } from '../hooks/useProfiles';
import { medicationsApi, type Medication } from '../api/medications';
import { api } from '../api/client';

interface Contact { id: string; name: string; specialty?: string }
interface MedIntake { id: string; medication_id: string; scheduled_at: string; taken_at?: string; skipped_reason?: string; notes?: string; created_at: string }

const ROUTES = ['oral', 'injection', 'topical', 'inhalation', 'sublingual', 'rectal', 'other'];

function toLocalDatetime(d: Date = new Date()): string {
  const pad = (n: number) => n.toString().padStart(2, '0');
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

export function Medications() {
  const { t } = useTranslation();
  const { data: profilesData } = useProfiles();
  const profiles = profilesData || [];
  const [selectedProfile, setSelectedProfile] = useState('');
  const [showActive, setShowActive] = useState(true);
  const [showForm, setShowForm] = useState(false);
  const [deleteTarget, setDeleteTarget] = useState<string | null>(null);
  const [editTarget, setEditTarget] = useState<Medication | null>(null);
  const [selectedMed, setSelectedMed] = useState<Medication | null>(null);
  const [intakeMed, setIntakeMed] = useState<Medication | null>(null);
  const [showIntakeModal, setShowIntakeModal] = useState(false);
  const [intakeDatetime, setIntakeDatetime] = useState(toLocalDatetime());
  const [lastTaken, setLastTaken] = useState<string | null>(null);
  const { fmt, relative } = useDateFormat();
  const queryClient = useQueryClient();
  const profileId = selectedProfile || profiles[0]?.id || '';

  // Queries
  const { data, isLoading } = useQuery({
    queryKey: ['medications', profileId, showActive],
    queryFn: () => showActive ? medicationsApi.active(profileId) : medicationsApi.list(profileId),
    enabled: !!profileId,
  });
  const { data: contactsData } = useQuery({
    queryKey: ['contacts', profileId],
    queryFn: () => api.get<{ items: Contact[] }>(`/api/v1/profiles/${profileId}/contacts`),
    enabled: !!profileId && (showForm || !!editTarget),
  });
  const contacts = contactsData?.items || [];
  const { data: intakeData } = useQuery({
    queryKey: ['med-intake', profileId, selectedMed?.id],
    queryFn: () => api.get<{ items: MedIntake[]; total: number }>(`/api/v1/profiles/${profileId}/medications/${selectedMed!.id}/intake?limit=200`),
    enabled: !!profileId && !!selectedMed,
  });
  const intakes = intakeData?.items || [];

  // Mutations
  const createMutation = useMutation({
    mutationFn: (med: Partial<Medication>) => medicationsApi.create(profileId, med),
    onSuccess: () => { queryClient.invalidateQueries({ queryKey: ['medications', profileId] }); setShowForm(false); reset(); },
  });
  const deleteMutation = useMutation({
    mutationFn: (id: string) => medicationsApi.delete(profileId, id),
    onSuccess: (_data, deletedId) => { queryClient.invalidateQueries({ queryKey: ['medications', profileId] }); if (selectedMed?.id === deletedId) setSelectedMed(null); },
  });
  const logIntake = useMutation({
    mutationFn: (datetime: string) => {
      const medId = selectedMed?.id || intakeMed?.id;
      if (!medId) throw new Error('no med');
      const iso = new Date(datetime).toISOString();
      return api.post(`/api/v1/profiles/${profileId}/medications/${medId}/intake`, { scheduled_at: iso, taken_at: iso });
    },
    onSuccess: () => {
      const medId = selectedMed?.id || intakeMed?.id;
      queryClient.invalidateQueries({ queryKey: ['med-intake'] });
      setShowIntakeModal(false);
      setIntakeMed(null);
      if (medId) { setLastTaken(medId); setTimeout(() => setLastTaken(null), 2000); }
    },
  });
  const updateMutation = useMutation({
    mutationFn: (data: Partial<Medication> & { id: string }) => medicationsApi.update(profileId, data.id, data),
    onSuccess: () => { queryClient.invalidateQueries({ queryKey: ['medications', profileId] }); setEditTarget(null); editReset(); },
  });

  const { register, handleSubmit, reset } = useForm<Partial<Medication>>();
  const { register: editRegister, handleSubmit: editHandleSubmit, reset: editReset } = useForm<Partial<Medication>>({
    values: editTarget ? {
      name: editTarget.name, dosage: editTarget.dosage ?? '', unit: editTarget.unit ?? '',
      frequency: editTarget.frequency ?? '', route: editTarget.route ?? '',
      prescribed_by: editTarget.prescribed_by ?? '', reason: editTarget.reason ?? '',
      started_at: editTarget.started_at ? editTarget.started_at.slice(0, 10) : '',
      ended_at: editTarget.ended_at ? editTarget.ended_at.slice(0, 10) : '',
    } : undefined,
  });

  const items = data?.items || [];

  // ── Detail View ──
  if (selectedMed) {
    return (
      <div className="page">
        <div className="page-header">
          <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
            <button className="btn-icon" onClick={() => setSelectedMed(null)} title={t('common.back')}>
              <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><polyline points="15 18 9 12 15 6"/></svg>
            </button>
            <div>
              <h2 style={{ margin: 0 }}>{selectedMed.name}</h2>
              <span className="text-muted" style={{ fontSize: 13 }}>
                {[selectedMed.dosage, selectedMed.unit, selectedMed.frequency].filter(Boolean).join(' · ')}
              </span>
            </div>
          </div>
          <div className="page-actions">
            <span className={`badge ${selectedMed.ended_at ? 'badge-inactive' : 'badge-active'}`}>
              {selectedMed.ended_at ? t('common.inactive') : t('common.active')}
            </span>
            <button className="btn btn-secondary" onClick={() => setEditTarget(selectedMed)}>
              <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" style={{ marginRight: 6 }}><path d="M11 4H4a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-7"/><path d="M18.5 2.5a2.121 2.121 0 0 1 3 3L12 15l-4 1 1-4 9.5-9.5z"/></svg>
              {t('common.edit')}
            </button>
            {!selectedMed.ended_at && (
              <button className="btn btn-add" onClick={() => { setIntakeDatetime(toLocalDatetime()); setShowIntakeModal(true); }}>
                <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round" style={{ marginRight: 6 }}><polyline points="20 6 9 17 4 12"/></svg>
                {t('medications.mark_taken')}
              </button>
            )}
          </div>
        </div>

        {/* Info Card */}
        <div className="card" style={{ marginBottom: 16 }}>
          <div className="table-scroll">
            <table className="data-table">
              <tbody>
                <tr><td className="text-muted" style={{ width: 180, fontWeight: 500 }}>{t('medications.dosage')}</td><td>{[selectedMed.dosage, selectedMed.unit].filter(Boolean).join(' ') || '—'}</td></tr>
                <tr><td className="text-muted" style={{ fontWeight: 500 }}>{t('medications.frequency')}</td><td>{selectedMed.frequency || '—'}</td></tr>
                <tr><td className="text-muted" style={{ fontWeight: 500 }}>{t('medications.route')}</td><td>{selectedMed.route ? t('medications.route_' + selectedMed.route) : '—'}</td></tr>
                <tr><td className="text-muted" style={{ fontWeight: 500 }}>{t('medications.prescribed_by')}</td><td>{selectedMed.prescribed_by || '—'}</td></tr>
                <tr><td className="text-muted" style={{ fontWeight: 500 }}>{t('medications.reason')}</td><td>{selectedMed.reason || '—'}</td></tr>
                <tr><td className="text-muted" style={{ fontWeight: 500 }}>{t('medications.started_at')}</td><td>{selectedMed.started_at ? fmt(selectedMed.started_at, 'dd. MMMM yyyy') : '—'}</td></tr>
                {selectedMed.ended_at && <tr><td className="text-muted" style={{ fontWeight: 500 }}>{t('medications.ended_at')}</td><td>{fmt(selectedMed.ended_at, 'dd. MMMM yyyy')}</td></tr>}
              </tbody>
            </table>
          </div>
        </div>

        {/* Intake History */}
        <div className="card">
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 12 }}>
            <h3 style={{ margin: 0 }}>{t('medications.intake_history')}</h3>
            {lastTaken === selectedMed.id && <span className="badge badge-active">{t('medications.taken')}</span>}
          </div>
          {intakes.length === 0 ? (
            <p className="text-muted">{t('medications.no_intakes')}</p>
          ) : (
            <div className="table-scroll">
              <table className="data-table">
                <thead>
                  <tr>
                    <th>{t('common.date')}</th>
                    <th>{t('common.time')}</th>
                    <th>{t('common.status')}</th>
                    <th>{t('common.notes')}</th>
                  </tr>
                </thead>
                <tbody>
                  {intakes.map((intake) => {
                    const d = intake.taken_at || intake.scheduled_at;
                    return (
                      <tr key={intake.id}>
                        <td>{fmt(d, 'dd. MMM yyyy')}</td>
                        <td>
                          {fmt(d, 'HH:mm')}
                          <span className="text-muted" style={{ fontSize: 11, marginLeft: 8 }}>{relative(d)}</span>
                        </td>
                        <td>
                          {intake.taken_at ? (
                            <span className="badge badge-active">{t('medications.taken')}</span>
                          ) : intake.skipped_reason ? (
                            <span className="badge badge-missed">{t('medications.skipped')}</span>
                          ) : (
                            <span className="badge badge-scheduled">{t('medications.scheduled')}</span>
                          )}
                        </td>
                        <td>{intake.notes || intake.skipped_reason || '—'}</td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          )}
        </div>

        {/* Intake Modal */}
        {showIntakeModal && (
          <div className="modal-overlay" onClick={() => setShowIntakeModal(false)}>
            <div className="modal" onClick={(e) => e.stopPropagation()} style={{ maxWidth: 380 }}>
              <div className="modal-header">
                <h3>{t('medications.mark_taken')}</h3>
                <button className="modal-close" onClick={() => setShowIntakeModal(false)}>&times;</button>
              </div>
              <div className="modal-body">
                <p className="text-muted" style={{ marginBottom: 12 }}>{selectedMed.name} — {[selectedMed.dosage, selectedMed.unit].filter(Boolean).join(' ')}</p>
                <div className="form-group">
                  <label>{t('common.date')} & {t('common.time')}</label>
                  <input type="datetime-local" value={intakeDatetime} onChange={(e) => setIntakeDatetime(e.target.value)} />
                </div>
              </div>
              <div className="modal-footer">
                <button className="btn btn-secondary" onClick={() => setShowIntakeModal(false)}>{t('common.cancel')}</button>
                <button className="btn btn-add" onClick={() => logIntake.mutate(intakeDatetime)} disabled={logIntake.isPending}>
                  {logIntake.isPending ? t('common.loading') : t('common.save')}
                </button>
              </div>
            </div>
          </div>
        )}

        {/* Edit Modal (reused) */}
        {editTarget && renderEditModal()}

        <ConfirmDelete open={!!deleteTarget} onConfirm={() => { deleteMutation.mutate(deleteTarget!); setDeleteTarget(null); }} onCancel={() => setDeleteTarget(null)} pending={deleteMutation.isPending} />
      </div>
    );
  }

  // ── List View ──
  return (
    <div className="page">
      <div className="page-header">
        <h2>{t('nav.medications')}</h2>
        <div className="page-actions">
          <ProfileSelector selectedId={profileId} onSelect={setSelectedProfile} />
          <label className="toggle-label">
            <input type="checkbox" checked={showActive} onChange={(e) => setShowActive(e.target.checked)} />
            {t('medications.active_only')}
          </label>
          <button className="btn btn-add" onClick={() => setShowForm(true)}>+ {t('common.add')}</button>
        </div>
      </div>

      <div className="card">
        {isLoading ? <p>{t('common.loading')}</p> : items.length === 0 ? <p className="text-muted">{t('common.no_data')}</p> : (
          <div className="table-scroll">
            <table className="data-table med-table">
              <thead>
                <tr>
                  <th>{t('common.name')}</th>
                  <th className="col-dosage">{t('medications.dosage')}</th>
                  <th className="col-frequency">{t('medications.frequency')}</th>
                  <th className="col-route">{t('medications.route')}</th>
                  <th className="col-prescribed">{t('medications.prescribed_by')}</th>
                  <th className="col-since">{t('common.since')}</th>
                  <th>{t('common.status')}</th>
                  <th></th>
                </tr>
              </thead>
              <tbody>
                {items.map((med) => (
                  <tr key={med.id} onClick={() => setSelectedMed(med)} style={{ cursor: 'pointer' }}>
                    <td><strong>{med.name}</strong></td>
                    <td className="col-dosage">{[med.dosage, med.unit].filter(Boolean).join(' ') || '—'}</td>
                    <td className="col-frequency">{med.frequency || '—'}</td>
                    <td className="col-route">{med.route ? t('medications.route_' + med.route) : '—'}</td>
                    <td className="col-prescribed">{med.prescribed_by || '—'}</td>
                    <td className="col-since">{med.started_at ? fmt(med.started_at, 'dd. MMM yy') : '—'}</td>
                    <td><span className={`badge ${med.ended_at ? 'badge-inactive' : 'badge-active'}`}>{med.ended_at ? t('common.inactive') : t('common.active')}</span></td>
                    <td>
                      <div style={{ display: 'flex', gap: 4 }}>
                        {!med.ended_at && (
                          <button className="btn-icon-sm" onClick={(e) => { e.stopPropagation(); setIntakeMed(med); setIntakeDatetime(toLocalDatetime()); setShowIntakeModal(true); }} title={t('medications.mark_taken')} style={{ color: lastTaken === med.id ? 'var(--color-success)' : undefined }}>
                            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round"><polyline points="20 6 9 17 4 12"/></svg>
                          </button>
                        )}
                        <button className="btn-icon-sm" onClick={(e) => { e.stopPropagation(); setEditTarget(med); }} title={t('medications.edit')}>
                          <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M11 4H4a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-7"/><path d="M18.5 2.5a2.121 2.121 0 0 1 3 3L12 15l-4 1 1-4 9.5-9.5z"/></svg>
                        </button>
                        <button className="btn-icon-sm" onClick={(e) => { e.stopPropagation(); setDeleteTarget(med.id); }} title={t('common.delete')}>×</button>
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>

      {/* Create Modal */}
      {showForm && (
        <div className="modal-overlay" onClick={() => setShowForm(false)}>
          <div className="modal" onClick={(e) => e.stopPropagation()}>
            <div className="modal-header">
              <h3>{t('medications.add')}</h3>
              <button className="modal-close" onClick={() => setShowForm(false)}>&times;</button>
            </div>
            <div className="modal-body">
              <form id="med-create-form" onSubmit={handleSubmit((d) => createMutation.mutate(d))}>
                <div className="form-row">
                  <div className="form-group"><label>{t('common.name')} *</label><input type="text" {...register('name')} required /></div>
                  <div className="form-group"><label>{t('medications.dosage')}</label><input type="text" {...register('dosage')} placeholder={t('medications.placeholder_dosage')} /></div>
                  <div className="form-group"><label>{t('medications.unit')}</label><input type="text" {...register('unit')} placeholder={t('medications.placeholder_unit')} /></div>
                </div>
                <div className="form-row">
                  <div className="form-group"><label>{t('medications.frequency')}</label><input type="text" {...register('frequency')} placeholder={t('medications.placeholder_frequency')} /></div>
                  <div className="form-group"><label>{t('medications.route')}</label>
                    <select {...register('route')}><option value="">{t('common.select')}</option>{ROUTES.map((r) => <option key={r} value={r}>{t('medications.route_' + r)}</option>)}</select>
                  </div>
                  <div className="form-group"><label>{t('medications.prescribed_by')}</label>
                    <input type="text" {...register('prescribed_by')} list="contacts-list" autoComplete="off" />
                    <datalist id="contacts-list">{contacts.map((c) => <option key={c.id} value={c.name}>{c.specialty ? `${c.name} — ${c.specialty}` : c.name}</option>)}</datalist>
                  </div>
                </div>
                <div className="form-group"><label>{t('medications.reason')}</label><input type="text" {...register('reason')} /></div>
              </form>
            </div>
            <div className="modal-footer">
              <button className="btn btn-secondary" onClick={() => setShowForm(false)}>{t('common.cancel')}</button>
              <button type="submit" form="med-create-form" className="btn btn-add" disabled={createMutation.isPending}>{createMutation.isPending ? t('common.loading') : t('common.save')}</button>
            </div>
          </div>
        </div>
      )}

      {editTarget && renderEditModal()}

      {/* Intake Modal from list */}
      {showIntakeModal && intakeMed && (
        <div className="modal-overlay" onClick={() => { setShowIntakeModal(false); setIntakeMed(null); }}>
          <div className="modal" onClick={(e) => e.stopPropagation()} style={{ maxWidth: 380 }}>
            <div className="modal-header">
              <h3>{t('medications.mark_taken')}</h3>
              <button className="modal-close" onClick={() => { setShowIntakeModal(false); setIntakeMed(null); }}>&times;</button>
            </div>
            <div className="modal-body">
              <p className="text-muted" style={{ marginBottom: 12 }}>{intakeMed.name} — {[intakeMed.dosage, intakeMed.unit].filter(Boolean).join(' ')}</p>
              <div className="form-group">
                <label>{t('common.date')} & {t('common.time')}</label>
                <input type="datetime-local" value={intakeDatetime} onChange={(e) => setIntakeDatetime(e.target.value)} />
              </div>
            </div>
            <div className="modal-footer">
              <button className="btn btn-secondary" onClick={() => { setShowIntakeModal(false); setIntakeMed(null); }}>{t('common.cancel')}</button>
              <button className="btn btn-add" onClick={() => logIntake.mutate(intakeDatetime)} disabled={logIntake.isPending}>
                {logIntake.isPending ? t('common.loading') : t('common.save')}
              </button>
            </div>
          </div>
        </div>
      )}

      <ConfirmDelete open={!!deleteTarget} onConfirm={() => { deleteMutation.mutate(deleteTarget!); setDeleteTarget(null); }} onCancel={() => setDeleteTarget(null)} pending={deleteMutation.isPending} />
    </div>
  );

  // ── Edit Modal (shared) ──
  function renderEditModal() {
    if (!editTarget) return null;
    return (
      <div className="modal-overlay" onClick={() => setEditTarget(null)}>
        <div className="modal" onClick={(e) => e.stopPropagation()}>
          <div className="modal-header">
            <h3>{t('medications.edit')}</h3>
            <button className="modal-close" onClick={() => setEditTarget(null)}>&times;</button>
          </div>
          <div className="modal-body">
            <form id="med-edit-form" onSubmit={editHandleSubmit((d) => updateMutation.mutate({ ...d, id: editTarget.id }))}>
              <div className="form-row">
                <div className="form-group"><label>{t('common.name')} *</label><input type="text" {...editRegister('name')} required /></div>
                <div className="form-group"><label>{t('medications.dosage')}</label><input type="text" {...editRegister('dosage')} /></div>
                <div className="form-group"><label>{t('medications.unit')}</label><input type="text" {...editRegister('unit')} /></div>
              </div>
              <div className="form-row">
                <div className="form-group"><label>{t('medications.frequency')}</label><input type="text" {...editRegister('frequency')} /></div>
                <div className="form-group"><label>{t('medications.route')}</label>
                  <select {...editRegister('route')}><option value="">{t('common.select')}</option>{ROUTES.map((r) => <option key={r} value={r}>{t('medications.route_' + r)}</option>)}</select>
                </div>
                <div className="form-group"><label>{t('medications.prescribed_by')}</label><input type="text" {...editRegister('prescribed_by')} list="edit-contacts-list" autoComplete="off" />
                  <datalist id="edit-contacts-list">{contacts.map((c) => <option key={c.id} value={c.name}>{c.specialty ? `${c.name} — ${c.specialty}` : c.name}</option>)}</datalist>
                </div>
              </div>
              <div className="form-group"><label>{t('medications.reason')}</label><input type="text" {...editRegister('reason')} /></div>
              <div className="form-row">
                <div className="form-group"><label>{t('medications.started_at')}</label><input type="date" {...editRegister('started_at')} /></div>
                <div className="form-group"><label>{t('medications.ended_at')}</label><input type="date" {...editRegister('ended_at')} /></div>
              </div>
            </form>
          </div>
          <div className="modal-footer">
            <button className="btn btn-secondary" onClick={() => setEditTarget(null)}>{t('common.cancel')}</button>
            <button type="submit" form="med-edit-form" className="btn btn-add" disabled={updateMutation.isPending}>{updateMutation.isPending ? t('common.loading') : t('common.save')}</button>
          </div>
        </div>
      </div>
    );
  }
}
