export function compareByColumn<T>(
  a: T,
  b: T,
  sortCol: string,
  sortDir: 'asc' | 'desc'
): number {
  const aVal = (a as unknown as Record<string, unknown>)[sortCol];
  const bVal = (b as unknown as Record<string, unknown>)[sortCol];
  if (aVal == null && bVal == null) return 0;
  if (aVal == null) return 1;
  if (bVal == null) return -1;
  const cmp = typeof aVal === 'string' ? aVal.localeCompare(bVal as string) : (aVal as number) - (bVal as number);
  return sortDir === 'asc' ? cmp : -cmp;
}
