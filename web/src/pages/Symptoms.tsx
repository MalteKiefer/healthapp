import { useState } from 'react';
import { useTranslation } from 'react-i18next';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { useForm } from 'react-hook-form';
import { format } from 'date-fns';
import { ProfileSelector } from '../components/ProfileSelector';
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
  const { data: profilesData } = useProfiles();
  const profiles = profilesData || [];
  const [selectedProfile, setSelectedProfile] = useState('');
  const [showForm, setShowForm] = useState(false);
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

  const { register, handleSubmit, reset, watch } = useForm<{
    symptom_type: string;
    intensity: number;
    body_region: string;
    trigger_factors: string;
    notes: string;
  }>();

  const items = data?.items || [];

  return (
    <div className="page">
      <div className="page-header">
        <h2>{t('nav.symptoms')}</h2>
        <div className="page-actions">
          <ProfileSelector selectedId={profileId} onSelect={setSelectedProfile} />
          <button className="btn btn-add" onClick={() => setShowForm(!showForm)}>+ Quick Entry</button>
        </div>
      </div>

      {showForm && (
        <div className="card form-card">
          <h3>{t('symptoms.add')}</h3>
          <form onSubmit={handleSubmit((data) => {
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
                  {SYMPTOM_TYPES.map((s) => <option key={s} value={s}>{s.replace(/_/g, ' ')}</option>)}
                </select>
              </div>
              <div className="form-group">
                <label>Intensity (0-10): {watch('intensity') || 0}</label>
                <input type="range" min="0" max="10" {...register('intensity')} style={{ width: '100%' }} />
              </div>
              <div className="form-group"><label>{t('symptoms.body_region')}</label>
                <select {...register('body_region')}>
                  <option value="">{t('common.not_specified')}</option>
                  {BODY_REGIONS.map((r) => <option key={r} value={r}>{r.replace(/_/g, ' ')}</option>)}
                </select>
              </div>
            </div>
            <div className="form-group"><label>{t('symptoms.trigger_factors')} ({t('symptoms.trigger_hint')})</label>
              <input type="text" {...register('trigger_factors')} placeholder="e.g. stress, weather change" />
            </div>
            <div className="form-group"><label>{t('common.notes')}</label><textarea rows={2} {...register('notes')} /></div>
            <div className="form-actions">
              <button type="submit" className="btn btn-add" disabled={createMutation.isPending}>{t('common.save')}</button>
              <button type="button" className="btn btn-secondary" onClick={() => setShowForm(false)}>{t('common.cancel')}</button>
            </div>
          </form>
        </div>
      )}

      <div className="card">
        {isLoading ? <p>{t('common.loading')}</p> : items.length === 0 ? <p className="text-muted">{t('common.no_data')}</p> : (
          <div className="timeline">
            {items.map((record) => (
              <div key={record.id} className="timeline-item">
                <div className="timeline-icon">📊</div>
                <div className="timeline-content">
                  <div className="timeline-date">{format(new Date(record.recorded_at), 'MMM d, yyyy HH:mm')}</div>
                  <div className="symptom-entries">
                    {record.entries?.map((e, i) => (
                      <div key={i} className="symptom-entry">
                        <span className="med-name">{e.symptom_type.replace(/_/g, ' ')}</span>
                        <span className={`badge ${intensityColor(e.intensity)}`}>{e.intensity}/10</span>
                        {e.body_region && <span className="badge badge-info">{e.body_region.replace(/_/g, ' ')}</span>}
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
    </div>
  );
}
