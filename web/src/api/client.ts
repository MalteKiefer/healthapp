const API_BASE = import.meta.env.VITE_API_URL || '';

interface RequestOptions {
  method?: string;
  body?: unknown;
  headers?: Record<string, string>;
}

let refreshPromise: Promise<boolean> | null = null;

class ApiError extends Error {
  status: number;
  code: string;

  constructor(
    status: number,
    code: string,
    message?: string,
  ) {
    super(message || code);
    this.name = 'ApiError';
    this.status = status;
    this.code = code;
  }
}

async function request<T>(path: string, options: RequestOptions = {}): Promise<T> {
  const headers: Record<string, string> = {
    'Content-Type': 'application/json',
    ...options.headers,
  };

  const res = await fetch(`${API_BASE}${path}`, {
    method: options.method || 'GET',
    headers,
    credentials: 'include',
    body: options.body ? JSON.stringify(options.body) : undefined,
  });

  if (res.status === 401) {
    // Don't try to refresh tokens for auth endpoints - 401 there means bad credentials
    const isAuthEndpoint = path.includes('/auth/login') || path.includes('/auth/register') || path.includes('/auth/recovery');

    if (!isAuthEndpoint) {
      if (!refreshPromise) {
        refreshPromise = tryRefresh().finally(() => {
          refreshPromise = null;
        });
      }

      const refreshed = await refreshPromise;
      if (refreshed) {
        return request<T>(path, options);
      }

      localStorage.removeItem('user_id');
      localStorage.removeItem('user_role');
      localStorage.removeItem('user_email');
      window.location.href = '/login';
    }

    throw new ApiError(401, 'unauthorized');
  }

  if (res.status === 451) {
    throw new ApiError(451, 'updated_policy_acceptance_required');
  }

  if (!res.ok) {
    const data = await res.json().catch(() => ({ error: 'unknown' }));
    throw new ApiError(res.status, data.error || 'unknown');
  }

  if (res.status === 204) {
    return undefined as T;
  }

  return res.json();
}

async function tryRefresh(): Promise<boolean> {
  try {
    const res = await fetch(`${API_BASE}/api/v1/auth/refresh`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      credentials: 'include',
    });

    if (!res.ok) return false;

    return true;
  } catch {
    return false;
  }
}

export const api = {
  get: <T>(path: string) => request<T>(path),
  post: <T>(path: string, body?: unknown) => request<T>(path, { method: 'POST', body }),
  patch: <T>(path: string, body?: unknown) => request<T>(path, { method: 'PATCH', body }),
  put: <T>(path: string, body?: unknown) => request<T>(path, { method: 'PUT', body }),
  delete: <T>(path: string) => request<T>(path, { method: 'DELETE' }),
};

export { ApiError };
