import { useState, useMemo } from 'react';
import { useTranslation } from 'react-i18next';
import { useQuery } from '@tanstack/react-query';
import { api } from '../api/client';

interface Contact {
  id: string;
  contact_type: string;
  name: string;
  specialty?: string;
  facility?: string;
  phone?: string;
  email?: string;
  address?: string;
}

interface ContactPickerProps {
  profileId: string;
  value?: string;
  onChange: (name: string, contact?: Contact) => void;
  label?: string;
  placeholder?: string;
}

export function ContactPicker({ profileId, value, onChange, label, placeholder }: ContactPickerProps) {
  const { t } = useTranslation();
  const [open, setOpen] = useState(false);
  const [search, setSearch] = useState('');

  const { data } = useQuery({
    queryKey: ['contacts', profileId],
    queryFn: () => api.get<{ items: Contact[] }>(`/api/v1/profiles/${profileId}/contacts`),
    enabled: !!profileId,
  });

  const contacts = data?.items || [];

  const filtered = useMemo(() => {
    if (!search) return contacts.filter(c => c.contact_type === 'medical');
    const q = search.toLowerCase();
    return contacts.filter(c =>
      c.name.toLowerCase().includes(q) ||
      c.specialty?.toLowerCase().includes(q) ||
      c.facility?.toLowerCase().includes(q)
    );
  }, [contacts, search]);

  const selectContact = (c: Contact) => {
    onChange(c.name, c);
    setOpen(false);
    setSearch('');
  };

  const displayValue = value || '';

  return (
    <div className="form-group">
      {label && <label>{label}</label>}
      <div style={{ display: 'flex', gap: 8 }}>
        <input
          type="text"
          value={displayValue}
          onChange={(e) => onChange(e.target.value)}
          placeholder={placeholder || t('contacts.pick_placeholder')}
          style={{ flex: 1 }}
        />
        <button
          type="button"
          className="btn btn-secondary"
          onClick={() => { setOpen(true); setSearch(''); }}
          style={{ flexShrink: 0, gap: 6 }}
        >
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
            <path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2" />
            <circle cx="9" cy="7" r="4" />
            <path d="M23 21v-2a4 4 0 0 0-3-3.87" />
            <path d="M16 3.13a4 4 0 0 1 0 7.75" />
          </svg>
          {t('contacts.pick')}
        </button>
      </div>

      {open && (
        <div className="modal-overlay" onClick={() => { setOpen(false); setSearch(''); }}>
          <div className="modal" onClick={(e) => e.stopPropagation()} style={{ maxWidth: 480 }}>
            <div className="modal-header">
              <h3>{t('contacts.pick_title')}</h3>
              <button className="modal-close" onClick={() => { setOpen(false); setSearch(''); }}>&times;</button>
            </div>
            <div className="modal-body">
              <div className="form-group" style={{ marginBottom: 12 }}>
                <input
                  type="text"
                  value={search}
                  onChange={(e) => setSearch(e.target.value)}
                  placeholder={t('contacts.pick_search')}
                  autoFocus
                />
              </div>
              {filtered.length === 0 ? (
                <p className="text-muted">{t('contacts.no_results')}</p>
              ) : (
                <div className="med-list" style={{ maxHeight: 320, overflowY: 'auto' }}>
                  {filtered.map((c) => (
                    <div
                      key={c.id}
                      className="med-item"
                      style={{ cursor: 'pointer' }}
                      onClick={() => selectContact(c)}
                    >
                      <div className="contact-avatar" style={{ width: 32, height: 32, fontSize: 13, flexShrink: 0 }}>
                        {c.name.charAt(0).toUpperCase()}
                      </div>
                      <div className="med-info">
                        <div className="med-name" style={{ fontSize: 13 }}>{c.name}</div>
                        <div className="med-details">
                          {[c.specialty, c.facility].filter(Boolean).join(' · ')}
                        </div>
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
