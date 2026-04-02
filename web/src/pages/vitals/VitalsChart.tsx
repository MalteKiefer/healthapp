import { useMemo } from 'react';
import { useTranslation } from 'react-i18next';
import {
  LineChart, Line, XAxis, YAxis, CartesianGrid, Tooltip,
  ResponsiveContainer, ReferenceLine,
} from 'recharts';

export interface MetricLine { key: string; label: string; unit: string; color: string }

export interface ChartTabDef {
  id: string;
  labelKey: string;
  dataKeys: string[];
  lines: MetricLine[];
  unit: string;
  refLines?: { value: number; label: string; color: string }[];
}

export const CHART_TABS: ChartTabDef[] = [
  {
    id: 'blood_pressure',
    labelKey: 'vitals.blood_pressure',
    dataKeys: ['blood_pressure_systolic', 'blood_pressure_diastolic'],
    lines: [
      { key: 'blood_pressure_systolic', label: 'vitals_data.systolic', unit: 'mmHg', color: '#FF3B30' },
      { key: 'blood_pressure_diastolic', label: 'vitals_data.diastolic', unit: 'mmHg', color: '#FF9500' },
    ],
    unit: 'mmHg',
    refLines: [
      { value: 120, label: 'vitals_data.optimal_sys', color: '#34C759' },
      { value: 80, label: 'vitals_data.optimal_dia', color: '#34C759' },
    ],
  },
  {
    id: 'pulse',
    labelKey: 'vitals.pulse',
    dataKeys: ['pulse'],
    lines: [{ key: 'pulse', label: 'vitals_data.pulse', unit: 'bpm', color: '#34C759' }],
    unit: 'bpm',
    refLines: [
      { value: 60, label: 'vitals_data.low_normal', color: '#FF9500' },
      { value: 100, label: 'vitals_data.high_normal', color: '#FF9500' },
    ],
  },
  {
    id: 'weight',
    labelKey: 'vitals.weight',
    dataKeys: ['weight'],
    lines: [{ key: 'weight', label: 'vitals_data.weight', unit: 'kg', color: '#AF52DE' }],
    unit: 'kg',
  },
  {
    id: 'temperature',
    labelKey: 'vitals.temperature',
    dataKeys: ['body_temperature'],
    lines: [{ key: 'body_temperature', label: 'vitals_data.temperature', unit: '\u00B0C', color: '#FF2D55' }],
    unit: '\u00B0C',
    refLines: [
      { value: 37.5, label: 'vitals_data.fever', color: '#FF9500' },
    ],
  },
  {
    id: 'oxygen',
    labelKey: 'vitals.oxygen',
    dataKeys: ['oxygen_saturation'],
    lines: [{ key: 'oxygen_saturation', label: 'vitals_data.spo2', unit: '%', color: '#007AFF' }],
    unit: '%',
    refLines: [
      { value: 95, label: 'vitals_data.normal', color: '#34C759' },
    ],
  },
  {
    id: 'glucose',
    labelKey: 'vitals.glucose',
    dataKeys: ['blood_glucose'],
    lines: [{ key: 'blood_glucose', label: 'vitals_data.glucose', unit: 'mmol/L', color: '#FF9500' }],
    unit: 'mmol/L',
  },
];

export interface ChartDataRow {
  date: string;
  fullDate: string;
  blood_pressure_systolic: number | null;
  blood_pressure_diastolic: number | null;
  pulse: number | null;
  weight: number | null;
  body_temperature: number | null;
  oxygen_saturation: number | null;
  blood_glucose: number | null;
}

interface LatestValuesData {
  values: (MetricLine & { value: number | undefined })[];
  date: string;
}

interface VitalsChartProps {
  chartData: ChartDataRow[];
  activeChartTab: string;
  setActiveChartTab: (tab: string) => void;
  tabsWithData: string[];
  currentTab: ChartTabDef | undefined;
  latestValues: LatestValuesData | null;
  chartRef: React.RefObject<HTMLDivElement | null>;
  isLoading: boolean;
}

export function VitalsChart({
  chartData,
  activeChartTab,
  setActiveChartTab,
  tabsWithData,
  currentTab,
  latestValues,
  chartRef,
  isLoading,
}: VitalsChartProps) {
  const { t } = useTranslation();

  const SingleChartTooltip = useMemo(() => {
    const TooltipComponent = ({ active, payload, label }: { active?: boolean; payload?: Array<{ name: string; value: number; color: string }>; label?: string }) => {
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
                <span>{line ? t(line.label) : p.name}: <strong>{p.value}</strong> {line?.unit}</span>
              </div>
            );
          })}
        </div>
      );
    };
    return TooltipComponent;
  }, [chartData, currentTab, t]);

  if (tabsWithData.length === 0) {
    return (
      <div className="card">
        <div className="chart-empty">{isLoading ? t('common.loading') : t('common.no_data')}</div>
      </div>
    );
  }

  return (
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
                  <span className="vital-latest-label">{t(v.label)}</span>
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
                domain={[currentTab.id === 'oxygen' ? 90 : 'auto', currentTab.id === 'oxygen' ? 100 : 'auto']}
                width={70}
                {...(currentTab.id === 'oxygen' ? { ticks: [90, 90.5, 91, 91.5, 92, 92.5, 93, 93.5, 94, 94.5, 95, 95.5, 96, 96.5, 97, 97.5, 98, 98.5, 99, 99.5, 100] } : {})}
              />
              <Tooltip content={<SingleChartTooltip />} />
              {currentTab.refLines?.map((ref) => (
                <ReferenceLine
                  key={ref.label}
                  y={ref.value}
                  stroke={ref.color}
                  strokeDasharray="6 4"
                  strokeOpacity={0.5}
                  label={{ value: t(ref.label), position: 'insideTopRight', fontSize: 11, fill: ref.color }}
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
                  name={t(line.label)}
                  connectNulls
                />
              ))}
            </LineChart>
          </ResponsiveContainer>
        </div>
      )}
    </>
  );
}
