import { useState, useEffect } from 'react';
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
  const [editTarget, setEditTarget] = useState<Contact | null>(null);
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

  const updateMutation = useMutation({
    mutationFn: (c: Partial<Contact> & { id: string }) =>
      api.patch(`/api/v1/profiles/${profileId}/contacts/${c.id}`, c),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['contacts', profileId] });
      setEditTarget(null);
      editReset();
    },
  });

  const deleteMutation = useMutation({
    mutationFn: (id: string) => api.delete(`/api/v1/profiles/${profileId}/contacts/${id}`),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['contacts', profileId] }),
  });

  const { register, handleSubmit, reset } = useForm<Partial<Contact>>();
  const { register: editRegister, handleSubmit: editHandleSubmit, reset: editReset } = useForm<Partial<Contact>>();
  const items = data?.items || [];

  useEffect(() => {
    if (editTarget) {
      editReset({
        name: editTarget.name,
        specialty: editTarget.specialty || '',
        facility: editTarget.facility || '',
        phone: editTarget.phone || '',
        email: editTarget.email || '',
        address: editTarget.address || '',
        is_emergency_contact: editTarget.is_emergency_contact,
      });
    }
  }, [editTarget, editReset]);

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
        <div className="modal-overlay" onClick={() => setShowForm(false)}>
          <div className="modal" onClick={(e) => e.stopPropagation()} style={{ maxWidth: 540 }}>
            <div className="modal-header">
              <h3>{t('contacts.add')}</h3>
              <button className="modal-close" onClick={() => setShowForm(false)}>&times;</button>
            </div>
            <form id="contact-create-form" onSubmit={handleSubmit((data) => createMutation.mutate(data))}>
              <div className="modal-body">
                <div className="form-row">
                  <div className="form-group"><label>{t('common.name')} *</label><input type="text" {...register('name')} required /></div>
                  <div className="form-group"><label>{t('contacts.specialty')}</label><input type="text" {...register('specialty')} placeholder={t('contacts.specialty_placeholder')} /></div>
                  <div className="form-group"><label>{t('contacts.facility')}</label><input type="text" {...register('facility')} /></div>
                </div>
                <div className="form-row">
                  <div className="form-group"><label>{t('contacts.phone')}</label><input type="tel" {...register('phone')} /></div>
                  <div className="form-group"><label>{t('contacts.email')}</label><input type="email" {...register('email')} /></div>
                </div>
                <div className="form-group"><label>{t('contacts.address')}</label><textarea rows={2} {...register('address')} /></div>
                <label className="toggle-label" style={{ marginBottom: 12 }}>
                  <input type="checkbox" {...register('is_emergency_contact')} />
                  {t('contacts.emergency_contact')}
                </label>
              </div>
              <div className="modal-footer">
                <button type="submit" className="btn btn-add" disabled={createMutation.isPending}>{t('common.save')}</button>
                <button type="button" className="btn btn-secondary" onClick={() => setShowForm(false)}>{t('common.cancel')}</button>
              </div>
            </form>
          </div>
        </div>
      )}

      <div className="card">
        {isLoading ? <p>{t('common.loading')}</p> : items.length === 0 ? <p className="text-muted">{t('common.no_data')}</p> : (
          <div className="contact-grid">
            {items.map((c) => (
              <div key={c.id} className="contact-card" onClick={() => setEditTarget(c)} style={{ cursor: 'pointer', position: 'relative' }}>
                <svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" style={{ position: 'absolute', top: 8, right: 8, opacity: 0.4 }}><path d="M11 4H4a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-7" /><path d="M18.5 2.5a2.121 2.121 0 0 1 3 3L12 15l-4 1 1-4 9.5-9.5z" /></svg>
                <div className="contact-header">
                  <div className="contact-avatar">{c.name.charAt(0).toUpperCase()}</div>
                  <div>
                    <div className="contact-name">{c.name}</div>
                    {c.specialty && <div className="text-muted" style={{ fontSize: 13 }}>{c.specialty}</div>}
                  </div>
                  {c.is_emergency_contact && <span className="badge badge-missed" style={{ marginLeft: 'auto' }}>{t('contacts.emergency')}</span>}
                </div>
                {c.facility && <div className="contact-detail">{c.facility}</div>}
                {c.phone && <div className="contact-detail">{c.phone}</div>}
                {c.email && <div className="contact-detail">{c.email}</div>}
                {c.address && <div className="contact-detail text-muted">{c.address}</div>}
                <button className="btn-icon-sm" onClick={(e) => { e.stopPropagation(); setDeleteTarget(c.id); }} style={{ alignSelf: 'flex-end' }}>×</button>
              </div>
            ))}
          </div>
        )}
      </div>

      {/* Edit Contact Modal */}
      {editTarget && (
        <div className="modal-overlay" onClick={() => setEditTarget(null)}>
          <div className="modal" onClick={(e) => e.stopPropagation()} style={{ maxWidth: 540 }}>
            <div className="modal-header">
              <h3>{t('contacts.edit')}</h3>
              <button className="modal-close" onClick={() => setEditTarget(null)}>&times;</button>
            </div>
            <form onSubmit={editHandleSubmit((data) => updateMutation.mutate({ ...data, id: editTarget.id }))}>
              <div className="modal-body">
                <div className="form-row">
                  <div className="form-group"><label>{t('common.name')} *</label><input type="text" {...editRegister('name')} required /></div>
                  <div className="form-group"><label>{t('contacts.specialty')}</label><input type="text" {...editRegister('specialty')} placeholder={t('contacts.specialty_placeholder')} /></div>
                  <div className="form-group"><label>{t('contacts.facility')}</label><input type="text" {...editRegister('facility')} /></div>
                </div>
                <div className="form-row">
                  <div className="form-group"><label>{t('contacts.phone')}</label><input type="tel" {...editRegister('phone')} /></div>
                  <div className="form-group"><label>{t('contacts.email')}</label><input type="email" {...editRegister('email')} /></div>
                </div>
                <div className="form-group"><label>{t('contacts.address')}</label><textarea rows={2} {...editRegister('address')} /></div>
                <label className="toggle-label" style={{ marginBottom: 12 }}>
                  <input type="checkbox" {...editRegister('is_emergency_contact')} />
                  {t('contacts.emergency_contact')}
                </label>
              </div>
              <div className="modal-footer">
                <button type="submit" className="btn btn-add" disabled={updateMutation.isPending}>{t('common.save')}</button>
                <button type="button" className="btn btn-secondary" onClick={() => setEditTarget(null)}>{t('common.cancel')}</button>
              </div>
            </form>
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
