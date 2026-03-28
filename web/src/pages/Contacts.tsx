import { useState } from 'react';
import { useTranslation } from 'react-i18next';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { useForm } from 'react-hook-form';
import { ProfileSelector } from '../components/ProfileSelector';
import { ConfirmDelete } from '../components/ConfirmDelete';
import { useProfiles } from '../hooks/useProfiles';
import { api } from '../api/client';

interface Contact {
  id: string;
  name: string;
  specialty?: string;
  facility?: string;
  phone?: string;
  email?: string;
  address?: string;
  notes?: string;
  is_emergency_contact: boolean;
}

export function Contacts() {
  const { t } = useTranslation();
  const { data: profilesData } = useProfiles();
  const profiles = profilesData || [];
  const [selectedProfile, setSelectedProfile] = useState('');
  const [showForm, setShowForm] = useState(false);
  const [deleteTarget, setDeleteTarget] = useState<string | null>(null);
  const queryClient = useQueryClient();
  const profileId = selectedProfile || profiles[0]?.id || '';

  const { data, isLoading } = useQuery({
    queryKey: ['contacts', profileId],
    queryFn: () => api.get<{ items: Contact[] }>(`/api/v1/profiles/${profileId}/contacts`),
    enabled: !!profileId,
  });

  const createMutation = useMutation({
    mutationFn: (c: Partial<Contact>) => api.post(`/api/v1/profiles/${profileId}/contacts`, c),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['contacts', profileId] });
      setShowForm(false);
      reset();
    },
  });

  const deleteMutation = useMutation({
    mutationFn: (id: string) => api.delete(`/api/v1/profiles/${profileId}/contacts/${id}`),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['contacts', profileId] }),
  });

  const { register, handleSubmit, reset } = useForm<Partial<Contact>>();
  const items = data?.items || [];

  return (
    <div className="page">
      <div className="page-header">
        <h2>{t('nav.contacts')}</h2>
        <div className="page-actions">
          <ProfileSelector selectedId={profileId} onSelect={setSelectedProfile} />
          <button className="btn btn-add" onClick={() => setShowForm(!showForm)}>+ {t('common.add')}</button>
        </div>
      </div>

      {showForm && (
        <div className="card form-card">
          <h3>{t('contacts.add')}</h3>
          <form onSubmit={handleSubmit((data) => createMutation.mutate(data))}>
            <div className="form-row">
              <div className="form-group"><label>{t('common.name')} *</label><input type="text" {...register('name')} required /></div>
              <div className="form-group"><label>{t('contacts.specialty')}</label><input type="text" {...register('specialty')} placeholder="e.g. Cardiology" /></div>
              <div className="form-group"><label>{t('contacts.facility')}</label><input type="text" {...register('facility')} /></div>
            </div>
            <div className="form-row">
              <div className="form-group"><label>{t('contacts.phone')}</label><input type="tel" {...register('phone')} /></div>
              <div className="form-group"><label>{t('contacts.email')}</label><input type="email" {...register('email')} /></div>
            </div>
            <div className="form-group"><label>{t('contacts.address')}</label><textarea rows={2} {...register('address')} /></div>
            <label className="toggle-label" style={{ marginBottom: 12 }}>
              <input type="checkbox" {...register('is_emergency_contact')} />
              Emergency contact
            </label>
            <div className="form-actions">
              <button type="submit" className="btn btn-add" disabled={createMutation.isPending}>{t('common.save')}</button>
              <button type="button" className="btn btn-secondary" onClick={() => setShowForm(false)}>{t('common.cancel')}</button>
            </div>
          </form>
        </div>
      )}

      <div className="card">
        {isLoading ? <p>{t('common.loading')}</p> : items.length === 0 ? <p className="text-muted">{t('common.no_data')}</p> : (
          <div className="contact-grid">
            {items.map((c) => (
              <div key={c.id} className="contact-card">
                <div className="contact-header">
                  <div className="contact-avatar">{c.name.charAt(0).toUpperCase()}</div>
                  <div>
                    <div className="contact-name">{c.name}</div>
                    {c.specialty && <div className="text-muted" style={{ fontSize: 13 }}>{c.specialty}</div>}
                  </div>
                  {c.is_emergency_contact && <span className="badge badge-missed" style={{ marginLeft: 'auto' }}>Emergency</span>}
                </div>
                {c.facility && <div className="contact-detail">{c.facility}</div>}
                {c.phone && <div className="contact-detail">{c.phone}</div>}
                {c.email && <div className="contact-detail">{c.email}</div>}
                {c.address && <div className="contact-detail text-muted">{c.address}</div>}
                <button className="btn-icon-sm" onClick={() => setDeleteTarget(c.id)} style={{ alignSelf: 'flex-end' }}>×</button>
              </div>
            ))}
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
