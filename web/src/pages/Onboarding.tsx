import { useState, useCallback } from 'react';
import { useNavigate } from 'react-router-dom';
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

  if (score <= 2) return { score, label: 'Weak', color: 'var(--color-danger)' };
  if (score <= 4) return { score, label: 'Fair', color: 'var(--color-warning)' };
  return { score, label: 'Strong', color: 'var(--color-success)' };
}

// ---- Component ----

const TOTAL_STEPS = 6;

export function Onboarding() {
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
      setError('All fields are required.');
      return;
    }
    if (data.passphrase !== data.passphraseConfirm) {
      setError('Passphrases do not match.');
      return;
    }
    if (data.passphrase.length < 8) {
      setError('Passphrase must be at least 8 characters.');
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
        setError('Connection error. Please try again.');
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
        setError('Failed to set up 2FA. Please try again.');
      }
    } finally {
      setLoading(false);
    }
  };

  const handleVerify2FA = async () => {
    setError('');
    if (data.totpCode.length !== 6) {
      setError('Please enter a 6-digit code.');
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
        setError('Verification failed. Please try again.');
      }
    } finally {
      setLoading(false);
    }
  };

  const handleCreateProfile = async () => {
    setError('');
    if (!data.profileName) {
      setError('Profile name is required.');
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
        setError('Failed to create profile. Please try again.');
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
            <h1>Welcome to HealthVault</h1>
            <p className="auth-tagline" style={{ marginBottom: 16 }}>
              Your personal health data, protected by zero-knowledge encryption.
              Only you can access your information — not even our servers can
              read it.
            </p>
            <div className="alert alert-warning" style={{ marginBottom: 24 }}>
              <strong>Important:</strong> Your passphrase cannot be reset. If
              you lose it, your data is permanently inaccessible.
            </div>
            <button
              type="button"
              className="btn btn-primary"
              onClick={() => setStep(2)}
            >
              Get Started
            </button>
          </div>
        );

      case 2:
        return (
          <div>
            <h2>Account Setup</h2>
            <div className="form-group">
              <label htmlFor="ob-email">Email</label>
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
              <label htmlFor="ob-display-name">Display Name</label>
              <input
                id="ob-display-name"
                type="text"
                value={data.displayName}
                onChange={(e) => update('displayName', e.target.value)}
                required
              />
            </div>
            <div className="form-group">
              <label htmlFor="ob-passphrase">Passphrase</label>
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
                      {strength.label}
                    </span>
                  </div>
                </div>
              )}
            </div>
            <div className="form-group">
              <label htmlFor="ob-passphrase-confirm">Confirm Passphrase</label>
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
              Remember: your passphrase is the only way to access your data. We
              cannot recover it for you.
            </p>
            <button
              type="button"
              className="btn btn-primary"
              disabled={loading}
              onClick={handleAccountSetup}
            >
              {loading ? 'Creating account...' : 'Continue'}
            </button>
          </div>
        );

      case 3:
        return (
          <div>
            <h2>Recovery Codes</h2>
            <p
              style={{
                fontSize: 14,
                color: 'var(--color-text-secondary)',
                marginBottom: 16,
              }}
            >
              Save these recovery codes in a safe place. They can be used to
              access your account if you lose your second factor.
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
                Copy All
              </button>
              <button
                type="button"
                className="btn btn-secondary"
                onClick={handleDownloadCodes}
              >
                Download as .txt
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
              I have saved these codes in a safe place
            </label>
            <button
              type="button"
              className="btn btn-primary"
              disabled={!data.codesAcknowledged}
              onClick={() => setStep(4)}
            >
              Continue
            </button>
          </div>
        );

      case 4:
        return (
          <div>
            <h2>Two-Factor Authentication</h2>
            <p
              style={{
                fontSize: 14,
                color: 'var(--color-text-secondary)',
                marginBottom: 16,
              }}
            >
              Add an extra layer of security to your account with a TOTP
              authenticator app.
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
                  {loading ? 'Setting up...' : 'Set up 2FA'}
                </button>
              </div>
            ) : (
              <div>
                <div className="form-group">
                  <label>Provisioning URI</label>
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
                    Copy this URI into your authenticator app, or scan the QR
                    code (coming soon).
                  </p>
                </div>
                <div className="form-group">
                  <label htmlFor="ob-totp">Verification Code</label>
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
                  {loading ? 'Verifying...' : 'Verify & Continue'}
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
                Skip for now
              </button>
            </div>
          </div>
        );

      case 5:
        return (
          <div>
            <h2>Create Your First Profile</h2>
            <p
              style={{
                fontSize: 14,
                color: 'var(--color-text-secondary)',
                marginBottom: 16,
              }}
            >
              Set up a health profile. You can add more profiles later for
              family members.
            </p>
            <div className="form-group">
              <label htmlFor="ob-profile-name">Profile Name</label>
              <input
                id="ob-profile-name"
                type="text"
                value={data.profileName}
                onChange={(e) => update('profileName', e.target.value)}
                required
                placeholder="e.g. John"
              />
            </div>
            <div className="form-group">
              <label htmlFor="ob-dob">Date of Birth</label>
              <input
                id="ob-dob"
                type="date"
                value={data.dateOfBirth}
                onChange={(e) => update('dateOfBirth', e.target.value)}
              />
            </div>
            <div className="form-group">
              <label htmlFor="ob-sex">Biological Sex</label>
              <select
                id="ob-sex"
                value={data.biologicalSex}
                onChange={(e) => update('biologicalSex', e.target.value)}
              >
                <option value="unspecified">Prefer not to say</option>
                <option value="male">Male</option>
                <option value="female">Female</option>
                <option value="other">Other</option>
              </select>
            </div>
            <div className="form-group">
              <label htmlFor="ob-blood-type">Blood Type</label>
              <select
                id="ob-blood-type"
                value={data.bloodType}
                onChange={(e) => update('bloodType', e.target.value)}
              >
                <option value="">Unknown</option>
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
              {loading ? 'Creating profile...' : 'Create Profile'}
            </button>
          </div>
        );

      case 6:
        return (
          <div style={{ textAlign: 'center' }}>
            <h2 style={{ marginBottom: 16 }}>Setup Complete</h2>
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
                Account created
              </div>
              <div>
                <span style={{ color: 'var(--color-success)', marginRight: 8 }}>
                  &#10003;
                </span>
                Recovery codes saved
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
                Two-factor authentication
                {!data.twoFactorEnabled && (
                  <span
                    style={{
                      fontSize: 12,
                      color: 'var(--color-text-secondary)',
                      marginLeft: 4,
                    }}
                  >
                    (skipped)
                  </span>
                )}
              </div>
              <div>
                <span style={{ color: 'var(--color-success)', marginRight: 8 }}>
                  &#10003;
                </span>
                Health profile created
              </div>
            </div>
            <button
              type="button"
              className="btn btn-primary"
              onClick={() => navigate('/')}
            >
              Go to Dashboard
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
        <div className="step-indicator">Step {step} of {TOTAL_STEPS}</div>
        {error && <div className="alert alert-error">{error}</div>}
        {renderStep()}
      </div>
    </div>
  );
}
