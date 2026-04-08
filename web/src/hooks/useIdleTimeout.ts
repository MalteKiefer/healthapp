import { useEffect, useRef, useCallback } from 'react';
import { useNavigate } from 'react-router-dom';
import { useQueryClient } from '@tanstack/react-query';
import { clearAllKeys } from '../crypto';
import { useAuthStore } from '../store/auth';

const IDLE_TIMEOUT_MS = 60 * 60 * 1000; // 60 minutes
const EVENTS = ['mousedown', 'keydown', 'scroll', 'touchstart'];

/**
 * useIdleTimeout — clears encryption keys and logs out after inactivity.
 * This ensures sensitive key material doesn't persist in memory indefinitely.
 */
export function useIdleTimeout() {
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const { isAuthenticated, logout } = useAuthStore();
  const timerRef = useRef<ReturnType<typeof setTimeout>>(undefined);

  const handleIdle = useCallback(() => {
    clearAllKeys();
    logout();
    queryClient.clear();
    navigate('/login', { state: { reason: 'idle_timeout' } });
  }, [logout, queryClient, navigate]);

  const resetTimer = useCallback(() => {
    if (timerRef.current) clearTimeout(timerRef.current);
    timerRef.current = setTimeout(handleIdle, IDLE_TIMEOUT_MS);
  }, [handleIdle]);

  useEffect(() => {
    if (!isAuthenticated) return;

    resetTimer();

    for (const event of EVENTS) {
      window.addEventListener(event, resetTimer, { passive: true });
    }

    return () => {
      if (timerRef.current) clearTimeout(timerRef.current);
      for (const event of EVENTS) {
        window.removeEventListener(event, resetTimer);
      }
    };
  }, [isAuthenticated, resetTimer]);
}
