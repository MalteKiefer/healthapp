import React, { useState } from 'react';
import { useTranslation } from 'react-i18next';
import { useQuery } from '@tanstack/react-query';
import { Link } from 'react-router-dom';
import { api } from '../api/client';

interface SearchResults {
  results: Record<string, SearchItem[]>;
}

interface SearchItem {
  id: string;
  name?: string;
  title?: string;
  vaccine_name?: string;
  marker?: string;
  [key: string]: unknown;
}

const TYPE_ICONS: Record<string, React.ReactNode> = {
  medications: (
    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <path d="M10.5 1.5L3.5 8.5a5 5 0 0 0 7 7l7-7a5 5 0 0 0-7-7z" />
      <path d="M7 10.5L13.5 4" />
    </svg>
  ),
  allergies: (
    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <path d="M10.29 3.86L1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z" />
      <line x1="12" y1="9" x2="12" y2="13" />
      <line x1="12" y1="17" x2="12.01" y2="17" />
    </svg>
  ),
  diagnoses: (
    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <path d="M16 4h2a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2h2" />
      <rect x="8" y="2" width="8" height="4" rx="1" ry="1" />
    </svg>
  ),
  vaccinations: (
    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <path d="M17 3l4 4" />
      <path d="M19 5L7.5 16.5" />
      <path d="M11 11l-4 4" />
      <path d="M3.5 20.5l4-4" />
      <path d="M6.5 14.5l3 3" />
    </svg>
  ),
  contacts: (
    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2" />
      <circle cx="12" cy="7" r="4" />
    </svg>
  ),
  diary: (
    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <path d="M4 19.5A2.5 2.5 0 0 1 6.5 17H20" />
      <path d="M6.5 2H20v20H6.5A2.5 2.5 0 0 1 4 19.5v-15A2.5 2.5 0 0 1 6.5 2z" />
    </svg>
  ),
};

const TYPE_ROUTES: Record<string, string> = {
  medications: '/medications', allergies: '/allergies', diagnoses: '/diagnoses',
  vaccinations: '/vaccinations', contacts: '/contacts', diary: '/diary',
};

export function Search() {
  const { t } = useTranslation();
  const [query, setQuery] = useState('');
  const [debouncedQuery, setDebouncedQuery] = useState('');

  const { data, isLoading } = useQuery({
    queryKey: ['search', debouncedQuery],
    queryFn: () => api.get<SearchResults>(`/api/v1/search?q=${encodeURIComponent(debouncedQuery)}`),
    enabled: debouncedQuery.length >= 2,
  });

  const handleSearch = (value: string) => {
    setQuery(value);
    // Simple debounce
    clearTimeout((window as unknown as Record<string, ReturnType<typeof setTimeout>>).__searchTimer);
    (window as unknown as Record<string, ReturnType<typeof setTimeout>>).__searchTimer = setTimeout(() => {
      setDebouncedQuery(value);
    }, 300);
  };

  const results = data?.results || {};
  const hasResults = Object.values(results).some((items) => items && items.length > 0);

  return (
    <div className="page">
      <h2>{t('common.search')}</h2>

      <div className="search-box">
        <input
          type="search"
          className="search-input"
          placeholder={t('search.placeholder')}
          value={query}
          onChange={(e) => handleSearch(e.target.value)}
          autoFocus
        />
      </div>

      {isLoading && <p className="text-muted" style={{ marginTop: 16 }}>{t('common.loading')}</p>}

      {debouncedQuery.length >= 2 && !isLoading && !hasResults && (
        <p className="text-muted" style={{ marginTop: 16 }}>{t('search.no_results', { query: debouncedQuery })}</p>
      )}

      {hasResults && (
        <div className="search-results">
          {Object.entries(results).map(([type, items]) => {
            if (!items || items.length === 0) return null;
            return (
              <div key={type} className="card" style={{ marginTop: 16 }}>
                <div className="card-header">
                  <h3>{TYPE_ICONS[type] || null} {t('nav.' + type)}</h3>
                  <Link to={TYPE_ROUTES[type] || '/'} className="card-link">{t('search.view_all')}</Link>
                </div>
                <div className="search-items">
                  {items.map((item) => (
                    <div key={item.id} className="search-item">
                      <span className="search-item-name">
                        {item.name || item.title || item.vaccine_name || item.marker || item.id}
                      </span>
                    </div>
                  ))}
                </div>
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}
