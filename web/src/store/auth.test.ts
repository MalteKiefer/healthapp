import { describe, it, expect, beforeEach, vi } from 'vitest';
import { useAuthStore } from './auth';

// Mock fetch so logout() doesn't make real network calls
globalThis.fetch = vi.fn().mockResolvedValue({ ok: true });

describe('Auth store', () => {
  beforeEach(() => {
    localStorage.clear();
    useAuthStore.setState({
      isAuthenticated: false,
      userId: null,
      role: null,
      email: null,
    });
  });

  it('starts unauthenticated', () => {
    const state = useAuthStore.getState();
    expect(state.isAuthenticated).toBe(false);
    expect(state.userId).toBeNull();
  });

  it('login sets auth state and localStorage', () => {
    const { login } = useAuthStore.getState();
    login('user-1', 'admin');

    const state = useAuthStore.getState();
    expect(state.isAuthenticated).toBe(true);
    expect(state.userId).toBe('user-1');
    expect(state.role).toBe('admin');
    expect(localStorage.getItem('user_id')).toBe('user-1');
    expect(localStorage.getItem('user_role')).toBe('admin');
  });

  it('logout clears auth state and localStorage', async () => {
    const { login, logout } = useAuthStore.getState();
    login('user-1', 'user');
    await logout();

    const state = useAuthStore.getState();
    expect(state.isAuthenticated).toBe(false);
    expect(state.userId).toBeNull();
    expect(localStorage.getItem('user_id')).toBeNull();
  });
});
