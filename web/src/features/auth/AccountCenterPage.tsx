import { ChevronRight, KeyRound, UserRoundCog } from 'lucide-react';
import { Link } from 'react-router-dom';

import { PageHeader, Panel } from '@/shared/components/admin-ui';
import { useMe } from '@/shared/hooks/useMe';
import './account-center.css';

function AccountDestination({
  to,
  title,
  description,
  icon: Icon,
}: {
  to: string;
  title: string;
  description: string;
  icon: typeof KeyRound;
}) {
  return (
    <Link className="account-destination" to={to}>
      <span className="account-destination-icon" aria-hidden="true">
        <Icon size={21} />
      </span>
      <span className="account-destination-copy">
        <strong>{title}</strong>
        <span>{description}</span>
      </span>
      <ChevronRight className="account-destination-arrow" size={19} aria-hidden="true" />
    </Link>
  );
}

export default function AccountCenterPage() {
  const me = useMe();
  const isAdmin = me.data?.role === 'admin';

  return (
    <section className="account-center">
      <PageHeader
        eyebrow="Administration"
        title="Account center"
        description={isAdmin ? 'Manage your personal security and team access.' : 'Manage your personal security.'}
      />

      <div className="account-center-grid">
        <Panel title="Your account" description="Review and protect your signed-in access.">
          <AccountDestination
            to="/admin/security"
            title="Security"
            description="Review signed-in devices, revoke access you do not recognize, and review account activity."
            icon={KeyRound}
          />
        </Panel>

        {isAdmin && (
          <Panel title="Administration" description="Manage access for the AquaLogic team.">
            <AccountDestination
              to="/admin/staff"
              title="Staff & roles"
              description="Manage staff accounts, roles, activation state, and password resets."
              icon={UserRoundCog}
            />
          </Panel>
        )}
      </div>
    </section>
  );
}
