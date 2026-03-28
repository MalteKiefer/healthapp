import { useTranslation } from 'react-i18next';
import { de, enUS } from 'date-fns/locale';
import { format as fnsFormat, formatDistanceToNow as fnsDistanceToNow } from 'date-fns';

const LOCALES: Record<string, typeof enUS> = { de, en: enUS };

export function useDateFormat() {
  const { i18n } = useTranslation();
  const locale = LOCALES[i18n.language] || enUS;

  const fmt = (date: Date | string, pattern: string) =>
    fnsFormat(typeof date === 'string' ? new Date(date) : date, pattern, { locale });

  const relative = (date: Date | string) =>
    fnsDistanceToNow(typeof date === 'string' ? new Date(date) : date, { addSuffix: true, locale });

  return { fmt, relative, locale };
}
