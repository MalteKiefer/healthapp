# HealthVault Redesign — Design Specification

**Date:** 2026-03-31
**Status:** Approved
**Scope:** Complete CSS redesign — layout, navigation, color, typography, components, responsive behavior, dark mode

## Overview

A fully independent visual identity for HealthVault. Warm, human, professional. No platform-specific aesthetic (no Apple, no Material). Soft and rounded components, compact data density, smooth subtle animations. Light-first with a fully designed warm dark mode.

The navigation is **adaptive** — fundamentally different UX per screen size, not just a responsive collapse.

---

## 1. Color Palette & Tokens

### Light Theme

```css
:root {
  /* Backgrounds */
  --bg: #FAF8F5;
  --bg-subtle: #F3F0EB;
  --surface: #FFFFFF;
  --surface-hover: #F9F7F4;

  /* Text */
  --text: #2C2825;
  --text-secondary: #7A7269;
  --text-tertiary: #A8A099;

  /* Borders */
  --border: #E8E3DC;
  --border-subtle: #F0ECE6;

  /* Shadows */
  --shadow-sm: 0 1px 3px rgba(44, 40, 37, 0.06);
  --shadow-md: 0 4px 12px rgba(44, 40, 37, 0.08);
  --shadow-lg: 0 8px 24px rgba(44, 40, 37, 0.10);

  /* Primary (Terracotta/Copper) */
  --primary: #B8704A;
  --primary-hover: #A5623F;
  --primary-light: rgba(184, 112, 74, 0.08);
  --primary-text: #FFFFFF;

  /* Semantic */
  --success: #5A8A5C;
  --warning: #C4933B;
  --danger: #C4513B;
  --info: #5A7A8A;
}
```

### Dark Theme

```css
[data-theme="dark"] {
  /* Backgrounds — warm brown undertone, never cold gray */
  --bg: #1C1A17;
  --bg-subtle: #242119;
  --surface: #2A2621;
  --surface-hover: #332E28;

  /* Text */
  --text: #EDE9E3;
  --text-secondary: #9C958C;
  --text-tertiary: #6B645C;

  /* Borders */
  --border: #3A352E;
  --border-subtle: #302B25;

  /* Shadows — stronger on dark backgrounds */
  --shadow-sm: 0 1px 3px rgba(0, 0, 0, 0.20);
  --shadow-md: 0 4px 12px rgba(0, 0, 0, 0.28);
  --shadow-lg: 0 8px 24px rgba(0, 0, 0, 0.35);

  /* Primary — lightened for contrast on dark */
  --primary: #D4956E;
  --primary-hover: #C4845D;
  --primary-light: rgba(212, 149, 110, 0.12);

  /* Semantic — lightened, never neon */
  --success: #7AAE7C;
  --warning: #D4A84E;
  --danger: #D4715B;
  --info: #7A9AAA;
}
```

### Design Principle

No pure grays. Every neutral has a warm sand/beige undertone. This gives the app a human, inviting character — even when displaying medical data.

---

## 2. Typography & Spacing

### Font Stack

```css
:root {
  --font: system-ui, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;
  --font-mono: 'Cascadia Code', 'Fira Code', 'SF Mono', ui-monospace, monospace;
}
```

No `-apple-system` or `BlinkMacSystemFont` — deliberate break from Apple aesthetic.

### Type Scale

| Token | Size | Weight | Line-Height | Use |
|-------|------|--------|-------------|-----|
| `--text-xs` | 11px | 400 | 1.4 | Badges, timestamps |
| `--text-sm` | 13px | 400 | 1.5 | Labels, table text |
| `--text-base` | 15px | 400 | 1.6 | Body text, inputs |
| `--text-lg` | 17px | 500 | 1.5 | Card titles, nav items |
| `--text-xl` | 21px | 600 | 1.3 | Section headings |
| `--text-2xl` | 27px | 700 | 1.2 | Page titles |
| `--text-3xl` | 34px | 700 | 1.1 | Dashboard numbers, hero values |

### Typography Principles

- **Weight over size** for hierarchy — differences primarily through `font-weight` (400 to 700), not extreme size jumps
- **Generous letter-spacing** on headings: `-0.02em`
- **Monospace for values**: vital values, dosages, dates/times in `--font-mono`
- **Uppercase sparingly**: only small labels/badges, with `letter-spacing: 0.05em`

### Spacing System (8px base grid)

| Token | Value | Use |
|-------|-------|-----|
| `--space-1` | 4px | Inline gaps, icon padding |
| `--space-2` | 8px | Tight padding, small gaps |
| `--space-3` | 12px | Input padding, list gaps |
| `--space-4` | 16px | Card padding, section gaps |
| `--space-5` | 20px | Between sections |
| `--space-6` | 24px | Page padding (mobile) |
| `--space-8` | 32px | Page padding (tablet) |
| `--space-10` | 40px | Page padding (desktop) |
| `--space-12` | 48px | Large gaps between areas |

### Border Radius

| Token | Value | Use |
|-------|-------|-----|
| `--radius-sm` | 6px | Badges, small chips |
| `--radius` | 10px | Buttons, inputs |
| `--radius-lg` | 14px | Cards |
| `--radius-xl` | 20px | Modals, large containers |
| `--radius-full` | 9999px | Avatars, round elements |

---

## 3. Adaptive Navigation

Three fundamentally different navigation systems per screen size.

### Breakpoints

| Token | Range | Device |
|-------|-------|--------|
| `--bp-mobile` | 0 – 639px | Smartphones |
| `--bp-tablet` | 640 – 1023px | Tablets, small laptops |
| `--bp-desktop` | 1024px+ | Desktop, large screens |

### Navigation Groups (shared across all sizes)

1. **Gesundheit**: Dashboard, Vitals, Labs, Medications, Vaccinations, Allergies, Diagnoses
2. **Tracking**: Diary, Symptoms, Appointments, Tasks
3. **Verwaltung**: Documents, Contacts, Family, Shares, Emergency
4. **System**: Settings, Calendar Feeds, Export, Activity, Admin (conditional)

### Desktop (>=1024px): Compact Sidebar

- **Width:** 240px expanded, 64px collapsed
- **Position:** Fixed left, full height
- **Structure:**
  - Top: Brand logo + app name
  - Profile selector (active profile with avatar)
  - 4 collapsible groups with page items
  - Bottom: Theme toggle, collapse button
- **Collapsed state:** Icons only, group labels as tooltips, hover expands temporarily
- **Active state:** `--primary-light` background + `--primary` text + 3px left border in `--primary`
- **Transition:** 250ms ease for collapse/expand

### Tablet (640–1023px): Top-Bar with Group Tabs

- **Primary nav:** Sticky horizontal bar at top
  - Left: Compact logo
  - Center: 4 group tabs as horizontal buttons
  - Right: Profile selector, notifications, avatar menu
- **Secondary nav:** Second row below, shows sub-pages of active group as horizontally scrollable pills
- **Active state:** Active group tab gets underline in `--primary`, active sub-page as filled pill
- **Advantage:** Full width for content, no sidebar space consumption

### Mobile (<640px): Hamburger + Fullscreen Overlay

- **Visible:** Slim top-bar with logo (left), notifications + hamburger (right)
- **Hamburger opens:** Fullscreen overlay (slides from top, 250ms ease)
  - Search field at top
  - Profile selector
  - Grouped list of all pages (collapsible sections)
  - Theme toggle + settings at bottom
- **Closes:** Tap backdrop, swipe-down, or navigating to a page
- **No bottom tab bar** — with 28 pages, a 4-5 item bar would be too limiting

### Shared Principles

- All three systems use the same groups and order
- Profile selector reachable on all screen sizes
- Notification bell visible on all screen sizes
- Keyboard navigation (Tab, Enter, Escape) works everywhere

---

## 4. Layout System & Page Structure

### Grid System

**Desktop:**
- Page container: `max-width: 1280px`, centered, `padding: 0 var(--space-10)`
- Content grid: `grid-template-columns: repeat(12, 1fr)`, `gap: var(--space-5)`
- Cards fill 4, 6, or 12 columns

**Tablet:**
- Page container: full width, `padding: 0 var(--space-8)`
- Content grid: `grid-template-columns: repeat(6, 1fr)`, `gap: var(--space-4)`
- Cards fill 3 or 6 columns

**Mobile:**
- Page container: full width, `padding: 0 var(--space-6)`
- Content grid: `grid-template-columns: 1fr`, `gap: var(--space-3)`
- Single column, stacked

### Page Structure (consistent across all pages)

```
+--------------------------------------+
|  Page Header                         |
|  Title (text-2xl) + optional Actions |
+--------------------------------------+
|  Optional: Filter-Bar / Toolbar      |
|  (sticky below nav)                  |
+--------------------------------------+
|  Content Grid                        |
|  +----------+ +----------+          |
|  |   Card   | |   Card   |          |
|  +----------+ +----------+          |
|  +-------------------------+         |
|  |  Wide Card / Table      |         |
|  +-------------------------+         |
+--------------------------------------+
|  Optional: Pagination / Load More    |
+--------------------------------------+
```

### Page Header

- Title left, action buttons right
- Mobile: title and actions stack vertically
- No breadcrumbs — flat hierarchy doesn't need them

### Filter-Bar / Toolbar

- For filterable pages (Vitals, Medications, Documents, etc.)
- Sticky below navigation when scrolling
- Horizontal row: filter chips, date range picker, search field
- Mobile: collapsible section or bottom-sheet

### Tables

- **Desktop:** Full table, all columns
- **Tablet:** Fewer columns, less important hidden via CSS
- **Mobile: Card transformation** — table rows become stacked mini-cards with vertical key-value pairs. Far more readable than squeezed horizontal tables.

### Modals & Forms

- **Desktop/Tablet:** Centered modal with backdrop, `max-width: 560px`, `--radius-xl`
- **Mobile:** Bottom-sheet sliding from below, `border-radius` only top, full width
- **Forms:** Desktop 2-column where appropriate, mobile always single-column

### Empty States

- Simple warm-toned SVG illustration + short text + primary CTA button
- Centered in content area

---

## 5. Component Style

### Cards

- Background: `--surface`
- Border: `1px solid --border-subtle`
- Border-radius: `--radius-lg` (14px)
- Shadow: `--shadow-sm` default, `--shadow-md` on hover (200ms transition)
- Padding: `--space-4` (16px)

**Variants:**
- **Standard** — overviews, statistics, lists
- **Status** — 4px left colored border via `--success`, `--warning`, `--danger`
- **Interactive** — hover raises shadow + `translateY(-1px)`, cursor pointer
- **Grouped** — multiple cards visually connected in shared container, separated by `--border-subtle` line only

### Buttons

**Primary:** `--primary` bg, `--primary-text` text, `--radius` (10px), hover: `--primary-hover` + `--shadow-sm`
**Secondary:** transparent bg, `1px solid --border`, hover: `--bg-subtle`
**Ghost:** transparent bg, no border, `--text-secondary`, hover: `--bg-subtle`
**Danger:** like Primary with `--danger` colors

**Sizes:**
- `sm`: 8px 14px, `--text-sm`
- `md`: 10px 20px, `--text-base` (default)
- `lg`: 12px 24px, `--text-lg`

### Inputs & Forms

- Background: `--surface`
- Border: `1px solid --border`
- Border-radius: `--radius` (10px)
- Padding: `10px 14px`
- Focus: border `--primary`, box-shadow `0 0 0 3px var(--primary-light)`
- Labels: `--text-secondary`, `--text-sm`, `font-weight: 500`, `margin-bottom: var(--space-1)`

### Badges & Chips

- Border-radius: `--radius-sm` (6px)
- Padding: `2px 8px`
- Font: `--text-xs`, `font-weight: 600`
- Variants: default (`--bg-subtle` + `--text-secondary`), success, warning, danger — each with 12% opacity background + solid text

### Tables

- Header: `--bg-subtle`, `--text-secondary`, `--text-sm`, `font-weight: 600`, uppercase with letter-spacing
- Rows: `--surface`, `--border-subtle` bottom line
- Row hover: `--surface-hover`
- Cell padding: `--space-3` vertical, `--space-4` horizontal
- Numbers/values: `--font-mono`
- Sortable columns: pointer cursor, small arrow icon

### Avatars

- Border-radius: `--radius-full`
- Sizes: 24px (inline), 32px (nav), 40px (header), 64px (profile)
- Fallback: initials on `--primary-light` background in `--primary` text

### Tooltips

- Background: `--text` (inverted)
- Text: `--surface`, `--text-sm`
- Border-radius: `--radius-sm`
- Padding: `4px 10px`
- Appear: 200ms delay, 150ms fade-in

### Notification Bell

- Badge top-right: `--danger` background, white text, `--text-xs`, `--radius-full`, min-width 18px

---

## 6. Animations & Transitions

### Timing Tokens

| Token | Value | Use |
|-------|-------|-----|
| `--duration-fast` | 150ms | Color changes, opacity |
| `--duration-base` | 200ms | Hover states, buttons, focus |
| `--duration-smooth` | 250ms | Sidebar collapse, nav transitions |
| `--duration-slow` | 350ms | Modals, overlays, bottom-sheets |

**Easing:** `cubic-bezier(0.4, 0, 0.2, 1)` — natural deceleration.

### Hover & Focus

- Buttons: background + shadow in `--duration-base`
- Cards: shadow raise + `translateY(-1px)` in `--duration-base`
- Links/nav items: color in `--duration-fast`
- Inputs: border color + box-shadow in `--duration-fast`

### Navigation

- Sidebar collapse/expand: width in `--duration-smooth`, labels fade in `--duration-fast`
- Group tab switch (tablet): items slide, underline indicator glides to new position in `--duration-smooth`
- Mobile overlay: slides from top (`translateY(-100%) to 0`) in `--duration-slow`, backdrop fades in

### Modals & Bottom-Sheets

- Desktop/tablet modal: fade-in + scale (`0.97 to 1`) in `--duration-slow`
- Mobile bottom-sheet: slides from bottom (`translateY(100%) to 0`) in `--duration-slow`
- Close: reverse animation, same duration

### Content

- **No page transitions** — pages load instantly, speed over effect
- **Skeleton loading:** `--bg-subtle` pulse animation (opacity `0.6 to 1`, 1.5s loop)
- **Lists/tables:** No staggered animations — data appears immediately

### Micro-Interactions

- Toggles: smooth knob slide in `--duration-base`
- Checkbox/radio: scale animation on activate (`0.8 to 1`, `--duration-fast`)
- Sort arrows: rotation in `--duration-fast`

### Reduced Motion

```css
@media (prefers-reduced-motion: reduce) {
  *, *::before, *::after {
    animation-duration: 0.01ms !important;
    transition-duration: 0.01ms !important;
  }
}
```

---

## 7. Dark Mode

### Principles

- Warm character preserved — dark surfaces have brown/sand undertone, never cold gray
- Shadows become stronger on dark backgrounds
- Borders become more important for structure
- Primary and semantic colors lightened for contrast (WCAG AA minimum)
- No "neon on black" — semantic colors are lightened, not saturated

### Switching

- Toggle in sidebar (desktop), top-bar (tablet), overlay footer (mobile)
- `data-theme="dark"` on `<html>` element
- Transition: `--duration-smooth` on body `background-color` and `color`
- Persisted in Zustand store + localStorage
- Default: light, respects `prefers-color-scheme` on first visit

### Full token mapping in Section 1.

---

## 8. Implementation Scope

### What Changes

- **`index.css`** — new root CSS variables (complete replacement)
- **`App.css`** — complete rewrite (~3,356 lines current)
- **`Layout.tsx`** — new adaptive navigation component (replaces current sidebar-only layout)
- **`store/ui.ts`** — extend with sidebar collapsed state, breakpoint awareness
- **All page components** — CSS class updates to match new design tokens and grid system

### What Stays

- React component logic (state, data fetching, form handling)
- API layer (`/api/*`)
- Zustand stores (auth logic)
- React Query hooks
- i18n system
- Crypto module
- Router structure and routes

### CSS Architecture

- Keep pure CSS approach (no framework introduction)
- Keep CSS custom properties system
- Keep `data-theme` approach for dark mode
- Reorganize: consider splitting `App.css` into logical sections via CSS imports for maintainability

### Approach

- **Approach: "Layered Navigation"** — three distinct nav patterns per breakpoint
- Implement mobile-first, then layer on tablet and desktop styles
- Table-to-card transformation on mobile via CSS + minimal component changes
