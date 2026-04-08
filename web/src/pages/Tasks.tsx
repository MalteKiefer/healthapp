import { useState, useMemo } from 'react';
import { compareByColumn } from '../utils/sorting';
import { useTranslation } from 'react-i18next';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { useForm } from 'react-hook-form';
import { isPast, differenceInDays } from 'date-fns';
import { fixDates } from '../utils/dates';
import { ProfileSelector } from '../components/ProfileSelector';
import { useDateFormat } from '../hooks/useDateLocale';
import { ConfirmDelete } from '../components/ConfirmDelete';
import { useProfiles } from '../hooks/useProfiles';
import { api } from '../api/client';
import { tasksApi, type Task } from '../api/tasks';

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
  const [sortCol, setSortCol] = useState<string>('due_date');
  const [sortDir, setSortDir] = useState<'asc' | 'desc'>('asc');
  const [showForm, setShowForm] = useState(false);
  const [deleteTarget, setDeleteTarget] = useState<string | null>(null);
  const queryClient = useQueryClient();
  const profileId = selectedProfile || profiles[0]?.id || '';

  const { data, isLoading } = useQuery({
    queryKey: ['tasks', profileId, showOpen],
    queryFn: () => showOpen
      ? api.get<{ items: Task[] }>(`/api/v1/profiles/${profileId}/tasks/open`)
      : tasksApi.list(profileId),
    enabled: !!profileId,
  });

  const createMutation = useMutation({
    mutationFn: (task: Partial<Task>) => tasksApi.create(profileId, fixDates(task as Record<string, unknown>, ['due_date']) as Partial<Task>),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['tasks', profileId] });
      setShowForm(false);
      reset();
    },
  });

  const updateMutation = useMutation({
    mutationFn: ({ id, ...data }: { id: string } & Partial<Task>) =>
      tasksApi.update(profileId, id, fixDates(data as Record<string, unknown>, ['due_date']) as Partial<Task>),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['tasks', profileId] }),
  });

  const deleteMutation = useMutation({
    mutationFn: (id: string) => tasksApi.delete(profileId, id),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['tasks', profileId] }),
  });

  const { register, handleSubmit, reset } = useForm<Partial<Task>>();
  const items = data?.items || [];

  const sortedItems = useMemo(() => {
    const priorityOrder: Record<string, number> = { urgent: 0, high: 1, normal: 2, low: 3 };
    return [...items].sort((a, b) => {
      let aVal: unknown, bVal: unknown;
      if (sortCol === 'priority') {
        aVal = priorityOrder[a.priority] ?? 99;
        bVal = priorityOrder[b.priority] ?? 99;
      } else {
        return compareByColumn(a, b, sortCol, sortDir);
      }
      if (aVal == null && bVal == null) return 0;
      if (aVal == null) return 1;
      if (bVal == null) return -1;
      const cmp = typeof aVal === 'string' ? aVal.localeCompare(bVal as string) : (aVal as number) - (bVal as number);
      return sortDir === 'asc' ? cmp : -cmp;
    });
  }, [items, sortCol, sortDir]);

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
              <button className="btn-icon-sm" onClick={() => setShowForm(false)} aria-label={t('common.close')}>&times;</button>
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
          <>
          <div style={{ display: 'flex', gap: 8, marginBottom: 12, alignItems: 'center' }}>
            <span className="text-muted" style={{ fontSize: 12 }}>{t('common.sort')}:</span>
            <select className="metric-selector" value={sortCol} onChange={(e) => setSortCol(e.target.value)}>
              <option value="title">{t('common.title')}</option>
              <option value="due_date">{t('common.due_date')}</option>
              <option value="priority">{t('common.priority')}</option>
              <option value="status">{t('common.status')}</option>
            </select>
            <button className="btn-icon-sm" onClick={() => setSortDir(d => d === 'asc' ? 'desc' : 'asc')} aria-label={t('common.sort')}>
              {sortDir === 'asc' ? '↑' : '↓'}
            </button>
          </div>
          <div className="task-list">
            {sortedItems.map((task) => {
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
                    <button className="btn-icon-sm" onClick={() => setDeleteTarget(task.id)} aria-label={t('common.delete')}>×</button>
                  </div>
                </div>
              );
            })}
          </div>
          </>
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
