import {
  FishSymbol
} from 'lucide-react';

import { ResourceManager } from '@/shared/components/ResourceManager';

export function Fish() {
  return (
    <ResourceManager
      title="Fish species"
      singular="Fish species"
      path="/fish"
      description="Maintain the species information shown to staff and customers."
      fields={[
        { key: 'common_name', label: 'Common name', required: true },
        { key: 'scientific_name', label: 'Scientific name', required: true },
        { key: 'photo_url', label: 'Photo URL', type: 'url' },
        { key: 'description', label: 'Description', type: 'textarea' },
        { key: 'diet', label: 'Diet', type: 'textarea' },
        { key: 'compatibility_notes', label: 'Compatibility notes', type: 'textarea' },
        { key: 'care_tips', label: 'Care tips', type: 'textarea' },
      ]}
      searchValues={(record) => [
        String(record.common_name ?? ''),
        String(record.scientific_name ?? ''),
      ]}
      renderRecord={(record) => (
        <>
          <span className="resource-avatar resource-photo">
            {record.photo_url ? (
              <img src={String(record.photo_url)} alt="" />
            ) : (
              <FishSymbol size={20} aria-hidden="true" />
            )}
          </span>
          <span className="resource-primary">
            <strong>{String(record.common_name)}</strong>
            <small>{String(record.scientific_name)}</small>
          </span>
          <span className="resource-description">
            {String(record.description ?? 'No description added yet.')}
          </span>
          <span className="resource-meta">
            <strong>Diet</strong>
            <small>{String(record.diet ?? 'Not specified')}</small>
          </span>
        </>
      )}
    />
  );
}

export default Fish;
