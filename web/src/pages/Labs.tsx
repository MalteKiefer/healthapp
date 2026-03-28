import { useState } from 'react';
import { useTranslation } from 'react-i18next';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { useForm, useFieldArray } from 'react-hook-form';
import { format } from 'date-fns';
import { ProfileSelector } from '../components/ProfileSelector';
import { useProfiles } from '../hooks/useProfiles';
import { api } from '../api/client';

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
  const { data: profilesData } = useProfiles();
  const profiles = profilesData || [];
  const [selectedProfile, setSelectedProfile] = useState('');
  const [showForm, setShowForm] = useState(false);
  const [expandedId, setExpandedId] = useState<string | null>(null);
  const queryClient = useQueryClient();
  const profileId = selectedProfile || profiles[0]?.id || '';

  const { data, isLoading } = useQuery({
    queryKey: ['labs', profileId],
    queryFn: () => api.get<{ items: LabResult[]; total: number }>(`/api/v1/profiles/${profileId}/labs`),
    enabled: !!profileId,
  });

  const createMutation = useMutation({
    mutationFn: (lab: Partial<LabResult>) => api.post(`/api/v1/profiles/${profileId}/labs`, lab),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['labs', profileId] });
      setShowForm(false);
      reset();
    },
  });

  const { register, handleSubmit, reset, control } = useForm<{
    lab_name: string;
    ordered_by: string;
    sample_date: string;
    values: LabValue[];
  }>({
    defaultValues: { values: [{ marker: '', unit: '' }] },
  });

  const { fields, append, remove } = useFieldArray({ control, name: 'values' });

  const items = data?.items || [];

  return (
    <div className="page">
      <div className="page-header">
        <h2>{t('nav.labs')}</h2>
        <div className="page-actions">
          <ProfileSelector selectedId={profileId} onSelect={setSelectedProfile} />
          <button className="btn btn-add" onClick={() => setShowForm(!showForm)}>+ {t('common.add')}</button>
        </div>
      </div>

      {showForm && (
        <div className="card form-card">
          <h3>{t('labs.add')}</h3>
          <form onSubmit={handleSubmit((data) => createMutation.mutate(data))}>
            <div className="form-row">
              <div className="form-group"><label>{t('labs.lab_name')}</label><input type="text" {...register('lab_name')} /></div>
              <div className="form-group"><label>{t('labs.ordered_by')}</label><input type="text" {...register('ordered_by')} /></div>
              <div className="form-group"><label>{t('labs.sample_date')} *</label><input type="date" {...register('sample_date')} required /></div>
            </div>

            <h4 style={{ marginTop: 16, marginBottom: 8, fontSize: 14 }}>{t('labs.values')}</h4>
            {fields.map((field, index) => (
              <div key={field.id} className="form-row" style={{ alignItems: 'flex-end' }}>
                <div className="form-group"><label>{t('labs.marker')}</label><input type="text" {...register(`values.${index}.marker`)} placeholder="e.g. Hemoglobin" /></div>
                <div className="form-group"><label>{t('labs.value')}</label><input type="number" step="0.01" {...register(`values.${index}.value`, { valueAsNumber: true })} /></div>
                <div className="form-group"><label>{t('labs.unit')}</label><input type="text" {...register(`values.${index}.unit`)} placeholder="g/dL" /></div>
                <div className="form-group"><label>{t('labs.ref_low')}</label><input type="number" step="0.01" {...register(`values.${index}.reference_low`, { valueAsNumber: true })} /></div>
                <div className="form-group"><label>{t('labs.ref_high')}</label><input type="number" step="0.01" {...register(`values.${index}.reference_high`, { valueAsNumber: true })} /></div>
                <button type="button" className="btn-icon-sm" onClick={() => remove(index)} style={{ marginBottom: 16 }}>×</button>
              </div>
            ))}
            <button type="button" className="btn btn-secondary" onClick={() => append({ marker: '', unit: '' })} style={{ marginBottom: 16 }}>
              + Add Marker
            </button>

            <div className="form-actions">
              <button type="submit" className="btn btn-add" disabled={createMutation.isPending}>{t('common.save')}</button>
              <button type="button" className="btn btn-secondary" onClick={() => setShowForm(false)}>{t('common.cancel')}</button>
            </div>
          </form>
        </div>
      )}

      <div className="card">
        {isLoading ? <p>{t('common.loading')}</p> : items.length === 0 ? <p className="text-muted">{t('common.no_data')}</p> : (
          <div className="lab-list">
            {items.map((lab) => (
              <div key={lab.id} className="lab-item">
                <div className="lab-header" onClick={() => setExpandedId(expandedId === lab.id ? null : lab.id)}>
                  <div className="lab-info">
                    <div className="med-name">{lab.lab_name || 'Lab Result'}</div>
                    <div className="med-details">
                      {format(new Date(lab.sample_date), 'MMM d, yyyy')}
                      {lab.ordered_by && ` · ${lab.ordered_by}`}
                      · {lab.values?.length || 0} markers
                    </div>
                  </div>
                  <span className="expand-icon">{expandedId === lab.id ? '▼' : '▶'}</span>
                </div>
                {expandedId === lab.id && lab.values && (
                  <div className="lab-values">
                    <table className="data-table">
                      <thead><tr><th>{t('labs.marker')}</th><th>{t('labs.value')}</th><th>{t('labs.unit')}</th><th>{t('labs.reference')}</th><th>{t('labs.flag')}</th></tr></thead>
                      <tbody>
                        {lab.values.map((v, i) => (
                          <tr key={i}>
                            <td>{v.marker}</td>
                            <td className={flagColor(v.flag)}><strong>{v.value ?? '—'}</strong></td>
                            <td>{v.unit || '—'}</td>
                            <td className="text-muted">{v.reference_low != null && v.reference_high != null ? `${v.reference_low}–${v.reference_high}` : '—'}</td>
                            <td><span className={`badge ${flagColor(v.flag)}`}>{v.flag || 'normal'}</span></td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </div>
                )}
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}
