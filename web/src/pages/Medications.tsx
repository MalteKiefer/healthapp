import { useReducer, useMemo } from 'react';
import { compareByColumn } from '../utils/sorting';
import { useTranslation } from 'react-i18next';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { useForm } from 'react-hook-form';
import { useDateFormat } from '../hooks/useDateLocale';
import { ProfileSelector } from '../components/ProfileSelector';
import { ConfirmDelete } from '../components/ConfirmDelete';
import { useProfiles } from '../hooks/useProfiles';
import { medicationsApi, type Medication } from '../api/medications';
import { ContactPicker } from '../components/ContactPicker';
import { useFocusTrap } from '../hooks/useFocusTrap';

const ROUTES = ['oral', 'injection', 'topical', 'inhalation', 'sublingual', 'rectal', 'other'];

function toLocalDatetime(d: Date = new Date()): string {
  const pad = (n: number) => n.toString().padStart(2, '0');
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

// ── UI State & Reducer ──

interface MedsUIState {
  selectedProfile: string;
  showActive: boolean;
  sortCol: string;
  sortDir: 'asc' | 'desc';
  intakeSortCol: string;
  intakeSortDir: 'asc' | 'desc';
  showForm: boolean;
  deleteTarget: string | null;
  editTarget: Medication | null;
  selectedMed: Medication | null;
  intakeMed: Medication | null;
  showIntakeModal: boolean;
  intakeDatetime: string;
  lastTaken: string | null;
  deleteIntakeTarget: string | null;
}

type MedsAction =
  | { type: 'SELECT_PROFILE'; id: string }
  | { type: 'SET_SHOW_ACTIVE'; value: boolean }
  | { type: 'SET_SORT'; col: string }
  | { type: 'SET_INTAKE_SORT'; col: string }
  | { type: 'SHOW_FORM' }
  | { type: 'HIDE_FORM' }
  | { type: 'SET_DELETE_TARGET'; id: string | null }
  | { type: 'SET_EDIT_TARGET'; med: Medication | null }
  | { type: 'SELECT_MED'; med: Medication | null }
  | { type: 'OPEN_INTAKE_MODAL'; med: Medication | null }
  | { type: 'CLOSE_INTAKE_MODAL' }
  | { type: 'SET_INTAKE_DATETIME'; value: string }
  | { type: 'SET_LAST_TAKEN'; id: string | null }
  | { type: 'SET_DELETE_INTAKE_TARGET'; id: string | null };

const initialMedsUIState: MedsUIState = {
  selectedProfile: '',
  showActive: true,
  sortCol: 'name',
  sortDir: 'asc',
  intakeSortCol: 'date',
  intakeSortDir: 'desc',
  showForm: false,
  deleteTarget: null,
  editTarget: null,
  selectedMed: null,
  intakeMed: null,
  showIntakeModal: false,
  intakeDatetime: toLocalDatetime(),
  lastTaken: null,
  deleteIntakeTarget: null,
};

function medsReducer(state: MedsUIState, action: MedsAction): MedsUIState {
  switch (action.type) {
    case 'SELECT_PROFILE':
      return { ...state, selectedProfile: action.id };
    case 'SET_SHOW_ACTIVE':
      return { ...state, showActive: action.value };
    case 'SET_SORT':
      if (state.sortCol === action.col) {
        return { ...state, sortDir: state.sortDir === 'asc' ? 'desc' : 'asc' };
      }
      return { ...state, sortCol: action.col, sortDir: 'asc' };
    case 'SET_INTAKE_SORT':
      if (state.intakeSortCol === action.col) {
        return { ...state, intakeSortDir: state.intakeSortDir === 'asc' ? 'desc' : 'asc' };
      }
      return { ...state, intakeSortCol: action.col, intakeSortDir: 'desc' };
    case 'SHOW_FORM':
      return { ...state, showForm: true };
    case 'HIDE_FORM':
      return { ...state, showForm: false };
    case 'SET_DELETE_TARGET':
      return { ...state, deleteTarget: action.id };
    case 'SET_EDIT_TARGET':
      return { ...state, editTarget: action.med };
    case 'SELECT_MED':
      return { ...state, selectedMed: action.med };
    case 'OPEN_INTAKE_MODAL':
      return { ...state, intakeMed: action.med, intakeDatetime: toLocalDatetime(), showIntakeModal: true };
    case 'CLOSE_INTAKE_MODAL':
      return { ...state, showIntakeModal: false, intakeMed: null };
    case 'SET_INTAKE_DATETIME':
      return { ...state, intakeDatetime: action.value };
    case 'SET_LAST_TAKEN':
      return { ...state, lastTaken: action.id };
    case 'SET_DELETE_INTAKE_TARGET':
      return { ...state, deleteIntakeTarget: action.id };
    default:
      return state;
  }
}

export function Medications() {
  const { t } = useTranslation();
  const { data: profilesData } = useProfiles();
  const profiles = profilesData || [];

  const [ui, dispatch] = useReducer(medsReducer, initialMedsUIState);

  const { fmt, relative } = useDateFormat();
  const createModalRef = useFocusTrap(ui.showForm);
  const intakeModalRef = useFocusTrap(ui.showIntakeModal);
  const queryClient = useQueryClient();
  const profileId = ui.selectedProfile || profiles[0]?.id || '';

  // Queries — always fetch full list; active filtering done client-side
  const { data: allData, isLoading } = useQuery({
    queryKey: ['medications', profileId],
    queryFn: () => medicationsApi.list(profileId),
    enabled: !!profileId,
  });
  const data = useMemo(() => {
    if (!allData) return allData;
    if (!ui.showActive) return allData;
    const activeItems = allData.items.filter((m: Medication) => !m.ended_at);
    return { items: activeItems, total: activeItems.length };
  }, [allData, ui.showActive]);
  const { data: intakeData } = useQuery({
    queryKey: ['med-intake', profileId, ui.selectedMed?.id],
    queryFn: () => medicationsApi.listIntake(profileId, ui.selectedMed!.id),
    enabled: !!profileId && !!ui.selectedMed,
  });
  const intakes = intakeData?.items || [];
  // Adherence endpoint removed (410 Gone) — computed client-side if needed.
  const adherenceData: { rate?: number } | undefined = undefined;

  // Mutations
  const createMutation = useMutation({
    mutationFn: (med: Partial<Medication>) => medicationsApi.create(profileId, med),
    onSuccess: () => { queryClient.invalidateQueries({ queryKey: ['medications', profileId] }); dispatch({ type: 'HIDE_FORM' }); reset(); },
  });
  const deleteMutation = useMutation({
    mutationFn: (id: string) => medicationsApi.delete(profileId, id),
    onSuccess: (_data, deletedId) => {
      queryClient.invalidateQueries({ queryKey: ['medications', profileId] });
      if (ui.selectedMed?.id === deletedId) dispatch({ type: 'SELECT_MED', med: null });
    },
  });
  const logIntake = useMutation({
    mutationFn: (datetime: string) => {
      const medId = ui.selectedMed?.id || ui.intakeMed?.id;
      if (!medId) throw new Error('no med');
      const iso = new Date(datetime).toISOString();
      return medicationsApi.createIntake(profileId, medId, { scheduled_at: iso, taken_at: iso });
    },
    onSuccess: () => {
      const medId = ui.selectedMed?.id || ui.intakeMed?.id;
      queryClient.invalidateQueries({ queryKey: ['med-intake'] });
      dispatch({ type: 'CLOSE_INTAKE_MODAL' });
      if (medId) {
        dispatch({ type: 'SET_LAST_TAKEN', id: medId });
        setTimeout(() => dispatch({ type: 'SET_LAST_TAKEN', id: null }), 2000);
      }
    },
  });
  const updateMutation = useMutation({
    mutationFn: (data: Partial<Medication> & { id: string }) => {
      const payload = { ...data };
      if (payload.started_at && !payload.started_at.includes('T')) {
        payload.started_at = new Date(payload.started_at + 'T00:00:00').toISOString();
      }
      if (payload.ended_at && !payload.ended_at.includes('T')) {
        payload.ended_at = new Date(payload.ended_at + 'T00:00:00').toISOString();
      }
      if (!payload.ended_at) delete payload.ended_at;
      if (!payload.started_at) delete payload.started_at;
      return medicationsApi.update(profileId, payload.id, payload);
    },
    onSuccess: () => { queryClient.invalidateQueries({ queryKey: ['medications', profileId] }); dispatch({ type: 'SET_EDIT_TARGET', med: null }); editReset(); },
  });
  const deleteIntakeMutation = useMutation({
    mutationFn: (intakeId: string) => medicationsApi.deleteIntake(profileId, ui.selectedMed!.id, intakeId),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['med-intake'] }),
  });

  const { register, handleSubmit, reset, setValue, watch } = useForm<Partial<Medication>>();
  const { register: editRegister, handleSubmit: editHandleSubmit, reset: editReset, setValue: editSetValue, watch: editWatch } = useForm<Partial<Medication>>({
    values: ui.editTarget ? {
      name: ui.editTarget.name, dosage: ui.editTarget.dosage ?? '', unit: ui.editTarget.unit ?? '',
      frequency: ui.editTarget.frequency ?? '', route: ui.editTarget.route ?? '',
      prescribed_by: ui.editTarget.prescribed_by ?? '', reason: ui.editTarget.reason ?? '',
      started_at: ui.editTarget.started_at ? ui.editTarget.started_at.slice(0, 10) : '',
      ended_at: ui.editTarget.ended_at ? ui.editTarget.ended_at.slice(0, 10) : '',
    } : undefined,
  });

  const items = data?.items || [];

  const sortedItems = useMemo(
    () => [...items].sort((a, b) => compareByColumn(a, b, ui.sortCol, ui.sortDir)),
    [items, ui.sortCol, ui.sortDir]
  );

  // ── Detail View ──
  if (ui.selectedMed) {
    return (
      <div className="page">
        <div className="page-header">
          <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
            <button className="btn-icon" onClick={() => dispatch({ type: 'SELECT_MED', med: null })} title={t('common.back')} aria-label={t('common.back')}>
              <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><polyline points="15 18 9 12 15 6"/></svg>
            </button>
            <div>
              <h2 style={{ margin: 0 }}>{ui.selectedMed.name}</h2>
              <span className="text-muted" style={{ fontSize: 13 }}>
                {[ui.selectedMed.dosage, ui.selectedMed.unit, ui.selectedMed.frequency].filter(Boolean).join(' · ')}
              </span>
            </div>
          </div>
          <div className="page-actions">
            <span className={`badge ${ui.selectedMed.ended_at ? 'badge-inactive' : 'badge-active'}`}>
              {ui.selectedMed.ended_at ? t('common.inactive') : t('common.active')}
            </span>
            <button className="btn btn-secondary" onClick={() => dispatch({ type: 'SET_EDIT_TARGET', med: ui.selectedMed })}>
              <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" style={{ marginRight: 6 }}><path d="M11 4H4a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-7"/><path d="M18.5 2.5a2.121 2.121 0 0 1 3 3L12 15l-4 1 1-4 9.5-9.5z"/></svg>
              {t('common.edit')}
            </button>
            {!ui.selectedMed.ended_at && (
              <button className="btn btn-add" onClick={() => dispatch({ type: 'OPEN_INTAKE_MODAL', med: null })}>
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
                <tr><td className="text-muted" style={{ width: 180, fontWeight: 500 }}>{t('medications.dosage')}</td><td>{[ui.selectedMed.dosage, ui.selectedMed.unit].filter(Boolean).join(' ') || '—'}</td></tr>
                <tr><td className="text-muted" style={{ fontWeight: 500 }}>{t('medications.frequency')}</td><td>{ui.selectedMed.frequency || '—'}</td></tr>
                <tr><td className="text-muted" style={{ fontWeight: 500 }}>{t('medications.route')}</td><td>{ui.selectedMed.route ? t('medications.route_' + ui.selectedMed.route) : '—'}</td></tr>
                <tr><td className="text-muted" style={{ fontWeight: 500 }}>{t('medications.prescribed_by')}</td><td>{ui.selectedMed.prescribed_by || '—'}</td></tr>
                <tr><td className="text-muted" style={{ fontWeight: 500 }}>{t('medications.reason')}</td><td>{ui.selectedMed.reason || '—'}</td></tr>
                <tr><td className="text-muted" style={{ fontWeight: 500 }}>{t('medications.started_at')}</td><td>{ui.selectedMed.started_at ? fmt(ui.selectedMed.started_at, 'dd. MMMM yyyy') : '—'}</td></tr>
                {ui.selectedMed.ended_at && <tr><td className="text-muted" style={{ fontWeight: 500 }}>{t('medications.ended_at')}</td><td>{fmt(ui.selectedMed.ended_at, 'dd. MMMM yyyy')}</td></tr>}
              </tbody>
            </table>
          </div>
        </div>

        {/* Intake History */}
        <div className="card">
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 12 }}>
            <h3 style={{ margin: 0 }}>{t('medications.intake_history')}</h3>
            {ui.lastTaken === ui.selectedMed.id && <span className="badge badge-active">{t('medications.taken')}</span>}
          </div>
          {intakes.length === 0 ? (
            <p className="text-muted">{t('medications.no_intakes')}</p>
          ) : (() => {
            const sortedIntakes = [...intakes].sort((a, b) => {
              const aD = a.taken_at || a.scheduled_at;
              const bD = b.taken_at || b.scheduled_at;
              if (ui.intakeSortCol === 'date') return ui.intakeSortDir === 'desc' ? bD.localeCompare(aD) : aD.localeCompare(bD);
              if (ui.intakeSortCol === 'status') {
                const aS = a.taken_at ? 0 : a.skipped_reason ? 2 : 1;
                const bS = b.taken_at ? 0 : b.skipped_reason ? 2 : 1;
                return ui.intakeSortDir === 'asc' ? aS - bS : bS - aS;
              }
              return 0;
            });
            return (
            <div className="table-scroll">
              <table className="data-table">
                <thead>
                  <tr>
                    {[
                      { key: 'date', label: t('common.date') },
                      { key: 'time', label: t('common.time') },
                      { key: 'status', label: t('common.status') },
                    ].map((col) => (
                      <th key={col.key} style={{ cursor: 'pointer', userSelect: 'none' }} onClick={() => dispatch({ type: 'SET_INTAKE_SORT', col: col.key })}>
                        {col.label} {ui.intakeSortCol === col.key ? (ui.intakeSortDir === 'asc' ? '↑' : '↓') : ''}
                      </th>
                    ))}
                    <th>{t('common.notes')}</th>
                    <th></th>
                  </tr>
                </thead>
                <tbody>
                  {sortedIntakes.map((intake) => {
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
                        <td>
                          <button className="btn-icon-sm" onClick={() => dispatch({ type: 'SET_DELETE_INTAKE_TARGET', id: intake.id })} title={t('common.delete')} aria-label={t('common.delete')}>×</button>
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
            );
          })()}
        </div>

        {/* Intake Modal */}
        {ui.showIntakeModal && (
          <div className="modal-overlay" onClick={() => dispatch({ type: 'CLOSE_INTAKE_MODAL' })}>
            <div className="modal" ref={intakeModalRef} onClick={(e) => e.stopPropagation()} style={{ maxWidth: 380 }}>
              <div className="modal-header">
                <h3>{t('medications.mark_taken')}</h3>
                <button className="modal-close" onClick={() => dispatch({ type: 'CLOSE_INTAKE_MODAL' })} aria-label={t('common.close')}>&times;</button>
              </div>
              <div className="modal-body">
                <p className="text-muted" style={{ marginBottom: 12 }}>{ui.selectedMed.name} — {[ui.selectedMed.dosage, ui.selectedMed.unit].filter(Boolean).join(' ')}</p>
                <div className="form-group">
                  <label>{t('common.date')} & {t('common.time')}</label>
                  <input type="datetime-local" value={ui.intakeDatetime} onChange={(e) => dispatch({ type: 'SET_INTAKE_DATETIME', value: e.target.value })} />
                </div>
              </div>
              <div className="modal-footer">
                <button className="btn btn-secondary" onClick={() => dispatch({ type: 'CLOSE_INTAKE_MODAL' })}>{t('common.cancel')}</button>
                <button className="btn btn-add" onClick={() => logIntake.mutate(ui.intakeDatetime)} disabled={logIntake.isPending}>
                  {logIntake.isPending ? t('common.loading') : t('common.save')}
                </button>
              </div>
            </div>
          </div>
        )}

        {/* Edit Modal (reused) */}
        {ui.editTarget && renderEditModal()}

        <ConfirmDelete open={!!ui.deleteTarget} onConfirm={() => { deleteMutation.mutate(ui.deleteTarget!); dispatch({ type: 'SET_DELETE_TARGET', id: null }); }} onCancel={() => dispatch({ type: 'SET_DELETE_TARGET', id: null })} pending={deleteMutation.isPending} />
        <ConfirmDelete open={!!ui.deleteIntakeTarget} onConfirm={() => { deleteIntakeMutation.mutate(ui.deleteIntakeTarget!); dispatch({ type: 'SET_DELETE_INTAKE_TARGET', id: null }); }} onCancel={() => dispatch({ type: 'SET_DELETE_INTAKE_TARGET', id: null })} pending={deleteIntakeMutation.isPending} />
      </div>
    );
  }

  // ── List View ──
  return (
    <div className="page">
      <div className="page-header">
        <h2>{t('nav.medications')}</h2>
        <div className="page-actions">
          <ProfileSelector selectedId={profileId} onSelect={(id) => dispatch({ type: 'SELECT_PROFILE', id })} />
          <label className="toggle-label">
            <input type="checkbox" checked={ui.showActive} onChange={(e) => dispatch({ type: 'SET_SHOW_ACTIVE', value: e.target.checked })} />
            {t('medications.active_only')}
          </label>
          <button className="btn btn-add" onClick={() => dispatch({ type: 'SHOW_FORM' })}>+ {t('common.add')}</button>
        </div>
      </div>

      {adherenceData?.rate != null && (
        <div className="card" style={{ marginBottom: 16, display: 'flex', alignItems: 'center', gap: 10 }}>
          <span className="badge badge-active" style={{ fontSize: 13 }}>{t('medications.adherence')}</span>
          <span>{t('medications.adherence_rate', { rate: Math.round(adherenceData.rate) })}</span>
        </div>
      )}

      <div className="card">
        {isLoading ? <p>{t('common.loading')}</p> : items.length === 0 ? <p className="text-muted">{t('common.no_data')}</p> : (
          <div className="table-scroll">
            <table className="data-table med-table">
              <thead>
                <tr>
                  <th style={{ cursor: 'pointer', userSelect: 'none' }} onClick={() => dispatch({ type: 'SET_SORT', col: 'name' })}>
                    {t('common.name')} {ui.sortCol === 'name' ? (ui.sortDir === 'asc' ? '↑' : '↓') : ''}
                  </th>
                  <th className="col-dosage" style={{ cursor: 'pointer', userSelect: 'none' }} onClick={() => dispatch({ type: 'SET_SORT', col: 'dosage' })}>
                    {t('medications.dosage')} {ui.sortCol === 'dosage' ? (ui.sortDir === 'asc' ? '↑' : '↓') : ''}
                  </th>
                  <th className="col-frequency" style={{ cursor: 'pointer', userSelect: 'none' }} onClick={() => dispatch({ type: 'SET_SORT', col: 'frequency' })}>
                    {t('medications.frequency')} {ui.sortCol === 'frequency' ? (ui.sortDir === 'asc' ? '↑' : '↓') : ''}
                  </th>
                  <th className="col-route" style={{ cursor: 'pointer', userSelect: 'none' }} onClick={() => dispatch({ type: 'SET_SORT', col: 'route' })}>
                    {t('medications.route')} {ui.sortCol === 'route' ? (ui.sortDir === 'asc' ? '↑' : '↓') : ''}
                  </th>
                  <th className="col-prescribed" style={{ cursor: 'pointer', userSelect: 'none' }} onClick={() => dispatch({ type: 'SET_SORT', col: 'prescribed_by' })}>
                    {t('medications.prescribed_by')} {ui.sortCol === 'prescribed_by' ? (ui.sortDir === 'asc' ? '↑' : '↓') : ''}
                  </th>
                  <th className="col-since" style={{ cursor: 'pointer', userSelect: 'none' }} onClick={() => dispatch({ type: 'SET_SORT', col: 'started_at' })}>
                    {t('common.since')} {ui.sortCol === 'started_at' ? (ui.sortDir === 'asc' ? '↑' : '↓') : ''}
                  </th>
                  <th style={{ cursor: 'pointer', userSelect: 'none' }} onClick={() => dispatch({ type: 'SET_SORT', col: 'ended_at' })}>
                    {t('common.status')} {ui.sortCol === 'ended_at' ? (ui.sortDir === 'asc' ? '↑' : '↓') : ''}
                  </th>
                  <th></th>
                </tr>
              </thead>
              <tbody>
                {sortedItems.map((med) => (
                  <tr key={med.id} onClick={() => dispatch({ type: 'SELECT_MED', med })} onKeyDown={(e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); dispatch({ type: 'SELECT_MED', med }); } }} tabIndex={0} style={{ cursor: 'pointer' }}>
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
                          <button className="btn-icon-sm" onClick={(e) => { e.stopPropagation(); dispatch({ type: 'OPEN_INTAKE_MODAL', med }); }} title={t('medications.mark_taken')} style={{ color: ui.lastTaken === med.id ? 'var(--color-success)' : undefined }}>
                            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round"><polyline points="20 6 9 17 4 12"/></svg>
                          </button>
                        )}
                        <button className="btn-icon-sm" onClick={(e) => { e.stopPropagation(); dispatch({ type: 'SET_EDIT_TARGET', med }); }} title={t('medications.edit')}>
                          <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M11 4H4a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-7"/><path d="M18.5 2.5a2.121 2.121 0 0 1 3 3L12 15l-4 1 1-4 9.5-9.5z"/></svg>
                        </button>
                        <button className="btn-icon-sm" onClick={(e) => { e.stopPropagation(); dispatch({ type: 'SET_DELETE_TARGET', id: med.id }); }} title={t('common.delete')}>×</button>
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
      {ui.showForm && (
        <div className="modal-overlay" onClick={() => dispatch({ type: 'HIDE_FORM' })}>
          <div className="modal" ref={createModalRef} onClick={(e) => e.stopPropagation()}>
            <div className="modal-header">
              <h3>{t('medications.add')}</h3>
              <button className="modal-close" onClick={() => dispatch({ type: 'HIDE_FORM' })}>&times;</button>
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
                  <ContactPicker profileId={profileId} value={watch('prescribed_by')} onChange={(name) => setValue('prescribed_by', name)} label={t('medications.prescribed_by')} />
                </div>
                <div className="form-group"><label>{t('medications.reason')}</label><input type="text" {...register('reason')} /></div>
              </form>
            </div>
            <div className="modal-footer">
              <button className="btn btn-secondary" onClick={() => dispatch({ type: 'HIDE_FORM' })}>{t('common.cancel')}</button>
              <button type="submit" form="med-create-form" className="btn btn-add" disabled={createMutation.isPending}>{createMutation.isPending ? t('common.loading') : t('common.save')}</button>
            </div>
          </div>
        </div>
      )}

      {ui.editTarget && renderEditModal()}

      {/* Intake Modal from list */}
      {ui.showIntakeModal && ui.intakeMed && (
        <div className="modal-overlay" onClick={() => dispatch({ type: 'CLOSE_INTAKE_MODAL' })}>
          <div className="modal" ref={intakeModalRef} onClick={(e) => e.stopPropagation()} style={{ maxWidth: 380 }}>
            <div className="modal-header">
              <h3>{t('medications.mark_taken')}</h3>
              <button className="modal-close" onClick={() => dispatch({ type: 'CLOSE_INTAKE_MODAL' })}>&times;</button>
            </div>
            <div className="modal-body">
              <p className="text-muted" style={{ marginBottom: 12 }}>{ui.intakeMed.name} — {[ui.intakeMed.dosage, ui.intakeMed.unit].filter(Boolean).join(' ')}</p>
              <div className="form-group">
                <label>{t('common.date')} & {t('common.time')}</label>
                <input type="datetime-local" value={ui.intakeDatetime} onChange={(e) => dispatch({ type: 'SET_INTAKE_DATETIME', value: e.target.value })} />
              </div>
            </div>
            <div className="modal-footer">
              <button className="btn btn-secondary" onClick={() => dispatch({ type: 'CLOSE_INTAKE_MODAL' })}>{t('common.cancel')}</button>
              <button className="btn btn-add" onClick={() => logIntake.mutate(ui.intakeDatetime)} disabled={logIntake.isPending}>
                {logIntake.isPending ? t('common.loading') : t('common.save')}
              </button>
            </div>
          </div>
        </div>
      )}

      <ConfirmDelete open={!!ui.deleteTarget} onConfirm={() => { deleteMutation.mutate(ui.deleteTarget!); dispatch({ type: 'SET_DELETE_TARGET', id: null }); }} onCancel={() => dispatch({ type: 'SET_DELETE_TARGET', id: null })} pending={deleteMutation.isPending} />
    </div>
  );

  // ── Edit Modal (shared) ──
  function renderEditModal() {
    if (!ui.editTarget) return null;
    return (
      <div className="modal-overlay" onClick={() => dispatch({ type: 'SET_EDIT_TARGET', med: null })}>
        <div className="modal" onClick={(e) => e.stopPropagation()}>
          <div className="modal-header">
            <h3>{t('medications.edit')}</h3>
            <button className="modal-close" onClick={() => dispatch({ type: 'SET_EDIT_TARGET', med: null })}>&times;</button>
          </div>
          <div className="modal-body">
            <form id="med-edit-form" onSubmit={editHandleSubmit((d) => updateMutation.mutate({ ...d, id: ui.editTarget!.id }))}>
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
                <ContactPicker profileId={profileId} value={editWatch('prescribed_by')} onChange={(name) => editSetValue('prescribed_by', name)} label={t('medications.prescribed_by')} />
              </div>
              <div className="form-group"><label>{t('medications.reason')}</label><input type="text" {...editRegister('reason')} /></div>
              <div className="form-row">
                <div className="form-group"><label>{t('medications.started_at')}</label><input type="date" {...editRegister('started_at')} /></div>
                <div className="form-group"><label>{t('medications.ended_at')}</label><input type="date" {...editRegister('ended_at')} /></div>
              </div>
            </form>
          </div>
          <div className="modal-footer">
            <button className="btn btn-secondary" onClick={() => dispatch({ type: 'SET_EDIT_TARGET', med: null })}>{t('common.cancel')}</button>
            <button type="submit" form="med-edit-form" className="btn btn-add" disabled={updateMutation.isPending}>{updateMutation.isPending ? t('common.loading') : t('common.save')}</button>
          </div>
        </div>
      </div>
    );
  }
}
