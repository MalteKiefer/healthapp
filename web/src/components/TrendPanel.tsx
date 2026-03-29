import { useMemo } from 'react';
import { useTranslation } from 'react-i18next';

interface DataPoint {
  measured_at: string;
  value: number;
}

interface TrendPanelProps {
  data: DataPoint[];
  metricName: string;
  unit: string;
}

/**
 * TrendPanel — Client-side statistical analysis.
 * Computes rolling averages, trend direction, variability.
 * No server-side analysis, no AI — purely descriptive statistics.
 */
export function TrendPanel({ data, metricName, unit }: TrendPanelProps) {
  const { t } = useTranslation();
  const stats = useMemo(() => {
    if (data.length < 2) return null;

    const values = data.map((d) => d.value).filter((v) => v != null);
    if (values.length < 2) return null;

    const n = values.length;
    const sum = values.reduce((a, b) => a + b, 0);
    const mean = sum / n;

    // Standard deviation
    const variance = values.reduce((acc, v) => acc + (v - mean) ** 2, 0) / n;
    const stdDev = Math.sqrt(variance);

    // Linear regression slope (trend)
    const xValues = values.map((_, i) => i);
    const xMean = (n - 1) / 2;
    const numerator = xValues.reduce((acc, x, i) => acc + (x - xMean) * (values[i] - mean), 0);
    const denominator = xValues.reduce((acc, x) => acc + (x - xMean) ** 2, 0);
    const slope = denominator !== 0 ? numerator / denominator : 0;

    // Trend percentage (slope as % of mean)
    const trendPercent = mean !== 0 ? (slope / mean) * 100 * n : 0;

    // Rolling averages
    const last7 = values.slice(-7);
    const last30 = values.slice(-30);
    const avg7 = last7.reduce((a, b) => a + b, 0) / last7.length;
    const avg30 = last30.reduce((a, b) => a + b, 0) / last30.length;

    // Min/Max
    const min = Math.min(...values);
    const max = Math.max(...values);

    // Variability classification
    const cv = mean !== 0 ? (stdDev / mean) * 100 : 0;
    const variability = cv < 5 ? 'low' : cv < 15 ? 'moderate' : 'high';

    return {
      mean: mean.toFixed(1),
      avg7: avg7.toFixed(1),
      avg30: avg30.toFixed(1),
      stdDev: stdDev.toFixed(1),
      slope: slope.toFixed(2),
      trendPercent: trendPercent.toFixed(1),
      trendDirection: slope > 0.01 ? 'up' : slope < -0.01 ? 'down' : 'stable',
      min: min.toFixed(1),
      max: max.toFixed(1),
      count: n,
      variability,
    };
  }, [data]);

  if (!stats) {
    return <p className="text-muted">{t('trend.min_data')}</p>;
  }

  const trendArrow = stats.trendDirection === 'up' ? '↑' : stats.trendDirection === 'down' ? '↓' : '→';
  const trendColor = stats.trendDirection === 'up' ? 'status-borderline' : stats.trendDirection === 'down' ? 'status-normal' : '';

  return (
    <div className="trend-panel">
      <h4>{t('trend.insights', { metric: metricName })}</h4>
      <div className="trend-grid">
        <div className="trend-stat">
          <div className="trend-label">{t('trend.avg_7d')}</div>
          <div className="trend-value">{stats.avg7} {unit}</div>
        </div>
        <div className="trend-stat">
          <div className="trend-label">{t('trend.avg_30d')}</div>
          <div className="trend-value">{stats.avg30} {unit}</div>
        </div>
        <div className="trend-stat">
          <div className="trend-label">{t('trend.trend')}</div>
          <div className={`trend-value ${trendColor}`}>
            {trendArrow} {Math.abs(Number(stats.trendPercent))}%
          </div>
        </div>
        <div className="trend-stat">
          <div className="trend-label">{t('trend.variability')}</div>
          <div className="trend-value">{t('trend.' + stats.variability)}</div>
        </div>
        <div className="trend-stat">
          <div className="trend-label">{t('trend.range')}</div>
          <div className="trend-value">{stats.min} – {stats.max} {unit}</div>
        </div>
        <div className="trend-stat">
          <div className="trend-label">{t('trend.measurements')}</div>
          <div className="trend-value">{stats.count}</div>
        </div>
      </div>
    </div>
  );
}
