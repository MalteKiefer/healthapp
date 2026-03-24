import { useState } from 'react';
import { useTranslation } from 'react-i18next';
import { useForm } from 'react-hook-form';
import {
  LineChart, Line, XAxis, YAxis, CartesianGrid, Tooltip,
  ResponsiveContainer, ReferenceLine,
} from 'recharts';
import { format } from 'date-fns';
import { ProfileSelector } from '../components/ProfileSelector';
import { useVitals, useVitalChart, useCreateVital } from '../hooks/useVitals';
import { useProfiles } from '../hooks/useProfiles';

interface VitalFormData {
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

const CHART_METRICS = [
  { key: 'blood_pressure_systolic', label: 'Systolic BP', unit: 'mmHg', color: '#dc2626' },
  { key: 'blood_pressure_diastolic', label: 'Diastolic BP', unit: 'mmHg', color: '#2563eb' },
  { key: 'pulse', label: 'Pulse', unit: 'bpm', color: '#16a34a' },
  { key: 'weight', label: 'Weight', unit: 'kg', color: '#7c3aed' },
  { key: 'blood_glucose', label: 'Blood Glucose', unit: 'mmol/L', color: '#d97706' },
  { key: 'body_temperature', label: 'Temperature', unit: '°C', color: '#0891b2' },
  { key: 'oxygen_saturation', label: 'SpO2', unit: '%', color: '#059669' },
];

export function Vitals() {
  const { t } = useTranslation();
  const { data: profilesData } = useProfiles();
  const profiles = profilesData?.items || [];
  const [selectedProfile, setSelectedProfile] = useState<string>('');
  const [selectedMetric, setSelectedMetric] = useState('blood_pressure_systolic');
  const [showForm, setShowForm] = useState(false);

  // Auto-select first profile
  const profileId = selectedProfile || profiles[0]?.id || '';

  const { data: vitalsData, isLoading } = useVitals(profileId, { limit: 50 });
  const { data: chartData } = useVitalChart(profileId, selectedMetric);
  const createVital = useCreateVital(profileId);

  const { register, handleSubmit, reset } = useForm<VitalFormData>();

  const onSubmit = async (data: VitalFormData) => {
    // Remove empty fields
    const cleaned = Object.fromEntries(
      Object.entries(data).filter(([, v]) => v !== '' && v !== undefined && v !== null)
    );
    await createVital.mutateAsync({
      ...cleaned,
      measured_at: new Date().toISOString(),
    });
    reset();
    setShowForm(false);
  };

  const chartPoints = (chartData?.points || []).map((p) => ({
    date: format(new Date(p.measured_at), 'MMM d'),
    value: p.values[selectedMetric],
  }));

  const currentMetric = CHART_METRICS.find((m) => m.key === selectedMetric);

  return (
    <div className="page">
      <div className="page-header">
        <h2>{t('vitals.title')}</h2>
        <div className="page-actions">
          <ProfileSelector selectedId={profileId} onSelect={setSelectedProfile} />
          <button className="btn btn-add" onClick={() => setShowForm(!showForm)}>
            + {t('vitals.add')}
          </button>
        </div>
      </div>

      {showForm && (
        <div className="card form-card">
          <h3>{t('vitals.add')}</h3>
          <form onSubmit={handleSubmit(onSubmit)} className="vital-form">
            <div className="form-row">
              <div className="form-group">
                <label>{t('vitals.systolic')} (mmHg)</label>
                <input type="number" {...register('blood_pressure_systolic', { valueAsNumber: true })} />
              </div>
              <div className="form-group">
                <label>{t('vitals.diastolic')} (mmHg)</label>
                <input type="number" {...register('blood_pressure_diastolic', { valueAsNumber: true })} />
              </div>
              <div className="form-group">
                <label>{t('vitals.pulse')} (bpm)</label>
                <input type="number" {...register('pulse', { valueAsNumber: true })} />
              </div>
            </div>

            <div className="form-row">
              <div className="form-group">
                <label>{t('vitals.weight')} (kg)</label>
                <input type="number" step="0.1" {...register('weight', { valueAsNumber: true })} />
              </div>
              <div className="form-group">
                <label>{t('vitals.temperature')} (°C)</label>
                <input type="number" step="0.1" {...register('body_temperature', { valueAsNumber: true })} />
              </div>
              <div className="form-group">
                <label>{t('vitals.oxygen')} (%)</label>
                <input type="number" step="0.1" {...register('oxygen_saturation', { valueAsNumber: true })} />
              </div>
            </div>

            <div className="form-row">
              <div className="form-group">
                <label>{t('vitals.glucose')} (mmol/L)</label>
                <input type="number" step="0.1" {...register('blood_glucose', { valueAsNumber: true })} />
              </div>
              <div className="form-group">
                <label>Sleep (minutes)</label>
                <input type="number" {...register('sleep_duration_minutes', { valueAsNumber: true })} />
              </div>
              <div className="form-group">
                <label>Sleep Quality (1-5)</label>
                <input type="number" min="1" max="5" {...register('sleep_quality', { valueAsNumber: true })} />
              </div>
            </div>

            <div className="form-group">
              <label>Notes</label>
              <textarea rows={2} {...register('notes')} />
            </div>

            <div className="form-actions">
              <button type="submit" className="btn btn-add" disabled={createVital.isPending}>
                {createVital.isPending ? t('common.loading') : t('common.save')}
              </button>
              <button type="button" className="btn btn-secondary" onClick={() => setShowForm(false)}>
                {t('common.cancel')}
              </button>
            </div>
          </form>
        </div>
      )}

      {/* Chart */}
      <div className="card chart-card">
        <div className="chart-header">
          <h3>Trend</h3>
          <select
            value={selectedMetric}
            onChange={(e) => setSelectedMetric(e.target.value)}
            className="metric-selector"
          >
            {CHART_METRICS.map((m) => (
              <option key={m.key} value={m.key}>{m.label} ({m.unit})</option>
            ))}
          </select>
        </div>

        {chartPoints.length > 0 ? (
          <ResponsiveContainer width="100%" height={300}>
            <LineChart data={chartPoints}>
              <CartesianGrid strokeDasharray="3 3" stroke="var(--color-border)" />
              <XAxis dataKey="date" fontSize={12} stroke="var(--color-text-secondary)" />
              <YAxis fontSize={12} stroke="var(--color-text-secondary)" />
              <Tooltip
                contentStyle={{
                  background: 'var(--color-surface)',
                  border: '1px solid var(--color-border)',
                  borderRadius: '6px',
                }}
              />
              {selectedMetric === 'blood_pressure_systolic' && (
                <ReferenceLine y={140} stroke="#d97706" strokeDasharray="3 3" label="Warning" />
              )}
              {selectedMetric === 'oxygen_saturation' && (
                <ReferenceLine y={95} stroke="#d97706" strokeDasharray="3 3" label="Warning" />
              )}
              <Line
                type="monotone"
                dataKey="value"
                stroke={currentMetric?.color || '#2563eb'}
                strokeWidth={2}
                dot={{ r: 3 }}
                activeDot={{ r: 5 }}
                name={currentMetric?.label}
              />
            </LineChart>
          </ResponsiveContainer>
        ) : (
          <div className="chart-empty">{t('common.no_data')}</div>
        )}
      </div>

      {/* Recent Vitals Table */}
      <div className="card">
        <h3>Recent Measurements</h3>
        {isLoading ? (
          <p>{t('common.loading')}</p>
        ) : (vitalsData?.items?.length ?? 0) === 0 ? (
          <p className="text-muted">{t('common.no_data')}</p>
        ) : (
          <div className="table-scroll">
            <table className="data-table">
              <thead>
                <tr>
                  <th>Date</th>
                  <th>BP</th>
                  <th>Pulse</th>
                  <th>Weight</th>
                  <th>Temp</th>
                  <th>SpO2</th>
                  <th>Glucose</th>
                  <th>BMI</th>
                </tr>
              </thead>
              <tbody>
                {vitalsData?.items?.map((v) => (
                  <tr key={v.id}>
                    <td>{format(new Date(v.measured_at), 'MMM d, HH:mm')}</td>
                    <td className={getBPClass(v.blood_pressure_systolic)}>
                      {v.blood_pressure_systolic && v.blood_pressure_diastolic
                        ? `${v.blood_pressure_systolic}/${v.blood_pressure_diastolic}`
                        : '—'}
                    </td>
                    <td>{v.pulse ?? '—'}</td>
                    <td>{v.weight != null ? `${v.weight} kg` : '—'}</td>
                    <td className={getTempClass(v.body_temperature)}>
                      {v.body_temperature != null ? `${v.body_temperature}°` : '—'}
                    </td>
                    <td className={getSpo2Class(v.oxygen_saturation)}>
                      {v.oxygen_saturation != null ? `${v.oxygen_saturation}%` : '—'}
                    </td>
                    <td>{v.blood_glucose != null ? v.blood_glucose : '—'}</td>
                    <td>{v.bmi != null ? v.bmi.toFixed(1) : '—'}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>
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
