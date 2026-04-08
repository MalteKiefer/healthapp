import { useState, useEffect } from 'react';
import { Link, Outlet, useNavigate, useLocation } from 'react-router-dom';
import { useTranslation } from 'react-i18next';
import { useAuthStore } from '../store/auth';
import { useUIStore } from '../store/ui';
import { clearAllKeys, generateProfileKey, getIdentityPrivateKey, setProfileKey, createKeyGrant } from '../crypto';
import { useProfiles } from '../hooks/useProfiles';
import { api } from '../api/client';
import type { Profile } from '../api/profiles';
import { useMutation, useQueryClient } from '@tanstack/react-query';
import { NotificationBell } from './NotificationBell';
import { SyncIndicator } from './SyncIndicator';
import { useIdleTimeout } from '../hooks/useIdleTimeout';
import { icons, useNavGroups } from './layout/NavItems';
import { AvatarMenu } from './layout/AvatarMenu';

export function Layout() {
  const { t } = useTranslation();
  const navigate = useNavigate();
  const location = useLocation();
  const { logout, role, email } = useAuthStore();
  const {
    sidebarCollapsed, toggleSidebarCollapsed,
    activeNavGroup, setActiveNavGroup,
    theme, toggleTheme,
  } = useUIStore();
  useIdleTimeout();

  const [mobileMenuOpen, setMobileMenuOpen] = useState(false);

  const navGroups = useNavGroups(role);

  const isActive = (path: string) =>
    path === '/' ? location.pathname === '/' : location.pathname.startsWith(path);

  // Auto-derive active group from current route
  useEffect(() => {
    for (const group of navGroups) {
      if (group.items.some((item) => isActive(item.path))) {
        setActiveNavGroup(group.key);
        return;
      }
    }
  }, [location.pathname, navGroups, setActiveNavGroup]);

  // Close mobile menu on navigation
  useEffect(() => {
    setMobileMenuOpen(false);
  }, [location.pathname]);

  const handleLogout = async () => {
    clearAllKeys();
    await logout();
    queryClient.clear();
    navigate('/login');
  };

  const activeGroupItems = navGroups.find((g) => g.key === activeNavGroup)?.items || [];

  // ── Profile gate: block the app until the user creates their first profile ──
  const { data: profilesData, isLoading: profilesLoading } = useProfiles();
  const profiles = profilesData || [];
  const queryClient = useQueryClient();
  const { userId } = useAuthStore();

  const [newProfileName, setNewProfileName] = useState('');
  const [newProfileDOB, setNewProfileDOB] = useState('');
  const [newProfileSex, setNewProfileSex] = useState('unspecified');

  const createFirstProfile = useMutation({
    mutationFn: async (body: { display_name: string; date_of_birth?: string; biological_sex: string }) => {
      const idPriv = getIdentityPrivateKey();
      const me = await api.get<{ identity_pubkey: string }>('/api/v1/users/me');
      if (idPriv && me.identity_pubkey && userId) {
        const profileKey = await generateProfileKey();
        const wrapped = await createKeyGrant(profileKey, idPriv, me.identity_pubkey, `selfgrant:${userId}`);
        const created = await api.post<Profile>('/api/v1/profiles', { ...body, self_grant: { encrypted_key: wrapped } });
        setProfileKey(created.id, profileKey);
        return created;
      }
      return api.post<Profile>('/api/v1/profiles', body);
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['profiles'] });
      setNewProfileName('');
      setNewProfileDOB('');
      setNewProfileSex('unspecified');
    },
  });

  const needsProfile = !profilesLoading && profiles.length === 0;

  return (
    <div className={`app-layout${sidebarCollapsed ? ' sidebar-collapsed' : ''}`} data-theme={theme}>
      <SyncIndicator />

      {needsProfile && (
        <div className="modal-overlay" style={{ zIndex: 9999 }}>
          <div className="modal-content" style={{ maxWidth: 420, padding: 32 }} onClick={(e) => e.stopPropagation()}>
            <h2>{t('onboarding.create_profile')}</h2>
            <p className="text-muted" style={{ marginBottom: 16 }}>{t('onboarding.create_profile_desc')}</p>
            <form onSubmit={(e) => {
              e.preventDefault();
              if (!newProfileName.trim()) return;
              createFirstProfile.mutate({
                display_name: newProfileName.trim(),
                date_of_birth: newProfileDOB || undefined,
                biological_sex: newProfileSex,
              });
            }}>
              <div className="form-group">
                <label>{t('settings.new_profile_name')}</label>
                <input type="text" value={newProfileName} onChange={(e) => setNewProfileName(e.target.value)}
                  placeholder={t('settings.new_profile_name_placeholder')} required autoFocus />
              </div>
              <div className="form-group">
                <label>{t('settings.new_profile_dob')}</label>
                <input type="date" value={newProfileDOB} onChange={(e) => setNewProfileDOB(e.target.value)} />
              </div>
              <div className="form-group">
                <label>{t('settings.new_profile_sex')}</label>
                <select value={newProfileSex} onChange={(e) => setNewProfileSex(e.target.value)}>
                  <option value="unspecified">{t('settings.sex_unspecified')}</option>
                  <option value="female">{t('settings.sex_female')}</option>
                  <option value="male">{t('settings.sex_male')}</option>
                  <option value="other">{t('settings.sex_other')}</option>
                </select>
              </div>
              <button type="submit" className="btn btn-add" style={{ width: '100%' }}
                disabled={!newProfileName.trim() || createFirstProfile.isPending}>
                {createFirstProfile.isPending ? t('common.loading') : t('settings.create_profile_btn')}
              </button>
            </form>
          </div>
        </div>
      )}

      {/* ═══════════════════════════════════════════════════
          DESKTOP SIDEBAR — hidden on tablet/mobile via CSS
         ═══════════════════════════════════════════════════ */}
      <aside className={`sidebar${sidebarCollapsed ? ' collapsed' : ''}`}>
        <div className="sidebar-header">
          <Link to="/" className="sidebar-brand">
            <svg className="brand-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
              <path d="M20.84 4.61a5.5 5.5 0 0 0-7.78 0L12 5.67l-1.06-1.06a5.5 5.5 0 0 0-7.78 7.78l1.06 1.06L12 21.23l7.78-7.78 1.06-1.06a5.5 5.5 0 0 0 0-7.78z" />
            </svg>
            {!sidebarCollapsed && <span className="brand-text">HealthVault</span>}
          </Link>
        </div>

        <nav className="sidebar-nav">
          {navGroups.map((group) => (
            <div key={group.key} className="nav-group">
              {!sidebarCollapsed && <div className="nav-group-label">{t(group.label)}</div>}
              {sidebarCollapsed && <div className="nav-divider" />}
              {group.items.map((item) => (
                <Link
                  key={item.path}
                  to={item.path}
                  className={`nav-item${isActive(item.path) ? ' active' : ''}`}
                >
                  <span className="nav-icon">{item.icon}</span>
                  {!sidebarCollapsed && <span className="nav-label">{t(item.label)}</span>}
                </Link>
              ))}
            </div>
          ))}
        </nav>

        <div className="sidebar-footer">
          <button className="btn-icon sidebar-theme-toggle" onClick={toggleTheme} aria-label="Toggle theme">
            {theme === 'light' ? icons.moon : icons.sun}
          </button>
          <button className="btn-icon sidebar-collapse-toggle" onClick={toggleSidebarCollapsed} aria-label="Toggle sidebar">
            {sidebarCollapsed ? icons.expand : icons.collapse}
          </button>
        </div>
      </aside>

      {/* ═══════════════════════════════════════════════════
          TABLET TOP-NAV — hidden on desktop/mobile via CSS
         ═══════════════════════════════════════════════════ */}
      <header className="tablet-nav">
        <div className="tablet-nav-primary">
          <Link to="/" className="tablet-brand">
            <svg className="brand-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
              <path d="M20.84 4.61a5.5 5.5 0 0 0-7.78 0L12 5.67l-1.06-1.06a5.5 5.5 0 0 0-7.78 7.78l1.06 1.06L12 21.23l7.78-7.78 1.06-1.06a5.5 5.5 0 0 0 0-7.78z" />
            </svg>
          </Link>
          <nav className="tablet-nav-groups">
            {navGroups.map((group) => (
              <button
                key={group.key}
                className={`tablet-group-tab${activeNavGroup === group.key ? ' active' : ''}`}
                onClick={() => setActiveNavGroup(group.key)}
              >
                {t(group.label)}
              </button>
            ))}
          </nav>
          <div className="tablet-nav-actions">
            <NotificationBell />
            <AvatarMenu email={email} role={role} theme={theme} onLogout={handleLogout} onToggleTheme={toggleTheme} />
          </div>
        </div>
        <nav className="tablet-subnav">
          {activeGroupItems.map((item) => (
            <Link
              key={item.path}
              to={item.path}
              className={`subnav-pill${isActive(item.path) ? ' active' : ''}`}
            >
              {t(item.label)}
            </Link>
          ))}
        </nav>
      </header>

      {/* ═══════════════════════════════════════════════════
          MOBILE HEADER — hidden on tablet/desktop via CSS
         ═══════════════════════════════════════════════════ */}
      <header className="mobile-header">
        <Link to="/" className="mobile-brand">
          <svg className="brand-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
            <path d="M20.84 4.61a5.5 5.5 0 0 0-7.78 0L12 5.67l-1.06-1.06a5.5 5.5 0 0 0-7.78 7.78l1.06 1.06L12 21.23l7.78-7.78 1.06-1.06a5.5 5.5 0 0 0 0-7.78z" />
          </svg>
          <span className="brand-text">HealthVault</span>
        </Link>
        <div className="mobile-header-actions">
          <NotificationBell />
          <button className="mobile-menu-btn" onClick={() => setMobileMenuOpen(true)} aria-label="Menu">
            {icons.menu}
          </button>
        </div>
      </header>

      {/* ═══════════════════════════════════════════════════
          MOBILE FULLSCREEN OVERLAY
         ═══════════════════════════════════════════════════ */}
      {mobileMenuOpen && (
        <>
          <div className="mobile-overlay-backdrop" onClick={() => setMobileMenuOpen(false)} />
          <div className="mobile-overlay">
            <div className="mobile-overlay-header">
              <span className="mobile-overlay-title">Menu</span>
              <button className="btn-icon" onClick={() => setMobileMenuOpen(false)} aria-label="Close">
                {icons.close}
              </button>
            </div>
            <nav className="mobile-overlay-nav">
              {navGroups.map((group) => (
                <div key={group.key} className="mobile-nav-group">
                  <div className="nav-group-label">{t(group.label)}</div>
                  {group.items.map((item) => (
                    <Link
                      key={item.path}
                      to={item.path}
                      className={`nav-item${isActive(item.path) ? ' active' : ''}`}
                    >
                      <span className="nav-icon">{item.icon}</span>
                      <span className="nav-label">{t(item.label)}</span>
                    </Link>
                  ))}
                </div>
              ))}
            </nav>
            <div className="mobile-overlay-footer">
              <button className="btn-ghost" onClick={toggleTheme}>
                {theme === 'light' ? icons.moon : icons.sun}
                <span>{theme === 'light' ? t('nav.dark_mode') : t('nav.light_mode')}</span>
              </button>
            </div>
          </div>
        </>
      )}

      {/* ═══════════════════════════════════════════════════
          MAIN CONTENT
         ═══════════════════════════════════════════════════ */}
      <main className="main-content">
        {/* Desktop-only topbar for notifications + avatar */}
        <header className="topbar">
          <div className="topbar-actions">
            <NotificationBell />
            <AvatarMenu email={email} role={role} theme={theme} onLogout={handleLogout} onToggleTheme={toggleTheme} />
          </div>
        </header>
        <Outlet />
      </main>
    </div>
  );
}
