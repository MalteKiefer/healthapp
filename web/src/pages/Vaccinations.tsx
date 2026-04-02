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
import { ContactPicker } from '../components/ContactPicker';

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
  const [editTarget, setEditTarget] = useState<Vaccination | null>(null);
  const [sortCol, setSortCol] = useState<string>('administered_at');
  const [sortDir, setSortDir] = useState<'asc'|'desc'>('desc');
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

  const fixDates = (data: Record<string, unknown>, dateFields: string[]) => {
    const cleaned = { ...data };
    for (const field of dateFields) {
      const val = cleaned[field];
      if (typeof val === 'string' && val && !val.includes('T')) {
        cleaned[field] = new Date(val + 'T00:00:00').toISOString();
      }
      if (typeof val === 'string' && val === '') {
        delete cleaned[field];
      }
    }
    return cleaned;
  };

  const createMutation = useMutation({
    mutationFn: (v: Partial<Vaccination>) => api.post(`/api/v1/profiles/${profileId}/vaccinations`, fixDates(v as Record<string, unknown>, ['administered_at', 'next_due_at'])),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['vaccinations', profileId] });
      setShowForm(false);
      reset();
    },
  });

  const updateMutation = useMutation({
    mutationFn: ({ id, ...data }: Partial<Vaccination> & { id: string }) =>
      api.patch(`/api/v1/profiles/${profileId}/vaccinations/${id}`, fixDates(data as Record<string, unknown>, ['administered_at', 'next_due_at'])),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['vaccinations', profileId] });
      queryClient.invalidateQueries({ queryKey: ['vaccinations-due', profileId] });
      setEditTarget(null);
    },
  });

  const deleteMutation = useMutation({
    mutationFn: (id: string) => api.delete(`/api/v1/profiles/${profileId}/vaccinations/${id}`),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['vaccinations', profileId] });
      queryClient.invalidateQueries({ queryKey: ['vaccinations-due', profileId] });
    },
  });

  const { register, handleSubmit, reset, setValue, watch } = useForm<Partial<Vaccination>>();
  const editForm = useForm<Partial<Vaccination>>({ values: editTarget ? {
    vaccine_name: editTarget.vaccine_name,
    trade_name: editTarget.trade_name || '',
    manufacturer: editTarget.manufacturer || '',
    administered_at: editTarget.administered_at?.slice(0, 10) || '',
    dose_number: editTarget.dose_number,
    lot_number: editTarget.lot_number || '',
    administered_by: editTarget.administered_by || '',
    next_due_at: editTarget.next_due_at?.slice(0, 10) || '',
    site: editTarget.site || '',
  } : undefined });
  const items = data?.items || [];
  const dueItems = dueData?.items || [];

  const sortedItems = [...items].sort((a, b) => {
    const aVal = (a as unknown as Record<string,unknown>)[sortCol];
    const bVal = (b as unknown as Record<string,unknown>)[sortCol];
    if (aVal == null && bVal == null) return 0;
    if (aVal == null) return 1;
    if (bVal == null) return -1;
    const cmp = typeof aVal === 'string' ? aVal.localeCompare(bVal as string) : (aVal as number) - (bVal as number);
    return sortDir === 'asc' ? cmp : -cmp;
  });

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
          <h3>{t('vaccinations.upcoming_boosters')}</h3>
          {dueItems.map((v) => {
            const days = v.next_due_at ? differenceInDays(new Date(v.next_due_at), new Date()) : 0;
            const overdue = v.next_due_at ? isPast(new Date(v.next_due_at)) : false;
            return (
              <div key={v.id} className="med-item" style={{ border: 'none', padding: '8px 0' }}>
                <div className="med-info">
                  <div className="med-name">{v.vaccine_name}</div>
                  <div className="med-details">
                    {v.next_due_at && (overdue
                      ? <span className="status-abnormal">{t('vaccinations.overdue_by', { days: Math.abs(days) })}</span>
                      : <span className="status-borderline">{t('vaccinations.due_in', { days, date: fmt(v.next_due_at, 'dd. MMM yyyy') })}</span>
                    )}
                  </div>
                </div>
              </div>
            );
          })}
        </div>
      )}

      {showForm && (
        <div className="modal-overlay" onClick={() => setShowForm(false)}>
          <div className="modal" onClick={(e) => e.stopPropagation()}>
            <div className="modal-header">
              <h3>{t('vaccinations.record')}</h3>
              <button className="modal-close" onClick={() => setShowForm(false)} aria-label={t('common.close')}>&times;</button>
            </div>
            <div className="modal-body">
              <form id="vacc-create-form" onSubmit={handleSubmit((data) => createMutation.mutate(data))}>
                <div className="form-row">
                  <div className="form-group">
                    <label>{t('vaccinations.vaccine_name')} *</label>
                    <input type="text" {...register('vaccine_name')} required />
                  </div>
                  <div className="form-group">
                    <label>{t('vaccinations.trade_name')}</label>
                    <input type="text" {...register('trade_name')} />
                  </div>
                  <div className="form-group">
                    <label>{t('vaccinations.manufacturer')}</label>
                    <input type="text" {...register('manufacturer')} />
                  </div>
                </div>
                <div className="form-row">
                  <div className="form-group">
                    <label>{t('vaccinations.date_administered')} *</label>
                    <input type="date" {...register('administered_at')} required />
                  </div>
                  <div className="form-group">
                    <label>{t('vaccinations.dose_number')}</label>
                    <input type="number" min="1" {...register('dose_number', { valueAsNumber: true })} />
                  </div>
                  <div className="form-group">
                    <label>{t('vaccinations.lot_number')}</label>
                    <input type="text" {...register('lot_number')} />
                  </div>
                </div>
                <div className="form-row">
                  <ContactPicker profileId={profileId} value={watch('administered_by')} onChange={(name) => setValue('administered_by', name)} label={t('vaccinations.administered_by')} />
                  <div className="form-group">
                    <label>{t('vaccinations.next_due_date')}</label>
                    <input type="date" {...register('next_due_at')} />
                  </div>
                  <div className="form-group">
                    <label>{t('vaccinations.injection_site')}</label>
                    <input type="text" {...register('site')} placeholder={t('vaccinations.site_placeholder')} />
                  </div>
                </div>
              </form>
            </div>
            <div className="modal-footer">
              <button type="button" className="btn btn-secondary" onClick={() => setShowForm(false)}>{t('common.cancel')}</button>
              <button type="submit" form="vacc-create-form" className="btn btn-add" disabled={createMutation.isPending}>{createMutation.isPending ? t('common.loading') : t('common.save')}</button>
            </div>
          </div>
        </div>
      )}

      <div className="card">
        <h3>{t('vaccinations.history')}</h3>
        {isLoading ? <p>{t('common.loading')}</p> : items.length === 0 ? <p className="text-muted">{t('common.no_data')}</p> : (
          <div className="table-scroll">
            <table className="data-table">
              <thead><tr>
                <th style={{ cursor: 'pointer', userSelect: 'none' }} onClick={() => { if (sortCol === 'administered_at') setSortDir(d => d === 'asc' ? 'desc' : 'asc'); else { setSortCol('administered_at'); setSortDir('desc'); } }}>
                  {t('common.date')} {sortCol === 'administered_at' ? (sortDir === 'asc' ? '\u2191' : '\u2193') : ''}
                </th>
                <th style={{ cursor: 'pointer', userSelect: 'none' }} onClick={() => { if (sortCol === 'vaccine_name') setSortDir(d => d === 'asc' ? 'desc' : 'asc'); else { setSortCol('vaccine_name'); setSortDir('desc'); } }}>
                  {t('vaccinations.vaccine')} {sortCol === 'vaccine_name' ? (sortDir === 'asc' ? '\u2191' : '\u2193') : ''}
                </th>
                <th style={{ cursor: 'pointer', userSelect: 'none' }} onClick={() => { if (sortCol === 'dose_number') setSortDir(d => d === 'asc' ? 'desc' : 'asc'); else { setSortCol('dose_number'); setSortDir('desc'); } }}>
                  {t('vaccinations.dose')} {sortCol === 'dose_number' ? (sortDir === 'asc' ? '\u2191' : '\u2193') : ''}
                </th>
                <th className="hide-mobile">{t('vaccinations.lot')}</th>
                <th className="hide-mobile" style={{ cursor: 'pointer', userSelect: 'none' }} onClick={() => { if (sortCol === 'administered_by') setSortDir(d => d === 'asc' ? 'desc' : 'asc'); else { setSortCol('administered_by'); setSortDir('desc'); } }}>
                  {t('vaccinations.administered_by')} {sortCol === 'administered_by' ? (sortDir === 'asc' ? '\u2191' : '\u2193') : ''}
                </th>
                <th style={{ cursor: 'pointer', userSelect: 'none' }} onClick={() => { if (sortCol === 'next_due_at') setSortDir(d => d === 'asc' ? 'desc' : 'asc'); else { setSortCol('next_due_at'); setSortDir('desc'); } }}>
                  {t('vaccinations.next_due')} {sortCol === 'next_due_at' ? (sortDir === 'asc' ? '\u2191' : '\u2193') : ''}
                </th>
                <th></th>
              </tr></thead>
              <tbody>
                {sortedItems.map((v) => (
                  <tr key={v.id} onClick={() => setEditTarget(v)} style={{ cursor: 'pointer' }}>
                    <td>{fmt(v.administered_at, 'dd. MMM yyyy')}</td>
                    <td><strong>{v.vaccine_name}</strong>{v.trade_name && <span className="text-muted hide-sm"> ({v.trade_name})</span>}</td>
                    <td>{v.dose_number || '—'}</td>
                    <td className="hide-mobile">{v.lot_number || '—'}</td>
                    <td className="hide-mobile">{v.administered_by || '—'}</td>
                    <td>{v.next_due_at ? fmt(v.next_due_at, 'dd. MMM yyyy') : '—'}</td>
                    <td>
                      <button
                        className="btn-icon-sm"
                        onClick={(e) => { e.stopPropagation(); setDeleteTarget(v.id); }}
                        title={t('common.delete')}
                        aria-label={t('common.delete')}
                      >×</button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>

      {editTarget && (
        <div className="modal-overlay" onClick={() => setEditTarget(null)}>
          <div className="modal" onClick={(e) => e.stopPropagation()}>
            <div className="modal-header">
              <h3>{t('vaccinations.edit')}</h3>
              <button className="modal-close" onClick={() => setEditTarget(null)} aria-label={t('common.close')}>&times;</button>
            </div>
            <div className="modal-body">
              <form id="vacc-edit-form" onSubmit={editForm.handleSubmit((data) => updateMutation.mutate({ id: editTarget.id, ...data }))}>
                <div className="form-row">
                  <div className="form-group">
                    <label>{t('vaccinations.vaccine_name')} *</label>
                    <input type="text" {...editForm.register('vaccine_name')} required />
                  </div>
                  <div className="form-group">
                    <label>{t('vaccinations.trade_name')}</label>
                    <input type="text" {...editForm.register('trade_name')} />
                  </div>
                  <div className="form-group">
                    <label>{t('vaccinations.manufacturer')}</label>
                    <input type="text" {...editForm.register('manufacturer')} />
                  </div>
                </div>
                <div className="form-row">
                  <div className="form-group">
                    <label>{t('vaccinations.date_administered')} *</label>
                    <input type="date" {...editForm.register('administered_at')} required />
                  </div>
                  <div className="form-group">
                    <label>{t('vaccinations.dose_number')}</label>
                    <input type="number" min="1" {...editForm.register('dose_number', { valueAsNumber: true })} />
                  </div>
                  <div className="form-group">
                    <label>{t('vaccinations.lot_number')}</label>
                    <input type="text" {...editForm.register('lot_number')} />
                  </div>
                </div>
                <div className="form-row">
                  <ContactPicker profileId={profileId} value={editForm.watch('administered_by')} onChange={(name) => editForm.setValue('administered_by', name)} label={t('vaccinations.administered_by')} />
                  <div className="form-group">
                    <label>{t('vaccinations.next_due_date')}</label>
                    <input type="date" {...editForm.register('next_due_at')} />
                  </div>
                  <div className="form-group">
                    <label>{t('vaccinations.injection_site')}</label>
                    <input type="text" {...editForm.register('site')} placeholder={t('vaccinations.site_placeholder')} />
                  </div>
                </div>
              </form>
            </div>
            <div className="modal-footer">
              <button type="button" className="btn btn-secondary" onClick={() => setEditTarget(null)}>{t('common.cancel')}</button>
              <button type="submit" form="vacc-edit-form" className="btn btn-add" disabled={updateMutation.isPending}>{updateMutation.isPending ? t('common.loading') : t('common.save')}</button>
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
