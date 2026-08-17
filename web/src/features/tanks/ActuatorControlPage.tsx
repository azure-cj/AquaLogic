import { api } from '@/shared/api/client';
import type { Tank } from '@/shared/api/models';
import {
  ErrorState,
  LoadingState,
  PageHeader,
} from '@/shared/components/admin-ui';
import { useMe } from '@/shared/hooks/useMe';
import { useQuery } from '@tanstack/react-query';
import { ArrowLeft } from 'lucide-react';
import { Link, Navigate, useParams } from 'react-router-dom';
import { ActuatorControlPanel, StaffActuatorNotice } from './ActuatorControlPanel';
import './styles.css';

export function ActuatorControlPage() {
  const { tankId } = useParams();
  const id = Number(tankId);
  const validId = Number.isInteger(id) && id > 0;
  const me = useMe();
  const isAdmin = me.data?.role === 'admin';
  const tank = useQuery({
    queryKey: ['tank', id],
    queryFn: () => api<Tank>(`/tanks/${id}`),
    enabled: validId && isAdmin,
  });

  if (!validId) {
    return (
      <section className="actuator-control-page">
        <ErrorState message="This tank actuator route is not valid." />
      </section>
    );
  }

  if (me.isLoading) {
    return (
      <section className="actuator-control-page">
        <LoadingState label="Checking administrator access…" />
      </section>
    );
  }

  if (me.isError) return <Navigate to="/admin/login" replace />;

  const backAction = (
    <Link className="button button-secondary" to={`/admin/tanks/${id}`}>
      <ArrowLeft size={16} /> Back to tank
    </Link>
  );

  if (!isAdmin) {
    return (
      <section className="actuator-control-page">
        <PageHeader
          eyebrow="Tank operations"
          title="Actuator controls"
          description="The focused actuator workspace is restricted to administrators."
          actions={backAction}
        />
        <StaffActuatorNotice />
      </section>
    );
  }

  return (
    <section className="actuator-control-page">
      <PageHeader
        eyebrow={`Tank operations · ${tank.data?.name ?? `Tank ${id}`}`}
        title="Actuator control center"
        description="Run light, feeder, timer, schedule, and guarded pump-test actions for this tank’s registered bridge."
        actions={backAction}
      />
      {tank.isLoading ? (
        <div className="panel actuator-page-loading">
          <LoadingState label="Loading tank actuator workspace…" />
        </div>
      ) : tank.isError || !tank.data ? (
        <ErrorState message="The registered tank could not be loaded, so actuator controls are unavailable." retry={() => tank.refetch()} />
      ) : (
        <>
          <div className="actuator-control-page-context" role="note">
            <div>
              <strong>Focused workspace</strong>
              <span>Use this page for schedules, timer controls, pump safety checks, and command history.</span>
            </div>
            <div>
              <strong>Safe command path</strong>
              <span>Commands are queued through AquaLogic; the browser never connects directly to the ESP32.</span>
            </div>
          </div>
          <ActuatorControlPanel tankId={id} variant="full" />
        </>
      )}
    </section>
  );
}

export default ActuatorControlPage;
