import { useState, useEffect, useMemo } from 'react';
import { compareByColumn } from '../utils/sorting';
import { useTranslation } from 'react-i18next';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { useForm } from 'react-hook-form';
import { ProfileSelector } from '../components/ProfileSelector';
import { ConfirmDelete } from '../components/ConfirmDelete';
import { useProfiles } from '../hooks/useProfiles';
import { contactsApi, type Contact } from '../api/contacts';

interface OSMResult {
  place_id: number;
  display_name: string;
  lat: string;
  lon: string;
  type: string;
  class: string;
  address?: {
    road?: string;
    house_number?: string;
    postcode?: string;
    city?: string;
    town?: string;
    village?: string;
    municipality?: string;
    state?: string;
    country?: string;
  };
  namedetails?: { name?: string };
  name?: string;
  extratags?: Record<string, string>;
  category?: string;
}


const formatAddress = (c: Contact) => {
  const parts = [c.street, [c.postal_code, c.city].filter(Boolean).join(' '), c.country].filter(Boolean);
  return parts.join(', ');
};

const cleanContact = (c: Partial<Contact>) => {
  const cleaned = { ...c };
  delete cleaned.address;
  if (!cleaned.specialty) delete cleaned.specialty;
  if (!cleaned.facility) delete cleaned.facility;
  if (!cleaned.phone) delete cleaned.phone;
  if (!cleaned.email) delete cleaned.email;
  if (!cleaned.street) delete cleaned.street;
  if (!cleaned.postal_code) delete cleaned.postal_code;
  if (!cleaned.city) delete cleaned.city;
  if (!cleaned.country) delete cleaned.country;
  if (!cleaned.notes) delete cleaned.notes;
  if (cleaned.latitude == null) delete cleaned.latitude;
  if (cleaned.longitude == null) delete cleaned.longitude;
  return cleaned;
};

export function Contacts() {
  const { t } = useTranslation();
  const { data: profilesData } = useProfiles();
  const profiles = profilesData || [];
  const [selectedProfile, setSelectedProfile] = useState('');
  const [sortCol, setSortCol] = useState<string>('name');
  const [sortDir, setSortDir] = useState<'asc' | 'desc'>('asc');
  const [showForm, setShowForm] = useState(false);
  const [deleteTarget, setDeleteTarget] = useState<string | null>(null);
  const [editTarget, setEditTarget] = useState<Contact | null>(null);
  const [activeTab, setActiveTab] = useState<'medical' | 'personal'>('medical');
  const [createType, setCreateType] = useState<'medical' | 'personal'>('medical');

  // OSM search state
  const [osmOpen, setOsmOpen] = useState<'create' | 'edit' | null>(null);
  const [osmQuery, setOsmQuery] = useState('');
  const [osmResults, setOsmResults] = useState<OSMResult[]>([]);
  const [osmLoading, setOsmLoading] = useState(false);

  const queryClient = useQueryClient();
  const profileId = selectedProfile || profiles[0]?.id || '';

  const { data, isLoading } = useQuery({
    queryKey: ['contacts', profileId],
    queryFn: () => contactsApi.list(profileId),
    enabled: !!profileId,
  });

  const { register, handleSubmit, reset, setValue } = useForm<Partial<Contact>>();
  const { register: editRegister, handleSubmit: editHandleSubmit, reset: editReset, setValue: editSetValue } = useForm<Partial<Contact>>();

  const createMutation = useMutation({
    mutationFn: (c: Partial<Contact>) => contactsApi.create(profileId, cleanContact(c)),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['contacts', profileId] });
      setShowForm(false);
      reset();
    },
  });

  const updateMutation = useMutation({
    mutationFn: (c: Partial<Contact> & { id: string }) =>
      contactsApi.update(profileId, c.id, cleanContact(c)),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['contacts', profileId] });
      setEditTarget(null);
      editReset();
    },
  });

  const deleteMutation = useMutation({
    mutationFn: (id: string) => contactsApi.delete(profileId, id),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['contacts', profileId] }),
  });

  const items = data?.items || [];

  const sortedItems = useMemo(
    () => [...items].sort((a, b) => compareByColumn(a, b, sortCol, sortDir)),
    [items, sortCol, sortDir]
  );

  const filteredItems = useMemo(() => {
    return sortedItems.filter(c => c.contact_type === activeTab);
  }, [sortedItems, activeTab]);

  useEffect(() => {
    if (editTarget) {
      editReset({
        name: editTarget.name,
        contact_type: editTarget.contact_type,
        specialty: editTarget.specialty || '',
        facility: editTarget.facility || '',
        phone: editTarget.phone || '',
        email: editTarget.email || '',
        street: editTarget.street || '',
        postal_code: editTarget.postal_code || '',
        city: editTarget.city || '',
        country: editTarget.country || '',
        latitude: editTarget.latitude,
        longitude: editTarget.longitude,
        notes: editTarget.notes || '',
        is_emergency_contact: editTarget.is_emergency_contact,
      });
    }
  }, [editTarget, editReset]);

  // OSM search — supports addresses AND POIs (hospitals, clinics, etc.)
  const searchOsm = async () => {
    if (osmQuery.length < 3) return;
    setOsmLoading(true);
    try {
      const res = await fetch(
        `https://nominatim.openstreetmap.org/search?q=${encodeURIComponent(osmQuery)}&format=jsonv2&addressdetails=1&namedetails=1&extratags=1&limit=8`,
        { headers: { 'User-Agent': 'HealthVault/1.0' } }
      );
      const data = await res.json();
      setOsmResults(data);
    } catch {
      setOsmResults([]);
    }
    setOsmLoading(false);
  };

  const getOsmCategory = (r: OSMResult): string | null => {
    const cat = r.category;
    const type = r.type;
    if (cat === 'amenity' && ['hospital', 'clinic', 'doctors', 'dentist', 'pharmacy', 'veterinary'].includes(type)) return type;
    if (cat === 'healthcare') return type;
    if (cat === 'building' && type === 'hospital') return 'hospital';
    return null;
  };

  const getOsmDisplayType = (r: OSMResult): string | null => {
    const cat = getOsmCategory(r);
    if (!cat) return null;
    const map: Record<string, string> = {
      hospital: 'Krankenhaus', clinic: 'Klinik', doctors: 'Arztpraxis',
      dentist: 'Zahnarzt', pharmacy: 'Apotheke', veterinary: 'Tierarzt',
    };
    return map[cat] || cat;
  };

  const selectOsmResult = (r: OSMResult) => {
    const addr = r.address || {};
    const street = [addr.road, addr.house_number].filter(Boolean).join(' ');
    const city = addr.city || addr.town || addr.village || addr.municipality || '';
    const setVal = osmOpen === 'create' ? setValue : editSetValue;
    if (street) setVal('street', street);
    if (addr.postcode) setVal('postal_code', addr.postcode);
    if (city) setVal('city', city);
    if (addr.country) setVal('country', addr.country);
    if (r.lat) setVal('latitude', parseFloat(r.lat));
    if (r.lon) setVal('longitude', parseFloat(r.lon));

    // For medical contacts: auto-fill name/facility from POI data
    const poiName = r.namedetails?.name || r.name || '';
    const currentType = osmOpen === 'create' ? createType : editTarget?.contact_type;
    if (currentType === 'medical' && poiName && getOsmCategory(r)) {
      setVal('facility', poiName);
      // If name field is empty, use POI name as contact name too
      const nameField = document.querySelector<HTMLInputElement>(
        osmOpen === 'create' ? '#contact-create-form input[name="name"]' : '#contact-edit-form input[name="name"]'
      );
      if (nameField && !nameField.value) {
        setVal('name', poiName);
      }
      // Extract phone/website from extratags if available
      const tags = r.extratags || {};
      if (tags.phone && !document.querySelector<HTMLInputElement>(`#contact-${osmOpen}-form input[name="phone"]`)?.value) {
        setVal('phone', tags.phone);
      }
      if (tags.email && !document.querySelector<HTMLInputElement>(`#contact-${osmOpen}-form input[name="email"]`)?.value) {
        setVal('email', tags.email);
      }
      if (tags.website) {
        setVal('notes', tags.website);
      }
    }

    setOsmOpen(null);
    setOsmResults([]);
    setOsmQuery('');
  };

  const closeOsm = () => {
    setOsmOpen(null);
    setOsmResults([]);
    setOsmQuery('');
  };

  const openCreateForm = () => {
    setCreateType(activeTab);
    setValue('contact_type', activeTab);
    setShowForm(true);
  };

  const handleCreateTypeChange = (type: 'medical' | 'personal') => {
    setCreateType(type);
    setValue('contact_type', type);
  };

  return (
    <div className="page">
      <div className="page-header">
        <h2>{t('nav.contacts')}</h2>
        <div className="page-actions">
          <ProfileSelector selectedId={profileId} onSelect={setSelectedProfile} />
          <button className="btn btn-add" onClick={openCreateForm}>+ {t('common.add')}</button>
        </div>
      </div>

      {/* Type Filter Tabs */}
      <div className="view-tabs">
        <button className={`view-tab${activeTab === 'medical' ? ' active' : ''}`} onClick={() => setActiveTab('medical')}>
          {t('contacts.type_medical')}
        </button>
        <button className={`view-tab${activeTab === 'personal' ? ' active' : ''}`} onClick={() => setActiveTab('personal')}>
          {t('contacts.type_personal')}
        </button>
      </div>

      {/* Create Contact Modal */}
      {showForm && (
        <div className="modal-overlay" onClick={() => setShowForm(false)}>
          <div className="modal" onClick={(e) => e.stopPropagation()} style={{ maxWidth: 540 }}>
            <div className="modal-header">
              <h3>{t('contacts.add')}</h3>
              <button className="modal-close" onClick={() => setShowForm(false)} aria-label={t('common.close')}>&times;</button>
            </div>
            <div className="modal-body">
              <form id="contact-create-form" onSubmit={handleSubmit((data) => createMutation.mutate(data))}>
                <div className="radio-group">
                  <label>
                    <input type="radio" value="medical" checked={createType === 'medical'} onChange={() => handleCreateTypeChange('medical')} />
                    <span>{t('contacts.type_medical')}</span>
                  </label>
                  <label>
                    <input type="radio" value="personal" checked={createType === 'personal'} onChange={() => handleCreateTypeChange('personal')} />
                    <span>{t('contacts.type_personal')}</span>
                  </label>
                </div>
                <input type="hidden" {...register('contact_type')} />

                <button type="button" className="btn btn-secondary" onClick={() => setOsmOpen('create')} style={{ width: '100%', marginBottom: 16, gap: 8 }}>
                  <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><circle cx="11" cy="11" r="8"/><path d="M21 21l-4.35-4.35"/></svg>
                  {t('contacts.search_address')}
                </button>

                <div className="form-group">
                  <label>{t('common.name')} *</label>
                  <input type="text" {...register('name')} required />
                </div>

                {createType === 'medical' && (
                  <div className="form-row">
                    <div className="form-group">
                      <label>{t('contacts.specialty')}</label>
                      <input type="text" {...register('specialty')} placeholder={t('contacts.specialty_placeholder')} />
                    </div>
                    <div className="form-group">
                      <label>{t('contacts.facility')}</label>
                      <input type="text" {...register('facility')} />
                    </div>
                  </div>
                )}

                <div className="form-row">
                  <div className="form-group">
                    <label>{t('contacts.phone')}</label>
                    <input type="tel" {...register('phone')} />
                  </div>
                  <div className="form-group">
                    <label>{t('contacts.email')}</label>
                    <input type="email" {...register('email')} />
                  </div>
                </div>

                {/* Address fields */}
                <div className="form-group">
                  <label>{t('contacts.street')}</label>
                  <input type="text" {...register('street')} />
                </div>
                <div className="form-row">
                  <div className="form-group">
                    <label>{t('contacts.postal_code')}</label>
                    <input type="text" {...register('postal_code')} />
                  </div>
                  <div className="form-group">
                    <label>{t('contacts.city')}</label>
                    <input type="text" {...register('city')} />
                  </div>
                </div>
                <div className="form-group">
                  <label>{t('contacts.country')}</label>
                  <input type="text" {...register('country')} />
                </div>

                <input type="hidden" {...register('latitude', { valueAsNumber: true })} />
                <input type="hidden" {...register('longitude', { valueAsNumber: true })} />

                <div className="form-group">
                  <label>{t('contacts.notes')}</label>
                  <textarea rows={2} {...register('notes')} />
                </div>

                <label className="toggle-label" style={{ marginBottom: 12 }}>
                  <input type="checkbox" {...register('is_emergency_contact')} />
                  {t('contacts.emergency_contact')}
                </label>
              </form>
            </div>
            <div className="modal-footer">
              <button type="button" className="btn btn-secondary" onClick={() => setShowForm(false)}>
                {t('common.cancel')}
              </button>
              <button type="submit" form="contact-create-form" className="btn btn-add" disabled={createMutation.isPending}>
                {t('common.save')}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Contact List */}
      <div className="card">
        {isLoading ? <p>{t('common.loading')}</p> : filteredItems.length === 0 ? <p className="text-muted">{t('common.no_data')}</p> : (
          <>
            <div style={{ display: 'flex', gap: 8, marginBottom: 12, alignItems: 'center' }}>
              <span className="text-muted" style={{ fontSize: 12 }}>{t('common.sort')}:</span>
              <select className="metric-selector" value={sortCol} onChange={(e) => setSortCol(e.target.value)}>
                <option value="name">{t('common.name')}</option>
                <option value="specialty">{t('contacts.specialty')}</option>
                <option value="facility">{t('contacts.facility')}</option>
              </select>
              <button className="btn-icon-sm" onClick={() => setSortDir(d => d === 'asc' ? 'desc' : 'asc')} aria-label={t('common.sort')}>
                {sortDir === 'asc' ? '\u2191' : '\u2193'}
              </button>
            </div>
            <div className="contact-grid">
              {filteredItems.map((c) => (
                <div key={c.id} className="contact-card" onClick={() => setEditTarget(c)} style={{ cursor: 'pointer', position: 'relative' }}>
                  <svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" style={{ position: 'absolute', top: 8, right: 8, opacity: 0.4 }}><path d="M11 4H4a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-7" /><path d="M18.5 2.5a2.121 2.121 0 0 1 3 3L12 15l-4 1 1-4 9.5-9.5z" /></svg>
                  <div className="contact-header">
                    <div className="contact-avatar">{c.name.charAt(0).toUpperCase()}</div>
                    <div>
                      <div className="contact-name">{c.name}</div>
                      {c.contact_type === 'medical' && c.specialty && <div className="text-muted" style={{ fontSize: 13 }}>{c.specialty}</div>}
                    </div>
                    {c.is_emergency_contact && <span className="badge badge-missed" style={{ marginLeft: 'auto' }}>{t('contacts.emergency')}</span>}
                  </div>
                  {c.contact_type === 'medical' && c.facility && <div className="contact-detail">{c.facility}</div>}
                  {c.phone && <div className="contact-detail">{c.phone}</div>}
                  {c.email && <div className="contact-detail">{c.email}</div>}
                  {formatAddress(c) && <div className="contact-detail text-muted">{formatAddress(c)}</div>}
                  {c.notes && <div className="contact-detail text-muted" style={{ fontSize: 12, fontStyle: 'italic' }}>{c.notes}</div>}
                  {c.latitude && c.longitude && (
                    <a
                      href={`https://www.openstreetmap.org/directions?mlat=${c.latitude}&mlon=${c.longitude}`}
                      target="_blank"
                      rel="noopener"
                      className="card-link"
                      onClick={e => e.stopPropagation()}
                    >
                      {t('contacts.show_route')}
                    </a>
                  )}
                  <button className="btn-icon-sm" onClick={(e) => { e.stopPropagation(); setDeleteTarget(c.id); }} style={{ alignSelf: 'flex-end' }} aria-label={t('common.delete')}>&times;</button>
                </div>
              ))}
            </div>
          </>
        )}
      </div>

      {/* Edit Contact Modal */}
      {editTarget && (
        <div className="modal-overlay" onClick={() => setEditTarget(null)}>
          <div className="modal" onClick={(e) => e.stopPropagation()} style={{ maxWidth: 540 }}>
            <div className="modal-header">
              <h3>{t('contacts.edit')}</h3>
              <button className="modal-close" onClick={() => setEditTarget(null)} aria-label={t('common.close')}>&times;</button>
            </div>
            <div className="modal-body">
              <form id="contact-edit-form" onSubmit={editHandleSubmit((data) => updateMutation.mutate({ ...data, id: editTarget.id }))}>
                <input type="hidden" {...editRegister('contact_type')} />

                <button type="button" className="btn btn-secondary" onClick={() => setOsmOpen('edit')} style={{ width: '100%', marginBottom: 16, gap: 8 }}>
                  <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><circle cx="11" cy="11" r="8"/><path d="M21 21l-4.35-4.35"/></svg>
                  {t('contacts.search_address')}
                </button>

                <div className="form-group">
                  <label>{t('common.name')} *</label>
                  <input type="text" {...editRegister('name')} required />
                </div>

                {editTarget.contact_type === 'medical' && (
                  <div className="form-row">
                    <div className="form-group">
                      <label>{t('contacts.specialty')}</label>
                      <input type="text" {...editRegister('specialty')} placeholder={t('contacts.specialty_placeholder')} />
                    </div>
                    <div className="form-group">
                      <label>{t('contacts.facility')}</label>
                      <input type="text" {...editRegister('facility')} />
                    </div>
                  </div>
                )}

                <div className="form-row">
                  <div className="form-group">
                    <label>{t('contacts.phone')}</label>
                    <input type="tel" {...editRegister('phone')} />
                  </div>
                  <div className="form-group">
                    <label>{t('contacts.email')}</label>
                    <input type="email" {...editRegister('email')} />
                  </div>
                </div>

                {/* Address fields */}
                <div className="form-group">
                  <label>{t('contacts.street')}</label>
                  <input type="text" {...editRegister('street')} />
                </div>
                <div className="form-row">
                  <div className="form-group">
                    <label>{t('contacts.postal_code')}</label>
                    <input type="text" {...editRegister('postal_code')} />
                  </div>
                  <div className="form-group">
                    <label>{t('contacts.city')}</label>
                    <input type="text" {...editRegister('city')} />
                  </div>
                </div>
                <div className="form-group">
                  <label>{t('contacts.country')}</label>
                  <input type="text" {...editRegister('country')} />
                </div>

                <input type="hidden" {...editRegister('latitude', { valueAsNumber: true })} />
                <input type="hidden" {...editRegister('longitude', { valueAsNumber: true })} />

                <div className="form-group">
                  <label>{t('contacts.notes')}</label>
                  <textarea rows={2} {...editRegister('notes')} />
                </div>

                <label className="toggle-label" style={{ marginBottom: 12 }}>
                  <input type="checkbox" {...editRegister('is_emergency_contact')} />
                  {t('contacts.emergency_contact')}
                </label>
              </form>
            </div>
            <div className="modal-footer">
              <button type="button" className="btn btn-secondary" onClick={() => setEditTarget(null)}>
                {t('common.cancel')}
              </button>
              <button type="submit" form="contact-edit-form" className="btn btn-add" disabled={updateMutation.isPending}>
                {t('common.save')}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* OSM Search Overlay */}
      {osmOpen && (
        <div className="modal-overlay" onClick={closeOsm}>
          <div className="modal" onClick={e => e.stopPropagation()} style={{ maxWidth: 560 }}>
            <div className="modal-header">
              <h3>{t('contacts.search_address')}</h3>
              <button className="modal-close" onClick={closeOsm} aria-label={t('common.close')}>&times;</button>
            </div>
            <div className="modal-body">
              <div className="form-group">
                <input
                  type="text"
                  value={osmQuery}
                  onChange={e => setOsmQuery(e.target.value)}
                  placeholder={t('contacts.search_placeholder')}
                  autoFocus
                  onKeyDown={e => { if (e.key === 'Enter') { e.preventDefault(); searchOsm(); } }}
                />
              </div>
              {osmLoading && <p className="text-muted">{t('common.loading')}</p>}
              {osmResults.length > 0 && (
                <>
                  {/* Map preview */}
                  <div style={{ borderRadius: 'var(--radius)', overflow: 'hidden', marginBottom: 12, border: '1px solid var(--border)' }}>
                    <iframe
                      title="Map"
                      width="100%"
                      height="180"
                      style={{ border: 'none', display: 'block' }}
                      src={`https://www.openstreetmap.org/export/embed.html?bbox=${parseFloat(osmResults[0].lon) - 0.02},${parseFloat(osmResults[0].lat) - 0.01},${parseFloat(osmResults[0].lon) + 0.02},${parseFloat(osmResults[0].lat) + 0.01}&layer=mapnik&marker=${osmResults[0].lat},${osmResults[0].lon}`}
                    />
                  </div>
                  <div className="med-list">
                    {osmResults.map((r: OSMResult, i: number) => {
                      const poiType = getOsmDisplayType(r);
                      const poiName = r.namedetails?.name || r.name || '';
                      return (
                        <div key={i} className="med-item" style={{ cursor: 'pointer' }} onClick={() => selectOsmResult(r)}>
                          <div className="med-info">
                            {poiName && poiType ? (
                              <>
                                <div className="med-name" style={{ fontSize: 13 }}>{poiName}</div>
                                <div className="med-details">
                                  <span className="badge badge-info" style={{ marginRight: 6 }}>{poiType}</span>
                                  {r.display_name}
                                </div>
                              </>
                            ) : (
                              <div className="med-name" style={{ fontSize: 13 }}>{r.display_name}</div>
                            )}
                          </div>
                        </div>
                      );
                    })}
                  </div>
                </>
              )}
              {!osmLoading && osmResults.length === 0 && osmQuery.length > 2 && (
                <p className="text-muted">{t('contacts.no_results')}</p>
              )}
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
