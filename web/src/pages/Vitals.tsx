import { useState, useCallback, useMemo, useRef } from 'react';
import { useTranslation } from 'react-i18next';
import { useForm } from 'react-hook-form';
import {
  LineChart, Line, XAxis, YAxis, CartesianGrid, Tooltip,
  ResponsiveContainer, ReferenceLine,
} from 'recharts';
import { format } from 'date-fns';
import * as XLSX from 'xlsx';
import { ProfileSelector } from '../components/ProfileSelector';
import { ConfirmDelete } from '../components/ConfirmDelete';
import { useVitals, useCreateVital, useDeleteVital } from '../hooks/useVitals';
import { useProfiles } from '../hooks/useProfiles';
import { useDateFormat } from '../hooks/useDateLocale';

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

interface MetricLine { key: string; label: string; unit: string; color: string }

interface ChartTabDef {
  id: string;
  labelKey: string;
  dataKeys: string[];
  lines: MetricLine[];
  unit: string;
  refLines?: { value: number; label: string; color: string }[];
}

const CHART_TABS: ChartTabDef[] = [
  {
    id: 'blood_pressure',
    labelKey: 'vitals.blood_pressure',
    dataKeys: ['blood_pressure_systolic', 'blood_pressure_diastolic'],
    lines: [
      { key: 'blood_pressure_systolic', label: 'Systolic', unit: 'mmHg', color: '#FF3B30' },
      { key: 'blood_pressure_diastolic', label: 'Diastolic', unit: 'mmHg', color: '#FF9500' },
    ],
    unit: 'mmHg',
    refLines: [
      { value: 120, label: 'Optimal sys.', color: '#34C759' },
      { value: 80, label: 'Optimal dia.', color: '#34C759' },
    ],
  },
  {
    id: 'pulse',
    labelKey: 'vitals.pulse',
    dataKeys: ['pulse'],
    lines: [{ key: 'pulse', label: 'Pulse', unit: 'bpm', color: '#34C759' }],
    unit: 'bpm',
    refLines: [
      { value: 60, label: 'Low normal', color: '#FF9500' },
      { value: 100, label: 'High normal', color: '#FF9500' },
    ],
  },
  {
    id: 'weight',
    labelKey: 'vitals.weight',
    dataKeys: ['weight'],
    lines: [{ key: 'weight', label: 'Weight', unit: 'kg', color: '#AF52DE' }],
    unit: 'kg',
  },
  {
    id: 'temperature',
    labelKey: 'vitals.temperature',
    dataKeys: ['body_temperature'],
    lines: [{ key: 'body_temperature', label: 'Temperature', unit: '\u00B0C', color: '#FF2D55' }],
    unit: '\u00B0C',
    refLines: [
      { value: 37.5, label: 'Fever', color: '#FF9500' },
    ],
  },
  {
    id: 'oxygen',
    labelKey: 'vitals.oxygen',
    dataKeys: ['oxygen_saturation'],
    lines: [{ key: 'oxygen_saturation', label: 'SpO2', unit: '%', color: '#007AFF' }],
    unit: '%',
    refLines: [
      { value: 95, label: 'Normal', color: '#34C759' },
    ],
  },
  {
    id: 'glucose',
    labelKey: 'vitals.glucose',
    dataKeys: ['blood_glucose'],
    lines: [{ key: 'blood_glucose', label: 'Glucose', unit: 'mmol/L', color: '#FF9500' }],
    unit: 'mmol/L',
  },
];

type TimeRange = '7d' | '30d' | '90d' | '1y' | 'all';
type ViewTab = 'chart' | 'table';

function exportExcel(vitals: Array<Record<string, unknown>>, t: (key: string) => string) {
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
  ws['!cols'] = headers.map((h) => ({ wch: Math.max(h.length + 2, 14) }));
  const wb = XLSX.utils.book_new();
  XLSX.utils.book_append_sheet(wb, ws, t('vitals.title'));
  XLSX.writeFile(wb, `${t('vitals.title')}_${format(new Date(), 'yyyy-MM-dd')}.xlsx`);
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
  const [activeChartTab, setActiveChartTab] = useState<string>('blood_pressure');
  const [deleteTarget, setDeleteTarget] = useState<string | null>(null);
  const chartRef = useRef<HTMLDivElement>(null);

  const { fmt } = useDateFormat();
  const profileId = selectedProfile || profiles[0]?.id || '';
  const { data: vitalsData, isLoading } = useVitals(profileId, { limit: 200 });
  const createVital = useCreateVital(profileId);
  const deleteVital = useDeleteVital(profileId);
  const { register, handleSubmit, reset } = useForm<VitalFormData>({ defaultValues: { measured_at: toLocalDatetime() } });

  const filteredVitals = useMemo(() => {
    const items = vitalsData?.items || [];
    if (timeRange === 'all') return items;
    const days = { '7d': 7, '30d': 30, '90d': 90, '1y': 365 }[timeRange];
    const cutoff = new Date(Date.now() - days * 86400000);
    return items.filter((v) => new Date(v.measured_at) >= cutoff);
  }, [vitalsData, timeRange]);

  const sortedVitals = useMemo(() =>
    filteredVitals.slice().sort((a, b) => new Date(a.measured_at).getTime() - new Date(b.measured_at).getTime()),
  [filteredVitals]);

  const chartData = useMemo(() =>
    sortedVitals.map((v) => ({
      date: fmt(v.measured_at, 'dd. MMM'),
      fullDate: fmt(v.measured_at, 'dd. MMM yyyy, HH:mm'),
      blood_pressure_systolic: v.blood_pressure_systolic ?? null,
      blood_pressure_diastolic: v.blood_pressure_diastolic ?? null,
      pulse: v.pulse ?? null,
      weight: v.weight ?? null,
      body_temperature: v.body_temperature ?? null,
      oxygen_saturation: v.oxygen_saturation ?? null,
      blood_glucose: v.blood_glucose ?? null,
    })),
  [sortedVitals]);

  // Determine which chart tabs have data
  const tabsWithData = useMemo(() => {
    const available: string[] = [];
    for (const tab of CHART_TABS) {
      const hasData = chartData.some((row) =>
        tab.dataKeys.some((k) => (row as Record<string, unknown>)[k] != null)
      );
      if (hasData) available.push(tab.id);
    }
    return available;
  }, [chartData]);

  // Auto-select first available tab if current has no data
  useMemo(() => {
    if (tabsWithData.length > 0 && !tabsWithData.includes(activeChartTab)) {
      setActiveChartTab(tabsWithData[0]);
    }
  }, [tabsWithData, activeChartTab]);

  const currentTab = CHART_TABS.find((t) => t.id === activeChartTab);

  const openModal = useCallback(() => { setSelectedVitals(new Set()); setModalStep(1); reset({ measured_at: toLocalDatetime() }); setShowModal(true); }, [reset]);
  const closeModal = useCallback(() => { setShowModal(false); setModalStep(1); setSelectedVitals(new Set()); reset(); }, [reset]);
  const toggleVitalChip = useCallback((id: VitalCategory) => { setSelectedVitals((prev) => { const n = new Set(prev); if (n.has(id)) n.delete(id); else n.add(id); return n; }); }, []);

  const onSubmit = async (data: VitalFormData) => {
    data.measured_at = new Date(data.measured_at).toISOString();
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

  const SingleChartTooltip = ({ active, payload, label }: { active?: boolean; payload?: Array<{ name: string; value: number; color: string }>; label?: string }) => {
    if (!active || !payload?.length) return null;
    const row = chartData.find((r) => r.date === label);
    return (
      <div style={{ background: 'var(--color-surface)', border: '1px solid var(--color-border)', borderRadius: 10, padding: '10px 14px', fontSize: 13, boxShadow: '0 4px 12px rgba(0,0,0,0.1)' }}>
        <div style={{ fontWeight: 600, marginBottom: 6 }}>{row?.fullDate || label}</div>
        {payload.map((p, i) => {
          const line = currentTab?.lines.find((l) => l.key === p.name);
          return (
            <div key={i} style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '2px 0' }}>
              <span style={{ width: 8, height: 8, borderRadius: '50%', background: p.color, flexShrink: 0 }} />
              <span>{line?.label || p.name}: <strong>{p.value}</strong> {line?.unit}</span>
            </div>
          );
        })}
      </div>
    );
  };

  // Compute latest values for the active tab
  const latestValues = useMemo(() => {
    if (!currentTab) return null;
    for (let i = sortedVitals.length - 1; i >= 0; i--) {
      const v = sortedVitals[i] as unknown as Record<string, unknown>;
      const vals = currentTab.lines
        .map((l) => ({ ...l, value: v[l.key] as number | undefined }))
        .filter((x) => x.value != null);
      if (vals.length > 0) {
        return { values: vals, date: fmt(v.measured_at as string, 'dd. MMM yyyy, HH:mm') };
      }
    }
    return null;
  }, [currentTab, sortedVitals]);

  return (
    <div className="page">
      <div className="page-header">
        <h2>{t('vitals.title')}</h2>
        <div className="page-actions">
          <ProfileSelector selectedId={profileId} onSelect={setSelectedProfile} />
          <button className="btn btn-add" onClick={openModal}>+ {t('vitals.add')}</button>
        </div>
      </div>

      {/* Input Modal */}
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

      {/* Top-level Toolbar: Chart vs Table + Time Range + Export */}
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
                  {r === 'all' ? t('common.all') : r}
                </button>
              ))}
            </div>
            <button
              className="btn btn-secondary"
              onClick={() => viewTab === 'chart' ? exportChartPNG(chartRef) : exportExcel(filteredVitals as unknown as Array<Record<string, unknown>>, t)}
              title={viewTab === 'chart' ? 'Export PNG' : 'Export Excel'}
            >
              <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" style={{ marginRight: 6 }}><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" y1="15" x2="12" y2="3"/></svg>
              Export
            </button>
          </div>
        </div>
      </div>

      {/* Chart View — with sub-tabs per vital type */}
      {viewTab === 'chart' && (
        <>
          {tabsWithData.length === 0 ? (
            <div className="card">
              <div className="chart-empty">{isLoading ? t('common.loading') : t('common.no_data')}</div>
            </div>
          ) : (
            <>
              {/* Metric sub-tabs */}
              <div className="vital-chart-tabs">
                {CHART_TABS.filter((tab) => tabsWithData.includes(tab.id)).map((tab) => (
                  <button
                    key={tab.id}
                    className={`vital-chart-tab${activeChartTab === tab.id ? ' active' : ''}`}
                    onClick={() => setActiveChartTab(tab.id)}
                  >
                    {t(tab.labelKey)}
                  </button>
                ))}
              </div>

              {/* Active chart */}
              {currentTab && (
                <div className="card chart-card" ref={chartRef}>
                  {/* Latest value summary */}
                  {latestValues && (
                    <div className="vital-latest">
                      {latestValues.values.map((v) => (
                        <div key={v.key} className="vital-latest-item">
                          <span className="vital-latest-value" style={{ color: v.color }}>
                            {v.value}
                          </span>
                          <span className="vital-latest-unit">{v.unit}</span>
                          <span className="vital-latest-label">{v.label}</span>
                        </div>
                      ))}
                      <span className="vital-latest-date">{latestValues.date}</span>
                    </div>
                  )}

                  <ResponsiveContainer width="100%" height={320}>
                    <LineChart data={chartData} margin={{ top: 10, right: 20, bottom: 5, left: 0 }}>
                      <CartesianGrid strokeDasharray="3 3" stroke="var(--color-border-subtle)" />
                      <XAxis dataKey="date" fontSize={12} stroke="var(--color-text-secondary)" />
                      <YAxis
                        fontSize={12}
                        stroke="var(--color-text-secondary)"
                        unit={` ${currentTab.unit}`}
                        domain={['auto', 'auto']}
                        width={70}
                      />
                      <Tooltip content={<SingleChartTooltip />} />
                      {currentTab.refLines?.map((ref) => (
                        <ReferenceLine
                          key={ref.label}
                          y={ref.value}
                          stroke={ref.color}
                          strokeDasharray="6 4"
                          strokeOpacity={0.5}
                          label={{ value: ref.label, position: 'insideTopRight', fontSize: 11, fill: ref.color }}
                        />
                      ))}
                      {currentTab.lines.map((line) => (
                        <Line
                          key={line.key}
                          type="monotone"
                          dataKey={line.key}
                          stroke={line.color}
                          strokeWidth={2.5}
                          dot={{ r: 4, fill: line.color, strokeWidth: 2, stroke: 'var(--color-surface)' }}
                          activeDot={{ r: 6 }}
                          name={line.label}
                          connectNulls
                        />
                      ))}
                    </LineChart>
                  </ResponsiveContainer>
                </div>
              )}
            </>
          )}
        </>
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
                    <th></th>
                  </tr>
                </thead>
                <tbody>
                  {filteredVitals.map((v) => (
                    <tr key={v.id}>
                      <td>{fmt(v.measured_at, 'dd. MMM yy, HH:mm')}</td>
                      <td className={getBPClass(v.blood_pressure_systolic)}>{v.blood_pressure_systolic && v.blood_pressure_diastolic ? `${v.blood_pressure_systolic}/${v.blood_pressure_diastolic}` : '\u2014'}</td>
                      <td>{v.pulse ?? '\u2014'}</td>
                      <td>{v.weight != null ? `${v.weight} kg` : '\u2014'}</td>
                      <td className={getTempClass(v.body_temperature)}>{v.body_temperature != null ? `${v.body_temperature}\u00B0` : '\u2014'}</td>
                      <td className={getSpo2Class(v.oxygen_saturation)}>{v.oxygen_saturation != null ? `${v.oxygen_saturation}%` : '\u2014'}</td>
                      <td>{v.blood_glucose != null ? v.blood_glucose : '\u2014'}</td>
                      <td>
                        <button
                          className="btn-icon-sm"
                          onClick={() => setDeleteTarget(v.id)}
                          title={t('common.delete')}
                        >×</button>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </div>
      )}

      <ConfirmDelete
        open={!!deleteTarget}
        onConfirm={() => { deleteVital.mutate(deleteTarget!); setDeleteTarget(null); }}
        onCancel={() => setDeleteTarget(null)}
        pending={deleteVital.isPending}
      />
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
