import { useState, useRef } from 'react';
import { useTranslation } from 'react-i18next';
import { createWorker } from 'tesseract.js';
import { api } from '../api/client';

export interface LabValue {
  marker: string;
  value: number;
  unit: string;
  referenceRange?: string;
}

export interface VitalValue {
  type: string;
  value: number;
  unit: string;
}

interface OCRResult {
  text: string;
  detectedDate: string | null;
  labValues: LabValue[];
  vitals: VitalValue[];
}

// Unified lab markers — abbreviations + full names (DE + EN)
interface MarkerDef {
  keys: RegExp; // regex matching abbreviation or full name in any language
  name: string; // canonical display name
  unit: string;
  range: [number, number]; // plausible value range
}

const MARKERS: MarkerDef[] = [
  { keys: /\b(LEU|Leukozyten|Leukocytes|WBC|White\s*Blood\s*Cells?)\b/i, name: 'Leukocytes (WBC)', unit: 'G/l', range: [0.1, 50] },
  { keys: /\b(ERY|Erythrozyten|Erythrocytes|RBC|Red\s*Blood\s*Cells?)\b/i, name: 'Erythrocytes (RBC)', unit: 'T/l', range: [1, 10] },
  { keys: /\b(HB|H[äa]moglobin|Hemoglobin|Hgb)\b/i, name: 'Hemoglobin', unit: 'g/dl', range: [3, 25] },
  { keys: /\b(HK|H[äa]matokrit|Hematocrit|HCT)\b/i, name: 'Hematocrit', unit: '%', range: [10, 70] },
  { keys: /\b(MCV)\b/i, name: 'MCV', unit: 'fl', range: [50, 130] },
  { keys: /\b(MCH)\b(?!\s*C)/i, name: 'MCH', unit: 'pg', range: [15, 50] },
  { keys: /\b(MCHC)\b/i, name: 'MCHC', unit: 'g/dl', range: [25, 40] },
  { keys: /\b(RDW)\b/i, name: 'RDW', unit: '%', range: [5, 30] },
  { keys: /\b(TZ|Thrombozyten|Thrombocytes|PLT|Platelets)\b/i, name: 'Platelets (PLT)', unit: 'G/l', range: [10, 900] },
  { keys: /\b(MPV)\b/i, name: 'MPV', unit: 'fl', range: [5, 20] },
  { keys: /\b(BZ|Glucose|Glukose|Blutzucker|Blood\s*Sugar)\b/i, name: 'Glucose', unit: 'mg/dl', range: [20, 600] },
  { keys: /\b(QUI|Quick)\b/i, name: 'Quick', unit: '%', range: [10, 150] },
  { keys: /\b(INR)\b/i, name: 'INR', unit: '', range: [0.5, 10] },
  { keys: /\b(PTT|aPTT)\b/i, name: 'PTT', unit: 'sec', range: [15, 100] },
  { keys: /\b(K|Kalium|Potassium)\b/i, name: 'Potassium (K)', unit: 'mmol/l', range: [2, 8] },
  { keys: /\b(NA|Natrium|Sodium)\b/i, name: 'Sodium (Na)', unit: 'mmol/l', range: [100, 180] },
  { keys: /\b(CA|Calcium|Kalzium)\b/i, name: 'Calcium', unit: 'mmol/l', range: [1, 4] },
  { keys: /\b(GT|GGT|Gamma.?GT|γ.?GT)\b/i, name: 'GGT', unit: 'U/l', range: [1, 1000] },
  { keys: /\b(GPT|ALT|ALAT)\b/i, name: 'ALT (GPT)', unit: 'U/l', range: [1, 1000] },
  { keys: /\b(GOT|AST|ASAT)\b/i, name: 'AST (GOT)', unit: 'U/l', range: [1, 1000] },
  { keys: /\b(KREAJ?|KREA|Kreatinin|Creatinine?)\b/i, name: 'Creatinine', unit: 'mg/dl', range: [0.1, 15] },
  { keys: /\b(GFR|eGFR)\b/i, name: 'eGFR', unit: 'ml/min/1.73m²', range: [5, 200] },
  { keys: /\b(CRP|C.?reaktiv|C.?Reactive)\b/i, name: 'CRP', unit: 'mg/l', range: [0, 300] },
  { keys: /\b(TSH)\b/i, name: 'TSH', unit: 'mU/l', range: [0.01, 50] },
  { keys: /\b(FT3|fT3|Free\s*T3)\b/i, name: 'fT3', unit: 'pg/ml', range: [1, 10] },
  { keys: /\b(FT4|fT4|Free\s*T4)\b/i, name: 'fT4', unit: 'ng/dl', range: [0.5, 5] },
  { keys: /\b(HbA1c|HBA1C|Glyco)\b/i, name: 'HbA1c', unit: '%', range: [3, 15] },
  { keys: /\b(CHOL|Cholesterin|Cholesterol)\b/i, name: 'Cholesterol', unit: 'mg/dl', range: [50, 500] },
  { keys: /\b(HDL)\b/i, name: 'HDL', unit: 'mg/dl', range: [10, 150] },
  { keys: /\b(LDL)\b/i, name: 'LDL', unit: 'mg/dl', range: [10, 400] },
  { keys: /\b(TRIG|Triglycerid|Triglyzerid)\b/i, name: 'Triglycerides', unit: 'mg/dl', range: [20, 1000] },
  { keys: /\b(FE|Eisen|Iron)\b/i, name: 'Iron', unit: 'µg/dl', range: [5, 300] },
  { keys: /\b(FERR|Ferritin)\b/i, name: 'Ferritin', unit: 'ng/ml', range: [1, 2000] },
  { keys: /\b(VITD|Vitamin\s*D|25.?OH)\b/i, name: 'Vitamin D', unit: 'ng/ml', range: [3, 150] },
  { keys: /\b(B12|Vitamin\s*B12|Cobalamin)\b/i, name: 'Vitamin B12', unit: 'pg/ml', range: [50, 2000] },
  { keys: /\b(FOLAT|Fols[äa]ure|Folate|Folic\s*Acid)\b/i, name: 'Folate', unit: 'ng/ml', range: [1, 50] },
  { keys: /\b(HARNS|Harns[äa]ure|Uric\s*Acid)\b/i, name: 'Uric Acid', unit: 'mg/dl', range: [1, 15] },
  { keys: /\b(BILI|Bilirubin)\b/i, name: 'Bilirubin', unit: 'mg/dl', range: [0.1, 20] },
  { keys: /\b(AP|Alkalische?\s*Phosphatase|ALP)\b/i, name: 'ALP', unit: 'U/l', range: [10, 500] },
  { keys: /\b(LIP|Lipase)\b/i, name: 'Lipase', unit: 'U/l', range: [1, 1000] },
  { keys: /\b(AMY|Amylase)\b/i, name: 'Amylase', unit: 'U/l', range: [10, 500] },
  { keys: /\b(LDH)\b/i, name: 'LDH', unit: 'U/l', range: [50, 1000] },
  { keys: /\b(CK|Creatinkinase|Creatine\s*Kinase)\b/i, name: 'CK', unit: 'U/l', range: [10, 5000] },
];

// Date patterns: DD.MM.YYYY, DD/MM/YYYY, YYYY-MM-DD, "Month DD, YYYY"
function detectDate(text: string): string | null {
  // German format: DD.MM.YYYY
  const deMatch = text.match(/(\d{2})\.(\d{2})\.(\d{4})/);
  if (deMatch) {
    const [, d, m, y] = deMatch;
    const date = new Date(`${y}-${m}-${d}`);
    if (!isNaN(date.getTime()) && date.getFullYear() >= 2000) return `${y}-${m}-${d}`;
  }
  // ISO: YYYY-MM-DD
  const isoMatch = text.match(/(\d{4})-(\d{2})-(\d{2})/);
  if (isoMatch) {
    const date = new Date(isoMatch[0]);
    if (!isNaN(date.getTime()) && date.getFullYear() >= 2000) return isoMatch[0];
  }
  // US: MM/DD/YYYY
  const usMatch = text.match(/(\d{2})\/(\d{2})\/(\d{4})/);
  if (usMatch) {
    const [, m, d, y] = usMatch;
    const date = new Date(`${y}-${m}-${d}`);
    if (!isNaN(date.getTime()) && date.getFullYear() >= 2000) return `${y}-${m}-${d}`;
  }
  return null;
}

function parseOCRText(text: string): OCRResult {
  const labValues: LabValue[] = [];
  const vitals: VitalValue[] = [];
  const seen = new Set<string>();

  const detectedDate = detectDate(text);

  const lines = text.split(/\n/);

  for (const rawLine of lines) {
    const line = rawLine.replace(/\|/g, ' ').replace(/\s+/g, ' ').trim();
    if (!line || line.length < 3) continue;

    // Skip header/metadata lines
    if (/Seite|Version|Build|isynet|Laborblatt|Normbereich|Ergebniswert|Bezeichnung|Analyse\b/i.test(line)) continue;
    if (/^Datum:|^Date:|^Page:/i.test(line)) continue;

    for (const marker of MARKERS) {
      if (seen.has(marker.name)) continue;
      if (!marker.keys.test(line)) continue;

      // Extract all numbers from the line
      const numRegex = /(\d{1,4}[.,]\d{1,2})/g;
      let m;
      while ((m = numRegex.exec(line)) !== null) {
        const val = parseFloat(m[1].replace(',', '.'));
        if (val >= 1900 && val <= 2100) continue;
        if (val >= marker.range[0] && val <= marker.range[1]) {
          // Look for reference range
          const afterVal = line.slice(m.index + m[0].length);
          const refMatch = afterVal.match(/(\d+[.,]?\d*)\s*[-–]\s*(\d+[.,]?\d*)/);
          labValues.push({
            marker: marker.name,
            value: val,
            unit: marker.unit,
            referenceRange: refMatch ? `${refMatch[1].replace(',', '.')}-${refMatch[2].replace(',', '.')}` : undefined,
          });
          seen.add(marker.name);
          break;
        }
      }

      // Also try integer-only matches for markers like Platelets, eGFR
      if (!seen.has(marker.name)) {
        const intRegex = /\b(\d{2,4})\b/g;
        let mi;
        while ((mi = intRegex.exec(line)) !== null) {
          const val = parseInt(mi[1]);
          if (val >= 1900 && val <= 2100) continue;
          if (val >= marker.range[0] && val <= marker.range[1]) {
            const afterVal = line.slice(mi.index + mi[0].length);
            const refMatch = afterVal.match(/(\d+[.,]?\d*)\s*[-–]\s*(\d+[.,]?\d*)/);
            labValues.push({
              marker: marker.name,
              value: val,
              unit: marker.unit,
              referenceRange: refMatch ? `${refMatch[1].replace(',', '.')}-${refMatch[2].replace(',', '.')}` : undefined,
            });
            seen.add(marker.name);
            break;
          }
        }
      }
    }

    // Vitals
    const bpMatch = line.match(/(?:Blutdruck|Blood\s*Pressure|RR|BD)\s*[:\s]*(\d{2,3})\s*[\/]\s*(\d{2,3})/i);
    if (bpMatch) {
      vitals.push({ type: 'Systolic BP', value: parseInt(bpMatch[1]), unit: 'mmHg' });
      vitals.push({ type: 'Diastolic BP', value: parseInt(bpMatch[2]), unit: 'mmHg' });
    }
    const pulseMatch = line.match(/(?:Puls|Pulse|Heart\s*Rate|HR|Herzfrequenz)\s*[:\s]*(\d{2,3})\s*(?:bpm|\/min)?/i);
    if (pulseMatch && !vitals.some(v => v.type === 'Pulse')) vitals.push({ type: 'Pulse', value: parseInt(pulseMatch[1]), unit: 'bpm' });
    const tempMatch = line.match(/(?:Temperatur|Temperature|Temp)\s*[:\s]*(\d{2}[.,]\d)\s*°?[CF]?/i);
    if (tempMatch && !vitals.some(v => v.type === 'Temperature')) vitals.push({ type: 'Temperature', value: parseFloat(tempMatch[1].replace(',', '.')), unit: '°C' });
    const weightMatch = line.match(/(?:Gewicht|Weight|Body\s*Weight)\s*[:\s]*(\d{2,3}[.,]?\d?)\s*kg/i);
    if (weightMatch && !vitals.some(v => v.type === 'Weight')) vitals.push({ type: 'Weight', value: parseFloat(weightMatch[1].replace(',', '.')), unit: 'kg' });
    const spo2Match = line.match(/(?:SpO2|Sauerstoff|O2.?Sat)\s*[:\s]*(\d{2,3})\s*%/i);
    if (spo2Match && !vitals.some(v => v.type === 'SpO2')) vitals.push({ type: 'SpO2', value: parseInt(spo2Match[1]), unit: '%' });
  }

  return { text, detectedDate, labValues, vitals };
}

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
    if (!file.type.startsWith('image/') && file.type !== 'application/pdf') {
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
          reference_low: lv.referenceRange ? parseFloat(lv.referenceRange.split('-')[0]) : undefined,
          reference_high: lv.referenceRange ? parseFloat(lv.referenceRange.split('-')[1]) : undefined,
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
