import { useState, useEffect } from 'react';
import { Link, Outlet, useNavigate, useLocation } from 'react-router-dom';
import { useTranslation } from 'react-i18next';
import { useAuthStore } from '../store/auth';
import { useUIStore } from '../store/ui';
import { clearAllKeys } from '../crypto';
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
    navigate('/login');
  };

  const activeGroupItems = navGroups.find((g) => g.key === activeNavGroup)?.items || [];

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
