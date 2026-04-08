import { useState, useRef } from 'react';
import { useTranslation } from 'react-i18next';
import { createWorker } from 'tesseract.js';
import { api } from '../api/client';
import { parseOCRText, type LabValue, type VitalValue, type OCRResult } from '../utils/ocrParser';

export type { LabValue, VitalValue };

interface OCRUploadProps {
  profileId?: string;
  onLabValuesDetected?: (values: LabValue[]) => void;
  onVitalsDetected?: (values: VitalValue[]) => void;
}

export function OCRUpload({ profileId, onLabValuesDetected, onVitalsDetected }: OCRUploadProps) {
  const { t } = useTranslation();
  const [processing, setProcessing] = useState(false);
  const [progress, setProgress] = useState(0);
  const [result, setResult] = useState<OCRResult | null>(null);
  const [error, setError] = useState('');
  const [saving, setSaving] = useState(false);
  const [saved, setSaved] = useState(false);
  const fileRef = useRef<HTMLInputElement>(null);

  const handleFile = async (file: File) => {
    const valid = await validateFileMagicBytes(file);
    if (!valid) {
      setError(t('ocr.invalid_file'));
      return;
    }

    setProcessing(true);
    setProgress(0);
    setError('');
    setResult(null);
    setSaved(false);

    try {
      let imageSource: File | string = file;
      if (file.type.startsWith('image/')) {
        try { imageSource = await autoRotateImage(file); } catch { imageSource = file; }
      }

      const worker = await createWorker('deu+eng', undefined, {
        workerPath: '/tesseract/worker.min.js',
        corePath: '/tesseract/tesseract-core-lstm.wasm.js',
        langPath: '/tesseract/lang',
        gzip: true,
        logger: (m) => {
          if (m.status === 'recognizing text') setProgress(Math.round(m.progress * 100));
        },
      });

      const { data } = await worker.recognize(imageSource);
      let parsed = parseOCRText(data.text);

      // Auto-rotate 90° if nothing found
      if (parsed.labValues.length === 0 && parsed.vitals.length === 0 && file.type.startsWith('image/')) {
        setProgress(0);
        const rotated = await rotateImage(file, 90);
        const { data: data90 } = await worker.recognize(rotated);
        const parsed90 = parseOCRText(data90.text);
        if (parsed90.labValues.length > parsed.labValues.length) parsed = parsed90;
      }

      await worker.terminate();
      setResult(parsed);

      if (parsed.labValues.length > 0 && onLabValuesDetected) onLabValuesDetected(parsed.labValues);
      if (parsed.vitals.length > 0 && onVitalsDetected) onVitalsDetected(parsed.vitals);
    } catch (err) {
      setError(t('ocr.error') + ': ' + (err instanceof Error ? err.message : ''));
    } finally {
      setProcessing(false);
    }
  };

  const handleSaveLabValues = async () => {
    if (!result || !profileId || result.labValues.length === 0) return;
    setSaving(true);
    try {
      const sampleDate = result.detectedDate ? new Date(result.detectedDate).toISOString() : new Date().toISOString();
      await api.post(`/api/v1/profiles/${profileId}/labs`, {
        lab_name: 'OCR Import',
        sample_date: sampleDate,
        values: result.labValues.map((lv) => ({
          marker: lv.marker,
          value: lv.value,
          unit: lv.unit,
          reference_low: (() => {
            const parts = lv.referenceRange?.split(/[\u2013\u2014\-]/).map(s => parseFloat(s.trim()));
            return parts?.[0] != null && !isNaN(parts[0]) ? parts[0] : undefined;
          })(),
          reference_high: (() => {
            const parts = lv.referenceRange?.split(/[\u2013\u2014\-]/).map(s => parseFloat(s.trim()));
            return parts?.[1] != null && !isNaN(parts[1]) ? parts[1] : undefined;
          })(),
        })),
      });
      setSaved(true);
    } catch {
      setError(t('ocr.save_error'));
    } finally {
      setSaving(false);
    }
  };

  return (
    <div className="ocr-upload">
      <div
        className={`ocr-dropzone${processing ? ' processing' : ''}`}
        onDragOver={(e) => e.preventDefault()}
        onDrop={(e) => { e.preventDefault(); const f = e.dataTransfer.files[0]; if (f) handleFile(f); }}
        onClick={() => !processing && fileRef.current?.click()}
      >
        <input ref={fileRef} type="file" accept="image/*,.pdf" onChange={(e) => { const f = e.target.files?.[0]; if (f) handleFile(f); }} style={{ display: 'none' }} />

        {processing ? (
          <div className="ocr-progress">
            <div className="ocr-spinner" />
            <p>{t('ocr.analyzing')} {progress}%</p>
            <div className="storage-bar" style={{ width: '100%', maxWidth: 200 }}>
              <div className="storage-fill" style={{ width: `${progress}%` }} />
            </div>
          </div>
        ) : (
          <>
            <svg width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="var(--color-text-secondary)" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
              <path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z" />
              <polyline points="14 2 14 8 20 8" />
              <path d="M9 15l3-3 3 3" /><line x1="12" y1="12" x2="12" y2="18" />
            </svg>
            <p style={{ margin: '8px 0 4px', fontWeight: 500 }}>{t('ocr.drop_title')}</p>
            <p className="text-muted" style={{ fontSize: 12 }}>{t('ocr.drop_subtitle')}</p>
          </>
        )}
      </div>

      {error && <div className="alert alert-error" style={{ marginTop: 12 }}>{error}</div>}

      {result && (
        <div className="ocr-results" style={{ marginTop: 16 }}>
          {/* Detected date */}
          {result.detectedDate && (
            <p style={{ marginBottom: 12, fontSize: 14 }}>
              <strong>{t('ocr.detected_date')}:</strong> {new Date(result.detectedDate).toLocaleDateString()}
            </p>
          )}

          {/* Lab values */}
          {result.labValues.length > 0 && (
            <div className="card" style={{ marginBottom: 12 }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 12 }}>
                <h3 style={{ margin: 0 }}>{t('ocr.lab_values_found', { count: result.labValues.length })}</h3>
                {profileId && !saved && (
                  <button className="btn btn-add" onClick={handleSaveLabValues} disabled={saving}>
                    {saving ? t('common.loading') : t('ocr.save_as_lab')}
                  </button>
                )}
                {saved && <span className="badge badge-completed">{t('ocr.saved')}</span>}
              </div>
              <div className="table-scroll">
                <table className="data-table">
                  <thead>
                    <tr>
                      <th>{t('ocr.marker')}</th>
                      <th>{t('ocr.value')}</th>
                      <th>{t('ocr.unit')}</th>
                      <th>{t('ocr.reference')}</th>
                    </tr>
                  </thead>
                  <tbody>
                    {result.labValues.map((lv, i) => (
                      <tr key={i}>
                        <td style={{ fontWeight: 500 }}>{lv.marker}</td>
                        <td>{lv.value}</td>
                        <td className="text-muted">{lv.unit}</td>
                        <td className="text-muted">{lv.referenceRange || '—'}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </div>
          )}

          {/* Vitals */}
          {result.vitals.length > 0 && (
            <div className="card" style={{ marginBottom: 12 }}>
              <h3 style={{ marginBottom: 12 }}>{t('ocr.vitals_found', { count: result.vitals.length })}</h3>
              <div className="table-scroll">
                <table className="data-table">
                  <thead><tr><th>{t('common.type')}</th><th>{t('ocr.value')}</th><th>{t('ocr.unit')}</th></tr></thead>
                  <tbody>
                    {result.vitals.map((v, i) => (
                      <tr key={i}><td style={{ fontWeight: 500 }}>{v.type}</td><td>{v.value}</td><td className="text-muted">{v.unit}</td></tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </div>
          )}

          {result.labValues.length === 0 && result.vitals.length === 0 && (
            <div className="alert alert-warning">{t('ocr.no_values_found')}</div>
          )}

          <details style={{ marginTop: 8 }}>
            <summary className="text-muted" style={{ cursor: 'pointer', fontSize: 13 }}>{t('ocr.show_raw_text')}</summary>
            <pre style={{ marginTop: 8, padding: 12, background: 'var(--color-bg)', borderRadius: 8, fontSize: 12, whiteSpace: 'pre-wrap', maxHeight: 200, overflow: 'auto' }}>
              {result.text}
            </pre>
          </details>
        </div>
      )}
    </div>
  );
}

async function validateFileMagicBytes(file: File): Promise<boolean> {
  const buffer = await file.slice(0, 8).arrayBuffer();
  const bytes = new Uint8Array(buffer);
  // JPEG: FF D8 FF
  if (bytes[0] === 0xFF && bytes[1] === 0xD8 && bytes[2] === 0xFF) return true;
  // PNG: 89 50 4E 47
  if (bytes[0] === 0x89 && bytes[1] === 0x50 && bytes[2] === 0x4E && bytes[3] === 0x47) return true;
  // PDF: 25 50 44 46 (%PDF)
  if (bytes[0] === 0x25 && bytes[1] === 0x50 && bytes[2] === 0x44 && bytes[3] === 0x46) return true;
  return false;
}

async function autoRotateImage(file: File): Promise<string> {
  return new Promise((resolve, reject) => {
    const img = new Image();
    img.onload = () => {
      const c = document.createElement('canvas');
      c.width = img.naturalWidth; c.height = img.naturalHeight;
      const ctx = c.getContext('2d');
      if (!ctx) { reject(new Error('no ctx')); return; }
      ctx.drawImage(img, 0, 0);
      resolve(c.toDataURL('image/png'));
    };
    img.onerror = reject;
    img.src = URL.createObjectURL(file);
  });
}

async function rotateImage(file: File, degrees: number): Promise<string> {
  return new Promise((resolve, reject) => {
    const img = new Image();
    img.onload = () => {
      const rad = (degrees * Math.PI) / 180;
      const sin = Math.abs(Math.sin(rad)), cos = Math.abs(Math.cos(rad));
      const c = document.createElement('canvas');
      c.width = img.naturalWidth * cos + img.naturalHeight * sin;
      c.height = img.naturalWidth * sin + img.naturalHeight * cos;
      const ctx = c.getContext('2d');
      if (!ctx) { reject(new Error('no ctx')); return; }
      ctx.translate(c.width / 2, c.height / 2);
      ctx.rotate(rad);
      ctx.drawImage(img, -img.naturalWidth / 2, -img.naturalHeight / 2);
      resolve(c.toDataURL('image/png'));
    };
    img.onerror = reject;
    img.src = URL.createObjectURL(file);
  });
}
