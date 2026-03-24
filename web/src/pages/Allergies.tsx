import { useState } from 'react';
import { useTranslation } from 'react-i18next';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { useForm } from 'react-hook-form';
import { ProfileSelector } from '../components/ProfileSelector';
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
  const profiles = profilesData?.items || [];
  const [selectedProfile, setSelectedProfile] = useState('');
  const [showForm, setShowForm] = useState(false);
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

  const { register, handleSubmit, reset } = useForm<Partial<Allergy>>();
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
        <div className="card form-card">
          <h3>Add Allergy</h3>
          <form onSubmit={handleSubmit((data) => createMutation.mutate({ ...data, status: 'active' }))}>
            <div className="form-row">
              <div className="form-group"><label>Allergen *</label><input type="text" {...register('name')} required placeholder="e.g. Penicillin, Peanuts" /></div>
              <div className="form-group"><label>Category *</label>
                <select {...register('category')} required>{CATEGORIES.map((c) => <option key={c} value={c}>{c}</option>)}</select>
              </div>
            </div>
            <div className="form-row">
              <div className="form-group"><label>Severity</label>
                <select {...register('severity')}><option value="">Select...</option>{SEVERITIES.map((s) => <option key={s} value={s}>{s.replace(/_/g, ' ')}</option>)}</select>
              </div>
              <div className="form-group"><label>Reaction Type</label>
                <select {...register('reaction_type')}><option value="">Select...</option>{REACTIONS.map((r) => <option key={r} value={r}>{r}</option>)}</select>
              </div>
              <div className="form-group"><label>Diagnosed By</label><input type="text" {...register('diagnosed_by')} /></div>
            </div>
            <div className="form-actions">
              <button type="submit" className="btn btn-add" disabled={createMutation.isPending}>{t('common.save')}</button>
              <button type="button" className="btn btn-secondary" onClick={() => setShowForm(false)}>{t('common.cancel')}</button>
            </div>
          </form>
        </div>
      )}

      <div className="card">
        {isLoading ? <p>{t('common.loading')}</p> : items.length === 0 ? <p className="text-muted">{t('common.no_data')}</p> : (
          <div className="med-list">
            {items.map((a) => (
              <div key={a.id} className="med-item">
                <div className="med-info">
                  <div className="med-name">{a.name}</div>
                  <div className="med-details">
                    {a.category} {a.reaction_type && `· ${a.reaction_type}`}
                  </div>
                </div>
                <div className="med-actions">
                  {a.severity && <span className={`badge ${SEVERITY_COLORS[a.severity] || ''}`}>{a.severity.replace(/_/g, ' ')}</span>}
                  <span className={`badge ${a.status === 'active' ? 'badge-active' : 'badge-inactive'}`}>{a.status}</span>
                  <button className="btn-icon-sm" onClick={() => deleteMutation.mutate(a.id)} title={t('common.delete')}>×</button>
                </div>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}
