import { useState, useMemo } from 'react';
import { compareByColumn } from '../utils/sorting';
import { useTranslation } from 'react-i18next';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { useForm, useFieldArray } from 'react-hook-form';
import { ProfileSelector } from '../components/ProfileSelector';
import { useDateFormat } from '../hooks/useDateLocale';
import { ConfirmDelete } from '../components/ConfirmDelete';
import { useProfiles } from '../hooks/useProfiles';
import { api } from '../api/client';
import { ContactPicker } from '../components/ContactPicker';
import { LabTrendsView } from '../components/LabTrendsView';
import { useFocusTrap } from '../hooks/useFocusTrap';

interface LabValue {
  marker: string;
  value?: number;
  unit?: string;
  reference_low?: number;
  reference_high?: number;
  flag?: string;
}

interface LabResult {
  id: string;
  lab_name?: string;
  ordered_by?: string;
  sample_date: string;
  result_date?: string;
  values: LabValue[];
  created_at: string;
}

function flagColor(flag?: string): string {
  if (!flag) return '';
  if (flag === 'critical') return 'status-critical';
  if (flag === 'high' || flag === 'low') return 'status-abnormal';
  return 'status-normal';
}

export function Labs() {
  const { t } = useTranslation();
  const { fmt } = useDateFormat();
  const { data: profilesData } = useProfiles();
  const profiles = profilesData || [];
  const [selectedProfile, setSelectedProfile] = useState('');
  const [showForm, setShowForm] = useState(false);
  const [sortCol, setSortCol] = useState<string>('sample_date');
  const [sortDir, setSortDir] = useState<'asc' | 'desc'>('desc');
  const [expandedId, setExpandedId] = useState<string | null>(null);
  const [deleteTarget, setDeleteTarget] = useState<string | null>(null);
  const [editTarget, setEditTarget] = useState<LabResult | null>(null);
  const modalRef = useFocusTrap(showForm);
  const editModalRef = useFocusTrap(!!editTarget);
  const [viewMode, setViewMode] = useState<'list' | 'trends'>('list');
  const queryClient = useQueryClient();
  const profileId = selectedProfile || profiles[0]?.id || '';

  const { data, isLoading } = useQuery({
    queryKey: ['labs', profileId],
    queryFn: () => api.get<{ items: LabResult[]; total: number }>(`/api/v1/profiles/${profileId}/labs`),
    enabled: !!profileId,
  });

  const cleanLab = (lab: Partial<LabResult>) => {
    const cleaned = { ...lab };
    // date inputs give "2026-04-02" — backend needs full ISO 8601
    if (cleaned.sample_date && !cleaned.sample_date.includes('T')) {
      cleaned.sample_date = new Date(cleaned.sample_date + 'T00:00:00').toISOString();
    }
    if (!cleaned.lab_name) delete cleaned.lab_name;
    if (!cleaned.ordered_by) delete cleaned.ordered_by;
    if (cleaned.values) {
      cleaned.values = cleaned.values.map((v: LabValue) => {
        const clean = { ...v };
        if (typeof clean.value === 'number' && isNaN(clean.value)) delete clean.value;
        if (typeof clean.reference_low === 'number' && isNaN(clean.reference_low)) delete clean.reference_low;
        if (typeof clean.reference_high === 'number' && isNaN(clean.reference_high)) delete clean.reference_high;
        return clean;
      });
    }
    return cleaned;
  };

  const createMutation = useMutation({
    mutationFn: (lab: Partial<LabResult>) => api.post(`/api/v1/profiles/${profileId}/labs`, cleanLab(lab)),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['labs', profileId] });
      queryClient.invalidateQueries({ queryKey: ['lab-trends'] });
      setShowForm(false);
      reset();
    },
  });

  const deleteMutation = useMutation({
    mutationFn: (id: string) => api.delete(`/api/v1/profiles/${profileId}/labs/${id}`),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['labs', profileId] });
      queryClient.invalidateQueries({ queryKey: ['lab-trends'] });
    },
  });

  const updateMutation = useMutation({
    mutationFn: (data: Partial<LabResult> & { id: string }) =>
      api.patch(`/api/v1/profiles/${profileId}/labs/${data.id}`, cleanLab(data)),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['labs', profileId] });
      queryClient.invalidateQueries({ queryKey: ['lab-trends'] });
      setEditTarget(null);
      editReset();
    },
  });

  const { register, handleSubmit, reset, control, setValue, watch } = useForm<{
    lab_name: string;
    ordered_by: string;
    sample_date: string;
    values: LabValue[];
  }>({
    defaultValues: { values: [{ marker: '', unit: '' }] },
  });

  const { fields, append, remove } = useFieldArray({ control, name: 'values' });

  const {
    register: editRegister,
    handleSubmit: editHandleSubmit,
    reset: editReset,
    control: editControl,
    setValue: editSetValue,
    watch: editWatch,
  } = useForm<{
    lab_name: string;
    ordered_by: string;
    sample_date: string;
    values: LabValue[];
  }>({
    values: editTarget ? {
      lab_name: editTarget.lab_name ?? '',
      ordered_by: editTarget.ordered_by ?? '',
      sample_date: editTarget.sample_date ? editTarget.sample_date.slice(0, 10) : '',
      values: editTarget.values?.length ? editTarget.values : [{ marker: '', unit: '' }],
    } : undefined,
  });

  const { fields: editFields, append: editAppend, remove: editRemove } = useFieldArray({ control: editControl, name: 'values' });

  const onEditSubmit = (formData: { lab_name: string; ordered_by: string; sample_date: string; values: LabValue[] }) => {
    if (!editTarget) return;
    updateMutation.mutate({ ...formData, id: editTarget.id });
  };

  const items = data?.items || [];

  const sortedItems = useMemo(
    () => [...items].sort((a, b) => compareByColumn(a, b, sortCol, sortDir)),
    [items, sortCol, sortDir]
  );

  return (
    <div className="page">
      <div className="page-header">
        <h2>{t('nav.labs')}</h2>
        <div className="page-actions">
          <div className="view-tabs">
            <button className={`view-tab${viewMode === 'list' ? ' active' : ''}`} onClick={() => setViewMode('list')}>
              {t('labs.view_list')}
            </button>
            <button className={`view-tab${viewMode === 'trends' ? ' active' : ''}`} onClick={() => setViewMode('trends')}>
              {t('labs.view_trends')}
            </button>
          </div>
          <ProfileSelector selectedId={profileId} onSelect={setSelectedProfile} />
          {viewMode === 'list' && (
            <button className="btn btn-add" onClick={() => setShowForm(!showForm)}>+ {t('common.add')}</button>
          )}
        </div>
      </div>

      {showForm && (
        <div className="modal-overlay" onClick={() => setShowForm(false)}>
          <div className="modal" ref={modalRef} onClick={(e) => e.stopPropagation()} style={{ maxWidth: 640 }}>
            <div className="modal-header">
              <h3>{t('labs.add')}</h3>
              <button className="modal-close" onClick={() => setShowForm(false)} aria-label={t('common.close')}>&times;</button>
            </div>
            <div className="modal-body">
              <form id="lab-create-form" onSubmit={handleSubmit((data) => createMutation.mutate(data))}>
                <div className="form-row">
                  <div className="form-group"><label>{t('labs.lab_name')}</label><input type="text" {...register('lab_name')} /></div>
                  <ContactPicker profileId={profileId} value={watch('ordered_by')} onChange={(name) => setValue('ordered_by', name)} label={t('labs.ordered_by')} />
                  <div className="form-group"><label>{t('labs.sample_date')} *</label><input type="date" {...register('sample_date')} required /></div>
                </div>

                <h4 style={{ marginTop: 16, marginBottom: 8, fontSize: 14 }}>{t('labs.values')}</h4>
                {fields.map((field, index) => (
                  <div key={field.id} className="form-row" style={{ alignItems: 'flex-end' }}>
                    <div className="form-group"><label>{t('labs.marker')}</label><input type="text" {...register(`values.${index}.marker`)} placeholder={t('labs.marker_placeholder')} /></div>
                    <div className="form-group"><label>{t('labs.value')}</label><input type="number" step="0.01" {...register(`values.${index}.value`, { valueAsNumber: true })} /></div>
                    <div className="form-group"><label>{t('labs.unit')}</label><input type="text" {...register(`values.${index}.unit`)} placeholder="g/dL" /></div>
                    <div className="form-group"><label>{t('labs.ref_low')}</label><input type="number" step="0.01" {...register(`values.${index}.reference_low`, { valueAsNumber: true })} /></div>
                    <div className="form-group"><label>{t('labs.ref_high')}</label><input type="number" step="0.01" {...register(`values.${index}.reference_high`, { valueAsNumber: true })} /></div>
                    <button type="button" className="btn-icon-sm" onClick={() => remove(index)} style={{ marginBottom: 16 }} aria-label={t('common.delete')}>×</button>
                  </div>
                ))}
                <button type="button" className="btn btn-secondary" onClick={() => append({ marker: '', unit: '' })} style={{ marginBottom: 16 }}>
                  {t('labs.add_marker')}
                </button>
              </form>
            </div>
            <div className="modal-footer">
              <button className="btn btn-secondary" onClick={() => setShowForm(false)}>{t('common.cancel')}</button>
              <button type="submit" form="lab-create-form" className="btn btn-add" disabled={createMutation.isPending}>{t('common.save')}</button>
            </div>
          </div>
        </div>
      )}

      {viewMode === 'trends' ? (
        <LabTrendsView profileId={profileId} />
      ) : (
      <div className="card">
        {isLoading ? <p>{t('common.loading')}</p> : items.length === 0 ? <p className="text-muted">{t('common.no_data')}</p> : (
          <>
          <div style={{ display: 'flex', gap: 8, marginBottom: 12 }}>
            <select className="metric-selector" value={sortCol} onChange={(e) => setSortCol(e.target.value)}>
              <option value="sample_date">{t('common.date')}</option>
              <option value="lab_name">{t('labs.lab_result')}</option>
            </select>
            <button className="btn-sm" onClick={() => setSortDir(d => d === 'asc' ? 'desc' : 'asc')} aria-label={t('common.sort')}>
              {sortDir === 'asc' ? '↑' : '↓'}
            </button>
          </div>
          <div className="lab-list">
            {sortedItems.map((lab) => (
              <div key={lab.id} className="lab-item">
                <div className="lab-header" onClick={() => setExpandedId(expandedId === lab.id ? null : lab.id)}>
                  <div className="lab-info">
                    <div className="med-name">{lab.lab_name || t('labs.lab_result')}</div>
                    <div className="med-details">
                      {fmt(lab.sample_date, 'dd. MMM yyyy')}
                      {lab.ordered_by && ` · ${lab.ordered_by}`}
                      · {lab.values?.length || 0} {t('labs.markers')}
                    </div>
                  </div>
                  <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                    <button
                      className="btn-icon-sm"
                      onClick={(e) => { e.stopPropagation(); setEditTarget(lab); }}
                      title={t('common.edit')}
                      aria-label={t('common.edit')}
                      style={{ fontSize: 14 }}
                    >&#9998;</button>
                    <button
                      className="btn-icon-sm"
                      onClick={(e) => { e.stopPropagation(); setDeleteTarget(lab.id); }}
                      title={t('common.delete')}
                      aria-label={t('common.delete')}
                    >×</button>
                    <span className="expand-icon" aria-label={expandedId === lab.id ? t('common.collapse') : t('common.expand')}>{expandedId === lab.id ? '▼' : '▶'}</span>
                  </div>
                </div>
                {expandedId === lab.id && lab.values && (
                  <div className="lab-values">
                    <table className="data-table">
                      <thead><tr><th>{t('labs.marker')}</th><th>{t('labs.value')}</th><th>{t('labs.unit')}</th><th className="hide-mobile">{t('labs.reference')}</th><th>{t('labs.flag')}</th></tr></thead>
                      <tbody>
                        {lab.values.map((v, i) => (
                          <tr key={i}>
                            <td>{v.marker}</td>
                            <td className={flagColor(v.flag)}><strong>{v.value ?? '—'}</strong></td>
                            <td>{v.unit || '—'}</td>
                            <td className="text-muted hide-mobile">{v.reference_low != null && v.reference_high != null ? `${v.reference_low}–${v.reference_high}` : '—'}</td>
                            <td><span className={`badge ${flagColor(v.flag)}`}>{v.flag || t('labs.flag_normal')}</span></td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </div>
                )}
              </div>
            ))}
          </div>
          </>
        )}
      </div>
      )}

      {/* Edit Modal */}
      {editTarget && (
        <div className="modal-overlay" onClick={() => setEditTarget(null)}>
          <div className="modal" ref={editModalRef} onClick={(e) => e.stopPropagation()} style={{ maxWidth: 640 }}>
            <div className="modal-header">
              <h3>{t('labs.edit')}</h3>
              <button className="modal-close" onClick={() => setEditTarget(null)} aria-label={t('common.close')}>&times;</button>
            </div>
            <div className="modal-body">
              <form id="lab-edit-form" onSubmit={editHandleSubmit(onEditSubmit)}>
                <div className="form-row">
                  <div className="form-group"><label>{t('labs.lab_name')}</label><input type="text" {...editRegister('lab_name')} /></div>
                  <ContactPicker profileId={profileId} value={editWatch('ordered_by')} onChange={(name) => editSetValue('ordered_by', name)} label={t('labs.ordered_by')} />
                  <div className="form-group"><label>{t('labs.sample_date')} *</label><input type="date" {...editRegister('sample_date')} required /></div>
                </div>

                <h4 style={{ marginTop: 16, marginBottom: 8, fontSize: 14 }}>{t('labs.values')}</h4>
                {editFields.map((field, index) => (
                  <div key={field.id} className="form-row" style={{ alignItems: 'flex-end' }}>
                    <div className="form-group"><label>{t('labs.marker')}</label><input type="text" {...editRegister(`values.${index}.marker`)} placeholder={t('labs.marker_placeholder')} /></div>
                    <div className="form-group"><label>{t('labs.value')}</label><input type="number" step="0.01" {...editRegister(`values.${index}.value`, { valueAsNumber: true })} /></div>
                    <div className="form-group"><label>{t('labs.unit')}</label><input type="text" {...editRegister(`values.${index}.unit`)} placeholder="g/dL" /></div>
                    <div className="form-group"><label>{t('labs.ref_low')}</label><input type="number" step="0.01" {...editRegister(`values.${index}.reference_low`, { valueAsNumber: true })} /></div>
                    <div className="form-group"><label>{t('labs.ref_high')}</label><input type="number" step="0.01" {...editRegister(`values.${index}.reference_high`, { valueAsNumber: true })} /></div>
                    <button type="button" className="btn-icon-sm" onClick={() => editRemove(index)} style={{ marginBottom: 16 }} aria-label={t('common.delete')}>×</button>
                  </div>
                ))}
                <button type="button" className="btn btn-secondary" onClick={() => editAppend({ marker: '', unit: '' })} style={{ marginBottom: 16 }}>
                  {t('labs.add_marker')}
                </button>
              </form>
            </div>
            <div className="modal-footer">
              <button className="btn btn-secondary" onClick={() => setEditTarget(null)}>{t('common.cancel')}</button>
              <button type="submit" form="lab-edit-form" className="btn btn-add" disabled={updateMutation.isPending}>
                {updateMutation.isPending ? t('common.loading') : t('common.save')}
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
