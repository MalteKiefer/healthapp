import { useState, useEffect } from 'react';
import { useTranslation } from 'react-i18next';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { useForm } from 'react-hook-form';
import { ProfileSelector } from '../components/ProfileSelector';
import { ConfirmDelete } from '../components/ConfirmDelete';
import { useProfiles } from '../hooks/useProfiles';
import { api } from '../api/client';

interface Allergy {
  id: string;
  name: string;
  category: string;
  reaction_type?: string;
  severity?: string;
  onset_date?: string;
  diagnosed_by?: string;
  status: string;
}

const CATEGORIES = ['medication', 'food', 'environmental', 'contact', 'other'];
const SEVERITIES = ['mild', 'moderate', 'severe', 'life_threatening'];
const REACTIONS = ['anaphylaxis', 'urticaria', 'angioedema', 'respiratory', 'gastrointestinal', 'skin', 'other'];

const SEVERITY_COLORS: Record<string, string> = {
  mild: 'status-normal', moderate: 'status-borderline',
  severe: 'status-abnormal', life_threatening: 'status-critical',
};

export function Allergies() {
  const { t } = useTranslation();
  const { data: profilesData } = useProfiles();
  const profiles = profilesData || [];
  const [selectedProfile, setSelectedProfile] = useState('');
  const [showForm, setShowForm] = useState(false);
  const [deleteTarget, setDeleteTarget] = useState<string | null>(null);
  const [editTarget, setEditTarget] = useState<Allergy | null>(null);
  const queryClient = useQueryClient();
  const profileId = selectedProfile || profiles[0]?.id || '';

  const { data, isLoading } = useQuery({
    queryKey: ['allergies', profileId],
    queryFn: () => api.get<{ items: Allergy[] }>(`/api/v1/profiles/${profileId}/allergies`),
    enabled: !!profileId,
  });

  const createMutation = useMutation({
    mutationFn: (a: Partial<Allergy>) => api.post(`/api/v1/profiles/${profileId}/allergies`, a),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['allergies', profileId] });
      setShowForm(false);
      reset();
    },
  });

  const deleteMutation = useMutation({
    mutationFn: (id: string) => api.delete(`/api/v1/profiles/${profileId}/allergies/${id}`),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['allergies', profileId] }),
  });

  const updateMutation = useMutation({
    mutationFn: (data: Partial<Allergy> & { id: string }) =>
      api.patch(`/api/v1/profiles/${profileId}/allergies/${data.id}`, data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['allergies', profileId] });
      setEditTarget(null);
      editReset();
    },
  });

  const { register, handleSubmit, reset } = useForm<Partial<Allergy>>();
  const { register: editRegister, handleSubmit: editHandleSubmit, reset: editReset, setValue: editSetValue } = useForm<Partial<Allergy>>();

  useEffect(() => {
    if (editTarget) {
      editSetValue('name', editTarget.name);
      editSetValue('category', editTarget.category);
      editSetValue('severity', editTarget.severity || '');
      editSetValue('reaction_type', editTarget.reaction_type || '');
      editSetValue('diagnosed_by', editTarget.diagnosed_by || '');
    }
  }, [editTarget, editSetValue]);

  const items = data?.items || [];

  return (
    <div className="page">
      <div className="page-header">
        <h2>{t('nav.allergies')}</h2>
        <div className="page-actions">
          <ProfileSelector selectedId={profileId} onSelect={setSelectedProfile} />
          <button className="btn btn-add" onClick={() => setShowForm(!showForm)}>+ {t('common.add')}</button>
        </div>
      </div>

      {showForm && (
        <div className="modal-overlay" onClick={() => setShowForm(false)}>
          <div className="modal" onClick={(e) => e.stopPropagation()}>
            <div className="modal-header">
              <h3>{t('allergies.add_allergy')}</h3>
              <button className="modal-close" onClick={() => setShowForm(false)}>&times;</button>
            </div>
            <div className="modal-body">
              <form id="allergy-create-form" onSubmit={handleSubmit((data) => createMutation.mutate({ ...data, status: 'active' }))}>
                <div className="form-row">
                  <div className="form-group"><label>{t('allergies.allergen')} *</label><input type="text" {...register('name')} required placeholder={t('allergies.allergen_placeholder')} /></div>
                  <div className="form-group"><label>{t('allergies.category_label')} *</label>
                    <select {...register('category')} required>{CATEGORIES.map((c) => <option key={c} value={c}>{t('allergies.cat_' + c)}</option>)}</select>
                  </div>
                </div>
                <div className="form-row">
                  <div className="form-group"><label>{t('allergies.severity')}</label>
                    <select {...register('severity')}><option value="">{t('common.select')}</option>{SEVERITIES.map((s) => <option key={s} value={s}>{t('allergies.sev_' + s)}</option>)}</select>
                  </div>
                  <div className="form-group"><label>{t('allergies.reaction_type')}</label>
                    <select {...register('reaction_type')}><option value="">{t('common.select')}</option>{REACTIONS.map((r) => <option key={r} value={r}>{t('allergies.react_' + r)}</option>)}</select>
                  </div>
                  <div className="form-group"><label>{t('allergies.diagnosed_by')}</label><input type="text" {...register('diagnosed_by')} /></div>
                </div>
              </form>
            </div>
            <div className="modal-footer">
              <button className="btn btn-secondary" onClick={() => setShowForm(false)}>{t('common.cancel')}</button>
              <button type="submit" form="allergy-create-form" className="btn btn-add" disabled={createMutation.isPending}>{t('common.save')}</button>
            </div>
          </div>
        </div>
      )}

      <div className="card">
        {isLoading ? <p>{t('common.loading')}</p> : items.length === 0 ? <p className="text-muted">{t('common.no_data')}</p> : (
          <div className="med-list">
            {items.map((a) => (
              <div key={a.id} className="med-item" style={{ cursor: 'pointer' }} onClick={() => setEditTarget(a)}>
                <div className="med-info">
                  <div className="med-name">{a.name}</div>
                  <div className="med-details">
                    {t('allergies.cat_' + a.category)} {a.reaction_type && `· ${t('allergies.react_' + a.reaction_type)}`}
                  </div>
                </div>
                <div className="med-actions">
                  {a.severity && <span className={`badge ${SEVERITY_COLORS[a.severity] || ''}`}>{t('allergies.sev_' + a.severity)}</span>}
                  <span className={`badge ${a.status === 'active' ? 'badge-active' : 'badge-inactive'}`}>{t('allergies.status_' + a.status)}</span>
                  <button className="btn-icon-sm" onClick={(e) => { e.stopPropagation(); setDeleteTarget(a.id); }} title={t('common.delete')}>×</button>
                </div>
              </div>
            ))}
          </div>
        )}
      </div>

      {/* Edit Modal */}
      {editTarget && (
        <div className="modal-overlay" onClick={() => setEditTarget(null)}>
          <div className="modal" onClick={(e) => e.stopPropagation()}>
            <div className="modal-header">
              <h3>{t('allergies.edit')}</h3>
              <button className="modal-close" onClick={() => setEditTarget(null)}>&times;</button>
            </div>
            <div className="modal-body">
              <form id="allergy-edit-form" onSubmit={editHandleSubmit((data) => updateMutation.mutate({ ...data, id: editTarget.id }))}>
                <div className="form-row">
                  <div className="form-group"><label>{t('allergies.allergen')} *</label><input type="text" {...editRegister('name')} required placeholder={t('allergies.allergen_placeholder')} /></div>
                  <div className="form-group"><label>{t('allergies.category_label')} *</label>
                    <select {...editRegister('category')} required>{CATEGORIES.map((c) => <option key={c} value={c}>{t('allergies.cat_' + c)}</option>)}</select>
                  </div>
                </div>
                <div className="form-row">
                  <div className="form-group"><label>{t('allergies.severity')}</label>
                    <select {...editRegister('severity')}><option value="">{t('common.select')}</option>{SEVERITIES.map((s) => <option key={s} value={s}>{t('allergies.sev_' + s)}</option>)}</select>
                  </div>
                  <div className="form-group"><label>{t('allergies.reaction_type')}</label>
                    <select {...editRegister('reaction_type')}><option value="">{t('common.select')}</option>{REACTIONS.map((r) => <option key={r} value={r}>{t('allergies.react_' + r)}</option>)}</select>
                  </div>
                  <div className="form-group"><label>{t('allergies.diagnosed_by')}</label><input type="text" {...editRegister('diagnosed_by')} /></div>
                </div>
              </form>
            </div>
            <div className="modal-footer">
              <button className="btn btn-secondary" onClick={() => setEditTarget(null)}>{t('common.cancel')}</button>
              <button type="submit" form="allergy-edit-form" className="btn btn-add" disabled={updateMutation.isPending}>{t('common.save')}</button>
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
