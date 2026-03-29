import { useState } from 'react';
import { useTranslation } from 'react-i18next';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { useForm } from 'react-hook-form';
import { isPast, differenceInDays } from 'date-fns';
import { ProfileSelector } from '../components/ProfileSelector';
import { useDateFormat } from '../hooks/useDateLocale';
import { ConfirmDelete } from '../components/ConfirmDelete';
import { useProfiles } from '../hooks/useProfiles';
import { api } from '../api/client';

interface Task {
  id: string;
  title: string;
  due_date?: string;
  priority: string;
  status: string;
  done_at?: string;
  notes?: string;
}

const PRIORITIES = ['low', 'normal', 'high', 'urgent'];
const PRIORITY_COLORS: Record<string, string> = {
  low: 'badge-inactive', normal: 'badge-info', high: 'badge-missed', urgent: 'status-critical',
};

export function Tasks() {
  const { t } = useTranslation();
  const { fmt } = useDateFormat();
  const { data: profilesData } = useProfiles();
  const profiles = profilesData || [];
  const [selectedProfile, setSelectedProfile] = useState('');
  const [showOpen, setShowOpen] = useState(true);
  const [showForm, setShowForm] = useState(false);
  const [deleteTarget, setDeleteTarget] = useState<string | null>(null);
  const queryClient = useQueryClient();
  const profileId = selectedProfile || profiles[0]?.id || '';

  const { data, isLoading } = useQuery({
    queryKey: ['tasks', profileId, showOpen],
    queryFn: () => api.get<{ items: Task[] }>(
      `/api/v1/profiles/${profileId}/tasks${showOpen ? '/open' : ''}`
    ),
    enabled: !!profileId,
  });

  const createMutation = useMutation({
    mutationFn: (task: Partial<Task>) => api.post(`/api/v1/profiles/${profileId}/tasks`, task),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['tasks', profileId] });
      setShowForm(false);
      reset();
    },
  });

  const updateMutation = useMutation({
    mutationFn: ({ id, ...data }: { id: string } & Partial<Task>) =>
      api.patch(`/api/v1/profiles/${profileId}/tasks/${id}`, data),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['tasks', profileId] }),
  });

  const deleteMutation = useMutation({
    mutationFn: (id: string) => api.delete(`/api/v1/profiles/${profileId}/tasks/${id}`),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['tasks', profileId] }),
  });

  const { register, handleSubmit, reset } = useForm<Partial<Task>>();
  const items = data?.items || [];

  return (
    <div className="page">
      <div className="page-header">
        <h2>{t('nav.tasks')}</h2>
        <div className="page-actions">
          <ProfileSelector selectedId={profileId} onSelect={setSelectedProfile} />
          <label className="toggle-label">
            <input type="checkbox" checked={showOpen} onChange={(e) => setShowOpen(e.target.checked)} />
            {t('tasks.open_only')}
          </label>
          <button className="btn btn-add" onClick={() => setShowForm(!showForm)}>+ {t('common.add')}</button>
        </div>
      </div>

      {showForm && (
        <div className="modal-overlay" onClick={() => setShowForm(false)}>
          <div className="modal" onClick={(e) => e.stopPropagation()}>
            <div className="modal-header">
              <h3>{t('tasks.add')}</h3>
              <button className="btn-icon-sm" onClick={() => setShowForm(false)}>&times;</button>
            </div>
            <div className="modal-body">
              <form id="task-create-form" onSubmit={handleSubmit((data) => createMutation.mutate({ ...data, status: 'open' }))}>
                <div className="form-row">
                  <div className="form-group"><label>{t('common.title')} *</label><input type="text" {...register('title')} required /></div>
                  <div className="form-group"><label>{t('common.due_date')}</label><input type="date" {...register('due_date')} /></div>
                  <div className="form-group"><label>{t('common.priority')}</label>
                    <select {...register('priority')}>{PRIORITIES.map((p) => <option key={p} value={p}>{t('tasks.priority_' + p)}</option>)}</select>
                  </div>
                </div>
                <div className="form-group"><label>{t('common.notes')}</label><textarea rows={2} {...register('notes')} /></div>
              </form>
            </div>
            <div className="modal-footer">
              <button type="submit" form="task-create-form" className="btn btn-add" disabled={createMutation.isPending}>{t('common.save')}</button>
              <button type="button" className="btn btn-secondary" onClick={() => setShowForm(false)}>{t('common.cancel')}</button>
            </div>
          </div>
        </div>
      )}

      <div className="card">
        {isLoading ? <p>{t('common.loading')}</p> : items.length === 0 ? <p className="text-muted">{t('common.no_data')}</p> : (
          <div className="task-list">
            {items.map((task) => {
              const overdue = task.due_date && task.status === 'open' && isPast(new Date(task.due_date));
              const daysLeft = task.due_date ? differenceInDays(new Date(task.due_date), new Date()) : null;

              return (
                <div key={task.id} className={`task-item ${overdue ? 'task-overdue' : ''}`}>
                  <button
                    className={`task-check ${task.status === 'done' ? 'task-done' : ''}`}
                    onClick={() => updateMutation.mutate({
                      id: task.id,
                      status: task.status === 'done' ? 'open' : 'done',
                    })}
                  >
                    {task.status === 'done' ? '✓' : '○'}
                  </button>
                  <div className="task-info">
                    <div className={`task-title ${task.status === 'done' ? 'task-completed-text' : ''}`}>
                      {task.title}
                    </div>
                    <div className="task-meta">
                      {task.due_date && (
                        <span className={overdue ? 'status-abnormal' : daysLeft !== null && daysLeft <= 7 ? 'status-borderline' : ''}>
                          {fmt(task.due_date, 'dd. MMM yyyy')}
                          {overdue && ` ${t('tasks.overdue')}`}
                        </span>
                      )}
                    </div>
                  </div>
                  <div className="med-actions">
                    <span className={`badge ${PRIORITY_COLORS[task.priority] || 'badge-info'}`}>{t('tasks.priority_' + task.priority)}</span>
                    <button className="btn-icon-sm" onClick={() => setDeleteTarget(task.id)}>×</button>
                  </div>
                </div>
              );
            })}
          </div>
        )}
      </div>

      <ConfirmDelete
        open={!!deleteTarget}
        onConfirm={() => { deleteMutation.mutate(deleteTarget!); setDeleteTarget(null); }}
        onCancel={() => setDeleteTarget(null)}
        pending={deleteMutation.isPending}
      />
    </div>
  );
}
