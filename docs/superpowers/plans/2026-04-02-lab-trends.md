# Lab Trends Dashboard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a trend visualization dashboard to the Labs page that shows line charts with reference ranges and statistics for all lab markers with 2+ numeric data points.

**Architecture:** New backend endpoint `GET /labs/trends` aggregates lab values by marker with server-side date filtering. Frontend adds a list/trends toggle to the existing Labs page. A new `LabTrendsView` component renders a responsive grid of compact marker cards that expand inline to full Recharts line charts with `ReferenceArea` and the existing `TrendPanel`.

**Tech Stack:** Go (chi router, pgx), React 19, TypeScript, Recharts 3, TanStack React Query 5, i18next

**Spec:** `docs/superpowers/specs/2026-04-02-lab-trends-design.md`

---

## File Map

| File | Action | Responsibility |
|---|---|---|
| `api/internal/domain/labs/model.go` | Modify | Add `MarkerTrend`, `TrendDataPoint` structs |
| `api/internal/domain/labs/repository.go` | Modify | Add `ListTrends` to interface |
| `api/internal/repository/postgres/lab.go` | Modify | Implement `ListTrends` SQL query |
| `api/internal/api/handlers/labs.go` | Modify | Add `HandleTrends` handler |
| `api/internal/api/router.go` | Modify | Register `/labs/trends` route |
| `web/src/components/LabTrendsView.tsx` | Create | Trend dashboard component (grid, charts, expand) |
| `web/src/pages/Labs.tsx` | Modify | Add list/trends view toggle |
| `web/src/i18n/de.json` | Modify | Add German translation keys |
| `web/src/i18n/en.json` | Modify | Add English translation keys |
| `web/src/App.css` | Modify | Add trend grid and card styles |

---

### Task 1: Backend — Domain Types

**Files:**
- Modify: `api/internal/domain/labs/model.go`

- [ ] **Step 1: Add trend types to model.go**

Append below the existing `ReferenceRange` struct at the end of `api/internal/domain/labs/model.go`:

```go
// TrendDataPoint represents a single measurement of a marker over time.
type TrendDataPoint struct {
	Date  time.Time `json:"date"`
	Value float64   `json:"value"`
	Flag  *string   `json:"flag,omitempty"`
}

// MarkerTrend represents the time series for a single lab marker.
type MarkerTrend struct {
	Marker        string           `json:"marker"`
	Unit          *string          `json:"unit,omitempty"`
	ReferenceLow  *float64         `json:"reference_low,omitempty"`
	ReferenceHigh *float64         `json:"reference_high,omitempty"`
	DataPoints    []TrendDataPoint `json:"data_points"`
}
```

- [ ] **Step 2: Verify it compiles**

Run: `cd /home/pr0ph37/Entwicklung/healthvault/api && go build ./...`
Expected: No errors.

- [ ] **Step 3: Commit**

```bash
git add api/internal/domain/labs/model.go
git commit -m "feat(labs): add MarkerTrend and TrendDataPoint domain types"
```

---

### Task 2: Backend — Repository Interface

**Files:**
- Modify: `api/internal/domain/labs/repository.go`

- [ ] **Step 1: Add ListTrends to the Repository interface**

Add the new method to the `Repository` interface in `api/internal/domain/labs/repository.go`. The `time` and `uuid` packages are already imported. Add the method after `CheckDuplicate`:

```go
ListTrends(ctx context.Context, profileID uuid.UUID, from, to *time.Time) ([]MarkerTrend, error)
```

The full interface becomes:

```go
type Repository interface {
	Create(ctx context.Context, lr *LabResult) error
	GetByID(ctx context.Context, id uuid.UUID) (*LabResult, error)
	List(ctx context.Context, profileID uuid.UUID, limit, offset int) ([]LabResult, int, error)
	Update(ctx context.Context, lr *LabResult) error
	SoftDelete(ctx context.Context, id uuid.UUID) error
	CheckDuplicate(ctx context.Context, lr *LabResult) (*uuid.UUID, error)
	ListTrends(ctx context.Context, profileID uuid.UUID, from, to *time.Time) ([]MarkerTrend, error)
}
```

Note: This will cause a compile error until we implement it in Task 3. That's expected.

- [ ] **Step 2: Verify the interface change is syntactically correct**

Run: `cd /home/pr0ph37/Entwicklung/healthvault/api && go vet ./internal/domain/labs/...`
Expected: No errors (vet only checks the package, not implementors).

- [ ] **Step 3: Commit**

```bash
git add api/internal/domain/labs/repository.go
git commit -m "feat(labs): add ListTrends method to repository interface"
```

---

### Task 3: Backend — PostgreSQL Implementation

**Files:**
- Modify: `api/internal/repository/postgres/lab.go`

- [ ] **Step 1: Implement ListTrends on LabRepo**

Add this method to the end of `api/internal/repository/postgres/lab.go`, before the closing of the file (after the `getValues` method):

```go
func (r *LabRepo) ListTrends(ctx context.Context, profileID uuid.UUID, from, to *time.Time) ([]labs.MarkerTrend, error) {
	query := `
		SELECT lv.marker, lv.value, lv.unit, lv.reference_low, lv.reference_high, lv.flag, lr.sample_date
		FROM lab_values lv
		JOIN lab_results lr ON lv.lab_result_id = lr.id
		WHERE lr.profile_id = $1
		  AND lr.is_current = TRUE
		  AND lr.deleted_at IS NULL
		  AND lv.value IS NOT NULL`

	args := []interface{}{profileID}
	argIdx := 2

	if from != nil {
		query += fmt.Sprintf(" AND lr.sample_date >= $%d", argIdx)
		args = append(args, *from)
		argIdx++
	}
	if to != nil {
		query += fmt.Sprintf(" AND lr.sample_date <= $%d", argIdx)
		args = append(args, *to)
		argIdx++
	}

	query += " ORDER BY lv.marker ASC, lr.sample_date ASC"

	rows, err := r.db.Query(ctx, query, args...)
	if err != nil {
		return nil, fmt.Errorf("query lab trends: %w", err)
	}
	defer rows.Close()

	// Group rows by marker
	trendsMap := make(map[string]*labs.MarkerTrend)
	var order []string

	for rows.Next() {
		var (
			marker       string
			value        float64
			unit         *string
			refLow       *float64
			refHigh      *float64
			flag         *string
			sampleDate   time.Time
		)
		if err := rows.Scan(&marker, &value, &unit, &refLow, &refHigh, &flag, &sampleDate); err != nil {
			return nil, fmt.Errorf("scan lab trend row: %w", err)
		}

		mt, exists := trendsMap[marker]
		if !exists {
			mt = &labs.MarkerTrend{Marker: marker}
			trendsMap[marker] = mt
			order = append(order, marker)
		}

		mt.DataPoints = append(mt.DataPoints, labs.TrendDataPoint{
			Date:  sampleDate,
			Value: value,
			Flag:  flag,
		})

		// Always update reference info from the latest row (rows are ordered by sample_date ASC)
		mt.Unit = unit
		mt.ReferenceLow = refLow
		mt.ReferenceHigh = refHigh
	}

	// Build result, filtering out markers with < 2 data points
	var results []labs.MarkerTrend
	for _, marker := range order {
		mt := trendsMap[marker]
		if len(mt.DataPoints) >= 2 {
			results = append(results, *mt)
		}
	}

	return results, nil
}
```

- [ ] **Step 2: Verify it compiles**

Run: `cd /home/pr0ph37/Entwicklung/healthvault/api && go build ./...`
Expected: No errors. The `LabRepo` now satisfies the updated `Repository` interface.

- [ ] **Step 3: Commit**

```bash
git add api/internal/repository/postgres/lab.go
git commit -m "feat(labs): implement ListTrends with marker aggregation query"
```

---

### Task 4: Backend — Handler & Route

**Files:**
- Modify: `api/internal/api/handlers/labs.go`
- Modify: `api/internal/api/router.go`

- [ ] **Step 1: Add HandleTrends to LabHandler**

Add this method to `api/internal/api/handlers/labs.go`, after the `HandleList` method (after line 73):

```go
// HandleTrends returns aggregated marker time series for trend visualization.
func (h *LabHandler) HandleTrends(w http.ResponseWriter, r *http.Request) {
	claims, ok := ClaimsFromContext(r.Context())
	if !ok {
		writeJSON(w, http.StatusUnauthorized, errorResponse("not_authenticated"))
		return
	}

	profileID, err := uuid.Parse(chi.URLParam(r, "profileID"))
	if err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse("invalid_profile_id"))
		return
	}

	hasAccess, err := h.profileRepo.HasAccess(r.Context(), profileID, claims.UserID)
	if err != nil || !hasAccess {
		writeJSON(w, http.StatusForbidden, errorResponse("access_denied"))
		return
	}

	var from, to *time.Time
	if v := r.URL.Query().Get("from"); v != "" {
		t, err := time.Parse(time.RFC3339, v)
		if err == nil {
			from = &t
		}
	}
	if v := r.URL.Query().Get("to"); v != "" {
		t, err := time.Parse(time.RFC3339, v)
		if err == nil {
			to = &t
		}
	}

	markers, err := h.labRepo.ListTrends(r.Context(), profileID, from, to)
	if err != nil {
		h.logger.Error("list lab trends", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse("internal_error"))
		return
	}

	writeJSON(w, http.StatusOK, map[string]interface{}{
		"markers": markers,
	})
}
```

- [ ] **Step 2: Register the route in router.go**

In `api/internal/api/router.go`, inside the `/labs` route group (around line 280), add the trends route **before** the `/{labID}` routes to prevent Chi from matching "trends" as a labID:

Change this block:

```go
r.Route("/labs", func(r chi.Router) {
	r.Get("/", s.LabHandler.HandleList)
	r.Post("/", s.LabHandler.HandleCreate)
	r.Get("/{labID}", s.LabHandler.HandleGet)
```

To:

```go
r.Route("/labs", func(r chi.Router) {
	r.Get("/", s.LabHandler.HandleList)
	r.Post("/", s.LabHandler.HandleCreate)
	r.Get("/trends", s.LabHandler.HandleTrends)
	r.Get("/{labID}", s.LabHandler.HandleGet)
```

- [ ] **Step 3: Verify it compiles**

Run: `cd /home/pr0ph37/Entwicklung/healthvault/api && go build ./...`
Expected: No errors.

- [ ] **Step 4: Commit**

```bash
git add api/internal/api/handlers/labs.go api/internal/api/router.go
git commit -m "feat(labs): add /trends endpoint with date range filtering"
```

---

### Task 5: Frontend — i18n Keys

**Files:**
- Modify: `web/src/i18n/en.json`
- Modify: `web/src/i18n/de.json`

- [ ] **Step 1: Add English translation keys**

In `web/src/i18n/en.json`, inside the `"labs"` object (after `"flag_normal": "normal"`), add:

```json
    "view_list": "List",
    "view_trends": "Trends",
    "no_trends": "Not enough data for trend display",
    "data_points": "data points",
    "current_value": "Current value"
```

So the labs block ends:

```json
    "flag_normal": "normal",
    "view_list": "List",
    "view_trends": "Trends",
    "no_trends": "Not enough data for trend display",
    "data_points": "data points",
    "current_value": "Current value"
  },
```

- [ ] **Step 2: Add German translation keys**

In `web/src/i18n/de.json`, inside the `"labs"` object (after `"flag_normal": "normal"`), add:

```json
    "view_list": "Liste",
    "view_trends": "Trends",
    "no_trends": "Nicht genug Daten für Trend-Anzeige",
    "data_points": "Datenpunkte",
    "current_value": "Aktueller Wert"
```

So the labs block ends:

```json
    "flag_normal": "normal",
    "view_list": "Liste",
    "view_trends": "Trends",
    "no_trends": "Nicht genug Daten für Trend-Anzeige",
    "data_points": "Datenpunkte",
    "current_value": "Aktueller Wert"
  },
```

- [ ] **Step 3: Commit**

```bash
git add web/src/i18n/en.json web/src/i18n/de.json
git commit -m "feat(labs): add i18n keys for trends view"
```

---

### Task 6: Frontend — CSS Styles

**Files:**
- Modify: `web/src/App.css`

- [ ] **Step 1: Add trend grid and card styles**

Add these styles to `web/src/App.css` before the comment block `/* -------------------------------------------------------------------------- 45. OCR UPLOAD -------------------------------------------------------------------------- */` (around line 3081):

```css
/* --------------------------------------------------------------------------
   LAB TRENDS
   -------------------------------------------------------------------------- */

.lab-trends-grid {
  display: grid;
  grid-template-columns: repeat(3, 1fr);
  gap: var(--space-3);
  margin-top: var(--space-3);
}

.lab-trend-card {
  background: var(--surface);
  border: 1px solid var(--border-subtle);
  border-radius: var(--radius-lg);
  padding: var(--space-3);
  cursor: pointer;
  transition: all var(--transition-fast);
}
.lab-trend-card:hover {
  border-color: var(--border);
  box-shadow: var(--shadow-sm);
}

.lab-trend-card-header {
  display: flex;
  justify-content: space-between;
  align-items: flex-start;
  margin-bottom: var(--space-2);
}
.lab-trend-card-marker {
  font-size: 11px;
  text-transform: uppercase;
  color: var(--text-secondary);
  font-weight: 600;
  letter-spacing: 0.5px;
}
.lab-trend-card-value {
  font-size: 22px;
  font-weight: 700;
  margin: 2px 0;
}
.lab-trend-card-unit {
  font-size: 12px;
  color: var(--text-secondary);
  margin-left: 4px;
  font-weight: 400;
}
.lab-trend-card-trend {
  font-size: 13px;
  font-weight: 500;
}

.lab-trend-expanded {
  grid-column: 1 / -1;
  background: var(--surface);
  border: 2px solid var(--primary);
  border-radius: var(--radius-lg);
  padding: var(--space-4);
}
.lab-trend-expanded-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: var(--space-3);
}
.lab-trend-expanded-content {
  display: grid;
  grid-template-columns: 1fr 280px;
  gap: var(--space-4);
  align-items: start;
}

@media (max-width: 900px) {
  .lab-trends-grid { grid-template-columns: repeat(2, 1fr); }
  .lab-trend-expanded-content { grid-template-columns: 1fr; }
}
@media (max-width: 600px) {
  .lab-trends-grid { grid-template-columns: 1fr; }
}
```

- [ ] **Step 2: Commit**

```bash
git add web/src/App.css
git commit -m "feat(labs): add CSS styles for trend grid and expanded cards"
```

---

### Task 7: Frontend — LabTrendsView Component

**Files:**
- Create: `web/src/components/LabTrendsView.tsx`

- [ ] **Step 1: Create the LabTrendsView component**

Create `web/src/components/LabTrendsView.tsx`:

```tsx
import { useState, useMemo } from 'react';
import { useTranslation } from 'react-i18next';
import { useQuery } from '@tanstack/react-query';
import {
  LineChart, Line, XAxis, YAxis, Tooltip, ResponsiveContainer, ReferenceArea,
} from 'recharts';
import { format, subDays, subMonths, subYears } from 'date-fns';
import { api } from '../api/client';
import { TrendPanel } from './TrendPanel';

type TimeRange = '7d' | '30d' | '90d' | '1y' | 'all';

interface TrendDataPoint {
  date: string;
  value: number;
  flag?: string;
}

interface MarkerTrend {
  marker: string;
  unit?: string;
  reference_low?: number;
  reference_high?: number;
  data_points: TrendDataPoint[];
}

interface LabTrendsResponse {
  markers: MarkerTrend[];
}

function getFromDate(range: TimeRange): string | undefined {
  const now = new Date();
  switch (range) {
    case '7d': return subDays(now, 7).toISOString();
    case '30d': return subDays(now, 30).toISOString();
    case '90d': return subDays(now, 90).toISOString();
    case '1y': return subYears(now, 1).toISOString();
    case 'all': return undefined;
  }
}

function trendDirection(points: TrendDataPoint[]): { arrow: string; color: string; label: string } {
  if (points.length < 2) return { arrow: '\u2192', color: 'var(--text-secondary)', label: 'stable' };
  const values = points.map(p => p.value);
  const n = values.length;
  const mean = values.reduce((a, b) => a + b, 0) / n;
  const xMean = (n - 1) / 2;
  const num = values.reduce((acc, v, i) => acc + (i - xMean) * (v - mean), 0);
  const den = values.reduce((acc, _, i) => acc + (i - xMean) ** 2, 0);
  const slope = den !== 0 ? num / den : 0;
  if (slope > 0.01) return { arrow: '\u2191', color: 'var(--warning)', label: 'up' };
  if (slope < -0.01) return { arrow: '\u2193', color: 'var(--success)', label: 'down' };
  return { arrow: '\u2192', color: 'var(--text-secondary)', label: 'stable' };
}

function MarkerSparkline({ points }: { points: TrendDataPoint[] }) {
  const data = points.map(p => ({ v: p.value }));
  return (
    <ResponsiveContainer width="100%" height={32}>
      <LineChart data={data} margin={{ top: 2, right: 2, bottom: 2, left: 2 }}>
        <Line type="monotone" dataKey="v" stroke="var(--primary)" strokeWidth={1.5} dot={false} />
      </LineChart>
    </ResponsiveContainer>
  );
}

function ExpandedChart({ marker }: { marker: MarkerTrend }) {
  const { t } = useTranslation();
  const chartData = marker.data_points.map(dp => ({
    date: format(new Date(dp.date), 'dd.MM.yy'),
    value: dp.value,
    flag: dp.flag,
  }));

  const trendData = marker.data_points.map(dp => ({
    measured_at: dp.date,
    value: dp.value,
  }));

  const hasRef = marker.reference_low != null && marker.reference_high != null;

  return (
    <div className="lab-trend-expanded">
      <div className="lab-trend-expanded-header">
        <div>
          <strong>{marker.marker}</strong>
          <span style={{ color: 'var(--text-secondary)', fontSize: 13, marginLeft: 8 }}>
            {marker.unit || ''} {hasRef && `\u2014 Ref: ${marker.reference_low}\u2013${marker.reference_high}`}
          </span>
        </div>
        <span style={{ fontSize: 13, color: 'var(--text-secondary)' }}>
          {marker.data_points.length} {t('labs.data_points')}
        </span>
      </div>
      <div className="lab-trend-expanded-content">
        <ResponsiveContainer width="100%" height={280}>
          <LineChart data={chartData} margin={{ top: 10, right: 20, bottom: 5, left: 0 }}>
            {hasRef && (
              <ReferenceArea
                y1={marker.reference_low!}
                y2={marker.reference_high!}
                fill="var(--success)"
                fillOpacity={0.08}
              />
            )}
            <XAxis dataKey="date" fontSize={12} stroke="var(--text-secondary)" />
            <YAxis
              fontSize={12}
              stroke="var(--text-secondary)"
              unit={marker.unit ? ` ${marker.unit}` : ''}
              width={70}
            />
            <Tooltip
              contentStyle={{
                background: 'var(--surface)',
                border: '1px solid var(--border)',
                borderRadius: 'var(--radius-sm)',
                fontSize: 13,
              }}
            />
            <Line
              type="monotone"
              dataKey="value"
              stroke="var(--primary)"
              strokeWidth={2.5}
              dot={{ r: 4, fill: 'var(--primary)', strokeWidth: 2, stroke: 'var(--surface)' }}
              activeDot={{ r: 6 }}
              name={marker.marker}
              connectNulls
            />
          </LineChart>
        </ResponsiveContainer>
        <TrendPanel data={trendData} metricName={marker.marker} unit={marker.unit || ''} />
      </div>
    </div>
  );
}

export function LabTrendsView({ profileId }: { profileId: string }) {
  const { t } = useTranslation();
  const [timeRange, setTimeRange] = useState<TimeRange>('all');
  const [expandedMarker, setExpandedMarker] = useState<string | null>(null);

  const from = useMemo(() => getFromDate(timeRange), [timeRange]);

  const { data, isLoading } = useQuery({
    queryKey: ['lab-trends', profileId, from],
    queryFn: () => {
      let url = `/api/v1/profiles/${profileId}/labs/trends`;
      const params: string[] = [];
      if (from) params.push(`from=${encodeURIComponent(from)}`);
      if (params.length > 0) url += '?' + params.join('&');
      return api.get<LabTrendsResponse>(url);
    },
    enabled: !!profileId,
  });

  const markers = data?.markers || [];

  const toggleExpand = (marker: string) => {
    setExpandedMarker(prev => prev === marker ? null : marker);
  };

  // Build grid items: cards + expanded card inserted after the right row
  const gridItems: JSX.Element[] = [];
  for (let i = 0; i < markers.length; i++) {
    const m = markers[i];
    const lastPoint = m.data_points[m.data_points.length - 1];
    const trend = trendDirection(m.data_points);

    gridItems.push(
      <div
        key={m.marker}
        className="lab-trend-card"
        onClick={() => toggleExpand(m.marker)}
        style={expandedMarker === m.marker ? { borderColor: 'var(--primary)' } : undefined}
      >
        <div className="lab-trend-card-header">
          <div className="lab-trend-card-marker">{m.marker}</div>
        </div>
        <div className="lab-trend-card-value">
          {lastPoint.value}
          <span className="lab-trend-card-unit">{m.unit || ''}</span>
        </div>
        <div className="lab-trend-card-trend" style={{ color: trend.color }}>
          {trend.arrow}
        </div>
        <MarkerSparkline points={m.data_points} />
      </div>
    );

    // Insert expanded card after this card if it's the expanded marker
    if (expandedMarker === m.marker) {
      gridItems.push(
        <ExpandedChart key={`${m.marker}-expanded`} marker={m} />
      );
    }
  }

  return (
    <>
      <div className="card" style={{ marginBottom: 16 }}>
        <div className="view-toolbar">
          <div className="chart-filters">
            {(['7d', '30d', '90d', '1y', 'all'] as TimeRange[]).map((r) => (
              <button
                key={r}
                className={`chart-range-btn${timeRange === r ? ' active' : ''}`}
                onClick={() => setTimeRange(r)}
              >
                {r === 'all' ? t('common.all') : r}
              </button>
            ))}
          </div>
        </div>
      </div>

      {isLoading ? (
        <div className="card"><p>{t('common.loading')}</p></div>
      ) : markers.length === 0 ? (
        <div className="card"><p className="text-muted">{t('labs.no_trends')}</p></div>
      ) : (
        <div className="lab-trends-grid">
          {gridItems}
        </div>
      )}
    </>
  );
}
```

- [ ] **Step 2: Verify it compiles**

Run: `cd /home/pr0ph37/Entwicklung/healthvault/web && npx tsc --noEmit`
Expected: No type errors.

- [ ] **Step 3: Commit**

```bash
git add web/src/components/LabTrendsView.tsx
git commit -m "feat(labs): add LabTrendsView component with grid, sparklines, and expanded charts"
```

---

### Task 8: Frontend — Integrate into Labs Page

**Files:**
- Modify: `web/src/pages/Labs.tsx`

- [ ] **Step 1: Add imports**

At the top of `web/src/pages/Labs.tsx`, add these imports after the existing imports (after line 10):

```tsx
import { LabTrendsView } from '../components/LabTrendsView';
```

- [ ] **Step 2: Add view mode state**

Inside the `Labs` component, after the `const [editTarget, setEditTarget]` line (line 49), add:

```tsx
const [viewMode, setViewMode] = useState<'list' | 'trends'>('list');
```

- [ ] **Step 3: Add view toggle buttons to page header**

In the `page-actions` div (around line 150), add the view toggle before the ProfileSelector. Replace the current `page-actions` div:

```tsx
<div className="page-actions">
  <div className="view-tabs">
    <button className={`view-tab${viewMode === 'list' ? ' active' : ''}`} onClick={() => setViewMode('list')}>
      {t('labs.view_list')}
    </button>
    <button className={`view-tab${viewMode === 'trends' ? ' active' : ''}`} onClick={() => setViewMode('trends')}>
      {t('labs.view_trends')}
    </button>
  </div>
  <ProfileSelector selectedId={profileId} onSelect={setSelectedProfile} />
  {viewMode === 'list' && (
    <button className="btn btn-add" onClick={() => setShowForm(!showForm)}>+ {t('common.add')}</button>
  )}
</div>
```

- [ ] **Step 4: Conditionally render list or trends view**

Wrap the existing list content (the `<div className="card">` that contains the lab list, starting around line 194) in a conditional. The `showForm` modal and `editTarget` modal stay outside the conditional (they're always available).

After the `showForm` modal's closing `)}` (around line 192) and before the list card `<div className="card">`, add:

```tsx
{viewMode === 'trends' ? (
  <LabTrendsView profileId={profileId} />
) : (
```

And after the list card's closing `</div>` (around line 256, before the edit modal), close the ternary:

```tsx
)}
```

- [ ] **Step 5: Verify it compiles**

Run: `cd /home/pr0ph37/Entwicklung/healthvault/web && npx tsc --noEmit`
Expected: No type errors.

- [ ] **Step 6: Commit**

```bash
git add web/src/pages/Labs.tsx
git commit -m "feat(labs): add list/trends view toggle to Labs page"
```

---

### Task 9: Manual Testing & Polish

- [ ] **Step 1: Start the dev servers**

Run the backend and frontend dev servers (follow existing project setup).

- [ ] **Step 2: Verify the API endpoint**

With at least one profile that has lab results with numeric values, test:

```bash
curl -H "Authorization: Bearer <token>" \
  "http://localhost:<port>/api/v1/profiles/<profileId>/labs/trends"
```

Expected: JSON with `markers` array. Each marker has `data_points` sorted by date. Only markers with 2+ points appear.

- [ ] **Step 3: Test with date filter**

```bash
curl -H "Authorization: Bearer <token>" \
  "http://localhost:<port>/api/v1/profiles/<profileId>/labs/trends?from=2026-01-01T00:00:00Z"
```

Expected: Only data points after the `from` date.

- [ ] **Step 4: Verify the UI**

1. Navigate to Labs page
2. Verify list/trends toggle buttons appear in header
3. Click "Trends" — should show time filter bar and grid of marker cards (or "not enough data" message)
4. Click a card — should expand with full line chart and TrendPanel
5. Click same card — should collapse
6. Switch time ranges — grid should update
7. Switch back to "List" — original list view restored
8. Test responsive: resize to tablet (2 columns) and mobile (1 column)

- [ ] **Step 5: Commit any fixes**

```bash
git add -u
git commit -m "fix(labs): polish lab trends view after manual testing"
```
