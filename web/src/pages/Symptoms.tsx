import { useState, useMemo } from 'react';
import { useTranslation } from 'react-i18next';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { useForm } from 'react-hook-form';
import {
  LineChart, Line, XAxis, YAxis, CartesianGrid, Tooltip,
  ResponsiveContainer, Legend,
} from 'recharts';
import { format } from 'date-fns';
import { ProfileSelector } from '../components/ProfileSelector';
import { useDateFormat } from '../hooks/useDateLocale';
import { ConfirmDelete } from '../components/ConfirmDelete';
import { useProfiles } from '../hooks/useProfiles';
import { api } from '../api/client';
import { symptomsApi, type SymptomRecord } from '../api/symptoms';

interface ChartDataPoint {
  date: string;
  [symptomType: string]: string | number;
}

type ViewTab = 'list' | 'chart';

const SYMPTOM_COLORS: Record<string, string> = {
  pain: '#ef4444',
  headache: '#f97316',
  nausea: '#eab308',
  fatigue: '#84cc16',
  dizziness: '#22c55e',
  shortness_of_breath: '#14b8a6',
  anxiety: '#06b6d4',
  mood: '#3b82f6',
  sleep_quality: '#8b5cf6',
  appetite: '#d946ef',
  custom: '#6b7280',
};

const SYMPTOM_TYPES = [
  'pain', 'headache', 'nausea', 'fatigue', 'dizziness',
  'shortness_of_breath', 'anxiety', 'mood', 'sleep_quality', 'appetite', 'custom',
];
const BODY_REGIONS = ['head', 'neck', 'chest', 'abdomen', 'back', 'left_arm', 'right_arm', 'left_leg', 'right_leg', 'general'];

function intensityColor(i: number): string {
  if (i >= 8) return 'status-critical';
  if (i >= 6) return 'status-abnormal';
  if (i >= 4) return 'status-borderline';
  return 'status-normal';
}

export function Symptoms() {
  const { t } = useTranslation();
  const { fmt } = useDateFormat();
  const { data: profilesData } = useProfiles();
  const profiles = profilesData || [];
  const [selectedProfile, setSelectedProfile] = useState('');
  const [viewTab, setViewTab] = useState<ViewTab>('list');
  const [sortDir, setSortDir] = useState<'asc' | 'desc'>('desc');
  const [showForm, setShowForm] = useState(false);
  const [deleteTarget, setDeleteTarget] = useState<string | null>(null);
  const [editTarget, setEditTarget] = useState<SymptomRecord | null>(null);
  const queryClient = useQueryClient();
  const profileId = selectedProfile || profiles[0]?.id || '';

  const { data, isLoading } = useQuery({
    queryKey: ['symptoms', profileId],
    queryFn: () => symptomsApi.list(profileId),
    enabled: !!profileId,
  });

  const { data: chartRaw } = useQuery({
    queryKey: ['symptoms-chart', profileId],
    queryFn: () => api.get<{ points: Array<{ date: string; symptom_type: string; intensity: number }> }>(`/api/v1/profiles/${profileId}/symptoms/chart`),
    enabled: !!profileId && viewTab === 'chart',
  });

  // Transform chart data: group by date, one key per symptom type
  const chartData: ChartDataPoint[] = (() => {
    if (!chartRaw?.points) return [];
    const byDate = new Map<string, ChartDataPoint>();
    for (const pt of chartRaw.points) {
      const dateKey = format(new Date(pt.date), 'dd.MM');
      if (!byDate.has(dateKey)) byDate.set(dateKey, { date: dateKey });
      byDate.get(dateKey)![pt.symptom_type] = pt.intensity;
    }
    return Array.from(byDate.values());
  })();

  const chartSymptomTypes = (() => {
    if (!chartRaw?.points) return [];
    return [...new Set(chartRaw.points.map((p) => p.symptom_type))];
  })();

  const createMutation = useMutation({
    mutationFn: (s: Partial<SymptomRecord>) => symptomsApi.create(profileId, s as Parameters<typeof symptomsApi.create>[1]),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['symptoms', profileId] });
      queryClient.invalidateQueries({ queryKey: ['symptoms-chart', profileId] });
      setShowForm(false);
      reset();
    },
  });

  const updateMutation = useMutation({
    mutationFn: ({ id, ...data }: Partial<SymptomRecord> & { id: string }) =>
      symptomsApi.update(profileId, id, data as Parameters<typeof symptomsApi.update>[2]),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['symptoms', profileId] });
      queryClient.invalidateQueries({ queryKey: ['symptoms-chart', profileId] });
      setEditTarget(null);
    },
  });

  const deleteMutation = useMutation({
    mutationFn: (id: string) => symptomsApi.delete(profileId, id),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['symptoms', profileId] });
      queryClient.invalidateQueries({ queryKey: ['symptoms-chart', profileId] });
    },
  });

  const { register, handleSubmit, reset, watch } = useForm<{
    symptom_type: string;
    intensity: number;
    body_region: string;
    trigger_factors: string;
    notes: string;
  }>();

  const editForm = useForm<{
    symptom_type: string;
    intensity: number;
    body_region: string;
    trigger_factors: string;
    notes: string;
  }>({ values: editTarget ? {
    symptom_type: editTarget.entries?.[0]?.symptom_type || '',
    intensity: editTarget.entries?.[0]?.intensity || 0,
    body_region: editTarget.entries?.[0]?.body_region || '',
    trigger_factors: editTarget.trigger_factors?.join(', ') || '',
    notes: editTarget.notes || '',
  } : undefined });

  const items = data?.items || [];

  const sortedItems = useMemo(() => {
    return [...items].sort((a, b) => {
      const cmp = a.recorded_at.localeCompare(b.recorded_at);
      return sortDir === 'asc' ? cmp : -cmp;
    });
  }, [items, sortDir]);

  return (
    <div className="page">
      <div className="page-header">
        <h2>{t('nav.symptoms')}</h2>
        <div className="page-actions">
          <ProfileSelector selectedId={profileId} onSelect={setSelectedProfile} />
          <button className="btn btn-add" onClick={() => setShowForm(!showForm)}>{t('symptoms.quick_entry')}</button>
        </div>
      </div>

      {showForm && (
        <div className="modal-overlay" onClick={() => setShowForm(false)}>
          <div className="modal" onClick={(e) => e.stopPropagation()}>
            <div className="modal-header">
              <h3>{t('symptoms.add')}</h3>
              <button className="btn-icon-sm" onClick={() => setShowForm(false)} aria-label={t('common.close')}>&times;</button>
            </div>
            <div className="modal-body">
              <form id="symptom-create-form" onSubmit={handleSubmit((data) => {
                createMutation.mutate({
                  recorded_at: new Date().toISOString(),
                  entries: [{
                    symptom_type: data.symptom_type,
                    intensity: Number(data.intensity),
                    body_region: data.body_region || undefined,
                  }],
                  trigger_factors: data.trigger_factors ? data.trigger_factors.split(',').map((s) => s.trim()) : undefined,
                  notes: data.notes || undefined,
                });
              })}>
                <div className="form-row">
                  <div className="form-group"><label>{t('symptoms.symptom')} *</label>
                    <select {...register('symptom_type')} required>
                      {SYMPTOM_TYPES.map((s) => <option key={s} value={s}>{t('symptoms.type_' + s)}</option>)}
                    </select>
                  </div>
                  <div className="form-group">
                    <label>{t('symptoms.intensity')}: {watch('intensity') || 0}</label>
                    <input type="range" min="0" max="10" {...register('intensity')} style={{ width: '100%' }} />
                  </div>
                  <div className="form-group"><label>{t('symptoms.body_region')}</label>
                    <select {...register('body_region')}>
                      <option value="">{t('common.not_specified')}</option>
                      {BODY_REGIONS.map((r) => <option key={r} value={r}>{t('symptoms.region_' + r)}</option>)}
                    </select>
                  </div>
                </div>
                <div className="form-group"><label>{t('symptoms.trigger_factors')} ({t('symptoms.trigger_hint')})</label>
                  <input type="text" {...register('trigger_factors')} placeholder={t('symptoms_data.trigger_placeholder')} />
                </div>
                <div className="form-group"><label>{t('common.notes')}</label><textarea rows={2} {...register('notes')} /></div>
              </form>
            </div>
            <div className="modal-footer">
              <button type="submit" form="symptom-create-form" className="btn btn-add" disabled={createMutation.isPending}>{t('common.save')}</button>
              <button type="button" className="btn btn-secondary" onClick={() => setShowForm(false)}>{t('common.cancel')}</button>
            </div>
          </div>
        </div>
      )}

      {/* View Tabs */}
      <div className="card" style={{ marginBottom: 16 }}>
        <div className="view-toolbar">
          <div className="view-tabs">
            <button className={`view-tab${viewTab === 'list' ? ' active' : ''}`} onClick={() => setViewTab('list')}>
              <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><rect x="3" y="3" width="18" height="18" rx="2"/><line x1="3" y1="9" x2="21" y2="9"/><line x1="3" y1="15" x2="21" y2="15"/><line x1="9" y1="3" x2="9" y2="21"/></svg>
              {t('symptoms.list_view')}
            </button>
            <button className={`view-tab${viewTab === 'chart' ? ' active' : ''}`} onClick={() => setViewTab('chart')}>
              <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><polyline points="22 12 18 12 15 21 9 3 6 12 2 12"/></svg>
              {t('symptoms.chart_view')}
            </button>
          </div>
        </div>
      </div>

      {/* Chart View */}
      {viewTab === 'chart' && (
        <div className="card chart-card">
          <h3 style={{ marginBottom: 16 }}>{t('symptoms.intensity_over_time')}</h3>
          {chartData.length === 0 ? (
            <div className="chart-empty">{t('common.no_data')}</div>
          ) : (
            <ResponsiveContainer width="100%" height={320}>
              <LineChart data={chartData} margin={{ top: 10, right: 20, bottom: 5, left: 0 }}>
                <CartesianGrid strokeDasharray="3 3" stroke="var(--color-border-subtle)" />
                <XAxis dataKey="date" fontSize={12} stroke="var(--color-text-secondary)" />
                <YAxis fontSize={12} stroke="var(--color-text-secondary)" domain={[0, 10]} width={40} />
                <Tooltip />
                <Legend />
                {chartSymptomTypes.map((type) => (
                  <Line
                    key={type}
                    type="monotone"
                    dataKey={type}
                    stroke={SYMPTOM_COLORS[type] || '#6b7280'}
                    strokeWidth={2.5}
                    dot={{ r: 4, fill: SYMPTOM_COLORS[type] || '#6b7280', strokeWidth: 2, stroke: 'var(--color-surface)' }}
                    activeDot={{ r: 6 }}
                    name={t('symptoms.type_' + type)}
                    connectNulls
                  />
                ))}
              </LineChart>
            </ResponsiveContainer>
          )}
        </div>
      )}

      {/* List View */}
      {viewTab === 'list' && (
      <div className="card">
        {isLoading ? <p>{t('common.loading')}</p> : items.length === 0 ? <p className="text-muted">{t('common.no_data')}</p> : (
          <>
          <div style={{ display: 'flex', gap: 8, marginBottom: 12, alignItems: 'center' }}>
            <span className="text-muted" style={{ fontSize: 12 }}>{t('common.sort')}:</span>
            <select className="metric-selector" value="recorded_at" disabled>
              <option value="recorded_at">{t('common.date')}</option>
            </select>
            <button className="btn-icon-sm" onClick={() => setSortDir(d => d === 'asc' ? 'desc' : 'asc')} aria-label={t('common.sort')}>
              {sortDir === 'asc' ? '↑' : '↓'}
            </button>
          </div>
          <div className="timeline">
            {sortedItems.map((record) => (
              <div key={record.id} className="timeline-item" onClick={() => setEditTarget(record)} style={{ cursor: 'pointer' }}>
                <div className="timeline-icon">📊</div>
                <div className="timeline-content" style={{ position: 'relative' }}>
                  <button
                    className="btn-icon-sm"
                    style={{ position: 'absolute', top: 0, right: 0 }}
                    onClick={(e) => { e.stopPropagation(); setDeleteTarget(record.id ?? null); }}
                    title={t('common.delete')}
                    aria-label={t('common.delete')}
                  >×</button>
                  <div className="timeline-date">{fmt(record.recorded_at, 'dd. MMM yyyy, HH:mm')}</div>
                  <div className="symptom-entries">
                    {record.entries?.map((e, i) => (
                      <div key={i} className="symptom-entry">
                        <span className="med-name">{t('symptoms.type_' + e.symptom_type)}</span>
                        <span className={`badge ${intensityColor(e.intensity)}`}>{e.intensity}/10</span>
                        {e.body_region && <span className="badge badge-info">{t('symptoms.region_' + e.body_region)}</span>}
                      </div>
                    ))}
                  </div>
                  {record.trigger_factors && record.trigger_factors.length > 0 && (
                    <div className="doc-tags" style={{ marginTop: 6 }}>
                      {record.trigger_factors.map((tf) => <span key={tf} className="tag">{tf}</span>)}
                    </div>
                  )}
                  {record.notes && <p className="timeline-desc">{record.notes}</p>}
                </div>
              </div>
            ))}
          </div>
          </>
        )}
      </div>
      )}

      {editTarget && (
        <div className="modal-overlay" onClick={() => setEditTarget(null)}>
          <div className="modal" onClick={(e) => e.stopPropagation()}>
            <div className="modal-header">
              <h3>{t('symptoms.edit')}</h3>
              <button className="modal-close" onClick={() => setEditTarget(null)} aria-label={t('common.close')}>&times;</button>
            </div>
            <div className="modal-body">
              <form id="symptom-edit-form" onSubmit={editForm.handleSubmit((data) => {
                updateMutation.mutate({
                  id: editTarget.id ?? '',
                  recorded_at: editTarget.recorded_at,
                  entries: [{
                    symptom_type: data.symptom_type,
                    intensity: Number(data.intensity),
                    body_region: data.body_region || undefined,
                  }],
                  trigger_factors: data.trigger_factors ? data.trigger_factors.split(',').map((s) => s.trim()) : undefined,
                  notes: data.notes || undefined,
                });
              })}>
                <div className="form-row">
                  <div className="form-group"><label>{t('symptoms.symptom')} *</label>
                    <select {...editForm.register('symptom_type')} required>
                      {SYMPTOM_TYPES.map((s) => <option key={s} value={s}>{t('symptoms.type_' + s)}</option>)}
                    </select>
                  </div>
                  <div className="form-group">
                    <label>{t('symptoms.intensity')}: {editForm.watch('intensity') || 0}</label>
                    <input type="range" min="0" max="10" {...editForm.register('intensity')} style={{ width: '100%' }} />
                  </div>
                  <div className="form-group"><label>{t('symptoms.body_region')}</label>
                    <select {...editForm.register('body_region')}>
                      <option value="">{t('common.not_specified')}</option>
                      {BODY_REGIONS.map((r) => <option key={r} value={r}>{t('symptoms.region_' + r)}</option>)}
                    </select>
                  </div>
                </div>
                <div className="form-group"><label>{t('symptoms.trigger_factors')} ({t('symptoms.trigger_hint')})</label>
                  <input type="text" {...editForm.register('trigger_factors')} placeholder={t('symptoms_data.trigger_placeholder')} />
                </div>
                <div className="form-group"><label>{t('common.notes')}</label><textarea rows={2} {...editForm.register('notes')} /></div>
              </form>
            </div>
            <div className="modal-footer">
              <button type="button" className="btn btn-secondary" onClick={() => setEditTarget(null)}>{t('common.cancel')}</button>
              <button type="submit" form="symptom-edit-form" className="btn btn-add" disabled={updateMutation.isPending}>{updateMutation.isPending ? t('common.loading') : t('common.save')}</button>
            </div>
          </div>
        </div>
      )}

      <ConfirmDelete
        open={!!deleteTarget}
        onConfirm={() => { deleteMutation.mutate(deleteTarget!); setDeleteTarget(null); }}
        onCancel={() => setDeleteTarget(null)}
        pending={deleteMutation.isPending}
      />
    </div>
  );
}
