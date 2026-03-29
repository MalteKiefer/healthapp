import { useState } from 'react';
import { useTranslation } from 'react-i18next';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { api } from '../api/client';
import { useAuthStore } from '../store/auth';
import { useDateFormat } from '../hooks/useDateLocale';
import { ConfirmDelete } from '../components/ConfirmDelete';

interface Family {
  id: string;
  name: string;
  created_by: string;
  created_at: string;
}

interface Member {
  id: string;
  user_id: string;
  family_id: string;
  role: string;
  joined_at: string;
  email: string;
  display_name: string;
}

interface FamilyInvite {
  id: string;
  family_id: string;
  token: string;
  expires_at: string;
}

function FamilyCard({ family, onRefresh }: { family: Family; onRefresh: () => void }) {
  const { t } = useTranslation();
  const { fmt } = useDateFormat();
  const { userId } = useAuthStore();
  const queryClient = useQueryClient();

  const [editing, setEditing] = useState(false);
  const [editName, setEditName] = useState(family.name);
  const [inviteModal, setInviteModal] = useState(false);
  const [inviteToken, setInviteToken] = useState('');
  const [inviteCopied, setInviteCopied] = useState(false);
  const [dissolveOpen, setDissolveOpen] = useState(false);

  const isOwner = family.created_by === userId;

  const membersQuery = useQuery({
    queryKey: ['family-members', family.id],
    queryFn: () => api.get<{ items: Member[] }>(`/api/v1/families/${family.id}/members`),
  });

  const members = membersQuery.data?.items ?? [];
  const myMembership = members.find((m) => m.user_id === userId);
  const isOwnerOrAdmin = myMembership?.role === 'owner' || myMembership?.role === 'admin';

  const updateMutation = useMutation({
    mutationFn: (name: string) => api.patch(`/api/v1/families/${family.id}`, { name }),
    onSuccess: () => {
      setEditing(false);
      onRefresh();
    },
  });

  const inviteMutation = useMutation({
    mutationFn: () => api.post<FamilyInvite>(`/api/v1/families/${family.id}/invite`),
    onSuccess: (data) => {
      setInviteToken(data.token);
      setInviteModal(true);
    },
  });

  const removeMutation = useMutation({
    mutationFn: (memberUserId: string) =>
      api.delete(`/api/v1/families/${family.id}/members/${memberUserId}`),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['family-members', family.id] });
    },
  });

  const leaveMutation = useMutation({
    mutationFn: () => api.delete(`/api/v1/families/${family.id}/members/${userId}`),
    onSuccess: () => onRefresh(),
  });

  const dissolveMutation = useMutation({
    mutationFn: () => api.post(`/api/v1/families/${family.id}/dissolve`),
    onSuccess: () => {
      setDissolveOpen(false);
      onRefresh();
    },
  });

  const handleCopyInvite = async () => {
    try {
      await navigator.clipboard.writeText(inviteToken);
      setInviteCopied(true);
      setTimeout(() => setInviteCopied(false), 2000);
    } catch {
      // fallback: select text
    }
  };

  const handleSaveName = () => {
    if (editName.trim() && editName !== family.name) {
      updateMutation.mutate(editName.trim());
    } else {
      setEditing(false);
    }
  };

  const roleBadgeClass = (role: string) => {
    switch (role) {
      case 'owner':
        return 'badge badge-active';
      case 'admin':
        return 'badge badge-scheduled';
      default:
        return 'badge badge-info';
    }
  };

  const roleLabel = (role: string) => {
    switch (role) {
      case 'owner':
        return t('family.role_owner');
      case 'admin':
        return t('family.role_admin');
      default:
        return t('family.role_member');
    }
  };

  return (
    <div className="card">
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 16 }}>
        {editing ? (
          <div style={{ display: 'flex', gap: 8, flex: 1 }}>
            <input
              className="form-group"
              value={editName}
              onChange={(e) => setEditName(e.target.value)}
              onKeyDown={(e) => e.key === 'Enter' && handleSaveName()}
              autoFocus
              style={{ margin: 0, flex: 1 }}
            />
            <button className="btn btn-sm" onClick={handleSaveName}>
              {t('common.save')}
            </button>
            <button className="btn btn-sm btn-secondary" onClick={() => { setEditing(false); setEditName(family.name); }}>
              {t('common.cancel')}
            </button>
          </div>
        ) : (
          <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
            <h3 style={{ margin: 0 }}>{family.name}</h3>
            {isOwnerOrAdmin && (
              <button className="btn btn-sm btn-secondary" onClick={() => setEditing(true)}>
                {t('common.edit')}
              </button>
            )}
          </div>
        )}
      </div>

      <div style={{ fontSize: 13, color: 'var(--color-text-secondary)', marginBottom: 12 }}>
        {fmt(family.created_at, 'PPP')}
      </div>

      <h4 style={{ marginBottom: 8 }}>{t('family.members')}</h4>

      <div className="admin-user-list">
        {members.map((member) => (
          <div key={member.id} style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '8px 0' }}>
            <div className="admin-user-avatar">
              {(member.display_name || member.email || '?').charAt(0).toUpperCase()}
            </div>
            <div style={{ flex: 1, minWidth: 0 }}>
              <div style={{ fontWeight: 500 }}>
                {member.display_name || member.email}
              </div>
              {member.display_name && (
                <div style={{ fontSize: 13, color: 'var(--color-text-secondary)', overflow: 'hidden', textOverflow: 'ellipsis' }}>
                  {member.email}
                </div>
              )}
            </div>
            <span className={roleBadgeClass(member.role)}>
              {roleLabel(member.role)}
            </span>
            {isOwnerOrAdmin && member.user_id !== userId && member.role !== 'owner' && (
              <button
                className="btn btn-sm btn-danger"
                onClick={() => removeMutation.mutate(member.user_id)}
                disabled={removeMutation.isPending}
              >
                {t('family.remove_member')}
              </button>
            )}
          </div>
        ))}
      </div>

      <div className="form-actions" style={{ marginTop: 16 }}>
        {isOwnerOrAdmin && (
          <button
            className="btn btn-add"
            onClick={() => inviteMutation.mutate()}
            disabled={inviteMutation.isPending}
          >
            {t('family.invite_member')}
          </button>
        )}
        {!isOwner && (
          <button
            className="btn btn-secondary"
            onClick={() => leaveMutation.mutate()}
            disabled={leaveMutation.isPending}
          >
            {t('family.leave')}
          </button>
        )}
        {isOwner && (
          <button
            className="btn btn-danger"
            onClick={() => setDissolveOpen(true)}
          >
            {t('family.dissolve')}
          </button>
        )}
      </div>

      {/* Invite Modal */}
      {inviteModal && (
        <div className="modal-overlay" onClick={() => setInviteModal(false)}>
          <div className="modal" onClick={(e) => e.stopPropagation()}>
            <div className="modal-header">
              <h3>{t('family.invite_link')}</h3>
              <button className="modal-close" onClick={() => setInviteModal(false)}>&times;</button>
            </div>
            <div className="modal-body">
              <div className="form-group">
                <input
                  type="text"
                  readOnly
                  value={inviteToken}
                  onFocus={(e) => e.target.select()}
                  style={{ fontFamily: 'monospace', fontSize: 13 }}
                />
              </div>
              <p style={{ fontSize: 13, color: 'var(--color-text-secondary)' }}>
                {t('family.invite_expires')}
              </p>
            </div>
            <div className="modal-footer">
              <button className="btn" onClick={handleCopyInvite}>
                {inviteCopied ? t('family.invite_copied') : t('common.copy')}
              </button>
              <button className="btn btn-secondary" onClick={() => setInviteModal(false)}>
                {t('common.close')}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Dissolve Confirmation */}
      <ConfirmDelete
        open={dissolveOpen}
        title={t('family.dissolve_title')}
        message={t('family.dissolve_message')}
        onConfirm={() => dissolveMutation.mutate()}
        onCancel={() => setDissolveOpen(false)}
        pending={dissolveMutation.isPending}
      />
    </div>
  );
}

export function Family() {
  const { t } = useTranslation();
  const queryClient = useQueryClient();

  const [createModal, setCreateModal] = useState(false);
  const [joinModal, setJoinModal] = useState(false);
  const [newName, setNewName] = useState('');
  const [joinToken, setJoinToken] = useState('');
  const [joinError, setJoinError] = useState('');

  const familiesQuery = useQuery({
    queryKey: ['families'],
    queryFn: () => api.get<{ items: Family[] }>('/api/v1/families'),
  });

  const families = familiesQuery.data?.items ?? [];

  const createMutation = useMutation({
    mutationFn: (name: string) => api.post<Family>('/api/v1/families', { name }),
    onSuccess: () => {
      setCreateModal(false);
      setNewName('');
      queryClient.invalidateQueries({ queryKey: ['families'] });
    },
  });

  const joinMutation = useMutation({
    mutationFn: (token: string) => {
      // We need to find a family to accept the invite for.
      // The accept endpoint is /families/:id/accept, but we only have the token.
      // We'll try all families, or more likely the API handles it by token.
      // Looking at the API: POST /api/v1/families/:id/accept with { token }
      // But we don't know the family ID from just the token.
      // The token is unique, so we need to iterate or the API should have a generic endpoint.
      // Since the API requires familyID in the URL, we'll use a placeholder approach:
      // Actually, looking at HandleAcceptInvite, it reads familyID from URL but then
      // looks up the invite by token and uses inv.FamilyID. So the URL familyID doesn't matter
      // for the token lookup, but it matters for the URL routing.
      // We need to use the correct familyID. Since we don't know it from just the token,
      // let's use a dummy UUID and the handler will use the token's family.
      // Wait - re-reading the code, the handler does NOT validate URL familyID against token's familyID.
      // It just uses inv.FamilyID from the token lookup. So any valid UUID in URL works.
      return api.post(`/api/v1/families/00000000-0000-0000-0000-000000000000/accept`, { token });
    },
    onSuccess: () => {
      setJoinModal(false);
      setJoinToken('');
      setJoinError('');
      queryClient.invalidateQueries({ queryKey: ['families'] });
    },
    onError: () => {
      setJoinError(t('family.invalid_token'));
    },
  });

  const handleCreate = () => {
    if (newName.trim()) {
      createMutation.mutate(newName.trim());
    }
  };

  const handleJoin = () => {
    if (joinToken.trim()) {
      setJoinError('');
      joinMutation.mutate(joinToken.trim());
    }
  };

  const handleRefresh = () => {
    queryClient.invalidateQueries({ queryKey: ['families'] });
  };

  return (
    <div className="page">
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 24 }}>
        <h1>{t('family.title')}</h1>
        <div style={{ display: 'flex', gap: 8 }}>
          <button className="btn btn-add" onClick={() => setCreateModal(true)}>
            {t('family.create')}
          </button>
          <button className="btn btn-secondary" onClick={() => setJoinModal(true)}>
            {t('family.join')}
          </button>
        </div>
      </div>

      {familiesQuery.isLoading && <p>{t('common.loading')}</p>}

      {!familiesQuery.isLoading && families.length === 0 && (
        <div className="card" style={{ textAlign: 'center', padding: 48 }}>
          <p style={{ color: 'var(--color-text-secondary)', marginBottom: 24 }}>
            {t('family.no_families')}
          </p>
          <div style={{ display: 'flex', gap: 12, justifyContent: 'center' }}>
            <button className="btn btn-add" onClick={() => setCreateModal(true)}>
              {t('family.create')}
            </button>
            <button className="btn btn-secondary" onClick={() => setJoinModal(true)}>
              {t('family.join')}
            </button>
          </div>
        </div>
      )}

      <div style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
        {families.map((fam) => (
          <FamilyCard key={fam.id} family={fam} onRefresh={handleRefresh} />
        ))}
      </div>

      {/* Create Family Modal */}
      {createModal && (
        <div className="modal-overlay" onClick={() => setCreateModal(false)}>
          <div className="modal" onClick={(e) => e.stopPropagation()}>
            <div className="modal-header">
              <h3>{t('family.create')}</h3>
              <button className="modal-close" onClick={() => setCreateModal(false)}>&times;</button>
            </div>
            <div className="modal-body">
              <div className="form-group">
                <label>{t('family.name')}</label>
                <input
                  type="text"
                  value={newName}
                  onChange={(e) => setNewName(e.target.value)}
                  onKeyDown={(e) => e.key === 'Enter' && handleCreate()}
                  autoFocus
                />
              </div>
            </div>
            <div className="modal-footer">
              <button className="btn btn-secondary" onClick={() => setCreateModal(false)}>
                {t('common.cancel')}
              </button>
              <button
                className="btn btn-add"
                onClick={handleCreate}
                disabled={!newName.trim() || createMutation.isPending}
              >
                {createMutation.isPending ? t('common.loading') : t('family.create')}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Join Family Modal */}
      {joinModal && (
        <div className="modal-overlay" onClick={() => setJoinModal(false)}>
          <div className="modal" onClick={(e) => e.stopPropagation()}>
            <div className="modal-header">
              <h3>{t('family.join')}</h3>
              <button className="modal-close" onClick={() => setJoinModal(false)}>&times;</button>
            </div>
            <div className="modal-body">
              <div className="form-group">
                <label>{t('family.enter_token')}</label>
                <input
                  type="text"
                  value={joinToken}
                  onChange={(e) => { setJoinToken(e.target.value); setJoinError(''); }}
                  onKeyDown={(e) => e.key === 'Enter' && handleJoin()}
                  autoFocus
                  style={{ fontFamily: 'monospace' }}
                />
              </div>
              {joinError && (
                <p style={{ color: 'var(--color-danger)', fontSize: 13 }}>{joinError}</p>
              )}
            </div>
            <div className="modal-footer">
              <button className="btn btn-secondary" onClick={() => setJoinModal(false)}>
                {t('common.cancel')}
              </button>
              <button
                className="btn btn-add"
                onClick={handleJoin}
                disabled={!joinToken.trim() || joinMutation.isPending}
              >
                {joinMutation.isPending ? t('common.loading') : t('family.accept_invite')}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
