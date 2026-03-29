import { useState } from 'react';
import { useTranslation } from 'react-i18next';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { useForm } from 'react-hook-form';
import { ProfileSelector } from '../components/ProfileSelector';
import { useDateFormat } from '../hooks/useDateLocale';
import { ConfirmDelete } from '../components/ConfirmDelete';
import { useProfiles } from '../hooks/useProfiles';
import { api } from '../api/client';

interface Diagnosis {
  id: string;
  name: string;
  icd10_code?: string;
  status: string;
  diagnosed_at?: string;
  diagnosed_by?: string;
  resolved_at?: string;
  notes?: string;
}

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
  const queryClient = useQueryClient();
  const profileId = selectedProfile || profiles[0]?.id || '';

  const { data, isLoading } = useQuery({
    queryKey: ['diagnoses', profileId],
    queryFn: () => api.get<{ items: Diagnosis[] }>(`/api/v1/profiles/${profileId}/diagnoses`),
    enabled: !!profileId,
  });

  const createMutation = useMutation({
    mutationFn: (d: Partial<Diagnosis>) => api.post(`/api/v1/profiles/${profileId}/diagnoses`, d),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['diagnoses', profileId] });
      setShowForm(false);
      reset();
    },
  });

  const updateMutation = useMutation({
    mutationFn: ({ id, ...data }: Partial<Diagnosis> & { id: string }) =>
      api.patch(`/api/v1/profiles/${profileId}/diagnoses/${id}`, data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['diagnoses', profileId] });
      setEditTarget(null);
    },
  });

  const deleteMutation = useMutation({
    mutationFn: (id: string) => api.delete(`/api/v1/profiles/${profileId}/diagnoses/${id}`),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['diagnoses', profileId] }),
  });

  const { register, handleSubmit, reset } = useForm<Partial<Diagnosis>>();
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
              <button className="modal-close" onClick={() => setShowForm(false)}>&times;</button>
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
                  <div className="form-group"><label>{t('diagnoses.diagnosed_by')}</label><input type="text" {...register('diagnosed_by')} /></div>
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
          <div className="med-list">
            {items.map((d) => (
              <div key={d.id} className="med-item" onClick={() => setEditTarget(d)} style={{ cursor: 'pointer' }}>
                <div className="med-info">
                  <div className="med-name">{d.name}{d.icd10_code && <span className="text-muted"> ({d.icd10_code})</span>}</div>
                  <div className="med-details">
                    {d.diagnosed_by && `${d.diagnosed_by} · `}
                    {d.diagnosed_at && fmt(d.diagnosed_at, 'dd. MMM yyyy')}
                    {d.resolved_at && ` — resolved ${fmt(d.resolved_at, 'dd. MMM yyyy')}`}
                  </div>
                </div>
                <div className="med-actions">
                  <span className={`badge ${STATUS_COLORS[d.status] || 'badge-info'}`}>{t('diagnoses.status_' + d.status)}</span>
                  <button className="btn-icon-sm" onClick={(e) => { e.stopPropagation(); setDeleteTarget(d.id); }} title={t('common.delete')}>×</button>
                </div>
              </div>
            ))}
          </div>
        )}
      </div>

      {editTarget && (
        <div className="modal-overlay" onClick={() => setEditTarget(null)}>
          <div className="modal" onClick={(e) => e.stopPropagation()}>
            <div className="modal-header">
              <h3>{t('diagnoses.edit')}</h3>
              <button className="modal-close" onClick={() => setEditTarget(null)}>&times;</button>
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
                  <div className="form-group"><label>{t('diagnoses.diagnosed_by')}</label><input type="text" {...editForm.register('diagnosed_by')} /></div>
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
