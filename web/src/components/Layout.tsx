import { Link, Outlet, useNavigate } from 'react-router-dom';
import { useTranslation } from 'react-i18next';
import { useAuthStore } from '../store/auth';
import { useUIStore } from '../store/ui';
import { api } from '../api/client';
import { clearAllKeys } from '../crypto';
import { NotificationBell } from './NotificationBell';
import { SyncIndicator } from './SyncIndicator';
import { useIdleTimeout } from '../hooks/useIdleTimeout';

const navItems = [
  { path: '/', label: 'nav.dashboard', icon: '⊞' },
  { path: '/search', label: 'common.search', icon: '🔍' },
  { path: '/vitals', label: 'nav.vitals', icon: '♡' },
  { path: '/labs', label: 'nav.labs', icon: '⚗' },
  { path: '/diary', label: 'nav.diary', icon: '📋' },
  { path: '/medications', label: 'nav.medications', icon: '💊' },
  { path: '/appointments', label: 'nav.appointments', icon: '📅' },
  { path: '/documents', label: 'nav.documents', icon: '📄' },
  { path: '/vaccinations', label: 'nav.vaccinations', icon: '💉' },
  { path: '/allergies', label: 'nav.allergies', icon: '⚠' },
  { path: '/diagnoses', label: 'nav.diagnoses', icon: '🏥' },
  { path: '/symptoms', label: 'nav.symptoms', icon: '📊' },
  { path: '/tasks', label: 'nav.tasks', icon: '☐' },
  { path: '/contacts', label: 'nav.contacts', icon: '👤' },
];

export function Layout() {
  const { t } = useTranslation();
  const navigate = useNavigate();
  const { logout, role } = useAuthStore();
  const { sidebarOpen, toggleSidebar, theme, toggleTheme } = useUIStore();
  useIdleTimeout();

  const handleLogout = async () => {
    try {
      await api.post('/api/v1/auth/logout');
    } catch { /* ignore */ }
    clearAllKeys(); // Wipe encryption keys from memory
    logout();
    navigate('/login');
  };

  return (
    <div className={`app-layout ${theme}`} data-theme={theme}>
      <SyncIndicator />

      <aside className={`sidebar ${sidebarOpen ? 'open' : 'collapsed'}`}>
        <div className="sidebar-header">
          <h1 className="app-title">{t('app.name')}</h1>
          <div className="sidebar-actions">
            <NotificationBell />
            <button onClick={toggleSidebar} className="btn-icon" aria-label="Toggle sidebar">
              ☰
            </button>
          </div>
        </div>

        <nav className="sidebar-nav">
          {navItems.map((item) => (
            <Link key={item.path} to={item.path} className="nav-item">
              <span className="nav-icon">{item.icon}</span>
              {sidebarOpen && <span className="nav-label">{t(item.label)}</span>}
            </Link>
          ))}
        </nav>

        <div className="sidebar-footer">
          <Link to="/calendar-feeds" className="nav-item">
            <span className="nav-icon">📅</span>
            {sidebarOpen && <span className="nav-label">Calendar Feeds</span>}
          </Link>
          {role === 'admin' && (
            <Link to="/admin" className="nav-item">
              <span className="nav-icon">🛡</span>
              {sidebarOpen && <span className="nav-label">{t('nav.admin')}</span>}
            </Link>
          )}
          <Link to="/settings" className="nav-item">
            <span className="nav-icon">⚙</span>
            {sidebarOpen && <span className="nav-label">{t('nav.settings')}</span>}
          </Link>
          <button onClick={toggleTheme} className="nav-item btn-text">
            <span className="nav-icon">{theme === 'light' ? '🌙' : '☀'}</span>
            {sidebarOpen && <span className="nav-label">{theme === 'light' ? 'Dark' : 'Light'}</span>}
          </button>
          <button onClick={handleLogout} className="nav-item btn-text">
            <span className="nav-icon">↩</span>
            {sidebarOpen && <span className="nav-label">{t('nav.logout')}</span>}
          </button>
        </div>
      </aside>

      <main className="main-content">
        <Outlet />
      </main>
    </div>
  );
}
