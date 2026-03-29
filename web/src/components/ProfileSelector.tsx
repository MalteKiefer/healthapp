import { useTranslation } from 'react-i18next';
import { useProfiles } from '../hooks/useProfiles';

interface Props {
  selectedId: string | undefined;
  onSelect: (id: string) => void;
}

export function ProfileSelector({ selectedId, onSelect }: Props) {
  const { t } = useTranslation();
  const { data, isLoading } = useProfiles();

  if (isLoading) return <select disabled><option>{t('common.loading')}</option></select>;

  const profiles = data || [];

  return (
    <select
      className="profile-selector"
      value={selectedId || ''}
      onChange={(e) => onSelect(e.target.value)}
    >
      {profiles.length === 0 && <option value="">{t('common.no_profiles')}</option>}
      {profiles.map((p) => (
        <option key={p.id} value={p.id}>
          {p.display_name}
        </option>
      ))}
    </select>
  );
}
