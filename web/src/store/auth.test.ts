import { describe, it, expect, beforeEach } from 'vitest';
import { useAuthStore } from './auth';

describe('Auth store', () => {
  beforeEach(() => {
    localStorage.clear();
    useAuthStore.setState({
      isAuthenticated: false,
      userId: null,
      role: null,
    });
  });

  it('starts unauthenticated', () => {
    const state = useAuthStore.getState();
    expect(state.isAuthenticated).toBe(false);
    expect(state.userId).toBeNull();
  });

  it('login sets auth state and localStorage', () => {
    const { login } = useAuthStore.getState();
    login('token123', 'refresh456', 'user-1', 'admin');

    const state = useAuthStore.getState();
    expect(state.isAuthenticated).toBe(true);
    expect(state.userId).toBe('user-1');
    expect(state.role).toBe('admin');
    expect(localStorage.getItem('access_token')).toBe('token123');
    expect(localStorage.getItem('refresh_token')).toBe('refresh456');
  });

  it('logout clears auth state and localStorage', () => {
    const { login, logout } = useAuthStore.getState();
    login('token', 'refresh', 'user-1', 'user');
    logout();

    const state = useAuthStore.getState();
    expect(state.isAuthenticated).toBe(false);
    expect(state.userId).toBeNull();
    expect(localStorage.getItem('access_token')).toBeNull();
  });
});
