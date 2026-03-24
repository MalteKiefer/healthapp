import { useState } from 'react';
import { useTranslation } from 'react-i18next';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { useForm } from 'react-hook-form';
import { Link } from 'react-router-dom';
import { format, formatDistanceToNow, isPast } from 'date-fns';
import { ProfileSelector } from '../components/ProfileSelector';
import { useProfiles } from '../hooks/useProfiles';
import { useVitals, useCreateVital } from '../hooks/useVitals';
import { api } from '../api/client';
import type { Vital } from '../api/vitals';

interface Task {
  id: string;
  title: string;
  due_date?: string;
  priority: string;
  status: string;
}

interface Appointment {
  id: string;
  title: string;
  scheduled_at: string;
  appointment_type: string;
  status: string;
}

interface Medication {
  id: string;
  name: string;
  dosage?: string;
  frequency?: string;
}

export function Dashboard() {
  const { t } = useTranslation();
  const { data: profilesData } = useProfiles();
  const profiles = profilesData?.items || [];
  const [selectedProfile, setSelectedProfile] = useState('');
  const queryClient = useQueryClient();

  const profileId = selectedProfile || profiles[0]?.id || '';

  // Fetch dashboard data
  const { data: vitalsData } = useVitals(profileId, { limit: 5 });
  const { data: tasksData } = useQuery({
    queryKey: ['tasks-open', profileId],
    queryFn: () => api.get<{ items: Task[] }>(`/api/v1/profiles/${profileId}/tasks/open`),
    enabled: !!profileId,
  });
  const { data: apptsData } = useQuery({
    queryKey: ['appointments-upcoming', profileId],
    queryFn: () => api.get<{ items: Appointment[] }>(`/api/v1/profiles/${profileId}/appointments/upcoming`),
    enabled: !!profileId,
  });
  const { data: medsData } = useQuery({
    queryKey: ['medications-active', profileId],
    queryFn: () => api.get<{ items: Medication[] }>(`/api/v1/profiles/${profileId}/medications/active`),
    enabled: !!profileId,
  });

  // Quick-add vital
  const createVital = useCreateVital(profileId);
  const { register, handleSubmit, reset } = useForm<{
    blood_pressure_systolic: number;
    blood_pressure_diastolic: number;
    pulse: number;
  }>();

  const onQuickAdd = (data: { blood_pressure_systolic: number; blood_pressure_diastolic: number; pulse: number }) => {
    const cleaned = Object.fromEntries(
      Object.entries(data).filter(([, v]) => v !== undefined && !isNaN(v as number) && v !== 0)
    );
    if (Object.keys(cleaned).length === 0) return;
    createVital.mutateAsync({ ...cleaned, measured_at: new Date().toISOString() }).then(() => reset());
  };

  const recentVitals = vitalsData?.items || [];
  const openTasks = tasksData?.items || [];
  const upcomingAppts = apptsData?.items || [];
  const activeMeds = medsData?.items || [];

  return (
    <div className="page">
      <div className="page-header">
        <h2>{t('nav.dashboard')}</h2>
        <ProfileSelector selectedId={profileId} onSelect={setSelectedProfile} />
      </div>

      {/* Quick-Add Widget */}
      <div className="card quick-add-card">
        <h3>Quick Add — Blood Pressure</h3>
        <form onSubmit={handleSubmit(onQuickAdd)} className="quick-add-form">
          <div className="quick-add-fields">
            <div className="quick-input">
              <input type="number" placeholder="SYS" {...register('blood_pressure_systolic', { valueAsNumber: true })} />
              <span className="quick-label">mmHg</span>
            </div>
            <span className="quick-separator">/</span>
            <div className="quick-input">
              <input type="number" placeholder="DIA" {...register('blood_pressure_diastolic', { valueAsNumber: true })} />
              <span className="quick-label">mmHg</span>
            </div>
            <div className="quick-input">
              <input type="number" placeholder="Pulse" {...register('pulse', { valueAsNumber: true })} />
              <span className="quick-label">bpm</span>
            </div>
          </div>
          <button type="submit" className="btn btn-add" disabled={createVital.isPending}>
            {createVital.isPending ? '...' : 'Save'}
          </button>
        </form>
      </div>

      <div className="dashboard-grid">
        {/* Open Tasks */}
        <div className="card">
          <div className="card-header">
            <h3>{t('nav.tasks')}</h3>
            <Link to="/tasks" className="card-link">View all</Link>
          </div>
          {openTasks.length === 0 ? (
            <p className="text-muted">{t('common.no_data')}</p>
          ) : (
            <div className="dash-list">
              {openTasks.slice(0, 5).map((task) => (
                <div key={task.id} className={`dash-item ${task.due_date && isPast(new Date(task.due_date)) ? 'status-abnormal' : ''}`}>
                  <span>☐ {task.title}</span>
                  {task.due_date && (
                    <span className="dash-meta">{format(new Date(task.due_date), 'MMM d')}</span>
                  )}
                </div>
              ))}
            </div>
          )}
        </div>

        {/* Upcoming Appointments */}
        <div className="card">
          <div className="card-header">
            <h3>{t('nav.appointments')}</h3>
            <Link to="/appointments" className="card-link">View all</Link>
          </div>
          {upcomingAppts.length === 0 ? (
            <p className="text-muted">{t('common.no_data')}</p>
          ) : (
            <div className="dash-list">
              {upcomingAppts.slice(0, 5).map((appt) => (
                <div key={appt.id} className="dash-item">
                  <span>{appt.title}</span>
                  <span className="dash-meta">
                    {format(new Date(appt.scheduled_at), 'MMM d, HH:mm')}
                  </span>
                </div>
              ))}
            </div>
          )}
        </div>

        {/* Active Medications */}
        <div className="card">
          <div className="card-header">
            <h3>{t('nav.medications')}</h3>
            <Link to="/medications" className="card-link">View all</Link>
          </div>
          {activeMeds.length === 0 ? (
            <p className="text-muted">{t('common.no_data')}</p>
          ) : (
            <div className="dash-list">
              {activeMeds.slice(0, 5).map((med) => (
                <div key={med.id} className="dash-item">
                  <span>{med.name}</span>
                  <span className="dash-meta">{[med.dosage, med.frequency].filter(Boolean).join(' · ')}</span>
                </div>
              ))}
            </div>
          )}
        </div>

        {/* Recent Vitals */}
        <div className="card">
          <div className="card-header">
            <h3>{t('vitals.title')}</h3>
            <Link to="/vitals" className="card-link">View all</Link>
          </div>
          {recentVitals.length === 0 ? (
            <p className="text-muted">{t('common.no_data')}</p>
          ) : (
            <div className="dash-list">
              {recentVitals.map((v) => (
                <div key={v.id} className="dash-item">
                  <span>
                    {v.blood_pressure_systolic && v.blood_pressure_diastolic
                      ? `BP ${v.blood_pressure_systolic}/${v.blood_pressure_diastolic}`
                      : v.weight ? `Weight ${v.weight}kg`
                      : v.body_temperature ? `Temp ${v.body_temperature}°`
                      : 'Vital'}
                    {v.pulse ? ` · ${v.pulse}bpm` : ''}
                  </span>
                  <span className="dash-meta">
                    {formatDistanceToNow(new Date(v.measured_at), { addSuffix: true })}
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
