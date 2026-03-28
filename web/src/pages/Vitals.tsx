import { useState, useCallback, useMemo, useRef } from 'react';
import { useTranslation } from 'react-i18next';
import { useForm } from 'react-hook-form';
import {
  LineChart, Line, XAxis, YAxis, CartesianGrid, Tooltip,
  ResponsiveContainer, Legend,
} from 'recharts';
import { format } from 'date-fns';
import * as XLSX from 'xlsx';
import { ProfileSelector } from '../components/ProfileSelector';
import { useVitals, useCreateVital } from '../hooks/useVitals';
import { useProfiles } from '../hooks/useProfiles';

function toLocalDatetime(date: Date = new Date()): string {
  const pad = (n: number) => n.toString().padStart(2, '0');
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}T${pad(date.getHours())}:${pad(date.getMinutes())}`;
}

interface VitalFormData {
  measured_at: string;
  blood_pressure_systolic?: number;
  blood_pressure_diastolic?: number;
  pulse?: number;
  oxygen_saturation?: number;
  weight?: number;
  height?: number;
  body_temperature?: number;
  blood_glucose?: number;
  sleep_duration_minutes?: number;
  sleep_quality?: number;
  notes?: string;
}

type VitalCategory = 'blood_pressure' | 'pulse' | 'weight' | 'temperature' | 'oxygen' | 'glucose' | 'sleep';

const VITAL_CHIPS: { id: VitalCategory; label: string; icon: string }[] = [
  { id: 'blood_pressure', label: 'Blood Pressure', icon: '\u2764\uFE0F' },
  { id: 'pulse', label: 'Pulse', icon: '\uD83D\uDC93' },
  { id: 'weight', label: 'Weight', icon: '\u2696\uFE0F' },
  { id: 'temperature', label: 'Temperature', icon: '\uD83C\uDF21\uFE0F' },
  { id: 'oxygen', label: 'SpO2', icon: '\uD83E\uDE78' },
  { id: 'glucose', label: 'Blood Glucose', icon: '\uD83E\uDE78' },
  { id: 'sleep', label: 'Sleep', icon: '\uD83D\uDCA4' },
];

interface MetricDef { key: string; label: string; unit: string; color: string }

const ALL_METRICS: MetricDef[] = [
  { key: 'blood_pressure_systolic', label: 'Sys. BP', unit: 'mmHg', color: '#FF3B30' },
  { key: 'blood_pressure_diastolic', label: 'Dia. BP', unit: 'mmHg', color: '#FF9500' },
  { key: 'pulse', label: 'Pulse', unit: 'bpm', color: '#34C759' },
  { key: 'weight', label: 'Weight', unit: 'kg', color: '#AF52DE' },
  { key: 'body_temperature', label: 'Temp', unit: '\u00B0C', color: '#FF2D55' },
  { key: 'oxygen_saturation', label: 'SpO2', unit: '%', color: '#007AFF' },
  { key: 'blood_glucose', label: 'Glucose', unit: 'mmol/L', color: '#FF9500' },
];

type TimeRange = '7d' | '30d' | '90d' | '1y' | 'all';
type ViewTab = 'chart' | 'table';

function exportExcel(vitals: Array<Record<string, unknown>>, t: (key: string) => string) {
  {
    const headers = [
      t('common.date'),
      `${t('vitals.systolic')} (mmHg)`,
      `${t('vitals.diastolic')} (mmHg)`,
      `${t('vitals.pulse')} (bpm)`,
      `${t('vitals.weight')} (kg)`,
      `${t('vitals.temperature')} (\u00B0C)`,
      `${t('vitals.oxygen')} (%)`,
      `${t('vitals.glucose')} (mmol/L)`,
    ];
    const keys = ['measured_at', 'blood_pressure_systolic', 'blood_pressure_diastolic', 'pulse', 'weight', 'body_temperature', 'oxygen_saturation', 'blood_glucose'];
    const rows = vitals.map((v) =>
      keys.map((k) => {
        if (k === 'measured_at') return format(new Date(v[k] as string), 'dd.MM.yyyy HH:mm');
        const val = v[k];
        return val != null ? Number(val) : '';
      })
    );
    const ws = XLSX.utils.aoa_to_sheet([headers, ...rows]);
    // Auto-width columns
    ws['!cols'] = headers.map((h) => ({ wch: Math.max(h.length + 2, 14) }));
    const wb = XLSX.utils.book_new();
    XLSX.utils.book_append_sheet(wb, ws, t('vitals.title'));
    XLSX.writeFile(wb, `${t('vitals.title')}_${format(new Date(), 'yyyy-MM-dd')}.xlsx`);
  }
}

function exportChartPNG(chartRef: React.RefObject<HTMLDivElement | null>) {
  const container = chartRef.current;
  if (!container) return;
  const svg = container.querySelector('svg');
  if (!svg) return;
  const svgData = new XMLSerializer().serializeToString(svg);
  const canvas = document.createElement('canvas');
  const rect = svg.getBoundingClientRect();
  canvas.width = rect.width * 2;
  canvas.height = rect.height * 2;
  const ctx = canvas.getContext('2d');
  if (!ctx) return;
  ctx.scale(2, 2);
  ctx.fillStyle = '#ffffff';
  ctx.fillRect(0, 0, rect.width, rect.height);
  const img = new Image();
  img.onload = () => {
    ctx.drawImage(img, 0, 0, rect.width, rect.height);
    const link = document.createElement('a');
    link.download = `vitalwerte_${format(new Date(), 'yyyy-MM-dd')}.png`;
    link.href = canvas.toDataURL('image/png');
    link.click();
  };
  img.src = 'data:image/svg+xml;base64,' + btoa(unescape(encodeURIComponent(svgData)));
}

export function Vitals() {
  const { t } = useTranslation();
  const { data: profilesData } = useProfiles();
  const profiles = profilesData || [];
  const [selectedProfile, setSelectedProfile] = useState<string>('');
  const [showModal, setShowModal] = useState(false);
  const [modalStep, setModalStep] = useState<1 | 2>(1);
  const [selectedVitals, setSelectedVitals] = useState<Set<VitalCategory>>(new Set());
  const [timeRange, setTimeRange] = useState<TimeRange>('30d');
  const [viewTab, setViewTab] = useState<ViewTab>('chart');
  const [visibleMetrics, setVisibleMetrics] = useState<Set<string>>(new Set(ALL_METRICS.map((m) => m.key)));
  const chartRef = useRef<HTMLDivElement>(null);

  const profileId = selectedProfile || profiles[0]?.id || '';
  const { data: vitalsData, isLoading } = useVitals(profileId, { limit: 200 });
  const createVital = useCreateVital(profileId);
  const { register, handleSubmit, reset } = useForm<VitalFormData>({ defaultValues: { measured_at: toLocalDatetime() } });

  const filteredVitals = useMemo(() => {
    const items = vitalsData?.items || [];
    if (timeRange === 'all') return items;
    const days = { '7d': 7, '30d': 30, '90d': 90, '1y': 365 }[timeRange];
    const cutoff = new Date(Date.now() - days * 86400000);
    return items.filter((v) => new Date(v.measured_at) >= cutoff);
  }, [vitalsData, timeRange]);

  const chartData = useMemo(() =>
    filteredVitals.slice().sort((a, b) => new Date(a.measured_at).getTime() - new Date(b.measured_at).getTime()).map((v) => ({
      date: format(new Date(v.measured_at), 'dd.MM'),
      fullDate: format(new Date(v.measured_at), 'dd.MM.yyyy HH:mm'),
      blood_pressure_systolic: v.blood_pressure_systolic ?? null,
      blood_pressure_diastolic: v.blood_pressure_diastolic ?? null,
      pulse: v.pulse ?? null,
      weight: v.weight ?? null,
      body_temperature: v.body_temperature ?? null,
      oxygen_saturation: v.oxygen_saturation ?? null,
      blood_glucose: v.blood_glucose ?? null,
    })),
  [filteredVitals]);

  const metricsWithData = useMemo(() => {
    const has = new Set<string>();
    for (const row of chartData) for (const m of ALL_METRICS) if ((row as Record<string, unknown>)[m.key] != null) has.add(m.key);
    return has;
  }, [chartData]);

  const toggleMetric = (key: string) => setVisibleMetrics((prev) => { const n = new Set(prev); if (n.has(key)) n.delete(key); else n.add(key); return n; });

  const openModal = useCallback(() => { setSelectedVitals(new Set()); setModalStep(1); reset({ measured_at: toLocalDatetime() }); setShowModal(true); }, [reset]);
  const closeModal = useCallback(() => { setShowModal(false); setModalStep(1); setSelectedVitals(new Set()); reset(); }, [reset]);
  const toggleVitalChip = useCallback((id: VitalCategory) => { setSelectedVitals((prev) => { const n = new Set(prev); if (n.has(id)) n.delete(id); else n.add(id); return n; }); }, []);

  const onSubmit = async (data: VitalFormData) => {
    data.measured_at = new Date(data.measured_at).toISOString();
    // Filter out empty, undefined, null, and NaN values
    const cleaned = Object.fromEntries(
      Object.entries(data).filter(([, v]) => {
        if (v === '' || v === undefined || v === null) return false;
        if (typeof v === 'number' && isNaN(v)) return false;
        return true;
      })
    );
    try {
      await createVital.mutateAsync(cleaned);
      closeModal();
    } catch (err) {
      console.error('Failed to save vitals:', err);
    }
  };

  const CustomTooltip = ({ active, payload, label }: { active?: boolean; payload?: Array<{ name: string; value: number; color: string }>; label?: string }) => {
    if (!active || !payload?.length) return null;
    const row = chartData.find((r) => r.date === label);
    return (
      <div style={{ background: 'var(--color-surface)', border: '1px solid var(--color-border)', borderRadius: 10, padding: '10px 14px', fontSize: 13, boxShadow: '0 4px 12px rgba(0,0,0,0.1)' }}>
        <div style={{ fontWeight: 600, marginBottom: 6 }}>{row?.fullDate || label}</div>
        {payload.map((p, i) => { const m = ALL_METRICS.find((x) => x.key === p.name); return (
          <div key={i} style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '2px 0' }}>
            <span style={{ width: 8, height: 8, borderRadius: '50%', background: p.color, flexShrink: 0 }} />
            <span>{m?.label || p.name}: <strong>{p.value}</strong> {m?.unit}</span>
          </div>
        ); })}
      </div>
    );
  };

  return (
    <div className="page">
      <div className="page-header">
        <h2>{t('vitals.title')}</h2>
        <div className="page-actions">
          <ProfileSelector selectedId={profileId} onSelect={setSelectedProfile} />
          <button className="btn btn-add" onClick={openModal}>+ {t('vitals.add')}</button>
        </div>
      </div>

      {/* Modal — unchanged */}
      {showModal && (
        <div className="modal-overlay" onClick={closeModal}>
          <div className="modal" onClick={(e) => e.stopPropagation()}>
            <div className="modal-header">
              <h3>{modalStep === 1 ? t('vitals.select_vitals') : t('vitals.enter_measurements')}</h3>
              <button className="modal-close" onClick={closeModal}>&times;</button>
            </div>
            <div className="stepper">
              <div className="stepper-track">
                <div className={`stepper-step ${modalStep >= 1 ? 'active' : ''}`}><span className="stepper-dot">1</span><span className="stepper-label">{t('vitals.step_select')}</span></div>
                <div className="stepper-line"><div className={`stepper-line-fill ${modalStep >= 2 ? 'filled' : ''}`} /></div>
                <div className={`stepper-step ${modalStep >= 2 ? 'active' : ''}`}><span className="stepper-dot">2</span><span className="stepper-label">{t('vitals.step_measure')}</span></div>
              </div>
              <p className="stepper-text">{t('vitals.step_of', { current: modalStep, total: 2 })}</p>
            </div>
            <div className="modal-body">
              {modalStep === 1 && (
                <div className="vital-picker">
                  {VITAL_CHIPS.map((chip) => (
                    <button key={chip.id} type="button" className={`vital-chip ${selectedVitals.has(chip.id) ? 'active' : ''}`} onClick={() => toggleVitalChip(chip.id)}>
                      <span className="vital-chip-icon">{chip.icon}</span>
                      <span className="vital-chip-label">{t(`vitals.${chip.id}`) || chip.label}</span>
                    </button>
                  ))}
                </div>
              )}
              {modalStep === 2 && (
                <form id="vitals-modal-form" onSubmit={handleSubmit(onSubmit)} className="vital-form">
                  <div className="form-group"><label>{t('vitals.date_time')}</label><input type="datetime-local" {...register('measured_at')} /></div>
                  {selectedVitals.has('blood_pressure') && (<fieldset className="vital-fieldset"><legend>{t('vitals.blood_pressure')}</legend><div className="form-row"><div className="form-group"><label>{t('vitals.systolic')} (mmHg)</label><input type="number" placeholder="120" {...register('blood_pressure_systolic', { setValueAs: (v: string) => { if (!v || v === '') return undefined; return parseFloat(String(v).replace(',', '.')); } })} /></div><div className="form-group"><label>{t('vitals.diastolic')} (mmHg)</label><input type="number" placeholder="80" {...register('blood_pressure_diastolic', { setValueAs: (v: string) => { if (!v || v === '') return undefined; return parseFloat(String(v).replace(',', '.')); } })} /></div></div></fieldset>)}
                  {selectedVitals.has('pulse') && (<fieldset className="vital-fieldset"><legend>{t('vitals.pulse')}</legend><div className="form-row"><div className="form-group"><label>{t('vitals.pulse')} (bpm)</label><input type="number" placeholder="72" {...register('pulse', { setValueAs: (v: string) => { if (!v || v === '') return undefined; return parseFloat(String(v).replace(',', '.')); } })} /></div></div></fieldset>)}
                  {selectedVitals.has('weight') && (<fieldset className="vital-fieldset"><legend>{t('vitals.weight')}</legend><div className="form-row"><div className="form-group"><label>{t('vitals.weight')} (kg)</label><input type="text" inputMode="decimal" placeholder="70.0" {...register('weight', { setValueAs: (v: string) => { if (!v || v === '') return undefined; return parseFloat(String(v).replace(',', '.')); } })} /></div></div></fieldset>)}
                  {selectedVitals.has('temperature') && (<fieldset className="vital-fieldset"><legend>{t('vitals.temperature')}</legend><div className="form-row"><div className="form-group"><label>{t('vitals.temperature')} ({'\u00B0'}C)</label><input type="text" inputMode="decimal" placeholder="36.6" {...register('body_temperature', { setValueAs: (v: string) => { if (!v || v === '') return undefined; return parseFloat(String(v).replace(',', '.')); } })} /></div></div></fieldset>)}
                  {selectedVitals.has('oxygen') && (<fieldset className="vital-fieldset"><legend>{t('vitals.oxygen')}</legend><div className="form-row"><div className="form-group"><label>{t('vitals.oxygen')} (%)</label><input type="text" inputMode="decimal" placeholder="98" {...register('oxygen_saturation', { setValueAs: (v: string) => { if (!v || v === '') return undefined; return parseFloat(String(v).replace(',', '.')); } })} /></div></div></fieldset>)}
                  {selectedVitals.has('glucose') && (<fieldset className="vital-fieldset"><legend>{t('vitals.glucose')}</legend><div className="form-row"><div className="form-group"><label>{t('vitals.glucose')} (mmol/L)</label><input type="text" inputMode="decimal" placeholder="5.5" {...register('blood_glucose', { setValueAs: (v: string) => { if (!v || v === '') return undefined; return parseFloat(String(v).replace(',', '.')); } })} /></div></div></fieldset>)}
                  {selectedVitals.has('sleep') && (<fieldset className="vital-fieldset"><legend>{t('vitals.sleep')}</legend><div className="form-row"><div className="form-group"><label>{t('vitals.sleep_duration')}</label><input type="number" placeholder="480" {...register('sleep_duration_minutes', { setValueAs: (v: string) => { if (!v || v === '') return undefined; return parseFloat(String(v).replace(',', '.')); } })} /></div><div className="form-group"><label>{t('vitals.sleep_quality')}</label><input type="number" min="1" max="5" placeholder="4" {...register('sleep_quality', { setValueAs: (v: string) => { if (!v || v === '') return undefined; return parseFloat(String(v).replace(',', '.')); } })} /></div></div></fieldset>)}
                  <div className="form-group"><label>{t('vitals.notes')}</label><textarea rows={2} placeholder="..." {...register('notes')} /></div>
                </form>
              )}
            </div>
            <div className="modal-footer">
              {modalStep === 1 ? (
                <>
                  <button type="button" className="btn btn-secondary" onClick={(e) => { e.stopPropagation(); closeModal(); }}>{t('common.cancel')}</button>
                  <button type="button" className="btn btn-add" disabled={selectedVitals.size === 0} onClick={(e) => { e.stopPropagation(); e.preventDefault(); setModalStep(2); }}>{t('common.next')}</button>
                </>
              ) : (
                <>
                  <button type="button" className="btn btn-secondary" onClick={(e) => { e.stopPropagation(); setModalStep(1); }}>{t('common.back')}</button>
                  <button type="submit" form="vitals-modal-form" className="btn btn-add" disabled={createVital.isPending}>{createVital.isPending ? t('common.loading') : t('common.save')}</button>
                </>
              )}
            </div>
          </div>
        </div>
      )}

      {/* Toolbar: Tabs + Time Range + Export */}
      <div className="card" style={{ marginBottom: 16 }}>
        <div className="view-toolbar">
          <div className="view-tabs">
            <button className={`view-tab${viewTab === 'chart' ? ' active' : ''}`} onClick={() => setViewTab('chart')}>
              <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><polyline points="22 12 18 12 15 21 9 3 6 12 2 12"/></svg>
              {t('vitals.title')}
            </button>
            <button className={`view-tab${viewTab === 'table' ? ' active' : ''}`} onClick={() => setViewTab('table')}>
              <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><rect x="3" y="3" width="18" height="18" rx="2"/><line x1="3" y1="9" x2="21" y2="9"/><line x1="3" y1="15" x2="21" y2="15"/><line x1="9" y1="3" x2="9" y2="21"/></svg>
              {t('common.date')}
            </button>
          </div>
          <div className="view-toolbar-right">
            <div className="chart-filters">
              {(['7d', '30d', '90d', '1y', 'all'] as TimeRange[]).map((r) => (
                <button key={r} className={`chart-range-btn${timeRange === r ? ' active' : ''}`} onClick={() => setTimeRange(r)}>
                  {r === 'all' ? 'Alle' : r}
                </button>
              ))}
            </div>
            <button
              className="btn btn-secondary"
              onClick={() => viewTab === 'chart' ? exportChartPNG(chartRef) : exportExcel(filteredVitals as unknown as Array<Record<string, unknown>>, t)}
              title={viewTab === 'chart' ? 'Export PNG' : 'Export Excel'}
            >
              <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" style={{ marginRight: 6 }}><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" y1="15" x2="12" y2="3"/></svg>
              Export {viewTab === 'chart' ? 'PNG' : 'CSV'}
            </button>
          </div>
        </div>
      </div>

      {/* Chart View */}
      {viewTab === 'chart' && (
        <div className="card chart-card" ref={chartRef}>
          <div className="metric-toggles">
            {ALL_METRICS.filter((m) => metricsWithData.has(m.key)).map((m) => (
              <button key={m.key} className={`metric-toggle${visibleMetrics.has(m.key) ? ' active' : ''}`} onClick={() => toggleMetric(m.key)} style={{ '--metric-color': m.color } as React.CSSProperties}>
                <span className="metric-dot" style={{ background: visibleMetrics.has(m.key) ? m.color : 'var(--color-border)' }} />
                {m.label}
              </button>
            ))}
          </div>
          {chartData.length > 0 ? (
            <ResponsiveContainer width="100%" height={400}>
              <LineChart data={chartData} margin={{ top: 5, right: 20, bottom: 5, left: 0 }}>
                <CartesianGrid strokeDasharray="3 3" stroke="var(--color-border-subtle)" />
                <XAxis dataKey="date" fontSize={12} stroke="var(--color-text-secondary)" />
                <YAxis fontSize={12} stroke="var(--color-text-secondary)" />
                <Tooltip content={<CustomTooltip />} />
                <Legend onClick={(e) => toggleMetric(e.dataKey as string)} wrapperStyle={{ cursor: 'pointer', fontSize: 12 }} />
                {ALL_METRICS.map((m) => visibleMetrics.has(m.key) ? (
                  <Line key={m.key} type="monotone" dataKey={m.key} stroke={m.color} strokeWidth={2} dot={{ r: 3, fill: m.color }} activeDot={{ r: 5 }} name={m.label} connectNulls />
                ) : null)}
              </LineChart>
            </ResponsiveContainer>
          ) : (
            <div className="chart-empty">{isLoading ? t('common.loading') : t('common.no_data')}</div>
          )}
        </div>
      )}

      {/* Table View */}
      {viewTab === 'table' && (
        <div className="card">
          {isLoading ? (
            <p>{t('common.loading')}</p>
          ) : filteredVitals.length === 0 ? (
            <p className="text-muted">{t('common.no_data')}</p>
          ) : (
            <div className="table-scroll">
              <table className="data-table">
                <thead>
                  <tr>
                    <th>{t('common.date')}</th>
                    <th>{t('vitals.blood_pressure')}</th>
                    <th>{t('vitals.pulse')}</th>
                    <th>{t('vitals.weight')}</th>
                    <th>{t('vitals.temperature')}</th>
                    <th>SpO2</th>
                    <th>{t('vitals.glucose')}</th>
                  </tr>
                </thead>
                <tbody>
                  {filteredVitals.map((v) => (
                    <tr key={v.id}>
                      <td>{format(new Date(v.measured_at), 'dd.MM.yy HH:mm')}</td>
                      <td className={getBPClass(v.blood_pressure_systolic)}>{v.blood_pressure_systolic && v.blood_pressure_diastolic ? `${v.blood_pressure_systolic}/${v.blood_pressure_diastolic}` : '\u2014'}</td>
                      <td>{v.pulse ?? '\u2014'}</td>
                      <td>{v.weight != null ? `${v.weight} kg` : '\u2014'}</td>
                      <td className={getTempClass(v.body_temperature)}>{v.body_temperature != null ? `${v.body_temperature}\u00B0` : '\u2014'}</td>
                      <td className={getSpo2Class(v.oxygen_saturation)}>{v.oxygen_saturation != null ? `${v.oxygen_saturation}%` : '\u2014'}</td>
                      <td>{v.blood_glucose != null ? v.blood_glucose : '\u2014'}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </div>
      )}
    </div>
  );
}

function getBPClass(systolic?: number): string {
  if (!systolic) return '';
  if (systolic >= 160) return 'status-critical';
  if (systolic >= 140) return 'status-abnormal';
  if (systolic >= 130) return 'status-borderline';
  return 'status-normal';
}
function getTempClass(temp?: number): string {
  if (!temp) return '';
  if (temp >= 38.5) return 'status-abnormal';
  if (temp >= 37.5) return 'status-borderline';
  return 'status-normal';
}
function getSpo2Class(spo2?: number): string {
  if (!spo2) return '';
  if (spo2 < 90) return 'status-critical';
  if (spo2 < 95) return 'status-borderline';
  return 'status-normal';
}
