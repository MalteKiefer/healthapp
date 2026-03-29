import { useState } from 'react';
import { useTranslation } from 'react-i18next';
import { ProfileSelector } from '../components/ProfileSelector';
import { useProfiles } from '../hooks/useProfiles';

/* ---------------------------------------------------------------------------
   Authenticated download helper
   --------------------------------------------------------------------------- */

async function downloadExport(profileId: string, format: string, filename: string) {
  const token = localStorage.getItem('access_token');
  const res = await fetch(`/api/v1/profiles/${profileId}/export/${format}`, {
    headers: token ? { Authorization: `Bearer ${token}` } : {},
  });
  if (!res.ok) throw new Error('Export failed');
  const blob = await res.blob();
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = filename;
  a.click();
  URL.revokeObjectURL(url);
}

/* ---------------------------------------------------------------------------
   SVG Icons
   --------------------------------------------------------------------------- */

const svgProps = {
  width: 32,
  height: 32,
  viewBox: '0 0 24 24',
  fill: 'none',
  stroke: 'currentColor',
  strokeWidth: 1.5,
  strokeLinecap: 'round' as const,
  strokeLinejoin: 'round' as const,
};

function FhirIcon() {
  return (
    <svg {...svgProps}>
      <path d="M9 3H5a2 2 0 0 0-2 2v4" />
      <path d="M15 3h4a2 2 0 0 1 2 2v4" />
      <path d="M9 21H5a2 2 0 0 1-2-2v-4" />
      <path d="M15 21h4a2 2 0 0 0 2-2v-4" />
      <path d="M12 8v8" />
      <path d="M8 12h8" />
    </svg>
  );
}

function CalendarIcon() {
  return (
    <svg {...svgProps}>
      <rect x="3" y="4" width="18" height="18" rx="2" />
      <line x1="16" y1="2" x2="16" y2="6" />
      <line x1="8" y1="2" x2="8" y2="6" />
      <line x1="3" y1="10" x2="21" y2="10" />
    </svg>
  );
}

function PdfIcon() {
  return (
    <svg {...svgProps}>
      <path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z" />
      <polyline points="14 2 14 8 20 8" />
      <line x1="16" y1="13" x2="8" y2="13" />
      <line x1="16" y1="17" x2="8" y2="17" />
      <polyline points="10 9 9 9 8 9" />
    </svg>
  );
}

function DownloadSmallIcon() {
  return (
    <svg width={16} height={16} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4" />
      <polyline points="7 10 12 15 17 10" />
      <line x1="12" y1="15" x2="12" y2="3" />
    </svg>
  );
}

/* ---------------------------------------------------------------------------
   Export format definitions
   --------------------------------------------------------------------------- */

interface ExportFormat {
  key: string;
  format: string;
  extension: string;
  icon: React.ReactNode;
  titleKey: string;
  descKey: string;
}

const EXPORT_FORMATS: ExportFormat[] = [
  {
    key: 'fhir',
    format: 'fhir',
    extension: '.json',
    icon: <FhirIcon />,
    titleKey: 'export.fhir_title',
    descKey: 'export.fhir_desc',
  },
  {
    key: 'ics',
    format: 'ics',
    extension: '.ics',
    icon: <CalendarIcon />,
    titleKey: 'export.ics_title',
    descKey: 'export.ics_desc',
  },
  {
    key: 'pdf',
    format: 'pdf',
    extension: '.pdf',
    icon: <PdfIcon />,
    titleKey: 'export.pdf_title',
    descKey: 'export.pdf_desc',
  },
];

/* ===========================================================================
   Export Page
   =========================================================================== */

export function Export() {
  const { t } = useTranslation();
  const { data: profilesData } = useProfiles();
  const profiles = profilesData || [];
  const [selectedProfile, setSelectedProfile] = useState('');
  const [downloading, setDownloading] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const profileId = selectedProfile || profiles[0]?.id || '';

  const handleDownload = async (fmt: ExportFormat) => {
    if (!profileId || downloading) return;
    setError(null);
    setDownloading(fmt.key);
    try {
      const profileName = profiles.find((p) => p.id === profileId)?.display_name || 'healthvault';
      const filename = `${profileName}-${fmt.key}${fmt.extension}`;
      await downloadExport(profileId, fmt.format, filename);
    } catch {
      setError(t('export.fhir_title')); // generic error fallback
    } finally {
      setDownloading(null);
    }
  };

  return (
    <div className="page">
      <div className="page-header">
        <h2>{t('export.title')}</h2>
        <div className="page-actions">
          <ProfileSelector selectedId={profileId} onSelect={setSelectedProfile} />
        </div>
      </div>

      {error && (
        <div className="card" style={{ background: 'var(--color-danger-light)', color: 'var(--color-danger)', marginBottom: 16, padding: '12px 16px' }}>
          {error}
        </div>
      )}

      <div className="export-grid">
        {EXPORT_FORMATS.map((fmt) => {
          const isActive = downloading === fmt.key;
          return (
            <div key={fmt.key} className="card export-card">
              <div className="export-card-icon">{fmt.icon}</div>
              <div className="export-card-body">
                <h3 className="export-card-title">{t(fmt.titleKey)}</h3>
                <p className="export-card-desc">{t(fmt.descKey)}</p>
              </div>
              <button
                className="btn btn-primary export-card-btn"
                onClick={() => handleDownload(fmt)}
                disabled={!profileId || !!downloading}
              >
                {isActive ? (
                  <>
                    <span className="export-spinner" />
                    {t('export.downloading')}
                  </>
                ) : (
                  <>
                    <DownloadSmallIcon />
                    {t('export.download')}
                  </>
                )}
              </button>
            </div>
          );
        })}
      </div>
    </div>
  );
}
