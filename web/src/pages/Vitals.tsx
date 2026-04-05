import { useState, useCallback, useMemo, useRef, useEffect } from 'react';
import { useFocusTrap } from '../hooks/useFocusTrap';
import { compareByColumn } from '../utils/sorting';
import { useTranslation } from 'react-i18next';
import { useForm } from 'react-hook-form';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { ProfileSelector } from '../components/ProfileSelector';
import { ConfirmDelete } from '../components/ConfirmDelete';
import { useVitals, useCreateVital, useDeleteVital, useUpdateVital } from '../hooks/useVitals';
import type { Vital } from '../api/vitals';
import { useProfiles } from '../hooks/useProfiles';
import { useDateFormat } from '../hooks/useDateLocale';
import { api } from '../api/client';
import { VitalsChart, CHART_TABS } from './vitals/VitalsChart';
import type { ChartDataRow } from './vitals/VitalsChart';
import { exportExcel, exportChartPNG } from './vitals/VitalsExport';

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

type ThresholdConfig = Record<string, { low?: number | null; high?: number | null }>;

const THRESHOLD_METRICS: { key: string; labelKey: string; unit: string }[] = [
  { key: 'blood_pressure_systolic', labelKey: 'vitals_data.systolic_bp', unit: 'mmHg' },
  { key: 'blood_pressure_diastolic', labelKey: 'vitals_data.diastolic_bp', unit: 'mmHg' },
  { key: 'pulse', labelKey: 'vitals_data.pulse', unit: 'bpm' },
  { key: 'body_temperature', labelKey: 'vitals_data.temperature', unit: '\u00B0C' },
  { key: 'oxygen_saturation', labelKey: 'vitals_data.spo2', unit: '%' },
  { key: 'blood_glucose', labelKey: 'vitals_data.blood_glucose', unit: 'mmol/L' },
  { key: 'weight', labelKey: 'vitals_data.weight', unit: 'kg' },
];

type TimeRange = '7d' | '30d' | '90d' | '1y' | 'all';
type ViewTab = 'chart' | 'table';

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
  const [editTarget, setEditTarget] = useState<Vital | null>(null);
  const [showThresholds, setShowThresholds] = useState(false);
  const [sortCol, setSortCol] = useState<string>('measured_at');
  const modalRef = useFocusTrap(showModal);
  const [sortDir, setSortDir] = useState<'asc' | 'desc'>('desc');
  const [thresholdForm, setThresholdForm] = useState<ThresholdConfig>({});
  const chartRef = useRef<HTMLDivElement>(null);
  const queryClient = useQueryClient();

  const { fmt } = useDateFormat();
  const profileId = selectedProfile || profiles[0]?.id || '';
  const { data: vitalsData, isLoading } = useVitals(profileId, { limit: 200 });
  const createVital = useCreateVital(profileId);
  const deleteVital = useDeleteVital(profileId);
  const updateVital = useUpdateVital(profileId);
  const { register, handleSubmit, reset } = useForm<VitalFormData>({ defaultValues: { measured_at: toLocalDatetime() } });

  const {
    register: editRegister,
    handleSubmit: editHandleSubmit,
    reset: editReset,
  } = useForm<VitalFormData>({
    values: editTarget ? {
      measured_at: editTarget.measured_at ? toLocalDatetime(new Date(editTarget.measured_at)) : toLocalDatetime(),
      blood_pressure_systolic: editTarget.blood_pressure_systolic,
      blood_pressure_diastolic: editTarget.blood_pressure_diastolic,
      pulse: editTarget.pulse,
      oxygen_saturation: editTarget.oxygen_saturation,
      weight: editTarget.weight,
      height: editTarget.height,
      body_temperature: editTarget.body_temperature,
      blood_glucose: editTarget.blood_glucose,
      sleep_duration_minutes: editTarget.sleep_duration_minutes,
      sleep_quality: editTarget.sleep_quality,
      notes: editTarget.notes ?? '',
    } : undefined,
  });

  const { data: thresholds } = useQuery({
    queryKey: ['vital-thresholds', profileId],
    queryFn: () => api.get<ThresholdConfig>(`/api/v1/profiles/${profileId}/vital-thresholds`),
    enabled: !!profileId && showThresholds,
  });

  const saveThresholds = useMutation({
    mutationFn: (data: ThresholdConfig) =>
      api.put(`/api/v1/profiles/${profileId}/vital-thresholds`, data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['vital-thresholds'] });
      setShowThresholds(false);
    },
  });

  // Initialize threshold form when data loads
  useEffect(() => {
    if (thresholds) {
      setThresholdForm(thresholds);
    }
  }, [thresholds]);

  const onEditSubmit = async (data: VitalFormData) => {
    if (!editTarget) return;
    data.measured_at = new Date(data.measured_at).toISOString();
    // Send cleared fields as explicit null so the backend clears them.
    // (The backend patches into the existing record — omitted keys would preserve the old value.)
    const payload: Record<string, unknown> = {};
    for (const [k, v] of Object.entries(data)) {
      if (v === '' || v === undefined || (typeof v === 'number' && isNaN(v))) {
        payload[k] = null;
      } else {
        payload[k] = v;
      }
    }
    // measured_at must never be null
    payload.measured_at = data.measured_at;
    try {
      await updateVital.mutateAsync({ ...payload, id: editTarget.id } as Partial<Vital> & { id: string });
      setEditTarget(null);
      editReset();
    } catch (err) {
      console.error('Failed to update vitals:', err);
    }
  };

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

  const chartData: ChartDataRow[] = useMemo(() =>
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
        tab.dataKeys.some((k) => (row as unknown as Record<string, unknown>)[k] != null)
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

  return (
    <div className="page">
      <div className="page-header">
        <h2>{t('vitals.title')}</h2>
        <div className="page-actions">
          <ProfileSelector selectedId={profileId} onSelect={setSelectedProfile} />
          <button className="btn btn-secondary" onClick={() => setShowThresholds(true)} title={t('vitals.thresholds')}>
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round"><circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 0 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-4 0v-.09a1.65 1.65 0 0 0-1.08-1.51 1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 0 1-2.83-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1 0-4h.09a1.65 1.65 0 0 0 1.51-1.08 1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 0 1 2.83-2.83l.06.06a1.65 1.65 0 0 0 1.82.33H9a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 0 1 2.83 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82V9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1.08z"/></svg>
          </button>
          <button className="btn btn-add" onClick={openModal}>+ {t('vitals.add')}</button>
        </div>
      </div>

      {/* Input Modal */}
      {showModal && (
        <div className="modal-overlay" onClick={closeModal}>
          <div className="modal" ref={modalRef} onClick={(e) => e.stopPropagation()}>
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
                  {selectedVitals.has('oxygen') && (<fieldset className="vital-fieldset"><legend>{t('vitals.oxygen')}</legend><div className="form-row"><div className="form-group"><label>{t('vitals.oxygen')} (%)</label><input type="text" inputMode="decimal" placeholder="98" {...register('oxygen_saturation', { setValueAs: (v: string) => { if (!v || v === '') return undefined; return Math.min(100, parseFloat(String(v).replace(',', '.'))); }, max: { value: 100, message: 'Max 100%' } })} /></div></div></fieldset>)}
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
              {t('vitals_data.chart_tab')}
            </button>
            <button className={`view-tab${viewTab === 'table' ? ' active' : ''}`} onClick={() => setViewTab('table')}>
              <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><rect x="3" y="3" width="18" height="18" rx="2"/><line x1="3" y1="9" x2="21" y2="9"/><line x1="3" y1="15" x2="21" y2="15"/><line x1="9" y1="3" x2="9" y2="21"/></svg>
              {t('vitals_data.table_tab')}
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
              title={viewTab === 'chart' ? t('vitals_data.export_png') : t('vitals_data.export_excel')}
            >
              <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" style={{ marginRight: 6 }}><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" y1="15" x2="12" y2="3"/></svg>
              {t('vitals_data.export')}
            </button>
          </div>
        </div>
      </div>

      {/* Chart View */}
      {viewTab === 'chart' && (
        <VitalsChart
          chartData={chartData}
          activeChartTab={activeChartTab}
          setActiveChartTab={setActiveChartTab}
          tabsWithData={tabsWithData}
          currentTab={currentTab}
          latestValues={latestValues}
          chartRef={chartRef}
          isLoading={isLoading}
        />
      )}

      {/* Table View */}
      {viewTab === 'table' && (
        <div className="card">
          {isLoading ? (
            <p>{t('common.loading')}</p>
          ) : filteredVitals.length === 0 ? (
            <p className="text-muted">{t('common.no_data')}</p>
          ) : (() => {
            // Group vitals by timestamp (rounded to minute)
            const grouped = new Map<string, typeof filteredVitals[0]>();
            for (const v of filteredVitals) {
              const key = v.measured_at.slice(0, 16); // YYYY-MM-DDTHH:MM
              const existing = grouped.get(key);
              if (existing) {
                // Merge: take non-null values from both
                if (v.blood_pressure_systolic != null) { (existing as unknown as Record<string, unknown>).blood_pressure_systolic = v.blood_pressure_systolic; (existing as unknown as Record<string, unknown>).blood_pressure_diastolic = v.blood_pressure_diastolic; }
                if (v.pulse != null) (existing as unknown as Record<string, unknown>).pulse = v.pulse;
                if (v.weight != null) (existing as unknown as Record<string, unknown>).weight = v.weight;
                if (v.body_temperature != null) (existing as unknown as Record<string, unknown>).body_temperature = v.body_temperature;
                if (v.oxygen_saturation != null) (existing as unknown as Record<string, unknown>).oxygen_saturation = v.oxygen_saturation;
                if (v.blood_glucose != null) (existing as unknown as Record<string, unknown>).blood_glucose = v.blood_glucose;
              } else {
                grouped.set(key, { ...v });
              }
            }
            const rows = Array.from(grouped.values());
            // Sort
            rows.sort((a, b) => compareByColumn(a, b, sortCol, sortDir));

            return (
            <div className="table-scroll">
              <table className="data-table">
                <thead>
                  <tr>
                    {[
                      { key: 'measured_at', label: t('common.date') },
                      { key: 'blood_pressure_systolic', label: t('vitals.blood_pressure') },
                      { key: 'pulse', label: t('vitals.pulse') },
                      { key: 'weight', label: t('vitals.weight') },
                      { key: 'body_temperature', label: t('vitals.temperature'), cls: 'hide-mobile' },
                      { key: 'oxygen_saturation', label: t('vitals_data.spo2'), cls: 'hide-mobile' },
                      { key: 'blood_glucose', label: t('vitals.glucose'), cls: 'hide-sm' },
                    ].map((col) => (
                      <th key={col.key} className={col.cls || ''} style={{ cursor: 'pointer', userSelect: 'none' }} onClick={() => { if (sortCol === col.key) setSortDir(sortDir === 'asc' ? 'desc' : 'asc'); else { setSortCol(col.key); setSortDir('desc'); } }}>
                        {col.label} {sortCol === col.key ? (sortDir === 'asc' ? '\u2191' : '\u2193') : ''}
                      </th>
                    ))}
                    <th></th>
                  </tr>
                </thead>
                <tbody>
                  {rows.map((v) => (
                    <tr key={v.id} style={{ cursor: 'pointer' }} onClick={() => setEditTarget(v as Vital)}>
                      <td>{fmt(v.measured_at, 'dd. MMM yy, HH:mm')}</td>
                      <td className={getBPClass(v.blood_pressure_systolic)}>{v.blood_pressure_systolic && v.blood_pressure_diastolic ? `${v.blood_pressure_systolic}/${v.blood_pressure_diastolic}` : '\u2014'}</td>
                      <td>{v.pulse ?? '\u2014'}</td>
                      <td>{v.weight != null ? `${v.weight} kg` : '\u2014'}</td>
                      <td className={`hide-mobile ${getTempClass(v.body_temperature)}`}>{v.body_temperature != null ? `${v.body_temperature}\u00B0` : '\u2014'}</td>
                      <td className={`hide-mobile ${getSpo2Class(v.oxygen_saturation)}`}>{v.oxygen_saturation != null ? `${v.oxygen_saturation}%` : '\u2014'}</td>
                      <td className="hide-sm">{v.blood_glucose != null ? v.blood_glucose : '\u2014'}</td>
                      <td>
                        <button
                          className="btn-icon-sm"
                          onClick={(e) => { e.stopPropagation(); setDeleteTarget(v.id); }}
                          title={t('common.delete')}
                        >&times;</button>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
            );
          })()}
        </div>
      )}

      {/* Edit Modal */}
      {editTarget && (
        <div className="modal-overlay" onClick={() => setEditTarget(null)}>
          <div className="modal" onClick={(e) => e.stopPropagation()}>
            <div className="modal-header">
              <h3>{t('vitals.edit')}</h3>
              <button className="modal-close" onClick={() => setEditTarget(null)}>&times;</button>
            </div>
            <div className="modal-body">
              <form id="vitals-edit-form" onSubmit={editHandleSubmit(onEditSubmit)} className="vital-form">
                <div className="form-group">
                  <label>{t('vitals.date_time')}</label>
                  <input type="datetime-local" {...editRegister('measured_at')} />
                </div>
                <fieldset className="vital-fieldset">
                  <legend>{t('vitals.blood_pressure')}</legend>
                  <div className="form-row">
                    <div className="form-group">
                      <label>{t('vitals.systolic')} (mmHg)</label>
                      <input type="number" placeholder="120" {...editRegister('blood_pressure_systolic', { setValueAs: (v: string) => { if (!v || v === '') return undefined; return parseFloat(String(v).replace(',', '.')); } })} />
                    </div>
                    <div className="form-group">
                      <label>{t('vitals.diastolic')} (mmHg)</label>
                      <input type="number" placeholder="80" {...editRegister('blood_pressure_diastolic', { setValueAs: (v: string) => { if (!v || v === '') return undefined; return parseFloat(String(v).replace(',', '.')); } })} />
                    </div>
                  </div>
                </fieldset>
                <div className="form-row">
                  <div className="form-group">
                    <label>{t('vitals.pulse')} (bpm)</label>
                    <input type="number" placeholder="72" {...editRegister('pulse', { setValueAs: (v: string) => { if (!v || v === '') return undefined; return parseFloat(String(v).replace(',', '.')); } })} />
                  </div>
                  <div className="form-group">
                    <label>{t('vitals.weight')} (kg)</label>
                    <input type="text" inputMode="decimal" placeholder="70.0" {...editRegister('weight', { setValueAs: (v: string) => { if (!v || v === '') return undefined; return parseFloat(String(v).replace(',', '.')); } })} />
                  </div>
                </div>
                <div className="form-row">
                  <div className="form-group">
                    <label>{t('vitals.temperature')} ({'\u00B0'}C)</label>
                    <input type="text" inputMode="decimal" placeholder="36.6" {...editRegister('body_temperature', { setValueAs: (v: string) => { if (!v || v === '') return undefined; return parseFloat(String(v).replace(',', '.')); } })} />
                  </div>
                  <div className="form-group">
                    <label>{t('vitals.oxygen')} (%)</label>
                    <input type="text" inputMode="decimal" placeholder="98" {...editRegister('oxygen_saturation', { setValueAs: (v: string) => { if (!v || v === '') return undefined; return Math.min(100, parseFloat(String(v).replace(',', '.'))); }, max: { value: 100, message: 'Max 100%' } })} />
                  </div>
                </div>
                <div className="form-group">
                  <label>{t('vitals.glucose')} (mmol/L)</label>
                  <input type="text" inputMode="decimal" placeholder="5.5" {...editRegister('blood_glucose', { setValueAs: (v: string) => { if (!v || v === '') return undefined; return parseFloat(String(v).replace(',', '.')); } })} />
                </div>
                <div className="form-group">
                  <label>{t('vitals.notes')}</label>
                  <textarea rows={2} placeholder="..." {...editRegister('notes')} />
                </div>
              </form>
            </div>
            <div className="modal-footer">
              <button type="button" className="btn btn-secondary" onClick={() => setEditTarget(null)}>{t('common.cancel')}</button>
              <button type="submit" form="vitals-edit-form" className="btn btn-add" disabled={updateVital.isPending}>
                {updateVital.isPending ? t('common.loading') : t('common.save')}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Threshold Configuration Modal */}
      {showThresholds && (
        <div className="modal-overlay" onClick={() => setShowThresholds(false)}>
          <div className="modal" onClick={(e) => e.stopPropagation()}>
            <div className="modal-header">
              <h3>{t('vitals.thresholds')}</h3>
              <button className="modal-close" onClick={() => setShowThresholds(false)}>&times;</button>
            </div>
            <div className="modal-body">
              <p className="text-muted" style={{ marginBottom: 16, fontSize: 13 }}>{t('vitals.threshold_hint')}</p>
              <div className="table-scroll">
                <table className="data-table">
                  <thead>
                    <tr>
                      <th>{t('vitals.title')}</th>
                      <th>{t('vitals.threshold_low')}</th>
                      <th>{t('vitals.threshold_high')}</th>
                    </tr>
                  </thead>
                  <tbody>
                    {THRESHOLD_METRICS.map((metric) => (
                      <tr key={metric.key}>
                        <td>{t(metric.labelKey)} <span className="text-muted">({metric.unit})</span></td>
                        <td>
                          <input
                            type="number"
                            step="any"
                            placeholder="-"
                            value={thresholdForm[metric.key]?.low ?? ''}
                            onChange={(e) => {
                              const val = e.target.value === '' ? null : parseFloat(e.target.value);
                              setThresholdForm((prev) => ({
                                ...prev,
                                [metric.key]: { ...prev[metric.key], low: val },
                              }));
                            }}
                            style={{ width: 80 }}
                          />
                        </td>
                        <td>
                          <input
                            type="number"
                            step="any"
                            placeholder="-"
                            value={thresholdForm[metric.key]?.high ?? ''}
                            onChange={(e) => {
                              const val = e.target.value === '' ? null : parseFloat(e.target.value);
                              setThresholdForm((prev) => ({
                                ...prev,
                                [metric.key]: { ...prev[metric.key], high: val },
                              }));
                            }}
                            style={{ width: 80 }}
                          />
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </div>
            <div className="modal-footer">
              <button type="button" className="btn btn-secondary" onClick={() => setShowThresholds(false)}>{t('common.cancel')}</button>
              <button
                type="button"
                className="btn btn-add"
                disabled={saveThresholds.isPending}
                onClick={() => saveThresholds.mutate(thresholdForm)}
              >
                {saveThresholds.isPending ? t('common.loading') : t('common.save')}
              </button>
            </div>
          </div>
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
