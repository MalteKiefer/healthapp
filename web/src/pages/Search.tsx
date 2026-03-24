import { useState } from 'react';
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

const TYPE_ICONS: Record<string, string> = {
  medications: '💊', allergies: '⚠', diagnoses: '🏥',
  vaccinations: '💉', contacts: '👤', diary: '📋',
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
          placeholder="Search medications, allergies, diagnoses, vaccinations..."
          value={query}
          onChange={(e) => handleSearch(e.target.value)}
          autoFocus
        />
      </div>

      {isLoading && <p className="text-muted" style={{ marginTop: 16 }}>{t('common.loading')}</p>}

      {debouncedQuery.length >= 2 && !isLoading && !hasResults && (
        <p className="text-muted" style={{ marginTop: 16 }}>No results found for "{debouncedQuery}"</p>
      )}

      {hasResults && (
        <div className="search-results">
          {Object.entries(results).map(([type, items]) => {
            if (!items || items.length === 0) return null;
            return (
              <div key={type} className="card" style={{ marginTop: 16 }}>
                <div className="card-header">
                  <h3>{TYPE_ICONS[type] || '📌'} {type}</h3>
                  <Link to={TYPE_ROUTES[type] || '/'} className="card-link">View all</Link>
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
