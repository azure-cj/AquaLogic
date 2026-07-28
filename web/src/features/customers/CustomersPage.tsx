import { api } from '@/shared/api/client';
import type { Tank } from '@/shared/api/models';
import {
  StatusBadge
} from '@/shared/components/admin-ui';
import {
  initials
} from '@/shared/utils/formatting';
import { useQuery } from '@tanstack/react-query';
import { useMe } from '@/shared/hooks/useMe';

import { ResourceManager } from '@/shared/components/ResourceManager';

export function Customers() {
  const me = useMe();
  const tanks = useQuery({ queryKey: ['tanks'], queryFn: () => api<Tank[]>('/tanks') });
  return (
    <ResourceManager
      title="Customers"
      singular="Customer"
      path="/customers"
      description="Manage customer contacts and see their assigned installations."
      fields={[
        { key: 'name', label: 'Customer name', required: true },
        { key: 'email', label: 'Email address', type: 'email' },
        { key: 'phone', label: 'Phone number', type: 'tel' },
        { key: 'notes', label: 'Notes', type: 'textarea' },
        { key: 'is_active', label: 'Active customer', type: 'checkbox' },
      ]}
      searchValues={(record) => [
        String(record.name ?? ''),
        String(record.email ?? ''),
        String(record.phone ?? ''),
      ]}
      renderRecord={(record) => {
        const assigned = (tanks.data ?? []).filter((tank) => tank.customer_id === record.id);
        return (
          <>
            <span className="resource-avatar">{initials(String(record.name))}</span>
            <span className="resource-primary">
              <strong>{String(record.name)}</strong>
              <small>{String(record.email ?? 'No email')}</small>
            </span>
            <span className="resource-description">
              {String(record.phone ?? 'No phone number')}
            </span>
            <span className="resource-meta">
              <StatusBadge value={record.is_active === false ? 'offline' : 'normal'} />
              <small>
                {assigned.length
                  ? assigned.map((tank) => tank.name).join(', ')
                  : 'No assigned tanks'}
              </small>
            </span>
          </>
        );
      }}
      canManage={me.data?.role !== 'staff'}
    />
  );
}

export default Customers;
