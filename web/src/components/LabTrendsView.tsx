import { useState, useMemo, type ReactElement } from 'react';
import { useTranslation } from 'react-i18next';
import { useQuery } from '@tanstack/react-query';
import {
  LineChart, Line, XAxis, YAxis, Tooltip, ResponsiveContainer, ReferenceArea,
} from 'recharts';
import { format, subDays, subYears } from 'date-fns';
import { api } from '../api/client';
import { TrendPanel } from './TrendPanel';

type TimeRange = '7d' | '30d' | '90d' | '1y' | 'all';

interface TrendDataPoint {
  date: string;
  value: number;
  flag?: string;
}

interface MarkerTrend {
  marker: string;
  unit?: string;
  reference_low?: number;
  reference_high?: number;
  data_points: TrendDataPoint[];
}

interface LabTrendsResponse {
  markers: MarkerTrend[];
}

function getFromDate(range: TimeRange): string | undefined {
  const now = new Date();
  switch (range) {
    case '7d': return subDays(now, 7).toISOString();
    case '30d': return subDays(now, 30).toISOString();
    case '90d': return subDays(now, 90).toISOString();
    case '1y': return subYears(now, 1).toISOString();
    case 'all': return undefined;
  }
}

function trendDirection(points: TrendDataPoint[]): { arrow: string; color: string; label: string } {
  if (points.length < 2) return { arrow: '\u2192', color: 'var(--text-secondary)', label: 'stable' };
  const values = points.map(p => p.value);
  const n = values.length;
  const mean = values.reduce((a, b) => a + b, 0) / n;
  const xMean = (n - 1) / 2;
  const num = values.reduce((acc, v, i) => acc + (i - xMean) * (v - mean), 0);
  const den = values.reduce((acc, _, i) => acc + (i - xMean) ** 2, 0);
  const slope = den !== 0 ? num / den : 0;
  if (slope > 0.01) return { arrow: '\u2191', color: 'var(--text-secondary)', label: 'up' };
  if (slope < -0.01) return { arrow: '\u2193', color: 'var(--text-secondary)', label: 'down' };
  return { arrow: '\u2192', color: 'var(--text-secondary)', label: 'stable' };
}

function MarkerSparkline({ points }: { points: TrendDataPoint[] }) {
  const data = points.map(p => ({ v: p.value }));
  return (
    <ResponsiveContainer width="100%" height={32}>
      <LineChart data={data} margin={{ top: 2, right: 2, bottom: 2, left: 2 }}>
        <Line type="monotone" dataKey="v" stroke="var(--primary)" strokeWidth={1.5} dot={false} />
      </LineChart>
    </ResponsiveContainer>
  );
}

function ExpandedChart({ marker }: { marker: MarkerTrend }) {
  const { t } = useTranslation();
  const chartData = marker.data_points.map(dp => ({
    date: format(new Date(dp.date), 'dd.MM.yy'),
    value: dp.value,
    flag: dp.flag,
  }));

  const trendData = marker.data_points.map(dp => ({
    measured_at: dp.date,
    value: dp.value,
  }));

  const hasRef = marker.reference_low != null && marker.reference_high != null;

  return (
    <div className="lab-trend-expanded">
      <div className="lab-trend-expanded-header">
        <div>
          <strong>{marker.marker}</strong>
          <span style={{ color: 'var(--text-secondary)', fontSize: 13, marginLeft: 8 }}>
            {marker.unit || ''} {hasRef && `\u2014 Ref: ${marker.reference_low}\u2013${marker.reference_high}`}
          </span>
        </div>
        <span style={{ fontSize: 13, color: 'var(--text-secondary)' }}>
          {marker.data_points.length} {t('labs.data_points')}
        </span>
      </div>
      <div className="lab-trend-expanded-content">
        <ResponsiveContainer width="100%" height={280}>
          <LineChart data={chartData} margin={{ top: 10, right: 20, bottom: 5, left: 0 }}>
            {hasRef && (
              <ReferenceArea
                y1={marker.reference_low!}
                y2={marker.reference_high!}
                fill="var(--success)"
                fillOpacity={0.08}
              />
            )}
            <XAxis dataKey="date" fontSize={12} stroke="var(--text-secondary)" />
            <YAxis
              fontSize={12}
              stroke="var(--text-secondary)"
              unit={marker.unit ? ` ${marker.unit}` : ''}
              width={70}
            />
            <Tooltip
              contentStyle={{
                background: 'var(--surface)',
                border: '1px solid var(--border)',
                borderRadius: 'var(--radius-sm)',
                fontSize: 13,
              }}
            />
            <Line
              type="monotone"
              dataKey="value"
              stroke="var(--primary)"
              strokeWidth={2.5}
              dot={{ r: 4, fill: 'var(--primary)', strokeWidth: 2, stroke: 'var(--surface)' }}
              activeDot={{ r: 6 }}
              name={marker.marker}
              connectNulls
            />
          </LineChart>
        </ResponsiveContainer>
        <TrendPanel data={trendData} metricName={marker.marker} unit={marker.unit || ''} />
      </div>
    </div>
  );
}

export function LabTrendsView({ profileId }: { profileId: string }) {
  const { t } = useTranslation();
  const [timeRange, setTimeRange] = useState<TimeRange>('all');
  const [expandedMarker, setExpandedMarker] = useState<string | null>(null);

  const from = useMemo(() => getFromDate(timeRange), [timeRange]);

  const { data, isLoading } = useQuery({
    queryKey: ['lab-trends', profileId, from],
    queryFn: () => {
      let url = `/api/v1/profiles/${profileId}/labs/trends`;
      const params: string[] = [];
      if (from) params.push(`from=${encodeURIComponent(from)}`);
      if (params.length > 0) url += '?' + params.join('&');
      return api.get<LabTrendsResponse>(url);
    },
    enabled: !!profileId,
  });

  const markers = data?.markers || [];

  const toggleExpand = (marker: string) => {
    setExpandedMarker(prev => prev === marker ? null : marker);
  };

  // Build grid items: cards + expanded card inserted after the right position
  const gridItems: ReactElement[] = [];
  for (let i = 0; i < markers.length; i++) {
    const m = markers[i];
    const lastPoint = m.data_points[m.data_points.length - 1];
    const trend = trendDirection(m.data_points);

    gridItems.push(
      <div
        key={m.marker}
        className="lab-trend-card"
        onClick={() => toggleExpand(m.marker)}
        onKeyDown={(e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); toggleExpand(m.marker); } }}
        role="button"
        tabIndex={0}
        aria-expanded={expandedMarker === m.marker}
        style={expandedMarker === m.marker ? { borderColor: 'var(--primary)' } : undefined}
      >
        <div className="lab-trend-card-header">
          <div className="lab-trend-card-marker">{m.marker}</div>
        </div>
        <div className="lab-trend-card-value">
          {lastPoint.value}
          <span className="lab-trend-card-unit">{m.unit || ''}</span>
        </div>
        <div className="lab-trend-card-trend" style={{ color: trend.color }}>
          {trend.arrow}
        </div>
        <MarkerSparkline points={m.data_points} />
      </div>
    );

    // Insert expanded card after this card if it's the expanded marker
    if (expandedMarker === m.marker) {
      gridItems.push(
        <ExpandedChart key={`${m.marker}-expanded`} marker={m} />
      );
    }
  }

  return (
    <>
      <div className="card" style={{ marginBottom: 16 }}>
        <div className="view-toolbar">
          <div className="chart-filters">
            {(['7d', '30d', '90d', '1y', 'all'] as TimeRange[]).map((r) => (
              <button
                key={r}
                className={`chart-range-btn${timeRange === r ? ' active' : ''}`}
                onClick={() => setTimeRange(r)}
              >
                {r === 'all' ? t('common.all') : r}
              </button>
            ))}
          </div>
        </div>
      </div>

      {isLoading ? (
        <div className="card"><p>{t('common.loading')}</p></div>
      ) : markers.length === 0 ? (
        <div className="card"><p className="text-muted">{t('labs.no_trends')}</p></div>
      ) : (
        <div className="lab-trends-grid">
          {gridItems}
        </div>
      )}
    </>
  );
}
