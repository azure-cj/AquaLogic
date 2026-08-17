import { api } from '@/shared/api/client';
import type { Tank } from '@/shared/api/models';
import {
  EmptyState,
  ErrorState,
  LoadingState,
  PageHeader,
  Panel,
  SearchField,
} from '@/shared/components/admin-ui';
import { useMe } from '@/shared/hooks/useMe';
import { useQuery } from '@tanstack/react-query';
import { ArrowRight, LockKeyhole, Power } from 'lucide-react';
import { useState } from 'react';
import { Link, Navigate } from 'react-router-dom';
import { StaffActuatorNotice } from './ActuatorControlPanel';
import './styles.css';

export function ActuatorDirectoryPage() {
  const me = useMe();
  const isAdmin = me.data?.role === 'admin';
  const [search, setSearch] = useState('');
  const tanks = useQuery({
    queryKey: ['tanks', 'actuator-directory'],
    queryFn: () => api<Tank[]>('/tanks'),
    enabled: isAdmin,
  });

  if (me.isLoading) {
    return <section className="actuator-directory-page"><LoadingState label="Checking administrator access…" /></section>;
  }

  if (me.isError) return <Navigate to="/admin/login" replace />;

  if (!isAdmin) {
    return (
      <section className="actuator-directory-page">
        <PageHeader
          eyebrow="Administration"
          title="Actuator controls"
          description="Tank actuator selection is restricted to administrators."
        />
        <StaffActuatorNotice />
      </section>
    );
  }

  const normalizedSearch = search.trim().toLowerCase();
  const visibleTanks = (tanks.data ?? []).filter((tank) =>
    [tank.name, tank.location, tank.customer?.name]
      .filter((value): value is string => Boolean(value))
      .some((value) => value.toLowerCase().includes(normalizedSearch)),
  );

  return (
    <section className="actuator-directory-page">
      <PageHeader
        eyebrow="Administration"
        title="Actuator controls"
        description="Choose a tank to open its focused control center. The backend keeps every command scoped to the bridge registered for that tank."
      />
      <div className="actuator-directory-note" role="note">
        <LockKeyhole size={18} aria-hidden="true" />
        <span>
          <strong>Server-scoped hardware access</strong>
          <small>The browser chooses a tank view only. It never chooses a device, receives a device key, or contacts the ESP32 directly.</small>
        </span>
      </div>
      <Panel
        title="Choose a tank"
        description={`${visibleTanks.length} of ${tanks.data?.length ?? 0} tanks available`}
        action={<SearchField value={search} onChange={setSearch} placeholder="Search tanks…" />}
      >
        {tanks.isLoading ? (
          <LoadingState label="Loading tanks…" />
        ) : tanks.isError ? (
          <ErrorState message="Tanks could not be loaded for actuator selection." retry={() => tanks.refetch()} />
        ) : visibleTanks.length ? (
          <div className="actuator-tank-grid">
            {visibleTanks.map((tank) => (
              <article className="actuator-tank-card" key={tank.id}>
                <div className="actuator-tank-card-heading">
                  <span className="actuator-tank-mark" aria-hidden="true"><Power size={18} /></span>
                  <div>
                    <p className="actuator-kicker">Tank {tank.id}</p>
                    <h3>{tank.name}</h3>
                    <small>{tank.location}{tank.customer ? ` · ${tank.customer.name}` : ''}</small>
                  </div>
                </div>
                <div className="actuator-tank-scope">
                  <span><small>Command boundary</small><strong>Registered tank only</strong></span>
                  <span><small>Hardware access</small><strong>Verified on open</strong></span>
                </div>
                <p className="actuator-tank-card-copy">Open the full workspace to view bridge freshness before sending a command.</p>
                <div className="actuator-tank-card-actions">
                  <Link className="button button-primary button-small" to={`/admin/tanks/${tank.id}/actuators`}>
                    Open controls <ArrowRight size={14} />
                  </Link>
                  <Link className="text-link" to={`/admin/tanks/${tank.id}`}>Tank workspace</Link>
                </div>
              </article>
            ))}
          </div>
        ) : (
          <EmptyState title="No matching tanks" message="Try another tank name, location, or customer." />
        )}
      </Panel>
    </section>
  );
}

export default ActuatorDirectoryPage;
