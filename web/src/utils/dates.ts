/**
 * Normalise date-only strings ("2024-01-15") to full ISO-8601 timestamps
 * and strip empty-string date values so the API never receives "".
 *
 * Used by every CRUD page that sends date fields (Diagnoses, Vaccinations,
 * Tasks, etc.).
 */
export function fixDates(
  data: Record<string, unknown>,
  dateFields: string[],
): Record<string, unknown> {
  const cleaned = { ...data };
  for (const field of dateFields) {
    const val = cleaned[field];
    if (typeof val === 'string' && val && !val.includes('T')) {
      cleaned[field] = new Date(val + 'T00:00:00').toISOString();
    }
    if (typeof val === 'string' && val === '') {
      delete cleaned[field];
    }
  }
  return cleaned;
}
