import { useState, useMemo } from 'react';
import { useTranslation } from 'react-i18next';
import { useQuery } from '@tanstack/react-query';
import { Link } from 'react-router-dom';
import { isPast } from 'date-fns';
import { ProfileSelector } from '../components/ProfileSelector';
import { useDateFormat } from '../hooks/useDateLocale';
import { OCRUpload } from '../components/OCRUpload';
import { useProfiles } from '../hooks/useProfiles';
import { useVitals } from '../hooks/useVitals';
import { api } from '../api/client';
import { diaryApi } from '../api/diary';
import { appointmentsApi } from '../api/appointments';
import { medicationsApi } from '../api/medications';

interface Task {
  id: string;
  title: string;
  due_date?: string;
  priority: string;
  status: string;
}

function formatVitalLabel(v: {
  blood_pressure_systolic?: number;
  blood_pressure_diastolic?: number;
  pulse?: number;
  weight?: number;
  body_temperature?: number;
  blood_glucose?: number;
  oxygen_saturation?: number;
}, t: (key: string) => string): string {
  if (v.blood_pressure_systolic && v.blood_pressure_diastolic) {
    const parts = [`${t('dashboard.bp')} ${v.blood_pressure_systolic}/${v.blood_pressure_diastolic}`];
    if (v.pulse) parts.push(`${v.pulse} ${t('dashboard.bpm')}`);
    return parts.join(' \u00b7 ');
  }
  if (v.weight) return `${t('dashboard.weight')} ${v.weight} ${t('dashboard.kg')}`;
  if (v.body_temperature) return `${t('dashboard.temp')} ${v.body_temperature}${t('dashboard.celsius')}`;
  if (v.blood_glucose) return `${t('dashboard.glucose')} ${v.blood_glucose} ${t('dashboard.mg_dl')}`;
  if (v.oxygen_saturation) return `${t('dashboard.spo2')} ${v.oxygen_saturation}${t('dashboard.percent')}`;
  if (v.pulse) return `${t('dashboard.pulse')} ${v.pulse} ${t('dashboard.bpm')}`;
  return t('dashboard.vital_recorded');
}

function getGreeting(t: (key: string) => string): string {
  const hour = new Date().getHours();
  return hour < 12 ? t('dashboard.good_morning') : hour < 18 ? t('dashboard.good_afternoon') : t('dashboard.good_evening');
}

export function Dashboard() {
  const { t } = useTranslation();
  const { fmt, relative } = useDateFormat();
  const { data: profilesData } = useProfiles();
  const profiles = profilesData || [];
  const [selectedProfile, setSelectedProfile] = useState('');

  const profileId = selectedProfile || profiles[0]?.id || '';

  // Fetch dashboard data
  const { data: vitalsData } = useVitals(profileId, { limit: 5 });
  const { data: tasksData, isLoading: tasksLoading, isError: tasksError } = useQuery({
    queryKey: ['tasks-open', profileId],
    queryFn: () => api.get<{ items: Task[] }>(`/api/v1/profiles/${profileId}/tasks/open`),
    enabled: !!profileId,
  });
  const { data: apptsData, isLoading: apptsLoading, isError: apptsError } = useQuery({
    queryKey: ['appointments-upcoming', profileId],
    queryFn: () => appointmentsApi.upcoming(profileId),
    enabled: !!profileId,
  });
  const { data: medsData, isLoading: medsLoading, isError: medsError } = useQuery({
    queryKey: ['medications-active', profileId],
    queryFn: () => medicationsApi.active(profileId),
    enabled: !!profileId,
  });
  const { data: diaryData, isLoading: diaryLoading, isError: diaryError } = useQuery({
    queryKey: ['diary-recent', profileId],
    queryFn: () => diaryApi.list(profileId, { limit: 5 }),
    enabled: !!profileId,
  });

  const recentVitals = vitalsData?.items || [];
  const openTasks = tasksData?.items || [];
  const upcomingAppts = apptsData?.items || [];
  const activeMeds = medsData?.items || [];
  const recentDiary = diaryData?.items || [];

  // Latest vital for the summary stat
  const latestVital = recentVitals[0];

  // Upcoming card: next 5 appointments + overdue tasks, sorted by date
  const upcomingItems = useMemo(() => {
    const items: { id: string; title: string; date: string; type: 'appointment' | 'task'; icon: string; overdue: boolean }[] = [];

    for (const appt of upcomingAppts.slice(0, 5)) {
      items.push({
        id: appt.id,
        title: appt.title,
        date: appt.scheduled_at,
        type: 'appointment',
        icon: '\uD83D\uDCC5',
        overdue: false,
      });
    }

    for (const task of openTasks) {
      const overdue = task.due_date ? isPast(new Date(task.due_date)) : false;
      items.push({
        id: task.id,
        title: task.title,
        date: task.due_date || '',
        type: 'task',
        icon: overdue ? '\u26A0\uFE0F' : '\u2610',
        overdue,
      });
    }

    return items
      .filter((item) => item.date)
      .sort((a, b) => new Date(a.date).getTime() - new Date(b.date).getTime())
      .slice(0, 5);
  }, [upcomingAppts, openTasks]);

  // Recent activity: last 5 vitals + diary entries combined
  const recentActivity = useMemo(() => {
    const items: { id: string; label: string; date: string; type: 'vital' | 'diary'; icon: string }[] = [];

    for (const v of recentVitals) {
      items.push({
        id: v.id,
        label: formatVitalLabel(v, t),
        date: v.measured_at,
        type: 'vital',
        icon: '\uD83E\uDE7A',
      });
    }

    for (const d of recentDiary) {
      items.push({
        id: d.id,
        label: d.title,
        date: d.started_at,
        type: 'diary',
        icon: '\uD83D\uDCD3',
      });
    }

    return items
      .sort((a, b) => new Date(b.date).getTime() - new Date(a.date).getTime())
      .slice(0, 5);
  }, [recentVitals, recentDiary, t]);

  const isLoading = tasksLoading || apptsLoading || medsLoading || diaryLoading;
  const isError = tasksError || apptsError || medsError || diaryError;

  if (isLoading) return <p>{t('common.loading')}</p>;
  if (isError) return <p className="text-muted">{t('common.error')}</p>;

  return (
    <div className="page">
      <div className="page-header">
        <div>
          <h2 style={{ marginBottom: 4 }}>{getGreeting(t)}</h2>
          <p className="text-muted" style={{ fontSize: 14 }}>
            {fmt(new Date(), 'EEEE, dd. MMMM yyyy')}
          </p>
        </div>
        <ProfileSelector selectedId={profileId} onSelect={setSelectedProfile} />
      </div>

      {/* Summary Stats Row */}
      <div className="stats-row">
        <Link to="/tasks" className="stat-card" style={{ textDecoration: 'none', color: 'inherit' }}>
          <div className="stat-value">{openTasks.length}</div>
          <div className="stat-label">{t('dashboard.open_tasks')}</div>
        </Link>

        <Link to="/appointments" className="stat-card" style={{ textDecoration: 'none', color: 'inherit' }}>
          <div className="stat-value">{upcomingAppts.length}</div>
          <div className="stat-label">{t('dashboard.upcoming_appts')}</div>
        </Link>

        <Link to="/medications" className="stat-card" style={{ textDecoration: 'none', color: 'inherit' }}>
          <div className="stat-value">{activeMeds.length}</div>
          <div className="stat-label">{t('dashboard.active_meds')}</div>
        </Link>

        <Link to="/vitals" className="stat-card" style={{ textDecoration: 'none', color: 'inherit' }}>
          <div className="stat-value" style={{ fontSize: 20 }}>
            {latestVital ? formatVitalLabel(latestVital, t) : '\u2014'}
          </div>
          <div className="stat-label">
            {latestVital
              ? relative(latestVital.measured_at)
              : t('dashboard.no_vitals_yet')}
          </div>
        </Link>
      </div>

      {/* OCR Document Scanner */}
      <div className="card" style={{ marginBottom: 16 }}>
        <div className="card-header">
          <h3>{t('ocr.scan_document')}</h3>
        </div>
        <OCRUpload profileId={profileId} />
      </div>

      {/* Two-Column Detail Cards */}
      <div className="dashboard-grid" style={{ gridTemplateColumns: '1fr 1fr' }}>
        {/* Upcoming Card */}
        <div className="card">
          <div className="card-header">
            <h3>{t('nav.appointments')} &amp; {t('nav.tasks')}</h3>
            <Link to="/appointments" className="card-link">{t('common.view_all')}</Link>
          </div>
          {upcomingItems.length === 0 ? (
            <p className="text-muted" style={{ fontSize: 13, padding: '12px 0' }}>
              {t('dashboard.empty_upcoming')}
            </p>
          ) : (
            <div className="dash-list">
              {upcomingItems.map((item) => (
                <div
                  key={item.id}
                  className={`dash-item${item.overdue ? ' status-abnormal' : ''}`}
                >
                  <span style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                    <span>{item.icon}</span>
                    <span>{item.title}</span>
                    <span className={`badge ${item.type === 'appointment' ? 'badge-scheduled' : item.overdue ? 'badge-missed' : 'badge-info'}`}>
                      {item.type === 'appointment' ? t('dashboard.appt') : t('dashboard.task')}
                    </span>
                  </span>
                  <span className="dash-meta">
                    {fmt(item.date, 'dd. MMM, HH:mm')}
                  </span>
                </div>
              ))}
            </div>
          )}
        </div>

        {/* Recent Activity Card */}
        <div className="card">
          <div className="card-header">
            <h3>{t('dashboard.recent_activity')}</h3>
            <Link to="/vitals" className="card-link">{t('common.view_all')}</Link>
          </div>
          {recentActivity.length === 0 ? (
            <p className="text-muted" style={{ fontSize: 13, padding: '12px 0' }}>
              {t('dashboard.empty_activity')}
            </p>
          ) : (
            <div className="dash-list">
              {recentActivity.map((item) => (
                <div key={item.id} className="dash-item">
                  <span style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                    <span>{item.icon}</span>
                    <span>{item.label}</span>
                    <span className={`badge ${item.type === 'vital' ? 'badge-active' : 'badge-info'}`}>
                      {item.type === 'vital' ? t('dashboard.vital') : t('dashboard.diary')}
                    </span>
                  </span>
                  <span className="dash-meta">
                    {relative(item.date)}
                  </span>
                </div>
              ))}
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
