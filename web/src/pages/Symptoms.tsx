import { useState } from 'react';
import { useTranslation } from 'react-i18next';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { useForm } from 'react-hook-form';
import { ProfileSelector } from '../components/ProfileSelector';
import { useDateFormat } from '../hooks/useDateLocale';
import { ConfirmDelete } from '../components/ConfirmDelete';
import { useProfiles } from '../hooks/useProfiles';
import { api } from '../api/client';

interface SymptomEntry {
  symptom_type: string;
  intensity: number;
  body_region?: string;
  duration_minutes?: number;
}

interface SymptomRecord {
  id: string;
  recorded_at: string;
  entries: SymptomEntry[];
  trigger_factors?: string[];
  notes?: string;
}

const SYMPTOM_TYPES = [
  'pain', 'headache', 'nausea', 'fatigue', 'dizziness',
  'shortness_of_breath', 'anxiety', 'mood', 'sleep_quality', 'appetite', 'custom',
];
const BODY_REGIONS = ['head', 'neck', 'chest', 'abdomen', 'back', 'left_arm', 'right_arm', 'left_leg', 'right_leg', 'general'];

function intensityColor(i: number): string {
  if (i >= 8) return 'status-critical';
  if (i >= 6) return 'status-abnormal';
  if (i >= 4) return 'status-borderline';
  return 'status-normal';
}

export function Symptoms() {
  const { t } = useTranslation();
  const { fmt } = useDateFormat();
  const { data: profilesData } = useProfiles();
  const profiles = profilesData || [];
  const [selectedProfile, setSelectedProfile] = useState('');
  const [showForm, setShowForm] = useState(false);
  const [deleteTarget, setDeleteTarget] = useState<string | null>(null);
  const [editTarget, setEditTarget] = useState<SymptomRecord | null>(null);
  const queryClient = useQueryClient();
  const profileId = selectedProfile || profiles[0]?.id || '';

  const { data, isLoading } = useQuery({
    queryKey: ['symptoms', profileId],
    queryFn: () => api.get<{ items: SymptomRecord[]; total: number }>(`/api/v1/profiles/${profileId}/symptoms`),
    enabled: !!profileId,
  });

  const createMutation = useMutation({
    mutationFn: (s: Partial<SymptomRecord>) => api.post(`/api/v1/profiles/${profileId}/symptoms`, s),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['symptoms', profileId] });
      setShowForm(false);
      reset();
    },
  });

  const updateMutation = useMutation({
    mutationFn: ({ id, ...data }: Partial<SymptomRecord> & { id: string }) =>
      api.patch(`/api/v1/profiles/${profileId}/symptoms/${id}`, data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['symptoms', profileId] });
      setEditTarget(null);
    },
  });

  const deleteMutation = useMutation({
    mutationFn: (id: string) => api.delete(`/api/v1/profiles/${profileId}/symptoms/${id}`),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['symptoms', profileId] }),
  });

  const { register, handleSubmit, reset, watch } = useForm<{
    symptom_type: string;
    intensity: number;
    body_region: string;
    trigger_factors: string;
    notes: string;
  }>();

  const editForm = useForm<{
    symptom_type: string;
    intensity: number;
    body_region: string;
    trigger_factors: string;
    notes: string;
  }>({ values: editTarget ? {
    symptom_type: editTarget.entries?.[0]?.symptom_type || '',
    intensity: editTarget.entries?.[0]?.intensity || 0,
    body_region: editTarget.entries?.[0]?.body_region || '',
    trigger_factors: editTarget.trigger_factors?.join(', ') || '',
    notes: editTarget.notes || '',
  } : undefined });

  const items = data?.items || [];

  return (
    <div className="page">
      <div className="page-header">
        <h2>{t('nav.symptoms')}</h2>
        <div className="page-actions">
          <ProfileSelector selectedId={profileId} onSelect={setSelectedProfile} />
          <button className="btn btn-add" onClick={() => setShowForm(!showForm)}>{t('symptoms.quick_entry')}</button>
        </div>
      </div>

      {showForm && (
        <div className="modal-overlay" onClick={() => setShowForm(false)}>
          <div className="modal" onClick={(e) => e.stopPropagation()}>
            <div className="modal-header">
              <h3>{t('symptoms.add')}</h3>
              <button className="btn-icon-sm" onClick={() => setShowForm(false)}>&times;</button>
            </div>
            <div className="modal-body">
              <form id="symptom-create-form" onSubmit={handleSubmit((data) => {
                createMutation.mutate({
                  recorded_at: new Date().toISOString(),
                  entries: [{
                    symptom_type: data.symptom_type,
                    intensity: Number(data.intensity),
                    body_region: data.body_region || undefined,
                  }],
                  trigger_factors: data.trigger_factors ? data.trigger_factors.split(',').map((s) => s.trim()) : undefined,
                  notes: data.notes || undefined,
                });
              })}>
                <div className="form-row">
                  <div className="form-group"><label>{t('symptoms.symptom')} *</label>
                    <select {...register('symptom_type')} required>
                      {SYMPTOM_TYPES.map((s) => <option key={s} value={s}>{t('symptoms.type_' + s)}</option>)}
                    </select>
                  </div>
                  <div className="form-group">
                    <label>{t('symptoms.intensity')}: {watch('intensity') || 0}</label>
                    <input type="range" min="0" max="10" {...register('intensity')} style={{ width: '100%' }} />
                  </div>
                  <div className="form-group"><label>{t('symptoms.body_region')}</label>
                    <select {...register('body_region')}>
                      <option value="">{t('common.not_specified')}</option>
                      {BODY_REGIONS.map((r) => <option key={r} value={r}>{t('symptoms.region_' + r)}</option>)}
                    </select>
                  </div>
                </div>
                <div className="form-group"><label>{t('symptoms.trigger_factors')} ({t('symptoms.trigger_hint')})</label>
                  <input type="text" {...register('trigger_factors')} placeholder="e.g. stress, weather change" />
                </div>
                <div className="form-group"><label>{t('common.notes')}</label><textarea rows={2} {...register('notes')} /></div>
              </form>
            </div>
            <div className="modal-footer">
              <button type="submit" form="symptom-create-form" className="btn btn-add" disabled={createMutation.isPending}>{t('common.save')}</button>
              <button type="button" className="btn btn-secondary" onClick={() => setShowForm(false)}>{t('common.cancel')}</button>
            </div>
          </div>
        </div>
      )}

      <div className="card">
        {isLoading ? <p>{t('common.loading')}</p> : items.length === 0 ? <p className="text-muted">{t('common.no_data')}</p> : (
          <div className="timeline">
            {items.map((record) => (
              <div key={record.id} className="timeline-item" onClick={() => setEditTarget(record)} style={{ cursor: 'pointer' }}>
                <div className="timeline-icon">📊</div>
                <div className="timeline-content" style={{ position: 'relative' }}>
                  <button
                    className="btn-icon-sm"
                    style={{ position: 'absolute', top: 0, right: 0 }}
                    onClick={(e) => { e.stopPropagation(); setDeleteTarget(record.id); }}
                    title={t('common.delete')}
                  >×</button>
                  <div className="timeline-date">{fmt(record.recorded_at, 'dd. MMM yyyy, HH:mm')}</div>
                  <div className="symptom-entries">
                    {record.entries?.map((e, i) => (
                      <div key={i} className="symptom-entry">
                        <span className="med-name">{t('symptoms.type_' + e.symptom_type)}</span>
                        <span className={`badge ${intensityColor(e.intensity)}`}>{e.intensity}/10</span>
                        {e.body_region && <span className="badge badge-info">{t('symptoms.region_' + e.body_region)}</span>}
                      </div>
                    ))}
                  </div>
                  {record.trigger_factors && record.trigger_factors.length > 0 && (
                    <div className="doc-tags" style={{ marginTop: 6 }}>
                      {record.trigger_factors.map((tf) => <span key={tf} className="tag">{tf}</span>)}
                    </div>
                  )}
                  {record.notes && <p className="timeline-desc">{record.notes}</p>}
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
              <h3>{t('symptoms.edit')}</h3>
              <button className="modal-close" onClick={() => setEditTarget(null)}>&times;</button>
            </div>
            <div className="modal-body">
              <form id="symptom-edit-form" onSubmit={editForm.handleSubmit((data) => {
                updateMutation.mutate({
                  id: editTarget.id,
                  recorded_at: editTarget.recorded_at,
                  entries: [{
                    symptom_type: data.symptom_type,
                    intensity: Number(data.intensity),
                    body_region: data.body_region || undefined,
                  }],
                  trigger_factors: data.trigger_factors ? data.trigger_factors.split(',').map((s) => s.trim()) : undefined,
                  notes: data.notes || undefined,
                });
              })}>
                <div className="form-row">
                  <div className="form-group"><label>{t('symptoms.symptom')} *</label>
                    <select {...editForm.register('symptom_type')} required>
                      {SYMPTOM_TYPES.map((s) => <option key={s} value={s}>{t('symptoms.type_' + s)}</option>)}
                    </select>
                  </div>
                  <div className="form-group">
                    <label>{t('symptoms.intensity')}: {editForm.watch('intensity') || 0}</label>
                    <input type="range" min="0" max="10" {...editForm.register('intensity')} style={{ width: '100%' }} />
                  </div>
                  <div className="form-group"><label>{t('symptoms.body_region')}</label>
                    <select {...editForm.register('body_region')}>
                      <option value="">{t('common.not_specified')}</option>
                      {BODY_REGIONS.map((r) => <option key={r} value={r}>{t('symptoms.region_' + r)}</option>)}
                    </select>
                  </div>
                </div>
                <div className="form-group"><label>{t('symptoms.trigger_factors')} ({t('symptoms.trigger_hint')})</label>
                  <input type="text" {...editForm.register('trigger_factors')} placeholder="e.g. stress, weather change" />
                </div>
                <div className="form-group"><label>{t('common.notes')}</label><textarea rows={2} {...editForm.register('notes')} /></div>
              </form>
            </div>
            <div className="modal-footer">
              <button type="button" className="btn btn-secondary" onClick={() => setEditTarget(null)}>{t('common.cancel')}</button>
              <button type="submit" form="symptom-edit-form" className="btn btn-add" disabled={updateMutation.isPending}>{updateMutation.isPending ? t('common.loading') : t('common.save')}</button>
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
