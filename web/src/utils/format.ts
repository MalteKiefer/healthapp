export function formatNumber(value: number, decimals = 1, locale = 'de-DE'): string {
  return value.toLocaleString(locale, {
    minimumFractionDigits: 0,
    maximumFractionDigits: decimals,
  });
}

export function formatBytes(bytes: number, locale = 'de-DE'): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${formatNumber(bytes / 1024, 1, locale)} KB`;
  if (bytes < 1024 * 1024 * 1024) return `${formatNumber(bytes / (1024 * 1024), 1, locale)} MB`;
  return `${formatNumber(bytes / (1024 * 1024 * 1024), 1, locale)} GB`;
}
