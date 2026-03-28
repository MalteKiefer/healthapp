import { useState } from 'react';
import { useTranslation } from 'react-i18next';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { useForm } from 'react-hook-form';
import { isPast, differenceInDays } from 'date-fns';
import { ProfileSelector } from '../components/ProfileSelector';
import { useDateFormat } from '../hooks/useDateLocale';
import { ConfirmDelete } from '../components/ConfirmDelete';
import { useProfiles } from '../hooks/useProfiles';
import { api } from '../api/client';

interface Vaccination {
  id: string;
  vaccine_name: string;
  trade_name?: string;
  manufacturer?: string;
  lot_number?: string;
  dose_number?: number;
  administered_at: string;
  administered_by?: string;
  next_due_at?: string;
  site?: string;
  notes?: string;
}

export function Vaccinations() {
  const { t } = useTranslation();
  const { fmt } = useDateFormat();
  const { data: profilesData } = useProfiles();
  const profiles = profilesData || [];
  const [selectedProfile, setSelectedProfile] = useState('');
  const [showForm, setShowForm] = useState(false);
  const [deleteTarget, setDeleteTarget] = useState<string | null>(null);
  const queryClient = useQueryClient();

  const profileId = selectedProfile || profiles[0]?.id || '';

  const { data, isLoading } = useQuery({
    queryKey: ['vaccinations', profileId],
    queryFn: () => api.get<{ items: Vaccination[] }>(`/api/v1/profiles/${profileId}/vaccinations`),
    enabled: !!profileId,
  });

  const { data: dueData } = useQuery({
    queryKey: ['vaccinations-due', profileId],
    queryFn: () => api.get<{ items: Vaccination[] }>(`/api/v1/profiles/${profileId}/vaccinations/due`),
    enabled: !!profileId,
  });

  const createMutation = useMutation({
    mutationFn: (v: Partial<Vaccination>) => api.post(`/api/v1/profiles/${profileId}/vaccinations`, v),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['vaccinations', profileId] });
      setShowForm(false);
      reset();
    },
  });

  const deleteMutation = useMutation({
    mutationFn: (id: string) => api.delete(`/api/v1/profiles/${profileId}/vaccinations/${id}`),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['vaccinations', profileId] });
      queryClient.invalidateQueries({ queryKey: ['vaccinations-due', profileId] });
    },
  });

  const { register, handleSubmit, reset } = useForm<Partial<Vaccination>>();
  const items = data?.items || [];
  const dueItems = dueData?.items || [];

  return (
    <div className="page">
      <div className="page-header">
        <h2>{t('nav.vaccinations')}</h2>
        <div className="page-actions">
          <ProfileSelector selectedId={profileId} onSelect={setSelectedProfile} />
          <button className="btn btn-add" onClick={() => setShowForm(!showForm)}>+ {t('common.add')}</button>
        </div>
      </div>

      {dueItems.length > 0 && (
        <div className="card" style={{ borderLeft: '4px solid var(--color-warning)', marginBottom: 16 }}>
          <h3>Upcoming Boosters</h3>
          {dueItems.map((v) => {
            const days = v.next_due_at ? differenceInDays(new Date(v.next_due_at), new Date()) : 0;
            const overdue = v.next_due_at ? isPast(new Date(v.next_due_at)) : false;
            return (
              <div key={v.id} className="med-item" style={{ border: 'none', padding: '8px 0' }}>
                <div className="med-info">
                  <div className="med-name">{v.vaccine_name}</div>
                  <div className="med-details">
                    {v.next_due_at && (overdue
                      ? <span className="status-abnormal">Overdue by {Math.abs(days)} days</span>
                      : <span className="status-borderline">Due in {days} days ({fmt(v.next_due_at, 'dd. MMM yyyy')})</span>
                    )}
                  </div>
                </div>
              </div>
            );
          })}
        </div>
      )}

      {showForm && (
        <div className="card form-card">
          <h3>Record Vaccination</h3>
          <form onSubmit={handleSubmit((data) => createMutation.mutate(data))}>
            <div className="form-row">
              <div className="form-group">
                <label>Vaccine Name *</label>
                <input type="text" {...register('vaccine_name')} required />
              </div>
              <div className="form-group">
                <label>Trade Name</label>
                <input type="text" {...register('trade_name')} />
              </div>
              <div className="form-group">
                <label>Manufacturer</label>
                <input type="text" {...register('manufacturer')} />
              </div>
            </div>
            <div className="form-row">
              <div className="form-group">
                <label>Date Administered *</label>
                <input type="date" {...register('administered_at')} required />
              </div>
              <div className="form-group">
                <label>Dose Number</label>
                <input type="number" min="1" {...register('dose_number', { valueAsNumber: true })} />
              </div>
              <div className="form-group">
                <label>Lot Number</label>
                <input type="text" {...register('lot_number')} />
              </div>
            </div>
            <div className="form-row">
              <div className="form-group">
                <label>Administered By</label>
                <input type="text" {...register('administered_by')} />
              </div>
              <div className="form-group">
                <label>Next Due Date</label>
                <input type="date" {...register('next_due_at')} />
              </div>
              <div className="form-group">
                <label>Injection Site</label>
                <input type="text" {...register('site')} placeholder="e.g. left arm" />
              </div>
            </div>
            <div className="form-actions">
              <button type="submit" className="btn btn-add" disabled={createMutation.isPending}>{t('common.save')}</button>
              <button type="button" className="btn btn-secondary" onClick={() => setShowForm(false)}>{t('common.cancel')}</button>
            </div>
          </form>
        </div>
      )}

      <div className="card">
        <h3>Vaccination History</h3>
        {isLoading ? <p>{t('common.loading')}</p> : items.length === 0 ? <p className="text-muted">{t('common.no_data')}</p> : (
          <div className="table-scroll">
            <table className="data-table">
              <thead><tr><th>Date</th><th>Vaccine</th><th>Dose</th><th>Lot #</th><th>Administered By</th><th>Next Due</th><th></th></tr></thead>
              <tbody>
                {items.map((v) => (
                  <tr key={v.id}>
                    <td>{fmt(v.administered_at, 'dd. MMM yyyy')}</td>
                    <td><strong>{v.vaccine_name}</strong>{v.trade_name && <span className="text-muted"> ({v.trade_name})</span>}</td>
                    <td>{v.dose_number || '—'}</td>
                    <td>{v.lot_number || '—'}</td>
                    <td>{v.administered_by || '—'}</td>
                    <td>{v.next_due_at ? fmt(v.next_due_at, 'dd. MMM yyyy') : '—'}</td>
                    <td>
                      <button
                        className="btn-icon-sm"
                        onClick={() => setDeleteTarget(v.id)}
                        title={t('common.delete')}
                      >×</button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>

      <ConfirmDelete
        open={!!deleteTarget}
        onConfirm={() => { deleteMutation.mutate(deleteTarget!); setDeleteTarget(null); }}
        onCancel={() => setDeleteTarget(null)}
        pending={deleteMutation.isPending}
      />
    </div>
  );
}
