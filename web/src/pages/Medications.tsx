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
  const profiles = profilesData || [];
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
            {t('medications.active_only')}
          </label>
          <button className="btn btn-add" onClick={() => setShowForm(!showForm)}>
            + {t('common.add')}
          </button>
        </div>
      </div>

      {showForm && (
        <div className="card form-card">
          <h3>{t('medications.add')}</h3>
          <form onSubmit={handleSubmit(onSubmit)}>
            <div className="form-row">
              <div className="form-group">
                <label>{t('common.name')} *</label>
                <input type="text" {...register('name')} required />
              </div>
              <div className="form-group">
                <label>{t('medications.dosage')}</label>
                <input type="text" {...register('dosage')} placeholder={t('medications.placeholder_dosage')} />
              </div>
              <div className="form-group">
                <label>{t('medications.unit')}</label>
                <input type="text" {...register('unit')} placeholder={t('medications.placeholder_unit')} />
              </div>
            </div>
            <div className="form-row">
              <div className="form-group">
                <label>{t('medications.frequency')}</label>
                <input type="text" {...register('frequency')} placeholder={t('medications.placeholder_frequency')} />
              </div>
              <div className="form-group">
                <label>{t('medications.route')}</label>
                <select {...register('route')}>
                  <option value="">{t('common.select')}</option>
                  {ROUTES.map((r) => <option key={r} value={r}>{t('medications.route_' + r)}</option>)}
                </select>
              </div>
              <div className="form-group">
                <label>{t('medications.prescribed_by')}</label>
                <input type="text" {...register('prescribed_by')} />
              </div>
            </div>
            <div className="form-group">
              <label>{t('medications.reason')}</label>
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
                    <div className="med-meta">{t('medications.prescribed_by')}: {med.prescribed_by}</div>
                  )}
                  {med.started_at && (
                    <div className="med-meta">
                      {t('common.since')} {format(new Date(med.started_at), 'MMM d, yyyy')}
                      {med.ended_at && ` — ${t('common.ended')} ${format(new Date(med.ended_at), 'MMM d, yyyy')}`}
                    </div>
                  )}
                </div>
                <div className="med-actions">
                  <span className={`badge ${med.ended_at ? 'badge-inactive' : 'badge-active'}`}>
                    {med.ended_at ? t('common.inactive') : t('common.active')}
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
