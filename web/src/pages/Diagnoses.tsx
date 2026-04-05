import { useState } from 'react';
import { useTranslation } from 'react-i18next';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { useForm } from 'react-hook-form';
import { ProfileSelector } from '../components/ProfileSelector';
import { useDateFormat } from '../hooks/useDateLocale';
import { ConfirmDelete } from '../components/ConfirmDelete';
import { useProfiles } from '../hooks/useProfiles';
import { diagnosesApi, type Diagnosis } from '../api/diagnoses';
import { ContactPicker } from '../components/ContactPicker';

const STATUSES = ['active', 'resolved', 'chronic', 'in_remission', 'suspected'];
const STATUS_COLORS: Record<string, string> = {
  active: 'badge-active', resolved: 'badge-inactive', chronic: 'badge-scheduled',
  in_remission: 'badge-info', suspected: 'badge-missed',
};

export function Diagnoses() {
  const { t } = useTranslation();
  const { fmt } = useDateFormat();
  const { data: profilesData } = useProfiles();
  const profiles = profilesData || [];
  const [selectedProfile, setSelectedProfile] = useState('');
  const [showForm, setShowForm] = useState(false);
  const [deleteTarget, setDeleteTarget] = useState<string | null>(null);
  const [editTarget, setEditTarget] = useState<Diagnosis | null>(null);
  const [sortCol, setSortCol] = useState<string>('diagnosed_at');
  const [sortDir, setSortDir] = useState<'asc'|'desc'>('desc');
  const queryClient = useQueryClient();
  const profileId = selectedProfile || profiles[0]?.id || '';

  const { data, isLoading } = useQuery({
    queryKey: ['diagnoses', profileId],
    queryFn: () => diagnosesApi.list(profileId),
    enabled: !!profileId,
  });

  const fixDates = (data: Record<string, unknown>, dateFields: string[]) => {
    const cleaned = { ...data };
    for (const field of dateFields) {
      const val = cleaned[field];
      if (typeof val === 'string' && val && !val.includes('T')) {
        cleaned[field] = new Date(val + 'T00:00:00').toISOString();
      }
      if (typeof val === 'string' && val === '') {
        delete cleaned[field];
      }
    }
    return cleaned;
  };

  const createMutation = useMutation({
    mutationFn: (d: Partial<Diagnosis>) => diagnosesApi.create(profileId, fixDates(d as Record<string, unknown>, ['diagnosed_at', 'resolved_at']) as Partial<Diagnosis>),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['diagnoses', profileId] });
      setShowForm(false);
      reset();
    },
  });

  const updateMutation = useMutation({
    mutationFn: ({ id, ...data }: Partial<Diagnosis> & { id: string }) =>
      diagnosesApi.update(profileId, id, fixDates(data as Record<string, unknown>, ['diagnosed_at', 'resolved_at']) as Partial<Diagnosis>),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['diagnoses', profileId] });
      setEditTarget(null);
    },
  });

  const deleteMutation = useMutation({
    mutationFn: (id: string) => diagnosesApi.delete(profileId, id),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['diagnoses', profileId] }),
  });

  const { register, handleSubmit, reset, setValue, watch } = useForm<Partial<Diagnosis>>();
  const editForm = useForm<Partial<Diagnosis>>({ values: editTarget ? {
    name: editTarget.name,
    icd10_code: editTarget.icd10_code || '',
    status: editTarget.status,
    diagnosed_at: editTarget.diagnosed_at?.slice(0, 10) || '',
    diagnosed_by: editTarget.diagnosed_by || '',
    resolved_at: editTarget.resolved_at?.slice(0, 10) || '',
    notes: editTarget.notes || '',
  } : undefined });
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
        <h2>{t('nav.diagnoses')}</h2>
        <div className="page-actions">
          <ProfileSelector selectedId={profileId} onSelect={setSelectedProfile} />
          <button className="btn btn-add" onClick={() => setShowForm(!showForm)}>+ {t('common.add')}</button>
        </div>
      </div>

      {showForm && (
        <div className="modal-overlay" onClick={() => setShowForm(false)}>
          <div className="modal" onClick={(e) => e.stopPropagation()}>
            <div className="modal-header">
              <h3>{t('diagnoses.add')}</h3>
              <button className="modal-close" onClick={() => setShowForm(false)} aria-label={t('common.close')}>&times;</button>
            </div>
            <div className="modal-body">
              <form id="diag-create-form" onSubmit={handleSubmit((data) => createMutation.mutate(data))}>
                <div className="form-row">
                  <div className="form-group"><label>{t('diagnoses.condition')} *</label><input type="text" {...register('name')} required /></div>
                  <div className="form-group"><label>{t('diagnoses.icd10_code')}</label><input type="text" {...register('icd10_code')} placeholder={t('diagnoses.icd10_placeholder')} /></div>
                  <div className="form-group"><label>{t('common.status')}</label>
                    <select {...register('status')}>{STATUSES.map((s) => <option key={s} value={s}>{t('diagnoses.status_' + s)}</option>)}</select>
                  </div>
                </div>
                <div className="form-row">
                  <div className="form-group"><label>{t('diagnoses.diagnosed_at')}</label><input type="date" {...register('diagnosed_at')} /></div>
                  <ContactPicker profileId={profileId} value={watch('diagnosed_by')} onChange={(name) => setValue('diagnosed_by', name)} label={t('diagnoses.diagnosed_by')} />
                </div>
              </form>
            </div>
            <div className="modal-footer">
              <button className="btn btn-secondary" onClick={() => setShowForm(false)}>{t('common.cancel')}</button>
              <button type="submit" form="diag-create-form" className="btn btn-add" disabled={createMutation.isPending}>{t('common.save')}</button>
            </div>
          </div>
        </div>
      )}

      <div className="card">
        {isLoading ? <p>{t('common.loading')}</p> : items.length === 0 ? <p className="text-muted">{t('common.no_data')}</p> : (
          <>
          <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 12 }}>
            <label style={{ fontSize: 14 }}>{t('common.sort_by')}:</label>
            <select value={sortCol} onChange={(e) => setSortCol(e.target.value)} style={{ fontSize: 14 }}>
              <option value="diagnosed_at">{t('common.date')}</option>
              <option value="name">{t('common.name')}</option>
              <option value="status">{t('common.status')}</option>
            </select>
            <button className="btn-icon-sm" onClick={() => setSortDir(d => d === 'asc' ? 'desc' : 'asc')} title={sortDir === 'asc' ? 'Descending' : 'Ascending'} aria-label={t('common.sort')}>
              {sortDir === 'asc' ? '\u2191' : '\u2193'}
            </button>
          </div>
          <div className="med-list">
            {sortedItems.map((d) => (
              <div key={d.id} className="med-item" onClick={() => setEditTarget(d)} style={{ cursor: 'pointer' }}>
                <div className="med-info">
                  <div className="med-name">{d.name}{d.icd10_code && <span className="text-muted"> ({d.icd10_code})</span>}</div>
                  <div className="med-details">
                    {d.diagnosed_by && `${d.diagnosed_by} · `}
                    {d.diagnosed_at && fmt(d.diagnosed_at, 'dd. MMM yyyy')}
                    {d.resolved_at && ` — ${t('diagnoses.resolved_prefix')} ${fmt(d.resolved_at, 'dd. MMM yyyy')}`}
                  </div>
                </div>
                <div className="med-actions">
                  <span className={`badge ${STATUS_COLORS[d.status] || 'badge-info'}`}>{t('diagnoses.status_' + d.status)}</span>
                  <button className="btn-icon-sm" onClick={(e) => { e.stopPropagation(); setDeleteTarget(d.id); }} title={t('common.delete')} aria-label={t('common.delete')}>×</button>
                </div>
              </div>
            ))}
          </div>
          </>
        )}
      </div>

      {editTarget && (
        <div className="modal-overlay" onClick={() => setEditTarget(null)}>
          <div className="modal" onClick={(e) => e.stopPropagation()}>
            <div className="modal-header">
              <h3>{t('diagnoses.edit')}</h3>
              <button className="modal-close" onClick={() => setEditTarget(null)} aria-label={t('common.close')}>&times;</button>
            </div>
            <div className="modal-body">
              <form id="diag-edit-form" onSubmit={editForm.handleSubmit((data) => updateMutation.mutate({ id: editTarget.id, ...data }))}>
                <div className="form-row">
                  <div className="form-group"><label>{t('diagnoses.condition')} *</label><input type="text" {...editForm.register('name')} required /></div>
                  <div className="form-group"><label>{t('diagnoses.icd10_code')}</label><input type="text" {...editForm.register('icd10_code')} placeholder={t('diagnoses.icd10_placeholder')} /></div>
                  <div className="form-group"><label>{t('common.status')}</label>
                    <select {...editForm.register('status')}>{STATUSES.map((s) => <option key={s} value={s}>{t('diagnoses.status_' + s)}</option>)}</select>
                  </div>
                </div>
                <div className="form-row">
                  <div className="form-group"><label>{t('diagnoses.diagnosed_at')}</label><input type="date" {...editForm.register('diagnosed_at')} /></div>
                  <ContactPicker profileId={profileId} value={editForm.watch('diagnosed_by')} onChange={(name) => editForm.setValue('diagnosed_by', name)} label={t('diagnoses.diagnosed_by')} />
                  <div className="form-group"><label>{t('diagnoses.resolved_at')}</label><input type="date" {...editForm.register('resolved_at')} /></div>
                </div>
                <div className="form-group"><label>{t('common.notes')}</label><textarea rows={3} {...editForm.register('notes')} /></div>
              </form>
            </div>
            <div className="modal-footer">
              <button type="button" className="btn btn-secondary" onClick={() => setEditTarget(null)}>{t('common.cancel')}</button>
              <button type="submit" form="diag-edit-form" className="btn btn-add" disabled={updateMutation.isPending}>{updateMutation.isPending ? t('common.loading') : t('common.save')}</button>
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
