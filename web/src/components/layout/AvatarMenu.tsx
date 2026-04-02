import { useState, useEffect, useRef } from 'react';
import { Link } from 'react-router-dom';
import { useTranslation } from 'react-i18next';

interface AvatarMenuProps {
  email: string | null;
  role: string | null;
  theme: string;
  onLogout: () => void;
  onToggleTheme: () => void;
}

export function AvatarMenu({ email, role, theme, onLogout, onToggleTheme }: AvatarMenuProps) {
  const { t } = useTranslation();
  const [avatarMenuOpen, setAvatarMenuOpen] = useState(false);
  const [avatarUrl, setAvatarUrl] = useState<string | null>(localStorage.getItem('user_avatar'));
  const avatarMenuRef = useRef<HTMLDivElement>(null);

  const displayName = email || 'User';
  const initials = email ? email.charAt(0).toUpperCase() : 'U';

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

  const renderAvatar = () =>
    avatarUrl ? (
      <img src={avatarUrl} alt="" className="avatar-circle avatar-img" />
    ) : (
      <div className="avatar-circle">{initials}</div>
    );

  return (
    <div className="avatar-menu" ref={avatarMenuRef}>
      <button className="avatar-btn" onClick={() => setAvatarMenuOpen((p) => !p)}>
        {renderAvatar()}
      </button>
      {avatarMenuOpen && (
        <div className="avatar-dropdown">
          <div className="avatar-dropdown-header">
            <strong>{displayName}</strong>
            {role && <span className="user-role">{role}</span>}
          </div>
          <div className="avatar-dropdown-divider" />
          <Link to="/settings" className="avatar-dropdown-item" onClick={() => setAvatarMenuOpen(false)}>
            {t('nav.settings')}
          </Link>
          <button className="avatar-dropdown-item" onClick={onToggleTheme}>
            {theme === 'light' ? t('nav.dark_mode') : t('nav.light_mode')}
          </button>
          <div className="avatar-dropdown-divider" />
          <button className="avatar-dropdown-item avatar-dropdown-danger" onClick={onLogout}>
            {t('nav.logout')}
          </button>
        </div>
      )}
    </div>
  );
}
