import { useState } from 'react';
import { useTranslation } from 'react-i18next';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { useForm } from 'react-hook-form';
import { format } from 'date-fns';
import { ProfileSelector } from '../components/ProfileSelector';
import { useProfiles } from '../hooks/useProfiles';
import { medicationsApi, type Medication } from '../api/medications';

const ROUTES = ['oral', 'injection', 'topical', 'inhalation', 'sublingual', 'rectal', 'other'];

export function Medications() {
  const { t } = useTranslation();
  const { data: profilesData } = useProfiles();
  const profiles = profilesData?.items || [];
  const [selectedProfile, setSelectedProfile] = useState('');
  const [showActive, setShowActive] = useState(true);
  const [showForm, setShowForm] = useState(false);
  const queryClient = useQueryClient();

  const profileId = selectedProfile || profiles[0]?.id || '';

  const { data, isLoading } = useQuery({
    queryKey: ['medications', profileId, showActive],
    queryFn: () => showActive ? medicationsApi.active(profileId) : medicationsApi.list(profileId),
    enabled: !!profileId,
  });

  const createMutation = useMutation({
    mutationFn: (med: Partial<Medication>) => medicationsApi.create(profileId, med),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['medications', profileId] });
      setShowForm(false);
      reset();
    },
  });

  const deleteMutation = useMutation({
    mutationFn: (id: string) => medicationsApi.delete(profileId, id),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['medications', profileId] }),
  });

  const { register, handleSubmit, reset } = useForm<Partial<Medication>>();

  const onSubmit = (formData: Partial<Medication>) => {
    createMutation.mutate(formData);
  };

  const items = data?.items || [];

  return (
    <div className="page">
      <div className="page-header">
        <h2>{t('nav.medications')}</h2>
        <div className="page-actions">
          <ProfileSelector selectedId={profileId} onSelect={setSelectedProfile} />
          <label className="toggle-label">
            <input
              type="checkbox"
              checked={showActive}
              onChange={(e) => setShowActive(e.target.checked)}
            />
            Active only
          </label>
          <button className="btn btn-add" onClick={() => setShowForm(!showForm)}>
            + {t('common.add')}
          </button>
        </div>
      </div>

      {showForm && (
        <div className="card form-card">
          <h3>Add Medication</h3>
          <form onSubmit={handleSubmit(onSubmit)}>
            <div className="form-row">
              <div className="form-group">
                <label>Name *</label>
                <input type="text" {...register('name')} required />
              </div>
              <div className="form-group">
                <label>Dosage</label>
                <input type="text" {...register('dosage')} placeholder="e.g. 500" />
              </div>
              <div className="form-group">
                <label>Unit</label>
                <input type="text" {...register('unit')} placeholder="e.g. mg" />
              </div>
            </div>
            <div className="form-row">
              <div className="form-group">
                <label>Frequency</label>
                <input type="text" {...register('frequency')} placeholder="e.g. twice daily" />
              </div>
              <div className="form-group">
                <label>Route</label>
                <select {...register('route')}>
                  <option value="">Select...</option>
                  {ROUTES.map((r) => <option key={r} value={r}>{r}</option>)}
                </select>
              </div>
              <div className="form-group">
                <label>Prescribed by</label>
                <input type="text" {...register('prescribed_by')} />
              </div>
            </div>
            <div className="form-group">
              <label>Reason</label>
              <input type="text" {...register('reason')} />
            </div>
            <div className="form-actions">
              <button type="submit" className="btn btn-add" disabled={createMutation.isPending}>
                {createMutation.isPending ? t('common.loading') : t('common.save')}
              </button>
              <button type="button" className="btn btn-secondary" onClick={() => setShowForm(false)}>
                {t('common.cancel')}
              </button>
            </div>
          </form>
        </div>
      )}

      <div className="card">
        {isLoading ? (
          <p>{t('common.loading')}</p>
        ) : items.length === 0 ? (
          <p className="text-muted">{t('common.no_data')}</p>
        ) : (
          <div className="med-list">
            {items.map((med) => (
              <div key={med.id} className="med-item">
                <div className="med-info">
                  <div className="med-name">{med.name}</div>
                  <div className="med-details">
                    {[med.dosage, med.unit, med.frequency, med.route].filter(Boolean).join(' · ')}
                  </div>
                  {med.prescribed_by && (
                    <div className="med-meta">Prescribed by: {med.prescribed_by}</div>
                  )}
                  {med.started_at && (
                    <div className="med-meta">
                      Since {format(new Date(med.started_at), 'MMM d, yyyy')}
                      {med.ended_at && ` — ended ${format(new Date(med.ended_at), 'MMM d, yyyy')}`}
                    </div>
                  )}
                </div>
                <div className="med-actions">
                  <span className={`badge ${med.ended_at ? 'badge-inactive' : 'badge-active'}`}>
                    {med.ended_at ? 'Ended' : 'Active'}
                  </span>
                  <button
                    className="btn-icon-sm"
                    onClick={() => deleteMutation.mutate(med.id)}
                    title={t('common.delete')}
                  >
                    ×
                  </button>
                </div>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}
