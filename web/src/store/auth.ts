import { create } from 'zustand';

interface AuthState {
  isAuthenticated: boolean;
  userId: string | null;
  role: string | null;
  login: (accessToken: string, refreshToken: string, userId: string, role: string) => void;
  logout: () => void;
  checkAuth: () => void;
}

export const useAuthStore = create<AuthState>((set) => ({
  isAuthenticated: !!localStorage.getItem('access_token'),
  userId: localStorage.getItem('user_id'),
  role: localStorage.getItem('user_role'),

  login: (accessToken, refreshToken, userId, role) => {
    localStorage.setItem('access_token', accessToken);
    localStorage.setItem('refresh_token', refreshToken);
    localStorage.setItem('user_id', userId);
    localStorage.setItem('user_role', role);
    set({ isAuthenticated: true, userId, role });
  },

  logout: () => {
    localStorage.removeItem('access_token');
    localStorage.removeItem('refresh_token');
    localStorage.removeItem('user_id');
    localStorage.removeItem('user_role');
    set({ isAuthenticated: false, userId: null, role: null });
  },

  checkAuth: () => {
    const token = localStorage.getItem('access_token');
    set({ isAuthenticated: !!token });
  },
}));
