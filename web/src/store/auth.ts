import { create } from 'zustand';

interface AuthState {
  isAuthenticated: boolean;
  userId: string | null;
  email: string | null;
  role: string | null;
  login: (userId: string, role: string, email?: string) => void;
  logout: () => Promise<void>;
  checkAuth: () => void;
}

export const useAuthStore = create<AuthState>((set) => ({
  isAuthenticated: !!localStorage.getItem('user_id'),
  userId: localStorage.getItem('user_id'),
  email: localStorage.getItem('user_email'),
  role: localStorage.getItem('user_role'),

  login: (userId, role, email) => {
    localStorage.setItem('user_id', userId);
    localStorage.setItem('user_role', role);
    if (email) localStorage.setItem('user_email', email);
    set({ isAuthenticated: true, userId, role, email: email || localStorage.getItem('user_email') });
  },

  logout: async () => {
    try {
      await fetch(`${import.meta.env.VITE_API_URL || ''}/api/v1/auth/logout`, {
        method: 'POST',
        credentials: 'include',
      });
    } catch {
      // Best-effort: clear local state even if the server call fails.
    }
    localStorage.removeItem('user_id');
    localStorage.removeItem('user_role');
    localStorage.removeItem('user_email');
    set({ isAuthenticated: false, userId: null, email: null, role: null });
  },

  checkAuth: () => {
    const userId = localStorage.getItem('user_id');
    set({ isAuthenticated: !!userId });
  },
}));
