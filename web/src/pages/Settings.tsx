import { useState, useEffect } from 'react';
import { useTranslation } from 'react-i18next';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { api } from '../api/client';
import { useUIStore } from '../store/ui';

interface UserPreferences {
  language: string;
  date_format: string;
  weight_unit: string;
  height_unit: string;
  temperature_unit: string;
  blood_glucose_unit: string;
  week_start: string;
  timezone: string;
}

interface SessionInfo {
  id: string;
  device_hint: string;
  ip_address: string;
  created_at: string;
  last_active_at: string;
}

export function Settings() {
  const { t, i18n } = useTranslation();
  const { theme, toggleTheme } = useUIStore();
  const queryClient = useQueryClient();

  const { data: prefs } = useQuery({
    queryKey: ['preferences'],
    queryFn: () => api.get<UserPreferences>('/api/v1/users/me/preferences'),
  });

  const { data: sessions } = useQuery({
    queryKey: ['sessions'],
    queryFn: () => api.get<SessionInfo[]>('/api/v1/users/me/sessions'),
  });

  const { data: storage } = useQuery({
    queryKey: ['storage'],
    queryFn: () => api.get<{ used_bytes: number; quota_bytes: number }>('/api/v1/users/me/storage'),
  });

  const updatePrefs = useMutation({
    mutationFn: (data: Partial<UserPreferences>) =>
      api.patch('/api/v1/users/me/preferences', data),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['preferences'] }),
  });

  const revokeSession = useMutation({
    mutationFn: (id: string) => api.delete(`/api/v1/users/me/sessions/${id}`),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['sessions'] }),
  });

  const revokeOthers = useMutation({
    mutationFn: () => api.delete('/api/v1/users/me/sessions/others'),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['sessions'] }),
  });

  const [language, setLanguage] = useState(prefs?.language || 'en');
  const [dateFormat, setDateFormat] = useState(prefs?.date_format || 'DMY');
  const [weightUnit, setWeightUnit] = useState(prefs?.weight_unit || 'kg');
  const [tempUnit, setTempUnit] = useState(prefs?.temperature_unit || 'celsius');
  const [glucoseUnit, setGlucoseUnit] = useState(prefs?.blood_glucose_unit || 'mmol_l');

  useEffect(() => {
    if (prefs) {
      setLanguage(prefs.language);
      setDateFormat(prefs.date_format);
      setWeightUnit(prefs.weight_unit);
      setTempUnit(prefs.temperature_unit);
      setGlucoseUnit(prefs.blood_glucose_unit);
    }
  }, [prefs]);

  const handleSavePrefs = () => {
    i18n.changeLanguage(language);
    localStorage.setItem('language', language);
    updatePrefs.mutate({
      language, date_format: dateFormat, weight_unit: weightUnit,
      temperature_unit: tempUnit, blood_glucose_unit: glucoseUnit,
    });
  };

  const usedMB = storage ? (storage.used_bytes / 1048576).toFixed(1) : '0';
  const quotaMB = storage ? (storage.quota_bytes / 1048576).toFixed(0) : '5120';
  const usagePercent = storage ? (storage.used_bytes / storage.quota_bytes * 100) : 0;

  return (
    <div className="page">
      <h2>{t('nav.settings')}</h2>

      {/* Appearance */}
      <div className="card settings-section">
        <h3>Appearance</h3>
        <div className="setting-row">
          <label>Theme</label>
          <button className="btn btn-secondary" onClick={toggleTheme}>
            {theme === 'light' ? 'Switch to Dark' : 'Switch to Light'}
          </button>
        </div>
      </div>

      {/* Preferences */}
      <div className="card settings-section">
        <h3>Preferences</h3>
        <div className="form-row">
          <div className="form-group">
            <label>Language</label>
            <select value={language} onChange={(e) => setLanguage(e.target.value)}>
              <option value="en">English</option>
              <option value="de">Deutsch</option>
            </select>
          </div>
          <div className="form-group">
            <label>Date Format</label>
            <select value={dateFormat} onChange={(e) => setDateFormat(e.target.value)}>
              <option value="DMY">DD.MM.YYYY</option>
              <option value="MDY">MM/DD/YYYY</option>
              <option value="YMD">YYYY-MM-DD</option>
            </select>
          </div>
        </div>
        <div className="form-row">
          <div className="form-group">
            <label>Weight</label>
            <select value={weightUnit} onChange={(e) => setWeightUnit(e.target.value)}>
              <option value="kg">Kilograms (kg)</option>
              <option value="lbs">Pounds (lbs)</option>
            </select>
          </div>
          <div className="form-group">
            <label>Temperature</label>
            <select value={tempUnit} onChange={(e) => setTempUnit(e.target.value)}>
              <option value="celsius">Celsius (°C)</option>
              <option value="fahrenheit">Fahrenheit (°F)</option>
            </select>
          </div>
          <div className="form-group">
            <label>Blood Glucose</label>
            <select value={glucoseUnit} onChange={(e) => setGlucoseUnit(e.target.value)}>
              <option value="mmol_l">mmol/L</option>
              <option value="mg_dl">mg/dL</option>
            </select>
          </div>
        </div>
        <button className="btn btn-add" onClick={handleSavePrefs} style={{ width: 'auto' }}>
          {t('common.save')}
        </button>
      </div>

      {/* Storage */}
      <div className="card settings-section">
        <h3>Storage</h3>
        <div className="storage-bar">
          <div className="storage-fill" style={{ width: `${Math.min(usagePercent, 100)}%` }} />
        </div>
        <p className="text-muted">{usedMB} MB of {quotaMB} MB used ({usagePercent.toFixed(1)}%)</p>
      </div>

      {/* Sessions */}
      <div className="card settings-section">
        <h3>Active Sessions</h3>
        <button className="btn btn-secondary" onClick={() => revokeOthers.mutate()} style={{ marginBottom: 12 }}>
          Terminate all other sessions
        </button>
        {Array.isArray(sessions) && sessions.length > 0 ? (
          <div className="session-list">
            {sessions.map((s) => (
              <div key={s.id} className="session-item">
                <div>
                  <div className="session-device">{s.device_hint || 'Unknown device'}</div>
                  <div className="text-muted" style={{ fontSize: 12 }}>
                    {s.ip_address} · Last active: {new Date(s.last_active_at).toLocaleString()}
                  </div>
                </div>
                <button className="btn-sm" onClick={() => revokeSession.mutate(s.id)}>
                  Terminate
                </button>
              </div>
            ))}
          </div>
        ) : (
          <p className="text-muted">No session data available</p>
        )}
      </div>
    </div>
  );
}
