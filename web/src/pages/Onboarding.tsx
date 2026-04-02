import { useState, useCallback } from 'react';
import { useNavigate } from 'react-router-dom';
import { useTranslation } from 'react-i18next';
import { api, ApiError } from '../api/client';
import { useAuthStore } from '../store/auth';

// ---- Types ----

interface RegisterResponse {
  user_id: string;
  auth_salt: string;
  pek_salt: string;
}

interface TwoFactorSetupResponse {
  provisioning_uri: string;
  secret: string;
}

interface RegisterCompleteResponse {
  access_token: string;
  refresh_token: string;
  user_id: string;
}

interface ProfileResponse {
  id: string;
}

interface OnboardingData {
  email: string;
  displayName: string;
  passphrase: string;
  passphraseConfirm: string;
  recoveryCodes: string[];
  codesAcknowledged: boolean;
  twoFactorEnabled: boolean;
  totpCode: string;
  provisioningUri: string;
  profileName: string;
  dateOfBirth: string;
  biologicalSex: string;
  bloodType: string;
  userId: string;
  authSalt: string;
  pekSalt: string;
}

// ---- Helpers ----

const BASE32_CHARS = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

function generateRecoveryCodes(count: number): string[] {
  const codes: string[] = [];
  for (let i = 0; i < count; i++) {
    const bytes = new Uint8Array(8);
    crypto.getRandomValues(bytes);
    let code = '';
    for (let j = 0; j < 8; j++) {
      code += BASE32_CHARS[bytes[j] % BASE32_CHARS.length];
    }
    codes.push(code);
  }
  return codes;
}

interface StrengthResult {
  score: number;
  label: string;
  color: string;
}

function checkPassphraseStrength(passphrase: string): StrengthResult {
  let score = 0;
  if (passphrase.length >= 8) score++;
  if (passphrase.length >= 12) score++;
  if (/[a-z]/.test(passphrase)) score++;
  if (/[A-Z]/.test(passphrase)) score++;
  if (/[0-9]/.test(passphrase)) score++;
  if (/[^a-zA-Z0-9]/.test(passphrase)) score++;

  if (score <= 2) return { score, label: 'weak', color: 'var(--color-danger)' };
  if (score <= 4) return { score, label: 'fair', color: 'var(--color-warning)' };
  return { score, label: 'strong', color: 'var(--color-success)' };
}

// ---- Component ----

const TOTAL_STEPS = 6;

export function Onboarding() {
  const { t } = useTranslation();
  const navigate = useNavigate();
  const { login } = useAuthStore();

  const [step, setStep] = useState(1);
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);
  const [data, setData] = useState<OnboardingData>({
    email: '',
    displayName: '',
    passphrase: '',
    passphraseConfirm: '',
    recoveryCodes: [],
    codesAcknowledged: false,
    twoFactorEnabled: false,
    totpCode: '',
    provisioningUri: '',
    profileName: '',
    dateOfBirth: '',
    biologicalSex: 'unspecified',
    bloodType: '',
    userId: '',
    authSalt: '',
    pekSalt: '',
  });

  const update = useCallback(
    <K extends keyof OnboardingData>(field: K, value: OnboardingData[K]) => {
      setData((prev) => ({ ...prev, [field]: value }));
    },
    [],
  );

  // ---- Step handlers ----

  const handleAccountSetup = async () => {
    setError('');
    if (!data.email || !data.displayName || !data.passphrase) {
      setError(t('onboarding.all_fields_required'));
      return;
    }
    if (data.passphrase !== data.passphraseConfirm) {
      setError(t('onboarding.passphrase_mismatch'));
      return;
    }
    if (data.passphrase.length < 8) {
      setError(t('onboarding.passphrase_min_length'));
      return;
    }

    setLoading(true);
    try {
      const res = await api.post<RegisterResponse>('/api/v1/auth/register', {
        email: data.email,
        display_name: data.displayName,
        auth_hash: data.passphrase,
      });
      update('userId', res.user_id);
      update('authSalt', res.auth_salt);
      update('pekSalt', res.pek_salt);

      // Generate recovery codes for next step
      const codes = generateRecoveryCodes(10);
      update('recoveryCodes', codes);

      setStep(3);
    } catch (err) {
      if (err instanceof ApiError) {
        setError(err.message);
      } else {
        setError(t('onboarding.connection_error'));
      }
    } finally {
      setLoading(false);
    }
  };

  const handleCopyAll = async () => {
    const text = data.recoveryCodes.join('\n');
    await navigator.clipboard.writeText(text);
  };

  const handleDownloadCodes = () => {
    const text = [
      'HealthVault Recovery Codes',
      '==========================',
      '',
      'Keep these codes in a safe place.',
      'Each code can only be used once.',
      '',
      ...data.recoveryCodes.map((code, i) => `${i + 1}. ${code}`),
      '',
      `Generated: ${new Date().toISOString()}`,
    ].join('\n');

    const blob = new Blob([text], { type: 'text/plain' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = 'healthvault-recovery-codes.txt';
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(url);
  };

  const handleSetup2FA = async () => {
    setError('');
    setLoading(true);
    try {
      const res = await api.get<TwoFactorSetupResponse>('/api/v1/auth/2fa/setup');
      update('provisioningUri', res.provisioning_uri);
    } catch (err) {
      if (err instanceof ApiError) {
        setError(err.message);
      } else {
        setError(t('onboarding.failed_2fa'));
      }
    } finally {
      setLoading(false);
    }
  };

  const handleVerify2FA = async () => {
    setError('');
    if (data.totpCode.length !== 6) {
      setError(t('onboarding.enter_6_digit'));
      return;
    }
    setLoading(true);
    try {
      await api.post('/api/v1/auth/2fa/enable', { code: data.totpCode });
      update('twoFactorEnabled', true);
      setStep(5);
    } catch (err) {
      if (err instanceof ApiError) {
        setError(err.message);
      } else {
        setError(t('onboarding.verification_failed'));
      }
    } finally {
      setLoading(false);
    }
  };

  const handleCreateProfile = async () => {
    setError('');
    if (!data.profileName) {
      setError(t('onboarding.profile_name_required'));
      return;
    }

    setLoading(true);
    try {
      const completeRes = await api.post<RegisterCompleteResponse>(
        '/api/v1/auth/register/complete',
        {
          user_id: data.userId,
          recovery_codes: data.recoveryCodes,
        },
      );

      login(
        completeRes.access_token,
        completeRes.refresh_token,
        completeRes.user_id,
        'user',
      );

      await api.post<ProfileResponse>('/api/v1/profiles', {
        display_name: data.profileName,
        date_of_birth: data.dateOfBirth || undefined,
        biological_sex: data.biologicalSex,
        blood_type: data.bloodType || undefined,
      });

      setStep(6);
    } catch (err) {
      if (err instanceof ApiError) {
        setError(err.message);
      } else {
        setError(t('onboarding.failed_create_profile'));
      }
    } finally {
      setLoading(false);
    }
  };

  // ---- Render helpers ----

  const strength = checkPassphraseStrength(data.passphrase);
  const progressPercent = ((step - 1) / (TOTAL_STEPS - 1)) * 100;

  const renderStep = () => {
    switch (step) {
      case 1:
        return (
          <div>
            <h1>{t('onboarding.welcome_title')}</h1>
            <p className="auth-tagline" style={{ marginBottom: 16 }}>
              {t('onboarding.welcome_desc')}
            </p>
            <div className="alert alert-warning" style={{ marginBottom: 24 }}>
              <strong>{t('onboarding.welcome_warning_bold')}</strong>{t('onboarding.welcome_warning_rest')}
            </div>
            <button
              type="button"
              className="btn btn-primary"
              onClick={() => setStep(2)}
            >
              {t('onboarding.get_started')}
            </button>
          </div>
        );

      case 2:
        return (
          <div>
            <h2>{t('onboarding.account_setup')}</h2>
            <div className="form-group">
              <label htmlFor="ob-email">{t('auth.email')}</label>
              <input
                id="ob-email"
                type="email"
                value={data.email}
                onChange={(e) => update('email', e.target.value)}
                required
                autoComplete="email"
              />
            </div>
            <div className="form-group">
              <label htmlFor="ob-display-name">{t('register.display_name')}</label>
              <input
                id="ob-display-name"
                type="text"
                value={data.displayName}
                onChange={(e) => update('displayName', e.target.value)}
                required
              />
            </div>
            <div className="form-group">
              <label htmlFor="ob-passphrase">{t('auth.passphrase')}</label>
              <input
                id="ob-passphrase"
                type="password"
                value={data.passphrase}
                onChange={(e) => update('passphrase', e.target.value)}
                required
                autoComplete="new-password"
              />
              {data.passphrase && (
                <div style={{ marginTop: 6 }}>
                  <div
                    style={{
                      display: 'flex',
                      alignItems: 'center',
                      gap: 8,
                      fontSize: 13,
                    }}
                  >
                    <div
                      style={{
                        flex: 1,
                        height: 4,
                        background: 'var(--color-border)',
                        borderRadius: 2,
                        overflow: 'hidden',
                      }}
                    >
                      <div
                        style={{
                          width: `${(strength.score / 6) * 100}%`,
                          height: '100%',
                          background: strength.color,
                          borderRadius: 2,
                          transition: 'width 0.2s',
                        }}
                      />
                    </div>
                    <span style={{ color: strength.color, fontWeight: 500 }}>
                      {t('onboarding.strength_' + strength.label)}
                    </span>
                  </div>
                </div>
              )}
            </div>
            <div className="form-group">
              <label htmlFor="ob-passphrase-confirm">{t('register.confirm_passphrase')}</label>
              <input
                id="ob-passphrase-confirm"
                type="password"
                value={data.passphraseConfirm}
                onChange={(e) => update('passphraseConfirm', e.target.value)}
                required
                autoComplete="new-password"
              />
            </div>
            <p
              style={{
                fontSize: 13,
                color: 'var(--color-warning)',
                marginBottom: 16,
              }}
            >
              {t('onboarding.passphrase_remember')}
            </p>
            <button
              type="button"
              className="btn btn-primary"
              disabled={loading}
              onClick={handleAccountSetup}
            >
              {loading ? t('onboarding.creating_account') : t('common.continue')}
            </button>
          </div>
        );

      case 3:
        return (
          <div>
            <h2>{t('onboarding.recovery_codes')}</h2>
            <p
              style={{
                fontSize: 14,
                color: 'var(--color-text-secondary)',
                marginBottom: 16,
              }}
            >
              {t('onboarding.recovery_codes_desc')}
            </p>
            <div className="recovery-grid">
              {data.recoveryCodes.map((code, i) => (
                <div key={i} className="recovery-code">
                  <span className="text-muted" style={{ marginRight: 8 }}>
                    {i + 1}.
                  </span>
                  {code}
                </div>
              ))}
            </div>
            <div
              style={{
                display: 'flex',
                gap: 8,
                marginTop: 16,
                marginBottom: 16,
              }}
            >
              <button
                type="button"
                className="btn btn-secondary"
                onClick={handleCopyAll}
              >
                {t('onboarding.copy_all')}
              </button>
              <button
                type="button"
                className="btn btn-secondary"
                onClick={handleDownloadCodes}
              >
                {t('onboarding.download_txt')}
              </button>
            </div>
            <label
              style={{
                display: 'flex',
                alignItems: 'center',
                gap: 8,
                fontSize: 14,
                marginBottom: 16,
                cursor: 'pointer',
              }}
            >
              <input
                type="checkbox"
                checked={data.codesAcknowledged}
                onChange={(e) => update('codesAcknowledged', e.target.checked)}
              />
              {t('onboarding.codes_acknowledged')}
            </label>
            <button
              type="button"
              className="btn btn-primary"
              disabled={!data.codesAcknowledged}
              onClick={() => setStep(4)}
            >
              {t('common.continue')}
            </button>
          </div>
        );

      case 4:
        return (
          <div>
            <h2>{t('onboarding.two_factor_title')}</h2>
            <p
              style={{
                fontSize: 14,
                color: 'var(--color-text-secondary)',
                marginBottom: 16,
              }}
            >
              {t('onboarding.two_factor_desc')}
            </p>

            {!data.provisioningUri ? (
              <div>
                <button
                  type="button"
                  className="btn btn-primary"
                  disabled={loading}
                  onClick={handleSetup2FA}
                  style={{ marginBottom: 12 }}
                >
                  {loading ? t('onboarding.setting_up_2fa') : t('onboarding.setup_2fa')}
                </button>
              </div>
            ) : (
              <div>
                <div className="form-group">
                  <label>{t('onboarding.provisioning_uri')}</label>
                  <input
                    type="text"
                    value={data.provisioningUri}
                    readOnly
                    style={{ fontFamily: 'var(--font-mono)', fontSize: 13 }}
                  />
                  <p
                    style={{
                      fontSize: 12,
                      color: 'var(--color-text-secondary)',
                      marginTop: 4,
                    }}
                  >
                    {t('onboarding.provisioning_hint')}
                  </p>
                </div>
                <div className="form-group">
                  <label htmlFor="ob-totp">{t('onboarding.verification_code')}</label>
                  <input
                    id="ob-totp"
                    type="text"
                    inputMode="numeric"
                    pattern="[0-9]{6}"
                    maxLength={6}
                    value={data.totpCode}
                    onChange={(e) => update('totpCode', e.target.value)}
                    placeholder="000000"
                    autoComplete="one-time-code"
                  />
                </div>
                <button
                  type="button"
                  className="btn btn-primary"
                  disabled={loading || data.totpCode.length !== 6}
                  onClick={handleVerify2FA}
                  style={{ marginBottom: 8 }}
                >
                  {loading ? t('onboarding.verifying') : t('onboarding.verify_continue')}
                </button>
              </div>
            )}

            <div style={{ textAlign: 'center', marginTop: 12 }}>
              <button
                type="button"
                className="btn btn-text"
                style={{
                  background: 'none',
                  border: 'none',
                  color: 'var(--color-text-secondary)',
                  textDecoration: 'underline',
                  cursor: 'pointer',
                  fontSize: 14,
                }}
                onClick={() => setStep(5)}
              >
                {t('onboarding.skip_for_now')}
              </button>
            </div>
          </div>
        );

      case 5:
        return (
          <div>
            <h2>{t('onboarding.create_profile')}</h2>
            <p
              style={{
                fontSize: 14,
                color: 'var(--color-text-secondary)',
                marginBottom: 16,
              }}
            >
              {t('onboarding.create_profile_desc')}
            </p>
            <div className="form-group">
              <label htmlFor="ob-profile-name">{t('onboarding.profile_name')}</label>
              <input
                id="ob-profile-name"
                type="text"
                value={data.profileName}
                onChange={(e) => update('profileName', e.target.value)}
                required
                placeholder={t('onboarding.profile_name_placeholder')}
              />
            </div>
            <div className="form-group">
              <label htmlFor="ob-dob">{t('onboarding.date_of_birth')}</label>
              <input
                id="ob-dob"
                type="date"
                value={data.dateOfBirth}
                onChange={(e) => update('dateOfBirth', e.target.value)}
              />
            </div>
            <div className="form-group">
              <label htmlFor="ob-sex">{t('onboarding.biological_sex')}</label>
              <select
                id="ob-sex"
                value={data.biologicalSex}
                onChange={(e) => update('biologicalSex', e.target.value)}
              >
                <option value="unspecified">{t('onboarding.sex_unspecified')}</option>
                <option value="male">{t('onboarding.sex_male')}</option>
                <option value="female">{t('onboarding.sex_female')}</option>
                <option value="other">{t('onboarding.sex_other')}</option>
              </select>
            </div>
            <div className="form-group">
              <label htmlFor="ob-blood-type">{t('onboarding.blood_type')}</label>
              <select
                id="ob-blood-type"
                value={data.bloodType}
                onChange={(e) => update('bloodType', e.target.value)}
              >
                <option value="">{t('onboarding.blood_type_unknown')}</option>
                <option value="A+">A+</option>
                <option value="A-">A-</option>
                <option value="B+">B+</option>
                <option value="B-">B-</option>
                <option value="AB+">AB+</option>
                <option value="AB-">AB-</option>
                <option value="O+">O+</option>
                <option value="O-">O-</option>
              </select>
            </div>
            <button
              type="button"
              className="btn btn-primary"
              disabled={loading}
              onClick={handleCreateProfile}
            >
              {loading ? t('onboarding.creating_profile') : t('onboarding.create_profile_btn')}
            </button>
          </div>
        );

      case 6:
        return (
          <div style={{ textAlign: 'center' }}>
            <h2 style={{ marginBottom: 16 }}>{t('onboarding.setup_complete')}</h2>
            <div
              style={{
                display: 'flex',
                flexDirection: 'column',
                gap: 8,
                alignItems: 'flex-start',
                margin: '0 auto 24px',
                maxWidth: 300,
                fontSize: 15,
              }}
            >
              <div>
                <span style={{ color: 'var(--color-success)', marginRight: 8 }}>
                  &#10003;
                </span>
                {t('onboarding.account_created')}
              </div>
              <div>
                <span style={{ color: 'var(--color-success)', marginRight: 8 }}>
                  &#10003;
                </span>
                {t('onboarding.recovery_codes_saved')}
              </div>
              <div>
                <span
                  style={{
                    color: data.twoFactorEnabled
                      ? 'var(--color-success)'
                      : 'var(--color-text-secondary)',
                    marginRight: 8,
                  }}
                >
                  {data.twoFactorEnabled ? '\u2713' : '\u2014'}
                </span>
                {t('onboarding.two_factor_auth')}
                {!data.twoFactorEnabled && (
                  <span
                    style={{
                      fontSize: 12,
                      color: 'var(--color-text-secondary)',
                      marginLeft: 4,
                    }}
                  >
                    {t('onboarding.skipped')}
                  </span>
                )}
              </div>
              <div>
                <span style={{ color: 'var(--color-success)', marginRight: 8 }}>
                  &#10003;
                </span>
                {t('onboarding.health_profile_created')}
              </div>
            </div>
            <button
              type="button"
              className="btn btn-primary"
              onClick={() => navigate('/')}
            >
              {t('onboarding.go_to_dashboard')}
            </button>
          </div>
        );

      default:
        return null;
    }
  };

  return (
    <div className="onboarding-page">
      <div className="onboarding-card">
        <div className="progress-bar">
          <div
            className="progress-bar-fill"
            style={{ width: `${progressPercent}%` }}
          />
        </div>
        <div className="step-indicator">{t('onboarding.step_of', { step, total: TOTAL_STEPS })}</div>
        {error && <div className="alert alert-error">{error}</div>}
        {renderStep()}
      </div>
    </div>
  );
}
