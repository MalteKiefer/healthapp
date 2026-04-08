import React, { useState, useEffect, useRef, useCallback } from 'react';
import { useTranslation } from 'react-i18next';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { useNavigate } from 'react-router-dom';
import Cropper from 'react-easy-crop';
import QRCode from 'qrcode';
import { api } from '../api/client';
import { ConfirmDelete } from '../components/ConfirmDelete';
import { useUIStore } from '../store/ui';
import { useAuthStore } from '../store/auth';
import { useProfiles } from '../hooks/useProfiles';
import type { Profile } from '../api/profiles';
import { useDateFormat } from '../hooks/useDateLocale';
import {
  deriveAuthHash,
  clearAllKeys,
  generateProfileKey,
  getIdentityPrivateKey,
  setProfileKey,
  getProfileKey,
  createKeyGrant,
  ensureProfileKey,
} from '../crypto';
import { formatNumber } from '../utils/format';

// ── Types ──

interface UserPreferences {
  language: string;
  date_format: string;
  weight_unit: string;
  height_unit: string;
  temperature_unit: string;
  blood_glucose_unit: string;
}

interface NotificationPreferences {
  vaccination_due: boolean;
  medication_reminder: boolean;
  lab_result_abnormal: boolean;
  emergency_access: boolean;
  export_ready: boolean;
  family_invite: boolean;
  session_new: boolean;
  storage_quota_warning: boolean;
}

const NOTIF_KEYS: (keyof NotificationPreferences)[] = [
  'vaccination_due', 'medication_reminder', 'lab_result_abnormal', 'emergency_access',
  'export_ready', 'family_invite', 'session_new', 'storage_quota_warning',
];

const NOTIF_LABEL_MAP: Record<keyof NotificationPreferences, string> = {
  vaccination_due: 'settings.notif_vaccination_due',
  medication_reminder: 'settings.notif_medication_reminder',
  lab_result_abnormal: 'settings.notif_lab_abnormal',
  emergency_access: 'settings.notif_emergency',
  export_ready: 'settings.notif_export_ready',
  family_invite: 'settings.notif_family_invite',
  session_new: 'settings.notif_session_new',
  storage_quota_warning: 'settings.notif_storage_warning',
};

interface SessionInfo {
  id: string;
  device_hint: string;
  ip_address: string;
  created_at: string;
  last_active_at: string;
  is_current: boolean;
}

interface UserInfo {
  id: string;
  email: string;
  display_name: string;
  role: string;
  totp_enabled: boolean;
  identity_pubkey: string;
}

interface CropArea { x: number; y: number; width: number; height: number }

// ── Helpers ──

const svgProps = { width: 20, height: 20, viewBox: '0 0 24 24', fill: 'none', stroke: 'currentColor', strokeWidth: 1.5, strokeLinecap: 'round' as const, strokeLinejoin: 'round' as const };

function parseDevice(hint: string): { name: string; icon: React.ReactNode } {
  const h = (hint || '').toLowerCase();
  if (h.includes('mobile') || h.includes('android') || h.includes('iphone'))
    return { name: hint.split(' ')[0] || 'Mobile', icon: <svg {...svgProps}><rect x="5" y="2" width="14" height="20" rx="2" /><line x1="12" y1="18" x2="12.01" y2="18" /></svg> };
  if (h.includes('tablet') || h.includes('ipad'))
    return { name: 'Tablet', icon: <svg {...svgProps}><rect x="4" y="2" width="16" height="20" rx="2" /><line x1="12" y1="18" x2="12.01" y2="18" /></svg> };
  return { name: hint ? hint.substring(0, 40) : 'Desktop', icon: <svg {...svgProps}><rect x="2" y="3" width="20" height="14" rx="2" /><line x1="8" y1="21" x2="16" y2="21" /><line x1="12" y1="17" x2="12" y2="21" /></svg> };
}

async function getCroppedImg(src: string, crop: CropArea): Promise<string> {
  const img = new Image();
  img.src = src;
  await new Promise((r) => { img.onload = r; });
  const canvas = document.createElement('canvas');
  const size = 256;
  canvas.width = size;
  canvas.height = size;
  const ctx = canvas.getContext('2d')!;
  ctx.drawImage(img, crop.x, crop.y, crop.width, crop.height, 0, 0, size, size);
  return canvas.toDataURL('image/jpeg', 0.85);
}

// ── Component ──

export function Settings() {
  const { t, i18n } = useTranslation();
  const { fmt, relative } = useDateFormat();
  const { theme, toggleTheme } = useUIStore();
  const { email, userId, logout } = useAuthStore();
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const fileInputRef = useRef<HTMLInputElement>(null);

  // Profile management state
  const { data: profilesData } = useProfiles();
  const profiles: Profile[] = profilesData || [];
  const [selectedProfileId, setSelectedProfileId] = useState<string>('');
  const [transferUserId, setTransferUserId] = useState('');
  const [showTransferModal, setShowTransferModal] = useState(false);
  const [pickedFamilyMember, setPickedFamilyMember] = useState(''); // "familyId:userId"
  const [profileMsg, setProfileMsg] = useState('');

  // New profile form state
  const [showCreateProfile, setShowCreateProfile] = useState(false);
  const [newProfileName, setNewProfileName] = useState('');
  const [newProfileDOB, setNewProfileDOB] = useState('');
  const [newProfileSex, setNewProfileSex] = useState('unspecified');

  const selectedProfile = profiles.find((p) => p.id === selectedProfileId);
  const isProfileOwner = selectedProfile?.owner_user_id === userId;

  const createProfileMutation = useMutation({
    mutationFn: async (body: { display_name: string; date_of_birth?: string; biological_sex: string }) => {
      // E2E profile key: generated client-side, self-grant wraps it for the
      // owner via ECDH. Server never sees the plaintext profile key.
      const idPriv = getIdentityPrivateKey();
      const myPubkey = userInfo?.identity_pubkey;
      if (!idPriv || !myPubkey || !userId) {
        // Missing crypto material — fall back to plain create so the feature
        // still works for users without keys unwrapped (legacy sessions).
        return api.post<Profile>('/api/v1/profiles', body);
      }
      const profileKey = await generateProfileKey();
      const wrapped = await createKeyGrant(profileKey, idPriv, myPubkey, `selfgrant:${userId}`);
      const created = await api.post<Profile>('/api/v1/profiles', {
        ...body,
        self_grant: { encrypted_key: wrapped },
      });
      setProfileKey(created.id, profileKey);
      return created;
    },
    onSuccess: (created) => {
      queryClient.invalidateQueries({ queryKey: ['profiles'] });
      setSelectedProfileId(created.id);
      setShowCreateProfile(false);
      setNewProfileName('');
      setNewProfileDOB('');
      setNewProfileSex('unspecified');
      setProfileMsg(t('settings.profile_created'));
    },
  });

  const archiveMutation = useMutation({
    mutationFn: (profileId: string) => api.post(`/api/v1/profiles/${profileId}/archive`),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['profiles'] });
      setProfileMsg(t('settings.profile_archived'));
    },
  });

  const unarchiveMutation = useMutation({
    mutationFn: (profileId: string) => api.post(`/api/v1/profiles/${profileId}/unarchive`),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['profiles'] });
      setProfileMsg(t('settings.profile_unarchived'));
    },
  });

  const transferMutation = useMutation({
    mutationFn: ({ profileId, newOwnerUserId }: { profileId: string; newOwnerUserId: string }) =>
      api.post(`/api/v1/profiles/${profileId}/transfer`, { new_owner_user_id: newOwnerUserId }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['profiles'] });
      setShowTransferModal(false);
      setTransferUserId('');
      setProfileMsg(t('settings.transfer_success'));
    },
  });

  const grantMutation = useMutation({
    mutationFn: async (args: {
      profileId: string;
      granteeUserId: string;
      granteeIdentityPubkey: string;
      familyId: string;
    }) => {
      const idPriv = getIdentityPrivateKey();
      const cachedKey = getProfileKey(args.profileId);
      if (!idPriv) throw new Error('identity_key_unavailable');
      if (!cachedKey) throw new Error('profile_key_unavailable');
      if (!userId) throw new Error('no_user_id');
      const ctx = `${args.profileId}:${userId}:${args.granteeUserId}`;
      const wrapped = await createKeyGrant(cachedKey, idPriv, args.granteeIdentityPubkey, ctx);
      return api.post(`/api/v1/profiles/${args.profileId}/grants`, {
        grantee_user_id: args.granteeUserId,
        encrypted_key: wrapped,
        grant_signature: '',
        via_family_id: args.familyId,
      });
    },
    onSuccess: () => {
      setPickedFamilyMember('');
      setProfileMsg(t('settings.grant_success'));
      if (selectedProfileId) {
        queryClient.invalidateQueries({ queryKey: ['profile-grants', selectedProfileId] });
      }
    },
    onError: (e) => {
      setProfileMsg((e as Error).message || t('settings.grant_failed'));
    },
  });

  const revokeGrantMutation = useMutation({
    mutationFn: ({ profileId, granteeUserId }: { profileId: string; granteeUserId: string }) =>
      api.delete(`/api/v1/profiles/${profileId}/grants/${granteeUserId}`),
    onSuccess: () => {
      setProfileMsg(t('settings.revoke_success'));
      if (selectedProfileId) {
        queryClient.invalidateQueries({ queryKey: ['profile-grants', selectedProfileId] });
      }
    },
  });

  // Queries
  const { data: userInfo, isLoading: userInfoLoading, isError: userInfoError } = useQuery({
    queryKey: ['me'],
    queryFn: () => api.get<UserInfo>('/api/v1/users/me'),
  });

  const { data: prefs } = useQuery({
    queryKey: ['preferences'],
    queryFn: () => api.get<UserPreferences>('/api/v1/users/me/preferences'),
  });

  const { data: sessionsData } = useQuery({
    queryKey: ['sessions'],
    queryFn: () => api.get<{ sessions: SessionInfo[] }>('/api/v1/users/me/sessions'),
  });
  const sessions = sessionsData?.sessions || [];

  const { data: storage } = useQuery({
    queryKey: ['storage'],
    queryFn: () => api.get<{ used_bytes: number; quota_bytes: number }>('/api/v1/users/me/storage'),
  });

  const { data: policy } = useQuery({
    queryKey: ['auth-policy'],
    queryFn: () => api.get<{ min_passphrase_length: number; require_uppercase: boolean; require_lowercase: boolean; require_numbers: boolean; require_symbols: boolean }>('/api/v1/auth/policy'),
  });
  const minPassLen = policy?.min_passphrase_length || 12;

  const { data: notifPrefs } = useQuery({
    queryKey: ['notification-preferences'],
    queryFn: () => api.get<NotificationPreferences>('/api/v1/notifications/preferences'),
  });

  // ── Family sharing data ──
  interface FamilySummary { id: string; name: string }
  interface FamilyMember { user_id: string; display_name: string; email: string; family_id: string; family_name?: string }
  interface GrantRow {
    id: string;
    grantee_user_id: string;
    granted_at: string;
    via_family_id?: string;
    email: string;
    display_name: string;
  }

  const { data: familiesData } = useQuery({
    queryKey: ['families'],
    queryFn: () => api.get<{ items: FamilySummary[] }>('/api/v1/families'),
  });
  const families = familiesData?.items || [];

  const memberQueries = useQuery({
    queryKey: ['family-members-all', families.map((f) => f.id).join(',')],
    enabled: families.length > 0,
    queryFn: async () => {
      const all: FamilyMember[] = [];
      for (const f of families) {
        const res = await api.get<{ items: Array<{ user_id: string; display_name: string; email: string }> }>(
          `/api/v1/families/${f.id}/members`,
        );
        for (const m of res.items) {
          all.push({ ...m, family_id: f.id, family_name: f.name });
        }
      }
      return all;
    },
  });
  const allFamilyMembers = memberQueries.data || [];

  const { data: grantsData } = useQuery({
    queryKey: ['profile-grants', selectedProfileId],
    enabled: !!selectedProfileId,
    queryFn: () => api.get<{ items: GrantRow[] }>(`/api/v1/profiles/${selectedProfileId}/grants`),
  });
  const currentGrants = grantsData?.items || [];
  const grantedUserIds = new Set(currentGrants.map((g) => g.grantee_user_id));

  // Family members minus self, minus those who already have a grant for the
  // selected profile. Deduped across families by user_id.
  const shareablePeople = (() => {
    const seen = new Set<string>();
    const out: FamilyMember[] = [];
    for (const m of allFamilyMembers) {
      if (m.user_id === userId) continue;
      if (grantedUserIds.has(m.user_id)) continue;
      if (seen.has(m.user_id)) continue;
      seen.add(m.user_id);
      out.push(m);
    }
    return out;
  })();

  // Mutations
  const updateNotifPrefs = useMutation({
    mutationFn: (data: Partial<NotificationPreferences>) =>
      api.patch('/api/v1/notifications/preferences', data),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['notification-preferences'] }),
  });

  const updatePrefs = useMutation({
    mutationFn: (data: Partial<UserPreferences>) => api.patch('/api/v1/users/me/preferences', data),
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

  const changePassMut = useMutation({
    mutationFn: (data: { current_auth_hash: string; new_auth_hash: string }) =>
      api.post('/api/v1/users/me/change-passphrase', data),
  });

  const setup2FAMut = useMutation({
    mutationFn: () => api.get<{ secret: string; provisioning_uri: string }>('/api/v1/auth/2fa/setup'),
  });

  const enable2FAMut = useMutation({
    mutationFn: (code: string) => api.post('/api/v1/auth/2fa/enable', { code }),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['me'] }),
  });

  const disable2FAMut = useMutation({
    mutationFn: (code: string) => api.post('/api/v1/auth/2fa/disable', { code }),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['me'] }),
  });

  const updateDisplayName = useMutation({
    mutationFn: (data: { display_name: string }) => api.patch('/api/v1/users/me', data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['me'] });
      setDisplayNameDirty(false);
    },
  });

  const deleteAccountMut = useMutation({
    mutationFn: () => api.delete('/api/v1/users/me'),
    onSuccess: () => {
      localStorage.clear();
      navigate('/login');
    },
  });

  // Preferences state
  const [language, setLanguage] = useState(prefs?.language || 'en');
  const [dateFormat, setDateFormat] = useState(prefs?.date_format || 'DMY');
  const [weightUnit, setWeightUnit] = useState(prefs?.weight_unit || 'kg');
  const [tempUnit, setTempUnit] = useState(prefs?.temperature_unit || 'celsius');
  const [glucoseUnit, setGlucoseUnit] = useState(prefs?.blood_glucose_unit || 'mmol_l');

  // Avatar state
  const [avatarUrl, setAvatarUrl] = useState<string | null>(localStorage.getItem('user_avatar'));
  const [cropSrc, setCropSrc] = useState<string | null>(null);
  const [crop, setCrop] = useState({ x: 0, y: 0 });
  const [zoom, setZoom] = useState(1);
  const [croppedArea, setCroppedArea] = useState<CropArea | null>(null);

  // Modal state
  const [showPassModal, setShowPassModal] = useState(false);
  const [currentPass, setCurrentPass] = useState('');
  const [newPass, setNewPass] = useState('');
  const [confirmPass, setConfirmPass] = useState('');
  const [passError, setPassError] = useState('');

  const [show2FAModal, setShow2FAModal] = useState(false);
  const [totpSetup, setTotpSetup] = useState<{ secret: string; provisioning_uri: string } | null>(null);
  const [totpQrDataUrl, setTotpQrDataUrl] = useState<string | null>(null);
  const [totpCode, setTotpCode] = useState('');
  const [showDisable2FA, setShowDisable2FA] = useState(false);
  const [disableCode, setDisableCode] = useState('');
  const [totpError, setTotpError] = useState('');

  // Recovery codes state
  const [showRecoveryCodes, setShowRecoveryCodes] = useState(false);
  const [recoveryCodes, setRecoveryCodes] = useState<string[]>([]);
  const [recoveryLoading, setRecoveryLoading] = useState(false);

  // Display name state
  const [displayName, setDisplayName] = useState('');
  const [displayNameDirty, setDisplayNameDirty] = useState(false);

  // Delete account state
  const [showDeleteAccount, setShowDeleteAccount] = useState(false);

  useEffect(() => {
    if (prefs) {
      setLanguage(prefs.language);
      setDateFormat(prefs.date_format);
      setWeightUnit(prefs.weight_unit);
      setTempUnit(prefs.temperature_unit);
      setGlucoseUnit(prefs.blood_glucose_unit);
    }
  }, [prefs]);

  useEffect(() => {
    if (userInfo && !displayNameDirty) {
      setDisplayName(userInfo.display_name || '');
    }
  }, [userInfo, displayNameDirty]);

  // Handlers
  const handleSavePrefs = () => {
    i18n.changeLanguage(language);
    localStorage.setItem('language', language);
    updatePrefs.mutate({ language, date_format: dateFormat, weight_unit: weightUnit, temperature_unit: tempUnit, blood_glucose_unit: glucoseUnit });
  };

  const handleAvatarSelect = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;
    if (file.size > 5 * 1048576) { alert(t('settings.avatar_too_large')); return; }
    const reader = new FileReader();
    reader.onload = () => setCropSrc(reader.result as string);
    reader.readAsDataURL(file);
    e.target.value = '';
  };

  const onCropComplete = useCallback((_: unknown, area: CropArea) => setCroppedArea(area), []);

  const handleCropSave = async () => {
    if (!cropSrc || !croppedArea) return;
    const dataUrl = await getCroppedImg(cropSrc, croppedArea);
    localStorage.setItem('user_avatar', dataUrl);
    setAvatarUrl(dataUrl);
    window.dispatchEvent(new Event('avatar-changed'));
    setCropSrc(null);
  };

  const handleAvatarRemove = () => {
    localStorage.removeItem('user_avatar');
    setAvatarUrl(null);
    window.dispatchEvent(new Event('avatar-changed'));
  };

  const handleChangePass = async () => {
    setPassError('');
    if (newPass !== confirmPass) { setPassError(t('settings.passphrase_mismatch')); return; }
    if (newPass.length < minPassLen) { setPassError(t('settings.passphrase_too_short', { min: minPassLen })); return; }
    if (policy?.require_uppercase && !/[A-Z]/.test(newPass)) { setPassError(t('settings.pass_need_upper')); return; }
    if (policy?.require_lowercase && !/[a-z]/.test(newPass)) { setPassError(t('settings.pass_need_lower')); return; }
    if (policy?.require_numbers && !/[0-9]/.test(newPass)) { setPassError(t('settings.pass_need_number')); return; }
    if (policy?.require_symbols && !/[!@#$%^&*()_+\-=\[\]{};':"\\|,.<>\/?]/.test(newPass)) { setPassError(t('settings.pass_need_symbol')); return; }
    try {
      const currentHash = await deriveAuthHash(currentPass, email || '');
      const newHash = await deriveAuthHash(newPass, email || '');
      await changePassMut.mutateAsync({ current_auth_hash: currentHash, new_auth_hash: newHash });
      setShowPassModal(false);
      setCurrentPass(''); setNewPass(''); setConfirmPass('');
      setTimeout(() => { clearAllKeys(); logout(); queryClient.clear(); navigate('/login'); }, 1500);
    } catch {
      setPassError(t('settings.passphrase_wrong'));
    }
  };

  const handleSetup2FA = async () => {
    setTotpError('');
    try {
      const data = await setup2FAMut.mutateAsync();
      setTotpSetup(data);
      setTotpCode('');
      const qrUrl = await QRCode.toDataURL(data.provisioning_uri, { width: 240, margin: 2 });
      setTotpQrDataUrl(qrUrl);
      setShow2FAModal(true);
    } catch {
      setTotpError(t('common.error'));
    }
  };

  const handleEnable2FA = async () => {
    setTotpError('');
    try {
      await enable2FAMut.mutateAsync(totpCode);
      setShow2FAModal(false);
      setTotpSetup(null);
    } catch {
      setTotpError(t('common.error'));
    }
  };

  const handleDisable2FA = async () => {
    setTotpError('');
    try {
      await disable2FAMut.mutateAsync(disableCode);
      setShowDisable2FA(false);
      setDisableCode('');
    } catch {
      setTotpError(t('common.error'));
    }
  };

  const handleRegenerateRecoveryCodes = async () => {
    setTotpError('');
    setRecoveryLoading(true);
    try {
      const data = await api.get<{ codes: string[] }>('/api/v1/auth/2fa/recovery-codes');
      setRecoveryCodes(data.codes);
      setShowRecoveryCodes(true);
    } catch {
      setTotpError(t('common.error'));
    }
    setRecoveryLoading(false);
  };

  const handleCopyRecoveryCodes = () => {
    navigator.clipboard.writeText(recoveryCodes.join('\n'));
  };

  const initials = email ? email.charAt(0).toUpperCase() : 'U';
  const usedMB = storage ? formatNumber(storage.used_bytes / 1048576, 1) : '0';
  const quotaMB = storage ? formatNumber(storage.quota_bytes / 1048576, 0) : '5120';
  const usagePercent = storage ? (storage.used_bytes / storage.quota_bytes * 100) : 0;
  const is2FA = userInfo?.totp_enabled ?? false;

  if (userInfoLoading) return <p>{t('common.loading')}</p>;
  if (userInfoError) return <p className="text-muted">{t('common.error')}</p>;

  return (
    <div className="page">
      <h2>{t('settings.title')}</h2>

      {/* ── Avatar ── */}
      <div className="card settings-section">
        <h3>{t('settings.avatar')}</h3>
        <div className="avatar-upload-row">
          <div className="avatar-upload-preview">
            {avatarUrl ? <img src={avatarUrl} alt={t('settings.avatar')} className="avatar-upload-img" /> : <div className="avatar-upload-placeholder">{initials}</div>}
          </div>
          <div className="avatar-upload-actions">
            <div style={{ display: 'flex', gap: 8 }}>
              <button className="btn btn-secondary" onClick={() => fileInputRef.current?.click()}>{t('settings.avatar_upload')}</button>
              {avatarUrl && <button className="btn btn-secondary" onClick={handleAvatarRemove}>{t('settings.avatar_remove')}</button>}
            </div>
            <input ref={fileInputRef} type="file" accept="image/jpeg,image/png,image/webp" hidden onChange={handleAvatarSelect} />
            <span className="text-muted" style={{ fontSize: 12 }}>{t('settings.avatar_hint')}</span>
          </div>
        </div>
      </div>

      {/* ── Display Name ── */}
      <div className="card settings-section">
        <h3>{t('settings.display_name')}</h3>
        <div className="form-row">
          <div className="form-group" style={{ flex: 1 }}>
            <label>{t('settings.display_name')}</label>
            <input
              type="text"
              value={displayName}
              onChange={(e) => { setDisplayName(e.target.value); setDisplayNameDirty(true); }}
              placeholder={email || ''}
            />
          </div>
        </div>
        <button
          className="btn btn-add"
          style={{ width: 'auto' }}
          onClick={() => updateDisplayName.mutate({ display_name: displayName })}
          disabled={updateDisplayName.isPending || !displayNameDirty}
        >
          {updateDisplayName.isPending ? t('common.loading') : t('common.save')}
        </button>
      </div>

      {/* ── Appearance ── */}
      <div className="card settings-section">
        <h3>{t('settings.appearance')}</h3>
        <div className="setting-row">
          <label>{t('settings.theme')}</label>
          <button className="btn btn-secondary" onClick={toggleTheme}>
            {theme === 'light' ? t('settings.switch_to_dark') : t('settings.switch_to_light')}
          </button>
        </div>
      </div>

      {/* ── Preferences ── */}
      <div className="card settings-section">
        <h3>{t('settings.preferences')}</h3>
        <div className="form-row">
          <div className="form-group"><label>{t('settings.language')}</label>
            <select value={language} onChange={(e) => setLanguage(e.target.value)}><option value="en">English</option><option value="de">Deutsch</option></select>
          </div>
          <div className="form-group"><label>{t('settings.date_format')}</label>
            <select value={dateFormat} onChange={(e) => setDateFormat(e.target.value)}><option value="DMY">DD.MM.YYYY</option><option value="MDY">MM/DD/YYYY</option><option value="YMD">YYYY-MM-DD</option></select>
          </div>
        </div>
        <div className="form-row">
          <div className="form-group"><label>{t('settings.weight')}</label>
            <select value={weightUnit} onChange={(e) => setWeightUnit(e.target.value)}><option value="kg">kg</option><option value="lbs">lbs</option></select>
          </div>
          <div className="form-group"><label>{t('settings.temperature')}</label>
            <select value={tempUnit} onChange={(e) => setTempUnit(e.target.value)}><option value="celsius">°C</option><option value="fahrenheit">°F</option></select>
          </div>
          <div className="form-group"><label>{t('settings.blood_glucose')}</label>
            <select value={glucoseUnit} onChange={(e) => setGlucoseUnit(e.target.value)}><option value="mmol_l">mmol/L</option><option value="mg_dl">mg/dL</option></select>
          </div>
        </div>
        <button className="btn btn-add" onClick={handleSavePrefs} style={{ width: 'auto' }}>{t('common.save')}</button>
      </div>

      {/* ── Security ── */}
      <div className="card settings-section">
        <h3>{t('settings.security')}</h3>

        {/* Passphrase */}
        <div className="security-block">
          <div className="security-header">
            <div className="security-icon">
              <svg {...svgProps}><rect x="3" y="11" width="18" height="11" rx="2" /><path d="M7 11V7a5 5 0 0 1 10 0v4" /></svg>
            </div>
            <div>
              <div className="security-title">{t('settings.change_passphrase')}</div>
              <div className="text-muted" style={{ fontSize: 13 }}>{email}</div>
            </div>
            <button className="btn btn-secondary" style={{ marginLeft: 'auto' }} onClick={() => setShowPassModal(true)}>
              {t('common.edit')}
            </button>
          </div>
        </div>

        {/* 2FA */}
        <div className="security-block" style={{ marginTop: 20 }}>
          <div className="security-header">
            <div className="security-icon">
              <svg {...svgProps}><path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z" /></svg>
            </div>
            <div>
              <div className="security-title">{t('settings.two_factor')}</div>
              <div className="text-muted" style={{ fontSize: 13 }}>
                {is2FA
                  ? <span style={{ color: 'var(--color-success)' }}>{t('settings.two_factor_enabled')}</span>
                  : t('settings.two_factor_disabled')}
              </div>
            </div>
            <button
              className={`btn ${is2FA ? 'btn-secondary' : 'btn-add'}`}
              style={{ marginLeft: 'auto' }}
              onClick={is2FA ? () => setShowDisable2FA(true) : handleSetup2FA}
            >
              {is2FA ? t('settings.disable_2fa') : t('settings.enable_2fa')}
            </button>
          </div>
        </div>

        {/* Recovery Codes */}
        <div className="security-block" style={{ marginTop: 20 }}>
          <div className="security-header">
            <div className="security-icon">
              <svg {...svgProps}><path d="M9 12h6m-3-3v6m-7-3a7 7 0 1 0 14 0 7 7 0 0 0-14 0z" /></svg>
            </div>
            <div>
              <div className="security-title">{t('settings.regenerate_codes')}</div>
            </div>
            <button
              className="btn btn-secondary"
              style={{ marginLeft: 'auto' }}
              onClick={handleRegenerateRecoveryCodes}
              disabled={recoveryLoading}
            >
              {recoveryLoading ? t('common.loading') : t('settings.regenerate_codes')}
            </button>
          </div>
        </div>
      </div>

      {/* ── Storage ── */}
      <div className="card settings-section">
        <h3>{t('settings.storage')}</h3>
        <div className="storage-bar"><div className="storage-fill" style={{ width: `${Math.min(usagePercent, 100)}%` }} /></div>
        <p className="text-muted">{t('settings.storage_usage', { used: usedMB, quota: quotaMB, percent: formatNumber(usagePercent, 1) })}</p>
      </div>

      {/* ── Sessions ── */}
      <div className="card settings-section">
        <div className="session-section-header">
          <h3>{t('settings.sessions')}</h3>
          {sessions.filter((s) => !s.is_current).length > 0 && (
            <button className="btn btn-secondary" onClick={() => revokeOthers.mutate()}>{t('settings.terminate_others')}</button>
          )}
        </div>
        {sessions.length > 0 ? (
          <div className="session-list">
            {sessions.slice().sort((a, b) => (a.is_current ? -1 : b.is_current ? 1 : 0)).map((s) => {
              const device = parseDevice(s.device_hint);
              return (
                <div key={s.id} className={`session-card${s.is_current ? ' session-current' : ''}`}>
                  <div className="session-icon">{device.icon}</div>
                  <div className="session-info">
                    <div className="session-device-name">
                      {device.name}
                      {s.is_current && <span className="session-badge">{t('settings.current_session')}</span>}
                    </div>
                    <div className="session-meta">{s.ip_address}</div>
                    <div className="session-meta">{t('settings.session_created')} {fmt(s.created_at, 'dd. MMM yyyy')} · {relative(s.last_active_at)}</div>
                  </div>
                  {!s.is_current && (
                    <button className="btn-icon-sm session-revoke" onClick={() => revokeSession.mutate(s.id)} title={t('settings.terminate')}>
                      <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><line x1="18" y1="6" x2="6" y2="18" /><line x1="6" y1="6" x2="18" y2="18" /></svg>
                    </button>
                  )}
                </div>
              );
            })}
          </div>
        ) : (
          <p className="text-muted">{t('settings.no_sessions')}</p>
        )}
      </div>

      {/* ── Notifications ── */}
      <div className="card settings-section">
        <h3>{t('settings.notifications')}</h3>
        {NOTIF_KEYS.map((key) => (
          <div key={key} className="toggle-switch">
            <div>
              <div className="toggle-switch-label">{t(NOTIF_LABEL_MAP[key])}</div>
            </div>
            <input
              type="checkbox"
              checked={notifPrefs?.[key] ?? true}
              onChange={(e) => updateNotifPrefs.mutate({ [key]: e.target.checked })}
            />
          </div>
        ))}
      </div>

      {/* ── Profile Management ── */}
      <div className="card settings-section">
        <h3>{t('settings.profile_management')}</h3>

        <div className="form-group" style={{ display: 'flex', gap: 8, alignItems: 'flex-end' }}>
          <select
            style={{ flex: 1 }}
            value={selectedProfileId}
            onChange={(e) => { setSelectedProfileId(e.target.value); setProfileMsg(''); }}
          >
            <option value="">{t('settings.no_profile_selected')}</option>
            {profiles.map((p) => (
              <option key={p.id} value={p.id}>
                {p.display_name}{p.archived_at ? ` (${t('settings.archived')})` : ''}
              </option>
            ))}
          </select>
          <button
            type="button"
            className="btn btn-add"
            onClick={() => { setShowCreateProfile((v) => !v); setProfileMsg(''); }}
          >
            {showCreateProfile ? t('common.cancel') : t('settings.new_profile')}
          </button>
        </div>

        {showCreateProfile && (
          <form
            onSubmit={(e) => {
              e.preventDefault();
              if (!newProfileName.trim()) return;
              createProfileMutation.mutate({
                display_name: newProfileName.trim(),
                date_of_birth: newProfileDOB || undefined,
                biological_sex: newProfileSex,
              });
            }}
            style={{ padding: 12, border: '1px solid var(--color-border)', borderRadius: 8, marginBottom: 12 }}
          >
            <div className="form-group">
              <label>{t('settings.new_profile_name')}</label>
              <input
                type="text"
                value={newProfileName}
                onChange={(e) => setNewProfileName(e.target.value)}
                placeholder={t('settings.new_profile_name_placeholder')}
                required
                autoFocus
              />
            </div>
            <div className="form-group">
              <label>{t('settings.new_profile_dob')}</label>
              <input
                type="date"
                value={newProfileDOB}
                onChange={(e) => setNewProfileDOB(e.target.value)}
              />
            </div>
            <div className="form-group">
              <label>{t('settings.new_profile_sex')}</label>
              <select
                value={newProfileSex}
                onChange={(e) => setNewProfileSex(e.target.value)}
              >
                <option value="unspecified">{t('settings.sex_unspecified')}</option>
                <option value="female">{t('settings.sex_female')}</option>
                <option value="male">{t('settings.sex_male')}</option>
                <option value="other">{t('settings.sex_other')}</option>
              </select>
            </div>
            <button
              type="submit"
              className="btn btn-add"
              disabled={!newProfileName.trim() || createProfileMutation.isPending}
            >
              {createProfileMutation.isPending ? t('common.loading') : t('settings.create_profile_btn')}
            </button>
          </form>
        )}

        {profileMsg && (
          <div className="alert alert-success" style={{ marginBottom: 12 }}>{profileMsg}</div>
        )}

        {selectedProfile && (
          <>
            {/* Archive / Unarchive */}
            <div style={{ marginBottom: 16 }}>
              {selectedProfile.archived_at ? (
                <button
                  className="btn btn-secondary"
                  onClick={() => unarchiveMutation.mutate(selectedProfile.id)}
                  disabled={unarchiveMutation.isPending}
                >
                  {unarchiveMutation.isPending ? t('common.loading') : t('settings.unarchive_profile')}
                </button>
              ) : (
                <button
                  className="btn btn-secondary"
                  onClick={() => archiveMutation.mutate(selectedProfile.id)}
                  disabled={archiveMutation.isPending}
                >
                  {archiveMutation.isPending ? t('common.loading') : t('settings.archive_profile')}
                </button>
              )}
            </div>

            {/* Transfer Ownership (owner only) */}
            {isProfileOwner && (
              <div style={{ marginBottom: 16 }}>
                <button
                  className="btn btn-secondary"
                  onClick={() => setShowTransferModal(true)}
                >
                  {t('settings.transfer_profile')}
                </button>
              </div>
            )}

            {/* Share with family member (owner only) */}
            {isProfileOwner && (
              <div>
                <h4 style={{ marginBottom: 8 }}>{t('settings.share_with_family')}</h4>
                {families.length === 0 ? (
                  <p className="text-muted" style={{ fontSize: 13 }}>{t('settings.no_families')}</p>
                ) : shareablePeople.length === 0 ? (
                  <p className="text-muted" style={{ fontSize: 13 }}>{t('settings.no_shareable_members')}</p>
                ) : (
                  <div style={{ display: 'flex', gap: 8, alignItems: 'flex-end', marginBottom: 16 }}>
                    <div className="form-group" style={{ flex: 1, margin: 0 }}>
                      <label>{t('settings.pick_family_member')}</label>
                      <select
                        value={pickedFamilyMember}
                        onChange={(e) => setPickedFamilyMember(e.target.value)}
                      >
                        <option value="">{t('settings.pick_family_member')}</option>
                        {shareablePeople.map((m) => (
                          <option key={`${m.family_id}:${m.user_id}`} value={`${m.family_id}:${m.user_id}`}>
                            {m.display_name || m.email} ({m.family_name})
                          </option>
                        ))}
                      </select>
                    </div>
                    <button
                      className="btn btn-add"
                      disabled={!pickedFamilyMember || grantMutation.isPending}
                      onClick={async () => {
                        const [familyId, granteeUserId] = pickedFamilyMember.split(':');
                        try {
                          // Make sure the profile key is unwrapped (may not
                          // have been if background fetch hasn't run yet).
                          if (userId) {
                            await ensureProfileKey(selectedProfile.id, userId, selectedProfile.owner_user_id);
                          }
                          const pk = await api.get<{ identity_pubkey: string }>(`/api/v1/users/${granteeUserId}/public-key`);
                          grantMutation.mutate({
                            profileId: selectedProfile.id,
                            granteeUserId,
                            granteeIdentityPubkey: pk.identity_pubkey,
                            familyId,
                          });
                        } catch {
                          setProfileMsg(t('settings.grant_failed'));
                        }
                      }}
                    >
                      {grantMutation.isPending ? t('common.loading') : t('settings.share_action')}
                    </button>
                  </div>
                )}

                <h4 style={{ marginTop: 16, marginBottom: 8 }}>{t('settings.current_access')}</h4>
                {currentGrants.length === 0 ? (
                  <p className="text-muted" style={{ fontSize: 13 }}>{t('settings.no_grants_yet')}</p>
                ) : (
                  <ul style={{ listStyle: 'none', padding: 0, margin: 0 }}>
                    {currentGrants
                      .filter((g) => g.grantee_user_id !== userId) /* hide own self-grant */
                      .map((g) => (
                        <li key={g.id} style={{ display: 'flex', alignItems: 'center', padding: '8px 0', borderBottom: '1px solid var(--color-border)' }}>
                          <div style={{ flex: 1 }}>
                            <div>{g.display_name || g.email}</div>
                            <div className="text-muted" style={{ fontSize: 12 }}>
                              {fmt(g.granted_at, 'PPP')}
                              {g.via_family_id ? ` — ${t('settings.shared_via_family')}` : ''}
                            </div>
                          </div>
                          <button
                            className="btn btn-sm btn-danger"
                            onClick={() => revokeGrantMutation.mutate({ profileId: selectedProfile.id, granteeUserId: g.grantee_user_id })}
                            disabled={revokeGrantMutation.isPending}
                          >
                            {t('settings.revoke_access')}
                          </button>
                        </li>
                      ))}
                  </ul>
                )}
              </div>
            )}
          </>
        )}
      </div>

      {/* ── Delete Account ── */}
      <div className="card settings-section" style={{ borderColor: 'var(--color-danger)' }}>
        <h3 style={{ color: 'var(--color-danger)' }}>{t('settings.delete_account')}</h3>
        <p className="text-muted" style={{ marginBottom: 16 }}>{t('settings.delete_account_message')}</p>
        <button className="btn btn-danger" onClick={() => setShowDeleteAccount(true)}>
          {t('settings.delete_account')}
        </button>
      </div>

      {/* ═══ MODALS ═══ */}

      {/* Avatar Crop Modal */}
      {cropSrc && (
        <div className="modal-overlay" onClick={() => setCropSrc(null)}>
          <div className="modal crop-modal" onClick={(e) => e.stopPropagation()}>
            <div className="modal-header">
              <h3>{t('settings.avatar')}</h3>
              <button className="modal-close" onClick={() => setCropSrc(null)}>&times;</button>
            </div>
            <div className="crop-container">
              <Cropper
                image={cropSrc}
                crop={crop}
                zoom={zoom}
                minZoom={0.5}
                maxZoom={5}
                aspect={1}
                cropShape="round"
                showGrid={false}
                objectFit="contain"
                onCropChange={setCrop}
                onZoomChange={setZoom}
                onCropComplete={onCropComplete}
              />
            </div>
            <div className="crop-zoom-bar">
              <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round"><circle cx="11" cy="11" r="8"/><line x1="21" y1="21" x2="16.65" y2="16.65"/><line x1="8" y1="11" x2="14" y2="11"/></svg>
              <input type="range" min={0.5} max={5} step={0.05} value={zoom} onChange={(e) => setZoom(Number(e.target.value))} />
              <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round"><circle cx="11" cy="11" r="8"/><line x1="21" y1="21" x2="16.65" y2="16.65"/><line x1="11" y1="8" x2="11" y2="14"/><line x1="8" y1="11" x2="14" y2="11"/></svg>
            </div>
            <div className="modal-footer">
              <button className="btn btn-secondary" onClick={() => setCropSrc(null)}>{t('common.cancel')}</button>
              <button className="btn btn-add" onClick={handleCropSave}>{t('common.save')}</button>
            </div>
          </div>
        </div>
      )}

      {/* Passphrase Change Modal */}
      {showPassModal && (
        <div className="modal-overlay" onClick={() => setShowPassModal(false)}>
          <div className="modal" onClick={(e) => e.stopPropagation()} style={{ maxWidth: 420 }}>
            <div className="modal-header">
              <h3>{t('settings.change_passphrase')}</h3>
              <button className="modal-close" onClick={() => { setShowPassModal(false); setPassError(''); }}>&times;</button>
            </div>
            <div className="modal-body">
              <p className="text-muted" style={{ fontSize: 13, marginBottom: 16 }}>{t('settings.passphrase_note')}</p>
              {passError && <div className="alert alert-error">{passError}</div>}
              <div className="form-group">
                <label>{t('settings.current_passphrase')}</label>
                <input type="password" value={currentPass} onChange={(e) => setCurrentPass(e.target.value)} autoComplete="current-password" />
              </div>
              <div className="form-group">
                <label>{t('settings.new_passphrase')}</label>
                <input type="password" value={newPass} onChange={(e) => setNewPass(e.target.value)} autoComplete="new-password" />
              </div>
              <div className="form-group">
                <label>{t('settings.confirm_passphrase')}</label>
                <input type="password" value={confirmPass} onChange={(e) => setConfirmPass(e.target.value)} autoComplete="new-password" />
              </div>
            </div>
            <div className="modal-footer">
              <button className="btn btn-secondary" onClick={() => setShowPassModal(false)}>{t('common.cancel')}</button>
              <button className="btn btn-add" onClick={handleChangePass} disabled={!currentPass || !newPass || changePassMut.isPending}>
                {changePassMut.isPending ? t('common.loading') : t('common.save')}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* 2FA Enable Modal */}
      {show2FAModal && totpSetup && (
        <div className="modal-overlay" onClick={() => setShow2FAModal(false)}>
          <div className="modal" onClick={(e) => e.stopPropagation()} style={{ maxWidth: 420 }}>
            <div className="modal-header">
              <h3>{t('settings.enable_2fa')}</h3>
              <button className="modal-close" onClick={() => { setShow2FAModal(false); setTotpSetup(null); }}>&times;</button>
            </div>
            <div className="modal-body" style={{ textAlign: 'center' }}>
              <p className="text-muted" style={{ marginBottom: 16 }}>{t('settings.scan_qr')}</p>
              {totpQrDataUrl && (
                <img
                  src={totpQrDataUrl}
                  alt="TOTP QR"
                  style={{ width: 200, height: 200, borderRadius: 12, border: '1px solid var(--color-border)' }}
                />
              )}
              <code style={{ display: 'block', margin: '12px auto', padding: '6px 12px', background: 'var(--color-bg-subtle)', borderRadius: 6, fontSize: 13, letterSpacing: 1, userSelect: 'all' as const }}>
                {totpSetup.secret}
              </code>
              <div className="form-group" style={{ marginTop: 16, textAlign: 'left' }}>
                <label>{t('settings.enter_code')}</label>
                <input type="text" inputMode="numeric" maxLength={6} value={totpCode} onChange={(e) => setTotpCode(e.target.value)} placeholder="000000" style={{ maxWidth: 160 }} />
              </div>
              {totpError && <div className="alert alert-error">{totpError}</div>}
            </div>
            <div className="modal-footer">
              <button className="btn btn-secondary" onClick={() => { setShow2FAModal(false); setTotpSetup(null); setTotpError(''); }}>{t('common.cancel')}</button>
              <button className="btn btn-add" onClick={handleEnable2FA} disabled={totpCode.length !== 6 || enable2FAMut.isPending}>
                {enable2FAMut.isPending ? t('common.loading') : t('settings.verify')}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* 2FA Disable Modal */}
      {showDisable2FA && (
        <div className="modal-overlay" onClick={() => setShowDisable2FA(false)}>
          <div className="modal" onClick={(e) => e.stopPropagation()} style={{ maxWidth: 380 }}>
            <div className="modal-header">
              <h3>{t('settings.disable_2fa')}</h3>
              <button className="modal-close" onClick={() => setShowDisable2FA(false)}>&times;</button>
            </div>
            <div className="modal-body">
              <div className="form-group">
                <label>{t('settings.enter_code')}</label>
                <input type="text" inputMode="numeric" maxLength={6} value={disableCode} onChange={(e) => setDisableCode(e.target.value)} placeholder="000000" style={{ maxWidth: 160 }} />
              </div>
              {totpError && <div className="alert alert-error">{totpError}</div>}
            </div>
            <div className="modal-footer">
              <button className="btn btn-secondary" onClick={() => { setShowDisable2FA(false); setTotpError(''); }}>{t('common.cancel')}</button>
              <button className="btn btn-danger" onClick={handleDisable2FA} disabled={disableCode.length !== 6 || disable2FAMut.isPending}>
                {disable2FAMut.isPending ? t('common.loading') : t('settings.disable_2fa')}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Recovery Codes Modal */}
      {showRecoveryCodes && (
        <div className="modal-overlay" onClick={() => setShowRecoveryCodes(false)}>
          <div className="modal" onClick={(e) => e.stopPropagation()} style={{ maxWidth: 440 }}>
            <div className="modal-header">
              <h3>{t('settings.regenerate_codes')}</h3>
              <button className="modal-close" onClick={() => setShowRecoveryCodes(false)}>&times;</button>
            </div>
            <div className="modal-body">
              <div className="alert alert-warning" style={{ marginBottom: 16 }}>{t('settings.codes_regenerated')}</div>
              <div className="recovery-grid">
                {recoveryCodes.map((code, i) => (
                  <div key={i} className="recovery-code">
                    <span className="text-muted" style={{ marginRight: 8 }}>{i + 1}.</span>
                    {code}
                  </div>
                ))}
              </div>
            </div>
            <div className="modal-footer">
              <button className="btn btn-secondary" onClick={handleCopyRecoveryCodes}>{t('settings.copy_codes')}</button>
              <button className="btn btn-add" onClick={() => setShowRecoveryCodes(false)}>{t('common.close')}</button>
            </div>
          </div>
        </div>
      )}

      {/* Transfer Ownership Modal */}
      {showTransferModal && selectedProfile && (
        <div className="modal-overlay" onClick={() => setShowTransferModal(false)}>
          <div className="modal" onClick={(e) => e.stopPropagation()} style={{ maxWidth: 420 }}>
            <div className="modal-header">
              <h3>{t('settings.transfer_profile')}</h3>
              <button className="modal-close" onClick={() => setShowTransferModal(false)}>&times;</button>
            </div>
            <div className="modal-body">
              <div className="alert alert-warning" style={{ marginBottom: 16 }}>
                {t('settings.transfer_confirm')}
              </div>
              <div className="form-group">
                <label>{t('settings.transfer_user_id')}</label>
                <input
                  type="text"
                  value={transferUserId}
                  onChange={(e) => setTransferUserId(e.target.value)}
                  placeholder="user-uuid"
                  style={{ fontFamily: 'monospace', fontSize: 13 }}
                  autoFocus
                />
              </div>
            </div>
            <div className="modal-footer">
              <button className="btn btn-secondary" onClick={() => setShowTransferModal(false)}>
                {t('common.cancel')}
              </button>
              <button
                className="btn btn-danger"
                onClick={() => transferMutation.mutate({ profileId: selectedProfile.id, newOwnerUserId: transferUserId })}
                disabled={!transferUserId.trim() || transferMutation.isPending}
              >
                {transferMutation.isPending ? t('common.loading') : t('settings.transfer_profile')}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Delete Account Confirm Modal */}
      <ConfirmDelete
        open={showDeleteAccount}
        title={t('settings.delete_account_title')}
        message={t('settings.delete_account_message')}
        onConfirm={() => deleteAccountMut.mutate()}
        onCancel={() => setShowDeleteAccount(false)}
        pending={deleteAccountMut.isPending}
      />
    </div>
  );
}
