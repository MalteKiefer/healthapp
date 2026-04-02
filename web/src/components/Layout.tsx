import { useState, useEffect, useRef, useMemo, type ReactNode } from 'react';
import { Link, Outlet, useNavigate, useLocation } from 'react-router-dom';
import { useTranslation } from 'react-i18next';
import { useAuthStore } from '../store/auth';
import { useUIStore } from '../store/ui';
import { clearAllKeys } from '../crypto';
import { NotificationBell } from './NotificationBell';
import { SyncIndicator } from './SyncIndicator';
import { useIdleTimeout } from '../hooks/useIdleTimeout';

interface NavItem {
  path: string;
  label: string;
  icon: ReactNode;
}

interface NavGroup {
  key: string;
  label: string;
  icon: ReactNode;
  items: NavItem[];
}

const svgProps = {
  width: 24,
  height: 24,
  viewBox: '0 0 24 24',
  fill: 'none',
  stroke: 'currentColor',
  strokeWidth: 1.5,
  strokeLinecap: 'round' as const,
  strokeLinejoin: 'round' as const,
};

const icons = {
  dashboard: (
    <svg {...svgProps}>
      <rect x="3" y="3" width="7" height="7" rx="1" />
      <rect x="14" y="3" width="7" height="7" rx="1" />
      <rect x="3" y="14" width="7" height="7" rx="1" />
      <rect x="14" y="14" width="7" height="7" rx="1" />
    </svg>
  ),
  search: (
    <svg {...svgProps}>
      <circle cx="11" cy="11" r="8" />
      <path d="M21 21l-4.35-4.35" />
    </svg>
  ),
  heart: (
    <svg {...svgProps}>
      <path d="M20.84 4.61a5.5 5.5 0 0 0-7.78 0L12 5.67l-1.06-1.06a5.5 5.5 0 0 0-7.78 7.78l1.06 1.06L12 21.23l7.78-7.78 1.06-1.06a5.5 5.5 0 0 0 0-7.78z" />
    </svg>
  ),
  beaker: (
    <svg {...svgProps}>
      <path d="M9 3h6" />
      <path d="M10 3v6.5L4 18h16l-6-8.5V3" />
    </svg>
  ),
  pill: (
    <svg {...svgProps}>
      <path d="M10.5 1.5l-8 8a4.95 4.95 0 0 0 7 7l8-8a4.95 4.95 0 0 0-7-7z" />
      <path d="M6.5 10.5l7-7" />
    </svg>
  ),
  syringe: (
    <svg {...svgProps}>
      <path d="M18 2l4 4" />
      <path d="M17 7l-10 10" />
      <path d="M19 5l-1.5 1.5" />
      <path d="M7 17l-4 4" />
      <path d="M15 5l-8.5 8.5" />
      <path d="M9 11l4 4" />
    </svg>
  ),
  alertTriangle: (
    <svg {...svgProps}>
      <path d="M10.29 3.86L1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z" />
      <line x1="12" y1="9" x2="12" y2="13" />
      <line x1="12" y1="17" x2="12.01" y2="17" />
    </svg>
  ),
  clipboardList: (
    <svg {...svgProps}>
      <path d="M16 4h2a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2h2" />
      <rect x="8" y="2" width="8" height="4" rx="1" />
      <path d="M9 12h6" />
      <path d="M9 16h6" />
    </svg>
  ),
  bookOpen: (
    <svg {...svgProps}>
      <path d="M2 3h6a4 4 0 0 1 4 4v14a3 3 0 0 0-3-3H2z" />
      <path d="M22 3h-6a4 4 0 0 0-4 4v14a3 3 0 0 1 3-3h7z" />
    </svg>
  ),
  activity: (
    <svg {...svgProps}>
      <polyline points="22 12 18 12 15 21 9 3 6 12 2 12" />
    </svg>
  ),
  calendar: (
    <svg {...svgProps}>
      <rect x="3" y="4" width="18" height="18" rx="2" />
      <line x1="16" y1="2" x2="16" y2="6" />
      <line x1="8" y1="2" x2="8" y2="6" />
      <line x1="3" y1="10" x2="21" y2="10" />
    </svg>
  ),
  checkSquare: (
    <svg {...svgProps}>
      <polyline points="9 11 12 14 22 4" />
      <path d="M21 12v7a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h11" />
    </svg>
  ),
  fileText: (
    <svg {...svgProps}>
      <path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z" />
      <polyline points="14 2 14 8 20 8" />
      <line x1="16" y1="13" x2="8" y2="13" />
      <line x1="16" y1="17" x2="8" y2="17" />
      <polyline points="10 9 9 9 8 9" />
    </svg>
  ),
  users: (
    <svg {...svgProps}>
      <path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2" />
      <circle cx="9" cy="7" r="4" />
      <path d="M23 21v-2a4 4 0 0 0-3-3.87" />
      <path d="M16 3.13a4 4 0 0 1 0 7.75" />
    </svg>
  ),
  rss: (
    <svg {...svgProps}>
      <path d="M4 11a9 9 0 0 1 9 9" />
      <path d="M4 4a16 16 0 0 1 16 16" />
      <circle cx="5" cy="19" r="1" />
    </svg>
  ),
  share: (
    <svg {...svgProps}>
      <circle cx="18" cy="5" r="3" />
      <circle cx="6" cy="12" r="3" />
      <circle cx="18" cy="19" r="3" />
      <line x1="8.59" y1="13.51" x2="15.42" y2="17.49" />
      <line x1="15.41" y1="6.51" x2="8.59" y2="10.49" />
    </svg>
  ),
  shield: (
    <svg {...svgProps}>
      <path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z" />
    </svg>
  ),
  settings: (
    <svg {...svgProps}>
      <circle cx="12" cy="12" r="3" />
      <path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 0 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-4 0v-.09a1.65 1.65 0 0 0-1.08-1.51 1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 0 1-2.83-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1 0-4h.09a1.65 1.65 0 0 0 1.51-1.08 1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 0 1 2.83-2.83l.06.06a1.65 1.65 0 0 0 1.82.33H9a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 0 1 2.83 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82V9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1.08z" />
    </svg>
  ),
  moon: (
    <svg {...svgProps}>
      <path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z" />
    </svg>
  ),
  sun: (
    <svg {...svgProps}>
      <circle cx="12" cy="12" r="5" />
      <line x1="12" y1="1" x2="12" y2="3" />
      <line x1="12" y1="21" x2="12" y2="23" />
      <line x1="4.22" y1="4.22" x2="5.64" y2="5.64" />
      <line x1="18.36" y1="18.36" x2="19.78" y2="19.78" />
      <line x1="1" y1="12" x2="3" y2="12" />
      <line x1="21" y1="12" x2="23" y2="12" />
      <line x1="4.22" y1="19.78" x2="5.64" y2="18.36" />
      <line x1="18.36" y1="5.64" x2="19.78" y2="4.22" />
    </svg>
  ),
  logOut: (
    <svg {...svgProps}>
      <path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4" />
      <polyline points="16 17 21 12 16 7" />
      <line x1="21" y1="12" x2="9" y2="12" />
    </svg>
  ),
  download: (
    <svg {...svgProps}>
      <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4" />
      <polyline points="7 10 12 15 17 10" />
      <line x1="12" y1="15" x2="12" y2="3" />
    </svg>
  ),
  emergency: (
    <svg {...svgProps}>
      <path d="M20.84 4.61a5.5 5.5 0 0 0-7.78 0L12 5.67l-1.06-1.06a5.5 5.5 0 0 0-7.78 7.78l1.06 1.06L12 21.23l7.78-7.78 1.06-1.06a5.5 5.5 0 0 0 0-7.78z" />
      <line x1="12" y1="9" x2="12" y2="15" />
      <line x1="9" y1="12" x2="15" y2="12" />
    </svg>
  ),
  menu: (
    <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
      <path d="M3 12h18M3 6h18M3 18h18" />
    </svg>
  ),
  close: (
    <svg {...svgProps}>
      <line x1="18" y1="6" x2="6" y2="18" />
      <line x1="6" y1="6" x2="18" y2="18" />
    </svg>
  ),
  chevronDown: (
    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <polyline points="6 9 12 15 18 9" />
    </svg>
  ),
  collapse: (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
      <polyline points="11 17 6 12 11 7" />
      <polyline points="18 17 13 12 18 7" />
    </svg>
  ),
  expand: (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
      <polyline points="13 17 18 12 13 7" />
      <polyline points="6 17 11 12 6 7" />
    </svg>
  ),
};

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

  const [avatarMenuOpen, setAvatarMenuOpen] = useState(false);
  const [mobileMenuOpen, setMobileMenuOpen] = useState(false);
  const [avatarUrl, setAvatarUrl] = useState<string | null>(localStorage.getItem('user_avatar'));
  const avatarMenuRef = useRef<HTMLDivElement>(null);

  const navGroups: NavGroup[] = useMemo(() => [
    {
      key: 'health',
      label: 'nav.group_health',
      icon: icons.heart,
      items: [
        { path: '/', label: 'nav.dashboard', icon: icons.dashboard },
        { path: '/search', label: 'common.search', icon: icons.search },
        { path: '/vitals', label: 'nav.vitals', icon: icons.heart },
        { path: '/labs', label: 'nav.labs', icon: icons.beaker },
        { path: '/medications', label: 'nav.medications', icon: icons.pill },
        { path: '/vaccinations', label: 'nav.vaccinations', icon: icons.syringe },
        { path: '/allergies', label: 'nav.allergies', icon: icons.alertTriangle },
        { path: '/diagnoses', label: 'nav.diagnoses', icon: icons.clipboardList },
      ],
    },
    {
      key: 'tracking',
      label: 'nav.group_tracking',
      icon: icons.activity,
      items: [
        { path: '/diary', label: 'nav.diary', icon: icons.bookOpen },
        { path: '/symptoms', label: 'nav.symptoms', icon: icons.activity },
        { path: '/appointments', label: 'nav.appointments', icon: icons.calendar },
        { path: '/tasks', label: 'nav.tasks', icon: icons.checkSquare },
      ],
    },
    {
      key: 'manage',
      label: 'nav.group_manage',
      icon: icons.fileText,
      items: [
        { path: '/documents', label: 'nav.documents', icon: icons.fileText },
        { path: '/contacts', label: 'nav.contacts', icon: icons.users },
        { path: '/family', label: 'nav.family', icon: icons.users },
        { path: '/shares', label: 'nav.shares', icon: icons.share },
        { path: '/emergency', label: 'nav.emergency', icon: icons.emergency },
      ],
    },
    {
      key: 'system',
      label: 'nav.group_system',
      icon: icons.settings,
      items: [
        { path: '/settings', label: 'nav.settings', icon: icons.settings },
        { path: '/calendar-feeds', label: 'nav.calendar_feeds', icon: icons.rss },
        { path: '/export', label: 'nav.export', icon: icons.download },
        { path: '/activity', label: 'nav.activity', icon: icons.activity },
        ...(role === 'admin' ? [{ path: '/admin', label: 'nav.admin', icon: icons.shield }] : []),
      ],
    },
  ], [role]);

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

  // Avatar menu click-outside
  useEffect(() => {
    function handleClickOutside(event: MouseEvent) {
      if (avatarMenuRef.current && !avatarMenuRef.current.contains(event.target as Node)) {
        setAvatarMenuOpen(false);
      }
    }
    if (avatarMenuOpen) {
      document.addEventListener('mousedown', handleClickOutside);
    }
    return () => document.removeEventListener('mousedown', handleClickOutside);
  }, [avatarMenuOpen]);

  // Avatar URL sync
  useEffect(() => {
    const onAvatarChanged = () => setAvatarUrl(localStorage.getItem('user_avatar'));
    window.addEventListener('avatar-changed', onAvatarChanged);
    return () => window.removeEventListener('avatar-changed', onAvatarChanged);
  }, []);

  const handleLogout = async () => {
    clearAllKeys();
    await logout();
    navigate('/login');
  };

  const displayName = email || 'User';
  const initials = email ? email.charAt(0).toUpperCase() : 'U';
  const activeGroupItems = navGroups.find((g) => g.key === activeNavGroup)?.items || [];

  const renderAvatar = () =>
    avatarUrl ? (
      <img src={avatarUrl} alt="" className="avatar-circle avatar-img" />
    ) : (
      <div className="avatar-circle">{initials}</div>
    );

  const renderAvatarDropdown = () =>
    avatarMenuOpen ? (
      <div className="avatar-dropdown">
        <div className="avatar-dropdown-header">
          <strong>{displayName}</strong>
          {role && <span className="user-role">{role}</span>}
        </div>
        <div className="avatar-dropdown-divider" />
        <Link to="/settings" className="avatar-dropdown-item" onClick={() => setAvatarMenuOpen(false)}>
          {t('nav.settings')}
        </Link>
        <button className="avatar-dropdown-item" onClick={toggleTheme}>
          {theme === 'light' ? t('nav.dark_mode') : t('nav.light_mode')}
        </button>
        <div className="avatar-dropdown-divider" />
        <button className="avatar-dropdown-item avatar-dropdown-danger" onClick={handleLogout}>
          {t('nav.logout')}
        </button>
      </div>
    ) : null;

  return (
    <div className={`app-layout${sidebarCollapsed ? ' sidebar-collapsed' : ''}`} data-theme={theme}>
      <SyncIndicator />

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
            <div className="avatar-menu" ref={avatarMenuRef}>
              <button className="avatar-btn" onClick={() => setAvatarMenuOpen((p) => !p)}>
                {renderAvatar()}
              </button>
              {renderAvatarDropdown()}
            </div>
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
            <div className="avatar-menu" ref={!avatarMenuOpen ? undefined : avatarMenuRef}>
              <button className="avatar-btn" onClick={() => setAvatarMenuOpen((p) => !p)}>
                {renderAvatar()}
              </button>
              {renderAvatarDropdown()}
            </div>
          </div>
        </header>
        <Outlet />
      </main>
    </div>
  );
}
