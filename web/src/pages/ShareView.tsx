import React, { useState, useEffect } from 'react';
import { useParams } from 'react-router-dom';
import i18n from '../i18n';
import { useTranslation } from 'react-i18next';
import { format } from 'date-fns';
import { de, enUS } from 'date-fns/locale';

const LOCALES: Record<string, typeof enUS> = { de, en: enUS };

function fmt(date: string | undefined, pattern: string, lang: string): string {
  if (!date) return '—';
  try { return format(new Date(date), pattern, { locale: LOCALES[lang] || enUS }); }
  catch { return date; }
}

const svgProps = { width: 18, height: 18, viewBox: '0 0 24 24', fill: 'none', stroke: 'currentColor', strokeWidth: 1.5, strokeLinecap: 'round' as const, strokeLinejoin: 'round' as const };

type ShareTab = 'medications' | 'allergies' | 'diagnoses' | 'vitals' | 'contacts';

interface ShareData {
  medications?: MedItem[];
  allergies?: AllergyItem[];
  diagnoses?: DiagItem[];
  vitals?: VitalItem[];
  contacts?: ContactItem[];
  generated_at?: string;
}
interface MedItem { name: string; dosage?: string; unit?: string; frequency?: string; route?: string; prescribed_by?: string; started_at?: string; ended_at?: string }
interface AllergyItem { name: string; category?: string; severity?: string; reaction_type?: string; status?: string }
interface DiagItem { name: string; icd10_code?: string; status?: string; diagnosed_at?: string; diagnosed_by?: string }
interface VitalItem { measured_at: string; blood_pressure_systolic?: number; blood_pressure_diastolic?: number; pulse?: number; weight?: number; body_temperature?: number; oxygen_saturation?: number; blood_glucose?: number }
interface ContactItem { name: string; specialty?: string; facility?: string; phone?: string; email?: string; is_emergency_contact?: boolean }

const TABS: { key: ShareTab; icon: React.ReactNode; en: string; de: string }[] = [
  { key: 'medications', icon: <svg {...svgProps}><path d="M10.5 1.5l-8 8a4.95 4.95 0 0 0 7 7l8-8a4.95 4.95 0 0 0-7-7z"/><path d="M6.5 10.5l7-7"/></svg>, en: 'Medications', de: 'Medikamente' },
  { key: 'allergies', icon: <svg {...svgProps}><path d="M10.29 3.86L1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z"/><line x1="12" y1="9" x2="12" y2="13"/><line x1="12" y1="17" x2="12.01" y2="17"/></svg>, en: 'Allergies', de: 'Allergien' },
  { key: 'diagnoses', icon: <svg {...svgProps}><path d="M16 4h2a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2h2"/><rect x="8" y="2" width="8" height="4" rx="1"/></svg>, en: 'Diagnoses', de: 'Diagnosen' },
  { key: 'vitals', icon: <svg {...svgProps}><path d="M20.84 4.61a5.5 5.5 0 0 0-7.78 0L12 5.67l-1.06-1.06a5.5 5.5 0 0 0-7.78 7.78l1.06 1.06L12 21.23l7.78-7.78 1.06-1.06a5.5 5.5 0 0 0 0-7.78z"/></svg>, en: 'Vitals', de: 'Vitalwerte' },
  { key: 'contacts', icon: <svg {...svgProps}><path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/></svg>, en: 'Contacts', de: 'Kontakte' },
];

function L(lang: string, en: string, de: string): string { return lang === 'de' ? de : en; }

export function ShareView() {
  const { shareID } = useParams<{ shareID: string }>();
  useTranslation();
  const [status, setStatus] = useState<'loading' | 'decrypting' | 'ready' | 'error' | 'expired'>('loading');
  const [error, setError] = useState('');
  const [data, setData] = useState<ShareData | null>(null);
  const [lang, setLang] = useState(navigator.language.startsWith('de') ? 'de' : 'en');
  const [activeTab, setActiveTab] = useState<ShareTab>('medications');

  useEffect(() => { i18n.changeLanguage(lang); }, [lang]);

  useEffect(() => {
    if (!shareID) return;
    const fragment = window.location.hash.slice(1);
    if (!fragment) { setStatus('error'); setError(L(lang, 'No decryption key found in URL.', 'Kein Entschlüsselungsschlüssel in der URL gefunden.')); return; }
    fetchAndDecrypt(shareID, fragment);
  }, [shareID]);

  async function fetchAndDecrypt(id: string, keyBase64: string) {
    try {
      const res = await fetch(`/api/v1/share/${id}`);
      if (res.status === 410) { setStatus('expired'); return; }
      if (!res.ok) { setStatus('error'); setError(L(lang, 'Share not found or has expired.', 'Freigabe nicht gefunden oder abgelaufen.')); return; }
      const bundle = await res.json();
      setStatus('decrypting');
      const base64 = keyBase64.replace(/-/g, '+').replace(/_/g, '/');
      const padded = base64 + '='.repeat((4 - base64.length % 4) % 4);
      const keyBytes = Uint8Array.from(atob(padded), (c) => c.charCodeAt(0));
      const tempKey = await crypto.subtle.importKey('raw', keyBytes, { name: 'AES-GCM', length: 256 }, false, ['decrypt']);
      const combined = Uint8Array.from(atob(bundle.encrypted_data), (c) => c.charCodeAt(0));
      const plaintext = await crypto.subtle.decrypt({ name: 'AES-GCM', iv: combined.slice(0, 12), tagLength: 128 }, tempKey, combined.slice(12));
      setData(JSON.parse(new TextDecoder().decode(plaintext)));
      setStatus('ready');
    } catch {
      setStatus('error');
      setError(L(lang, 'Failed to decrypt. The link may be invalid or corrupted.', 'Entschlüsselung fehlgeschlagen. Der Link ist möglicherweise ungültig.'));
    }
  }

  const tabsWithData = data ? TABS.filter((tb) => {
    const items = data[tb.key];
    return Array.isArray(items) && items.length > 0;
  }) : [];

  useEffect(() => {
    if (tabsWithData.length > 0 && !tabsWithData.find((t) => t.key === activeTab)) setActiveTab(tabsWithData[0].key);
  }, [tabsWithData, activeTab]);

  if (status !== 'ready') {
    return (
      <div className="auth-page">
        <div className="auth-card" style={{ maxWidth: 440 }}>
          <LangPicker lang={lang} setLang={setLang} />
          <svg width="40" height="40" viewBox="0 0 24 24" fill="none" stroke="var(--color-primary)" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" style={{ marginBottom: 16 }}><path d="M20.84 4.61a5.5 5.5 0 0 0-7.78 0L12 5.67l-1.06-1.06a5.5 5.5 0 0 0-7.78 7.78l1.06 1.06L12 21.23l7.78-7.78 1.06-1.06a5.5 5.5 0 0 0 0-7.78z"/></svg>
          <h1 style={{ fontSize: 22, marginBottom: 8 }}>HealthVault</h1>
          {status === 'loading' && <p className="text-muted">{L(lang, 'Loading...', 'Wird geladen...')}</p>}
          {status === 'decrypting' && <p className="text-muted">{L(lang, 'Decrypting in your browser...', 'Entschlüsselung im Browser...')}</p>}
          {status === 'expired' && <div className="alert alert-error">{L(lang, 'This share link has expired or been revoked.', 'Dieser Freigabelink ist abgelaufen oder wurde widerrufen.')}</div>}
          {status === 'error' && <div className="alert alert-error">{error}</div>}
        </div>
      </div>
    );
  }

  return (
    <div className="share-page">
      <div className="share-container">
        {/* Header */}
        <header className="share-header">
          <div className="share-brand">
            <svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="var(--color-primary)" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round"><path d="M20.84 4.61a5.5 5.5 0 0 0-7.78 0L12 5.67l-1.06-1.06a5.5 5.5 0 0 0-7.78 7.78l1.06 1.06L12 21.23l7.78-7.78 1.06-1.06a5.5 5.5 0 0 0 0-7.78z"/></svg>
            <div>
              <h1 style={{ fontSize: 20, margin: 0 }}>{L(lang, 'Health Summary', 'Gesundheitsübersicht')}</h1>
              <span className="text-muted" style={{ fontSize: 12 }}>
                {data?.generated_at && fmt(data.generated_at, 'dd. MMMM yyyy, HH:mm', lang)}
                {' · '}{L(lang, 'Decrypted locally', 'Lokal entschlüsselt')}
              </span>
            </div>
          </div>
          <LangPicker lang={lang} setLang={setLang} />
        </header>

        {/* Tabs */}
        <div className="share-tabs">
          {tabsWithData.map((tb) => (
            <button key={tb.key} className={`share-tab${activeTab === tb.key ? ' active' : ''}`} onClick={() => setActiveTab(tb.key)}>
              {tb.icon}
              <span className="share-tab-label">{lang === 'de' ? tb.de : tb.en}</span>
              <span className="share-tab-count">{(data?.[tb.key] as unknown[])?.length}</span>
            </button>
          ))}
        </div>

        {/* Content */}
        <div className="share-content">
          {activeTab === 'medications' && data?.medications && <MedsSection items={data.medications} lang={lang} />}
          {activeTab === 'allergies' && data?.allergies && <AllergiesSection items={data.allergies} lang={lang} />}
          {activeTab === 'diagnoses' && data?.diagnoses && <DiagSection items={data.diagnoses} lang={lang} />}
          {activeTab === 'vitals' && data?.vitals && <VitalsSection items={data.vitals} lang={lang} />}
          {activeTab === 'contacts' && data?.contacts && <ContactsSection items={data.contacts} lang={lang} />}
        </div>

        <footer className="share-footer">
          HealthVault · {L(lang, 'Zero-knowledge encrypted', 'Zero-Knowledge-verschlüsselt')}
        </footer>
      </div>
    </div>
  );
}

// ── Language Picker ──

function LangPicker({ lang, setLang }: { lang: string; setLang: (l: string) => void }) {
  return (
    <div className="radio-group" style={{ width: 'auto', flexShrink: 0 }}>
      <label style={{ flex: 'none', padding: '5px 12px', fontSize: 12 }}>
        <input type="radio" name="share-lang" checked={lang === 'de'} onChange={() => setLang('de')} /><span>DE</span>
      </label>
      <label style={{ flex: 'none', padding: '5px 12px', fontSize: 12 }}>
        <input type="radio" name="share-lang" checked={lang === 'en'} onChange={() => setLang('en')} /><span>EN</span>
      </label>
    </div>
  );
}

// ── Medications ──

function MedsSection({ items, lang }: { items: MedItem[]; lang: string }) {
  return (
    <div className="table-scroll">
      <table className="data-table share-table">
        <thead>
          <tr>
            <th>{L(lang, 'Name', 'Name')}</th>
            <th>{L(lang, 'Dosage', 'Dosierung')}</th>
            <th>{L(lang, 'Frequency', 'Häufigkeit')}</th>
            <th>{L(lang, 'Route', 'Weg')}</th>
            <th>{L(lang, 'Prescribed by', 'Verschrieben von')}</th>
            <th>{L(lang, 'Since', 'Seit')}</th>
            <th>{L(lang, 'Status', 'Status')}</th>
          </tr>
        </thead>
        <tbody>
          {items.map((m, i) => (
            <tr key={i}>
              <td><strong>{m.name}</strong></td>
              <td>{[m.dosage, m.unit].filter(Boolean).join(' ') || '—'}</td>
              <td>{m.frequency || '—'}</td>
              <td>{m.route || '—'}</td>
              <td>{m.prescribed_by || '—'}</td>
              <td>{fmt(m.started_at, 'dd. MMM yyyy', lang)}</td>
              <td><span className={`badge ${m.ended_at ? 'badge-inactive' : 'badge-active'}`}>{m.ended_at ? L(lang, 'Inactive', 'Inaktiv') : L(lang, 'Active', 'Aktiv')}</span></td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

// ── Allergies ──

function AllergiesSection({ items, lang }: { items: AllergyItem[]; lang: string }) {
  const sev: Record<string, string> = { mild: 'status-normal', moderate: 'status-borderline', severe: 'status-abnormal', life_threatening: 'status-critical' };
  return (
    <div className="table-scroll">
      <table className="data-table share-table">
        <thead>
          <tr>
            <th>{L(lang, 'Allergen', 'Allergen')}</th>
            <th>{L(lang, 'Category', 'Kategorie')}</th>
            <th>{L(lang, 'Reaction', 'Reaktion')}</th>
            <th>{L(lang, 'Severity', 'Schweregrad')}</th>
          </tr>
        </thead>
        <tbody>
          {items.map((a, i) => (
            <tr key={i}>
              <td><strong>{a.name}</strong></td>
              <td>{a.category || '—'}</td>
              <td>{a.reaction_type?.replace(/_/g, ' ') || '—'}</td>
              <td>{a.severity && <span className={`badge ${sev[a.severity] || ''}`}>{a.severity.replace(/_/g, ' ')}</span>}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

// ── Diagnoses ──

function DiagSection({ items, lang }: { items: DiagItem[]; lang: string }) {
  const sc: Record<string, string> = { active: 'badge-active', resolved: 'badge-inactive', chronic: 'badge-scheduled', in_remission: 'badge-info', suspected: 'badge-missed' };
  return (
    <div className="table-scroll">
      <table className="data-table share-table">
        <thead>
          <tr>
            <th>{L(lang, 'Condition', 'Erkrankung')}</th>
            <th>ICD-10</th>
            <th>{L(lang, 'Diagnosed by', 'Diagnostiziert von')}</th>
            <th>{L(lang, 'Date', 'Datum')}</th>
            <th>{L(lang, 'Status', 'Status')}</th>
          </tr>
        </thead>
        <tbody>
          {items.map((d, i) => (
            <tr key={i}>
              <td><strong>{d.name}</strong></td>
              <td><code>{d.icd10_code || '—'}</code></td>
              <td>{d.diagnosed_by || '—'}</td>
              <td>{fmt(d.diagnosed_at, 'dd. MMM yyyy', lang)}</td>
              <td>{d.status && <span className={`badge ${sc[d.status] || 'badge-info'}`}>{d.status.replace(/_/g, ' ')}</span>}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

// ── Vitals (with metric filter) ──

type VitalFilter = 'all' | 'bp' | 'pulse' | 'weight' | 'temp' | 'spo2' | 'glucose';

const VITAL_FILTERS: { key: VitalFilter; en: string; de: string }[] = [
  { key: 'all', en: 'All', de: 'Alle' },
  { key: 'bp', en: 'Blood Pressure', de: 'Blutdruck' },
  { key: 'pulse', en: 'Pulse', de: 'Puls' },
  { key: 'weight', en: 'Weight', de: 'Gewicht' },
  { key: 'temp', en: 'Temperature', de: 'Temperatur' },
  { key: 'spo2', en: 'SpO2', de: 'SpO2' },
  { key: 'glucose', en: 'Glucose', de: 'Glukose' },
];

function hasVitalData(v: VitalItem, f: VitalFilter): boolean {
  if (f === 'all') return true;
  if (f === 'bp') return v.blood_pressure_systolic != null;
  if (f === 'pulse') return v.pulse != null;
  if (f === 'weight') return v.weight != null;
  if (f === 'temp') return v.body_temperature != null;
  if (f === 'spo2') return v.oxygen_saturation != null;
  if (f === 'glucose') return v.blood_glucose != null;
  return true;
}

function VitalsSection({ items, lang }: { items: VitalItem[]; lang: string }) {
  const [filter, setFilter] = useState<VitalFilter>('all');
  const filtered = items.filter((v) => hasVitalData(v, filter));
  const showCol = (f: VitalFilter) => filter === 'all' || filter === f;

  return (
    <>
      <div className="share-vital-filters">
        {VITAL_FILTERS.map((f) => (
          <button key={f.key} className={`share-vital-filter${filter === f.key ? ' active' : ''}`} onClick={() => setFilter(f.key)}>
            {lang === 'de' ? f.de : f.en}
          </button>
        ))}
      </div>
      <div className="table-scroll">
        <table className="data-table share-table">
          <thead>
            <tr>
              <th>{L(lang, 'Date', 'Datum')}</th>
              {showCol('bp') && <th>{L(lang, 'Blood Pressure', 'Blutdruck')}</th>}
              {showCol('pulse') && <th>{L(lang, 'Pulse', 'Puls')}</th>}
              {showCol('weight') && <th>{L(lang, 'Weight', 'Gewicht')}</th>}
              {showCol('temp') && <th>{L(lang, 'Temp.', 'Temp.')}</th>}
              {showCol('spo2') && <th>SpO2</th>}
              {showCol('glucose') && <th>{L(lang, 'Glucose', 'Glukose')}</th>}
            </tr>
          </thead>
          <tbody>
            {filtered.length === 0 ? (
              <tr><td colSpan={8} className="text-muted" style={{ textAlign: 'center' }}>—</td></tr>
            ) : filtered.map((v, i) => (
              <tr key={i}>
                <td>{fmt(v.measured_at, 'dd. MMM yy, HH:mm', lang)}</td>
                {showCol('bp') && <td>{v.blood_pressure_systolic != null ? `${v.blood_pressure_systolic}/${v.blood_pressure_diastolic}` : '—'}</td>}
                {showCol('pulse') && <td>{v.pulse ?? '—'}</td>}
                {showCol('weight') && <td>{v.weight != null ? `${v.weight} kg` : '—'}</td>}
                {showCol('temp') && <td>{v.body_temperature != null ? `${v.body_temperature}°` : '—'}</td>}
                {showCol('spo2') && <td>{v.oxygen_saturation != null ? `${v.oxygen_saturation}%` : '—'}</td>}
                {showCol('glucose') && <td>{v.blood_glucose ?? '—'}</td>}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </>
  );
}

// ── Contacts ──

function ContactsSection({ items, lang }: { items: ContactItem[]; lang: string }) {
  return (
    <div className="table-scroll">
      <table className="data-table share-table">
        <thead>
          <tr>
            <th>{L(lang, 'Name', 'Name')}</th>
            <th>{L(lang, 'Specialty', 'Fachrichtung')}</th>
            <th>{L(lang, 'Facility', 'Einrichtung')}</th>
            <th>{L(lang, 'Phone', 'Telefon')}</th>
            <th>{L(lang, 'Email', 'E-Mail')}</th>
            <th></th>
          </tr>
        </thead>
        <tbody>
          {items.map((c, i) => (
            <tr key={i}>
              <td><strong>{c.name}</strong></td>
              <td>{c.specialty || '—'}</td>
              <td>{c.facility || '—'}</td>
              <td>{c.phone ? <a href={`tel:${c.phone}`} style={{ color: 'var(--color-primary)' }}>{c.phone}</a> : '—'}</td>
              <td>{c.email ? <a href={`mailto:${c.email}`} style={{ color: 'var(--color-primary)' }}>{c.email}</a> : '—'}</td>
              <td>{c.is_emergency_contact && <span className="badge badge-missed">{L(lang, 'Emergency', 'Notfall')}</span>}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
