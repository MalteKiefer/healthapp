# Lab Trends Dashboard — Design Spec

## Overview

Add a trend visualization dashboard to the existing Labs page. Users toggle between a list view (current) and a trends view that automatically displays line charts for all lab markers with multiple numeric data points over time.

## User Decisions

| Decision | Choice |
|---|---|
| Entry point | Dashboard view — auto-shows all markers with 2+ data points |
| Placement | Tab/toggle on existing Labs page (list vs. trends) |
| Layout | Hybrid grid with expand — compact cards that expand inline to full chart |
| Time filter | 7d, 30d, 90d, 1y, All (consistent with Vitals page) |
| Data scope | Numeric markers only (`value IS NOT NULL`) |
| Reference range | Colored background area (Recharts `ReferenceArea`) |
| Statistics | Full TrendPanel (mean, 7d/30d avg, std dev, trend slope, min/max, variability) |
| Backend strategy | New dedicated API endpoint with server-side aggregation |

## API Design

### Endpoint

```
GET /api/v1/profiles/{profileID}/labs/trends
```

### Query Parameters

| Param | Type | Required | Description |
|---|---|---|---|
| `from` | ISO 8601 datetime | No | Start date filter. Defaults to no lower bound. |
| `to` | ISO 8601 datetime | No | End date filter. Defaults to now. |

### Response

```json
{
  "markers": [
    {
      "marker": "Hämoglobin",
      "unit": "g/dL",
      "reference_low": 12.0,
      "reference_high": 16.0,
      "data_points": [
        { "date": "2026-01-15T00:00:00Z", "value": 13.5, "flag": "normal" },
        { "date": "2026-02-10T00:00:00Z", "value": 14.2, "flag": "normal" }
      ]
    }
  ]
}
```

### Rules

- Only markers with `value IS NOT NULL` (numeric) are included.
- Only markers with 2+ data points are returned.
- Data points are sorted by `sample_date ASC`.
- Reference values (`reference_low`, `reference_high`, `unit`) come from the most recent data point for each marker.
- Only `is_current = TRUE` and `deleted_at IS NULL` lab results are considered.

### SQL Strategy

Single query joining `lab_results` and `lab_values`, grouped by `marker`. Filter on `profile_id`, `is_current`, `deleted_at IS NULL`, `value IS NOT NULL`, and optional date range. Order by `sample_date ASC` within each marker group.

## Backend Changes

### New Types (`domain/labs/model.go`)

```go
type TrendDataPoint struct {
    Date  time.Time `json:"date"`
    Value float64   `json:"value"`
    Flag  *string   `json:"flag,omitempty"`
}

type MarkerTrend struct {
    Marker       string           `json:"marker"`
    Unit         *string          `json:"unit,omitempty"`
    ReferenceLow *float64         `json:"reference_low,omitempty"`
    ReferenceHigh *float64        `json:"reference_high,omitempty"`
    DataPoints   []TrendDataPoint `json:"data_points"`
}
```

### New Repository Method (`domain/labs/repository.go`)

```go
ListTrends(ctx context.Context, profileID uuid.UUID, from, to *time.Time) ([]MarkerTrend, error)
```

### PostgreSQL Implementation (`repository/postgres/lab.go`)

New method on `LabRepo` implementing `ListTrends`. Executes a single query that:
1. Joins `lab_results` with `lab_values`
2. Filters on `profile_id`, `is_current = TRUE`, `deleted_at IS NULL`, `value IS NOT NULL`
3. Applies optional `from`/`to` date filters on `sample_date`
4. Returns rows ordered by `marker ASC, sample_date ASC`
5. Go code groups rows into `[]MarkerTrend`, picking reference values from the last row per marker
6. Filters out markers with fewer than 2 data points

### New Handler (`handlers/labs.go`)

`HandleTrends` method on `LabHandler`:
- Parses `profileID` from URL, validates access
- Parses optional `from`/`to` query params
- Calls `ListTrends`
- Returns JSON response

### Route (`router.go`)

```
GET /api/v1/profiles/{profileID}/labs/trends
```

Registered before `/{labID}` to avoid route conflict with Chi.

## Frontend Design

### View Toggle (in `Labs.tsx`)

- New state: `viewMode: 'list' | 'trends'`
- Toggle buttons in the page header, next to the profile selector and add button
- When `viewMode === 'trends'`, render `<LabTrendsView profileId={profileId} />` instead of the list

### New Component: `LabTrendsView`

**File:** `web/src/components/LabTrendsView.tsx`

**Props:** `{ profileId: string }`

**Internal State:**
- `timeRange: '7d' | '30d' | '90d' | '1y' | 'all'` — controls `from`/`to` for API call
- `expandedMarker: string | null` — which marker card is expanded

**Structure:**

```
LabTrendsView
  ├── Time filter bar (7d | 30d | 90d | 1y | All buttons)
  ├── Grid of MarkerCards (compact)
  │     ├── Marker name
  │     ├── Current value + unit
  │     ├── Mini sparkline (small Recharts LineChart or inline SVG)
  │     └── Trend arrow + color (green=normal, red=critical, yellow=abnormal)
  └── Expanded card (when a marker is clicked)
        ├── Full Recharts LineChart
        │     ├── ReferenceArea for reference range (colored background)
        │     ├── Line with dots for data points
        │     ├── XAxis (dates), YAxis (values + unit)
        │     └── Tooltip (date, value, flag)
        └── TrendPanel (existing component, full statistics)
```

**Grid layout:**
- Desktop: 3 columns
- Tablet: 2 columns
- Mobile: 1 column

**Expanded card:**
- Spans full width below the grid
- Only one card expanded at a time
- Click same card again to collapse

### Data Fetching

```typescript
useQuery({
  queryKey: ['lab-trends', profileId, from, to],
  queryFn: () => api.get(`/api/v1/profiles/${profileId}/labs/trends?from=${from}&to=${to}`),
  enabled: !!profileId,
});
```

### Recharts Usage

- `ResponsiveContainer`, `LineChart`, `Line`, `XAxis`, `YAxis`, `Tooltip` — same as Vitals
- `ReferenceArea` — new, for colored reference range background (y1=reference_low, y2=reference_high)

### TrendPanel Integration

Map API data points to TrendPanel's expected interface:

```typescript
const trendData = marker.data_points.map(dp => ({
  measured_at: dp.date,
  value: dp.value,
}));

<TrendPanel data={trendData} metricName={marker.marker} unit={marker.unit} />
```

## i18n

New keys added to `de.json` and `en.json`:

| Key | DE | EN |
|---|---|---|
| `labs.view_list` | Liste | List |
| `labs.view_trends` | Trends | Trends |
| `labs.no_trends` | Nicht genug Daten für Trend-Anzeige | Not enough data for trends |
| `labs.data_points` | Datenpunkte | Data points |
| `labs.current_value` | Aktueller Wert | Current value |

Existing `trend.*` keys from TrendPanel are reused.

## Styling

No new CSS file. Uses existing classes:
- `card`, `trend-panel`, `trend-grid` — existing layout
- `status-normal`, `status-abnormal`, `status-critical` — existing color coding
- Grid and sparkline cards use CSS grid with responsive breakpoints added to the existing stylesheet

## Files Changed

| File | Change |
|---|---|
| `api/internal/domain/labs/model.go` | Add `MarkerTrend`, `TrendDataPoint` structs |
| `api/internal/domain/labs/repository.go` | Add `ListTrends` method to interface |
| `api/internal/repository/postgres/lab.go` | Implement `ListTrends` with SQL query |
| `api/internal/api/handlers/labs.go` | Add `HandleTrends` handler |
| `api/internal/api/router.go` | Add trends route |
| `web/src/components/LabTrendsView.tsx` | New component (grid, charts, trend panel) |
| `web/src/pages/Labs.tsx` | Add view mode toggle, conditionally render LabTrendsView |
| `web/src/i18n/de.json` | Add new translation keys |
| `web/src/i18n/en.json` | Add new translation keys |
