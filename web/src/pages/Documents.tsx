import { useState, useCallback } from 'react';
import { useTranslation } from 'react-i18next';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { format } from 'date-fns';
import { ProfileSelector } from '../components/ProfileSelector';
import { useProfiles } from '../hooks/useProfiles';
import { documentsApi, type Document as HealthDoc } from '../api/documents';

const CATEGORIES = [
  'lab_result', 'imaging', 'prescription', 'referral',
  'vaccination_record', 'discharge_summary', 'report', 'legal', 'other',
];

function formatBytes(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1048576) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / 1048576).toFixed(1)} MB`;
}

export function Documents() {
  const { t } = useTranslation();
  const { data: profilesData } = useProfiles();
  const profiles = profilesData?.items || [];
  const [selectedProfile, setSelectedProfile] = useState('');
  const [category, setCategory] = useState('');
  const [dragOver, setDragOver] = useState(false);
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
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['documents', profileId] }),
  });

  const handleFileUpload = useCallback((files: FileList | null) => {
    if (!files || !profileId) return;
    Array.from(files).forEach((file) => {
      uploadMutation.mutate({ file, cat: category || 'other' });
    });
  }, [profileId, category, uploadMutation]);

  const handleDrop = useCallback((e: React.DragEvent) => {
    e.preventDefault();
    setDragOver(false);
    handleFileUpload(e.dataTransfer.files);
  }, [handleFileUpload]);

  const items = data?.items || [];
  const filteredItems = category
    ? items.filter((d) => d.category === category)
    : items;

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
          <select
            value={category}
            onChange={(e) => setCategory(e.target.value)}
            className="metric-selector"
          >
            <option value="">All categories</option>
            {CATEGORIES.map((c) => (
              <option key={c} value={c}>{c.replace(/_/g, ' ')}</option>
            ))}
          </select>
          <label className="btn btn-add">
            Upload
            <input
              type="file"
              multiple
              hidden
              onChange={(e) => handleFileUpload(e.target.files)}
            />
          </label>
        </div>
      </div>

      {dragOver && (
        <div className="drop-overlay">
          <div className="drop-message">Drop files to upload</div>
        </div>
      )}

      {uploadMutation.isPending && (
        <div className="card">
          <p>Uploading...</p>
        </div>
      )}

      <div className="card">
        {isLoading ? (
          <p>{t('common.loading')}</p>
        ) : filteredItems.length === 0 ? (
          <p className="text-muted">{t('common.no_data')}</p>
        ) : (
          <div className="doc-list">
            {filteredItems.map((doc) => (
              <div key={doc.id} className="doc-item">
                <div className="doc-icon">
                  {getDocIcon(doc.mime_type)}
                </div>
                <div className="doc-info">
                  <div className="doc-name">{doc.filename_enc}</div>
                  <div className="doc-meta">
                    {formatBytes(doc.file_size_bytes)} · {doc.category.replace(/_/g, ' ')} · {format(new Date(doc.created_at), 'MMM d, yyyy')}
                  </div>
                  {doc.tags && doc.tags.length > 0 && (
                    <div className="doc-tags">
                      {doc.tags.map((tag) => <span key={tag} className="tag">{tag}</span>)}
                    </div>
                  )}
                </div>
                <button
                  className="btn-icon-sm"
                  onClick={() => deleteMutation.mutate(doc.id)}
                  title={t('common.delete')}
                >
                  ×
                </button>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}

function getDocIcon(mimeType: string): string {
  if (mimeType.startsWith('image/')) return '🖼';
  if (mimeType === 'application/pdf') return '📑';
  return '📄';
}
