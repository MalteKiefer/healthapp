import { useState, useCallback, useEffect, useRef } from 'react';
import { useTranslation } from 'react-i18next';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { ProfileSelector } from '../components/ProfileSelector';
import { useDateFormat } from '../hooks/useDateLocale';
import { ConfirmDelete } from '../components/ConfirmDelete';
import { useProfiles } from '../hooks/useProfiles';
import { documentsApi, type Document } from '../api/documents';
import { api } from '../api/client';
import { formatBytes } from '../utils/format';
import { getProfileKey } from '../crypto/keys';
import { decryptToBytes, decrypt } from '../crypto/encrypt';

const CATEGORIES = [
  'lab_result', 'imaging', 'prescription', 'referral',
  'vaccination_record', 'discharge_summary', 'report', 'legal', 'other',
];

/* ---------------------------------------------------------------------------
   SVG Icons (monochrome, stroke-based)
   --------------------------------------------------------------------------- */

function FileIcon({ size = 20 }: { size?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
      <path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z" />
      <polyline points="14 2 14 8 20 8" />
      <line x1="16" y1="13" x2="8" y2="13" />
      <line x1="16" y1="17" x2="8" y2="17" />
      <polyline points="10 9 9 9 8 9" />
    </svg>
  );
}

function ImageIcon({ size = 20 }: { size?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
      <rect x="3" y="3" width="18" height="18" rx="2" ry="2" />
      <circle cx="8.5" cy="8.5" r="1.5" />
      <polyline points="21 15 16 10 5 21" />
    </svg>
  );
}

function PdfIcon({ size = 20 }: { size?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
      <path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z" />
      <polyline points="14 2 14 8 20 8" />
      <path d="M9 15v-2h1.5a1.5 1.5 0 0 1 0 3H9z" />
      <path d="M14 13h1.5a1.5 1.5 0 0 1 0 3H14v-4z" />
    </svg>
  );
}

function DownloadIcon({ size = 18 }: { size?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
      <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4" />
      <polyline points="7 10 12 15 17 10" />
      <line x1="12" y1="15" x2="12" y2="3" />
    </svg>
  );
}

function ArrowLeftIcon({ size = 18 }: { size?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
      <line x1="19" y1="12" x2="5" y2="12" />
      <polyline points="12 19 5 12 12 5" />
    </svg>
  );
}

function UploadIcon({ size = 20 }: { size?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
      <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4" />
      <polyline points="17 8 12 3 7 8" />
      <line x1="12" y1="3" x2="12" y2="15" />
    </svg>
  );
}

function LinkIcon({ size = 16 }: { size?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
      <path d="M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71" />
      <path d="M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71" />
    </svg>
  );
}

function TrashIcon({ size = 16 }: { size?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
      <polyline points="3 6 5 6 21 6" />
      <path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2" />
    </svg>
  );
}

function CloseIcon({ size = 14 }: { size?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <line x1="18" y1="6" x2="6" y2="18" />
      <line x1="6" y1="6" x2="18" y2="18" />
    </svg>
  );
}

function getDocIconComponent(mimeType: string, size = 20) {
  if (mimeType.startsWith('image/')) return <ImageIcon size={size} />;
  if (mimeType === 'application/pdf') return <PdfIcon size={size} />;
  return <FileIcon size={size} />;
}

/* ---------------------------------------------------------------------------
   Filename decryption helper
   --------------------------------------------------------------------------- */

function useDecryptedFilename(profileId: string, doc: Document | null): string {
  const [name, setName] = useState('');
  useEffect(() => {
    if (!doc) { setName(''); return; }
    if (!doc.encrypted_at) { setName(doc.filename_enc); return; }
    const profileKey = getProfileKey(profileId);
    if (!profileKey) { setName(doc.filename_enc); return; }
    let cancelled = false;
    decrypt(doc.filename_enc, profileKey)
      .then((decrypted) => { if (!cancelled) setName(decrypted); })
      .catch(() => { if (!cancelled) setName(doc.filename_enc); });
    return () => { cancelled = true; };
  }, [profileId, doc?.id, doc?.filename_enc, doc?.encrypted_at]);
  return name;
}

/**
 * Decrypt a filename synchronously from cache or return the raw value.
 * For list views where we can't easily use a hook per-item, we fire-and-forget
 * decrypt and show the encrypted string until ready.
 */
function DecryptedName({ profileId, doc }: { profileId: string; doc: Document }) {
  const name = useDecryptedFilename(profileId, doc);
  return <>{name || doc.filename_enc}</>;
}

/* ---------------------------------------------------------------------------
   Blob URL fetcher for authenticated preview/download
   --------------------------------------------------------------------------- */

async function fetchBlobUrl(profileId: string, docId: string, mimeType: string): Promise<string> {
  const res = await fetch(documentsApi.downloadUrl(profileId, docId), {
    credentials: 'include',
  });
  if (!res.ok) throw new Error('Download failed');

  const isEncrypted = res.headers.get('X-Encrypted') === 'true';
  if (isEncrypted) {
    const profileKey = getProfileKey(profileId);
    if (!profileKey) throw new Error('No profile key for decryption');
    // The stored file is base64(iv+ciphertext) text written by encryptFile
    const base64Text = await res.text();
    const decryptedBytes = await decryptToBytes(base64Text, profileKey);
    const blob = new Blob([decryptedBytes], { type: mimeType });
    return URL.createObjectURL(blob);
  }

  // Legacy unencrypted file
  const blob = await res.blob();
  return URL.createObjectURL(blob);
}

/* ---------------------------------------------------------------------------
   Helper: parse linked records from tags
   --------------------------------------------------------------------------- */

function getLinkedRecords(tags: string[] | undefined): { type: string; id: string; name: string; raw: string }[] {
  if (!tags) return [];
  return tags
    .filter((t) => t.startsWith('link:'))
    .map((t) => {
      const parts = t.split(':');
      return { type: parts[1], id: parts[2], name: parts.slice(3).join(':') || parts[2].slice(0, 8), raw: t };
    })
    .filter((r) => r.type && r.id);
}

function getNonLinkTags(tags: string[] | undefined): string[] {
  if (!tags) return [];
  return tags.filter((t) => !t.startsWith('link:'));
}

/* ===========================================================================
   Shared style constants
   =========================================================================== */

const styleCardMB16 = { marginBottom: 16 } as const;
const styleBtnGap6 = { gap: 6 } as const;
const styleDocItemCursor = { cursor: 'pointer' } as const;

/* ===========================================================================
   Documents Page
   =========================================================================== */

export function Documents() {
  const { t } = useTranslation();
  const { fmt } = useDateFormat();
  const { data: profilesData } = useProfiles();
  const profiles = profilesData || [];
  const [selectedProfile, setSelectedProfile] = useState('');
  const [categoryFilter, setCategoryFilter] = useState('');
  const [dragOver, setDragOver] = useState(false);
  const [deleteTarget, setDeleteTarget] = useState<string | null>(null);
  const [selectedDoc, setSelectedDoc] = useState<Document | null>(null);
  const [uploadCategory, setUploadCategory] = useState('other');
  const queryClient = useQueryClient();

  const profileId = selectedProfile || profiles[0]?.id || '';

  const { data, isLoading } = useQuery({
    queryKey: ['documents', profileId],
    queryFn: () => documentsApi.list(profileId),
    enabled: !!profileId,
  });

  const uploadMutation = useMutation({
    mutationFn: ({ file, cat }: { file: File; cat: string }) =>
      documentsApi.upload(profileId, file, cat),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['documents', profileId] }),
  });

  const deleteMutation = useMutation({
    mutationFn: (id: string) => documentsApi.delete(profileId, id),
    // Use the mutation's variables (the deleted id) rather than deleteTarget,
    // which is cleared synchronously in the confirm handler and is already null
    // by the time onSuccess runs — the detail view would otherwise stay open.
    onSuccess: (_data, deletedId) => {
      queryClient.invalidateQueries({ queryKey: ['documents', profileId] });
      if (selectedDoc && deletedId === selectedDoc.id) {
        setSelectedDoc(null);
      }
    },
  });

  const updateMutation = useMutation({
    mutationFn: ({ id, data: updateData }: { id: string; data: Partial<Document> }) =>
      documentsApi.update(profileId, id, updateData),
    onSuccess: (updated) => {
      queryClient.invalidateQueries({ queryKey: ['documents', profileId] });
      setSelectedDoc(updated);
    },
  });

  const handleFileUpload = useCallback((files: FileList | null) => {
    if (!files || !profileId) return;
    Array.from(files).forEach((file) => {
      uploadMutation.mutate({ file, cat: uploadCategory });
    });
  }, [profileId, uploadCategory, uploadMutation]);

  const handleDrop = useCallback((e: React.DragEvent) => {
    e.preventDefault();
    setDragOver(false);
    handleFileUpload(e.dataTransfer.files);
  }, [handleFileUpload]);

  const [searchQuery, setSearchQuery] = useState('');

  const items = data?.items || [];
  const filteredItems = items.filter((d) => {
    if (categoryFilter && d.category !== categoryFilter) return false;
    if (!searchQuery.trim()) return true;
    const q = searchQuery.toLowerCase();
    if (d.filename_enc.toLowerCase().includes(q)) return true;
    if (t('documents.cat_' + d.category).toLowerCase().includes(q)) return true;
    if (d.tags?.some((tag) => tag.toLowerCase().includes(q))) return true;
    return false;
  });

  // When detail view is open
  if (selectedDoc) {
    return (
      <DocumentDetail
        doc={selectedDoc}
        profileId={profileId}
        onBack={() => setSelectedDoc(null)}
        onDelete={(id) => { setDeleteTarget(id); }}
        onUpdate={(id, updateData) => updateMutation.mutate({ id, data: updateData })}
        updatePending={updateMutation.isPending}
        t={t}
        fmt={fmt}
        deleteTarget={deleteTarget}
        deleteMutation={deleteMutation}
        setDeleteTarget={setDeleteTarget}
      />
    );
  }

  return (
    <div
      className={`page ${dragOver ? 'drop-active' : ''}`}
      onDragOver={(e) => { e.preventDefault(); setDragOver(true); }}
      onDragLeave={() => setDragOver(false)}
      onDrop={handleDrop}
    >
      <div className="page-header">
        <h2>{t('nav.documents')}</h2>
        <div className="page-actions">
          <ProfileSelector selectedId={profileId} onSelect={setSelectedProfile} />
          <div className="form-group" style={{ margin: 0, minWidth: 200 }}>
            <input
              type="text"
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              placeholder={t('documents.search_placeholder')}
              style={{ padding: '8px 14px', fontSize: 13 }}
            />
          </div>
          <select
            value={categoryFilter}
            onChange={(e) => setCategoryFilter(e.target.value)}
            className="metric-selector"
          >
            <option value="">{t('documents.all_categories')}</option>
            {CATEGORIES
              .map((c) => ({ value: c, label: t('documents.cat_' + c) }))
              .sort((a, b) => a.label.localeCompare(b.label))
              .map(({ value, label }) => (
                <option key={value} value={value}>{label}</option>
              ))}
          </select>
        </div>
      </div>

      {/* Upload area */}
      <div className="card" style={styleCardMB16}>
        <div
          className="doc-upload-zone"
          onClick={() => document.getElementById('doc-file-input')?.click()}
          onDragOver={(e) => { e.preventDefault(); e.stopPropagation(); }}
          onDrop={(e) => { e.preventDefault(); e.stopPropagation(); handleFileUpload(e.dataTransfer.files); }}
        >
          <UploadIcon size={32} />
          <p className="doc-upload-text">{t('documents.upload_hint')}</p>
          <div className="doc-upload-controls" onClick={(e) => e.stopPropagation()}>
            <select
              value={uploadCategory}
              onChange={(e) => setUploadCategory(e.target.value)}
              className="metric-selector"
            >
              {CATEGORIES
                .map((c) => ({ value: c, label: t('documents.cat_' + c) }))
                .sort((a, b) => a.label.localeCompare(b.label))
                .map(({ value, label }) => (
                  <option key={value} value={value}>{label}</option>
                ))}
            </select>
          </div>
          <input
            id="doc-file-input"
            type="file"
            multiple
            hidden
            onChange={(e) => { handleFileUpload(e.target.files); e.target.value = ''; }}
          />
        </div>
        {uploadMutation.isPending && (
          <div className="doc-upload-progress">
            <div className="doc-upload-spinner" />
            <span>{t('documents.uploading_file')}</span>
          </div>
        )}
      </div>

      {dragOver && (
        <div className="drop-overlay">
          <div className="drop-message">{t('documents.drop_files')}</div>
        </div>
      )}

      {/* Document list */}
      <div className="card">
        {isLoading ? (
          <p>{t('common.loading')}</p>
        ) : filteredItems.length === 0 ? (
          <p className="text-muted">{t('common.no_data')}</p>
        ) : (
          <div className="doc-list">
            {filteredItems.map((doc) => (
              <div
                key={doc.id}
                className="doc-item"
                style={styleDocItemCursor}
                onClick={() => setSelectedDoc(doc)}
              >
                <div className="doc-icon">
                  {getDocIconComponent(doc.mime_type, 26)}
                </div>
                <div className="doc-info">
                  <div className="doc-name"><DecryptedName profileId={profileId} doc={doc} /></div>
                  <div className="doc-meta">
                    <span className="doc-category-badge">{t('documents.cat_' + doc.category)}</span>
                    {' '}&middot;{' '}{formatBytes(doc.file_size_bytes)}{' '}&middot;{' '}{fmt(doc.created_at, 'dd. MMM yyyy')}
                  </div>
                  {doc.tags && getNonLinkTags(doc.tags).length > 0 && (
                    <div className="doc-tags">
                      {getNonLinkTags(doc.tags).map((tag) => <span key={tag} className="tag">{tag}</span>)}
                    </div>
                  )}
                </div>
                <button
                  className="btn-icon-sm"
                  onClick={(e) => { e.stopPropagation(); setDeleteTarget(doc.id); }}
                  title={t('common.delete')}
                  aria-label={t('common.delete')}
                >
                  <TrashIcon size={14} />
                </button>
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

/* ===========================================================================
   Document Detail View
   =========================================================================== */

interface DocumentDetailProps {
  doc: Document;
  profileId: string;
  onBack: () => void;
  onDelete: (id: string) => void;
  onUpdate: (id: string, data: Partial<Document>) => void;
  updatePending: boolean;
  t: (key: string) => string;
  fmt: (date: string, format: string) => string;
  deleteTarget: string | null;
  deleteMutation: ReturnType<typeof useMutation<unknown, Error, string>>;
  setDeleteTarget: (id: string | null) => void;
}

function DocumentDetail({
  doc, profileId, onBack, onDelete, onUpdate, updatePending,
  t, fmt, deleteTarget, deleteMutation, setDeleteTarget,
}: DocumentDetailProps) {
  const displayFilename = useDecryptedFilename(profileId, doc);
  const [editFilename, setEditFilename] = useState(doc.filename_enc);
  const [editCategory, setEditCategory] = useState(doc.category);
  const [editTags, setEditTags] = useState(getNonLinkTags(doc.tags).join(', '));
  const [blobUrl, setBlobUrl] = useState<string | null>(null);
  const [previewLoading, setPreviewLoading] = useState(false);
  const [previewError, setPreviewError] = useState(false);
  const blobUrlRef = useRef<string | null>(null);

  const linkedRecords = getLinkedRecords(doc.tags);

  const { data: labsData } = useQuery({
    queryKey: ['labs', profileId],
    queryFn: () => api.get<{ items: { id: string; lab_name?: string; sample_date: string }[] }>(`/api/v1/profiles/${profileId}/labs`),
    enabled: !!profileId,
  });

  const { data: diaryData } = useQuery({
    queryKey: ['diary', profileId],
    queryFn: () => api.get<{ items: { id: string; title: string; started_at: string }[]; total: number }>(`/api/v1/profiles/${profileId}/diary?limit=50`),
    enabled: !!profileId,
  });

  const { data: appointmentsData } = useQuery({
    queryKey: ['appointments', profileId],
    queryFn: () => api.get<{ items: { id: string; title: string; scheduled_at: string }[] }>(`/api/v1/profiles/${profileId}/appointments`),
    enabled: !!profileId,
  });
  const isImage = doc.mime_type.startsWith('image/');
  const isPdf = doc.mime_type === 'application/pdf';
  const canPreview = isImage || isPdf;

  // Sync edit state when doc changes or filename is decrypted
  useEffect(() => {
    setEditFilename(displayFilename || doc.filename_enc);
    setEditCategory(doc.category);
    setEditTags(getNonLinkTags(doc.tags).join(', '));
  }, [doc, displayFilename]);

  // Load blob URL for preview
  useEffect(() => {
    if (!canPreview) return;
    let cancelled = false;
    setPreviewLoading(true);
    setPreviewError(false);

    fetchBlobUrl(profileId, doc.id, doc.mime_type)
      .then((url) => {
        if (!cancelled) {
          setBlobUrl(url);
          blobUrlRef.current = url;
          setPreviewLoading(false);
        } else {
          URL.revokeObjectURL(url);
        }
      })
      .catch(() => {
        if (!cancelled) {
          setPreviewError(true);
          setPreviewLoading(false);
        }
      });

    return () => {
      cancelled = true;
      if (blobUrlRef.current) {
        URL.revokeObjectURL(blobUrlRef.current);
        blobUrlRef.current = null;
        setBlobUrl(null);
      }
    };
  }, [profileId, doc.id, canPreview]);

  const handleSave = async () => {
    const nonLinkTags = editTags
      .split(',')
      .map((t) => t.trim())
      .filter(Boolean);
    const linkTags = (doc.tags || []).filter((t) => t.startsWith('link:'));
    const allTags = [...nonLinkTags, ...linkTags];

    let filenameToSave = editFilename;
    if (doc.encrypted_at) {
      const profileKey = getProfileKey(profileId);
      if (profileKey) {
        const { encryptString } = await import('../crypto/encrypt');
        filenameToSave = await encryptString(editFilename, profileKey);
      }
    }

    onUpdate(doc.id, {
      filename_enc: filenameToSave,
      category: editCategory,
      tags: allTags,
    });
  };

  const handleAddLink = (value: string) => {
    const [type, id, ...nameParts] = value.split(':');
    const name = nameParts.join(':');
    const linkTag = `link:${type}:${id}:${name}`;
    const currentTags = doc.tags || [];
    if (currentTags.some((t) => t.startsWith(`link:${type}:${id}`))) return;
    onUpdate(doc.id, { tags: [...currentTags, linkTag] });
  };

  const handleRemoveLink = (rawTag: string) => {
    const currentTags = doc.tags || [];
    onUpdate(doc.id, { tags: currentTags.filter((t) => t !== rawTag) });
  };

  const handleDownload = async () => {
    try {
      const url = await fetchBlobUrl(profileId, doc.id, doc.mime_type);
      const a = document.createElement('a');
      a.href = url;
      a.download = displayFilename || doc.filename_enc;
      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);
      setTimeout(() => URL.revokeObjectURL(url), 1000);
    } catch {
      // Download failed silently
    }
  };

  const hasChanges =
    editFilename !== (displayFilename || doc.filename_enc) ||
    editCategory !== doc.category ||
    editTags !== getNonLinkTags(doc.tags).join(', ');

  return (
    <div className="page">
      <div className="page-header">
        <button className="btn btn-ghost" onClick={onBack} style={styleBtnGap6}>
          <ArrowLeftIcon size={16} />
          {t('common.back')}
        </button>
        <h2 style={{ flex: 1, marginLeft: 8 }}>{t('documents.detail')}</h2>
        <div className="page-actions">
          <button className="btn btn-secondary" onClick={handleDownload} style={styleBtnGap6}>
            <DownloadIcon size={16} />
            {t('documents.download')}
          </button>
          <button
            className="btn btn-danger"
            onClick={() => onDelete(doc.id)}
            style={styleBtnGap6}
          >
            <TrashIcon size={14} />
            {t('common.delete')}
          </button>
        </div>
      </div>

      {/* Document header info */}
      <div className="card" style={styleCardMB16}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
          <div className="doc-icon" style={{ color: 'var(--color-primary)' }}>
            {getDocIconComponent(doc.mime_type, 32)}
          </div>
          <div style={{ flex: 1, minWidth: 0 }}>
            <div style={{ fontWeight: 600, fontSize: 16 }}>{displayFilename}</div>
            <div style={{ fontSize: 13, color: 'var(--color-text-secondary)', marginTop: 2 }}>
              <span className="doc-category-badge">{t('documents.cat_' + doc.category)}</span>
              {' '}&middot;{' '}{formatBytes(doc.file_size_bytes)}{' '}&middot;{' '}{fmt(doc.created_at, 'dd. MMM yyyy, HH:mm')}
            </div>
          </div>
        </div>
      </div>

      {/* Preview panel */}
      <div className="card" style={styleCardMB16}>
        <h3 style={{ marginBottom: 12 }}>{t('documents.preview')}</h3>
        {canPreview ? (
          previewLoading ? (
            <div className="doc-preview-placeholder">
              <div className="doc-upload-spinner" />
              <span>{t('common.loading')}</span>
            </div>
          ) : previewError ? (
            <div className="doc-preview-placeholder">
              <FileIcon size={32} />
              <span style={{ color: 'var(--color-text-secondary)' }}>{t('documents.no_preview')}</span>
            </div>
          ) : blobUrl && isImage ? (
            <div className="doc-preview-container">
              <img
                src={blobUrl}
                alt={displayFilename}
                className="doc-preview-image"
              />
            </div>
          ) : blobUrl && isPdf ? (
            <div className="doc-preview-container">
              <iframe
                src={blobUrl}
                title={displayFilename}
                className="doc-preview-pdf"
              />
            </div>
          ) : null
        ) : (
          <div className="doc-preview-placeholder">
            <FileIcon size={48} />
            <span style={{ color: 'var(--color-text-secondary)', marginTop: 8 }}>{t('documents.no_preview')}</span>
            <button className="btn btn-secondary" onClick={handleDownload} style={{ marginTop: 12, gap: 6 }}>
              <DownloadIcon size={16} />
              {t('documents.download')}
            </button>
          </div>
        )}
      </div>

      {/* Metadata edit section */}
      <div className="card" style={styleCardMB16}>
        <h3 style={{ marginBottom: 12 }}>{t('common.edit')}</h3>
        <div className="doc-edit-form">
          <div className="form-group">
            <label>{t('documents.filename')}</label>
            <input
              type="text"
              value={editFilename}
              onChange={(e) => setEditFilename(e.target.value)}
            />
          </div>
          <div className="form-group">
            <label>{t('documents.category')}</label>
            <select
              value={editCategory}
              onChange={(e) => setEditCategory(e.target.value)}
              style={{ width: '100%' }}
            >
              {CATEGORIES
                .map((c) => ({ value: c, label: t('documents.cat_' + c) }))
                .sort((a, b) => a.label.localeCompare(b.label))
                .map(({ value, label }) => (
                  <option key={value} value={value}>{label}</option>
                ))}
            </select>
          </div>
          <div className="form-group">
            <label>{t('documents.tags')} <small style={{ color: 'var(--color-text-secondary)' }}>({t('documents.tags_hint')})</small></label>
            <input
              type="text"
              value={editTags}
              onChange={(e) => setEditTags(e.target.value)}
              placeholder={t('documents.tags_placeholder')}
            />
          </div>
          <button
            className="btn btn-primary"
            onClick={handleSave}
            disabled={!hasChanges || updatePending}
          >
            {updatePending ? t('common.loading') : t('documents.save_changes')}
          </button>
        </div>
      </div>

      {/* Linked records section */}
      <div className="card">
        <h3 style={{ marginBottom: 12, display: 'flex', alignItems: 'center', gap: 8 }}>
          <LinkIcon size={18} />
          {t('documents.linked_records')}
        </h3>

        {linkedRecords.length > 0 && (
          <div className="doc-linked-list" style={{ marginBottom: 12 }}>
            {linkedRecords.map((rec) => (
              <span key={`${rec.type}:${rec.id}`} className="doc-linked-badge">
                <span className="doc-linked-type">{t('nav.' + rec.type)}</span>
                <span className="doc-linked-id">{rec.name}</span>
                <button
                  className="doc-linked-remove"
                  onClick={() => handleRemoveLink(rec.raw)}
                  title={t('common.delete')}
                  aria-label={t('common.delete')}
                >
                  <CloseIcon size={10} />
                </button>
              </span>
            ))}
          </div>
        )}

        <div className="form-group">
          <select
            className="form-group"
            value=""
            onChange={(e) => {
              if (e.target.value) {
                handleAddLink(e.target.value);
                e.target.value = '';
              }
            }}
            style={{ width: '100%' }}
          >
            <option value="">{t('documents.link_to')}</option>
            {labsData?.items && labsData.items.length > 0 && (
              <optgroup label={t('nav.labs')}>
                {labsData.items
                  .filter((l) => !linkedRecords.some((r) => r.id === l.id))
                  .sort((a, b) => (a.lab_name || '').localeCompare(b.lab_name || ''))
                  .map((l) => (
                    <option key={l.id} value={`labs:${l.id}:${l.lab_name || 'Lab'}`}>
                      {l.lab_name || t('labs.lab_result')} — {fmt(l.sample_date, 'dd. MMM yyyy')}
                    </option>
                  ))}
              </optgroup>
            )}
            {diaryData?.items && diaryData.items.length > 0 && (
              <optgroup label={t('nav.diary')}>
                {diaryData.items
                  .filter((d) => !linkedRecords.some((r) => r.id === d.id))
                  .sort((a, b) => a.title.localeCompare(b.title))
                  .map((d) => (
                    <option key={d.id} value={`diary:${d.id}:${d.title}`}>
                      {d.title} — {fmt(d.started_at, 'dd. MMM yyyy')}
                    </option>
                  ))}
              </optgroup>
            )}
            {appointmentsData?.items && appointmentsData.items.length > 0 && (
              <optgroup label={t('nav.appointments')}>
                {appointmentsData.items
                  .filter((a) => !linkedRecords.some((r) => r.id === a.id))
                  .sort((a, b) => a.title.localeCompare(b.title))
                  .map((a) => (
                    <option key={a.id} value={`appointments:${a.id}:${a.title}`}>
                      {a.title} — {fmt(a.scheduled_at, 'dd. MMM yyyy')}
                    </option>
                  ))}
              </optgroup>
            )}
          </select>
        </div>
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
