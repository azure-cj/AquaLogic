import { api } from '@/shared/api/client';
import type { Customer, Tank } from '@/shared/api/models';
import {
  Drawer,
  ErrorState,
  LoadingState,
  Notice,
} from '@/shared/components/admin-ui';
import { ExternalLink } from 'lucide-react';
import { FormEvent, useState } from 'react';
import { Link } from 'react-router-dom';

function TankForm({ initial, customers, onDone }: { initial?: Tank; customers: Customer[]; onDone: () => void }) {
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);
  const submit = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault(); setBusy(true); setError('');
    const form = new FormData(event.currentTarget);
    const customer = form.get('customer_id'); const volume = form.get('volume_liters');
    const body = { name: form.get('name'), location: form.get('location'), public_location: form.get('public_location') || null, description: form.get('description') || null, is_public: form.get('is_public') === 'on', customer_id: customer ? Number(customer) : null, feeding_schedule: form.get('feeding_schedule') || null, public_care_notes: form.get('public_care_notes') || null, tank_code: form.get('tank_code') || null, habitat_label: form.get('habitat_label') || null, water_type: form.get('water_type') || null, volume_liters: volume ? Number(volume) : null, established_on: form.get('established_on') || null, hero_image_url: form.get('hero_image_url') || null };
    try { await api(initial ? `/tanks/${initial.id}` : '/tanks', { method: initial ? 'PUT' : 'POST', body: JSON.stringify(body) }); onDone(); }
    catch (caught) { setError(caught instanceof Error ? caught.message : 'Could not save tank'); }
    finally { setBusy(false); }
  };
  return <form className="drawer-form" id="tank-form" onSubmit={submit}>
    {error && <Notice tone="error">{error}</Notice>}
    <div className="form-section"><h3>Tank identity</h3><div className="form-grid"><label className="field"><span>Tank name</span><input name="name" defaultValue={initial?.name} required /></label><label className="field"><span>Location</span><input name="location" defaultValue={initial?.location} required /></label></div><label className="field"><span>Customer</span><select name="customer_id" defaultValue={initial?.customer_id ?? ''}><option value="">Unassigned</option>{customers.map((customer) => <option key={customer.id} value={customer.id}>{customer.name}</option>)}</select></label><label className="field"><span>Description</span><textarea name="description" defaultValue={initial?.description ?? ''} rows={3} /></label></div>
    <div className="form-section"><h3>Public configuration</h3><div className="form-grid"><label className="field"><span>Public location</span><input name="public_location" defaultValue={initial?.public_location ?? ''} maxLength={150} /></label><label className="field"><span>Public tank code</span><input name="tank_code" defaultValue={initial?.tank_code ?? ''} maxLength={32} /></label><label className="field"><span>Habitat label</span><input name="habitat_label" defaultValue={initial?.habitat_label ?? ''} maxLength={80} /></label><label className="field"><span>Water type</span><select name="water_type" defaultValue={initial?.water_type ?? ''}><option value="">Not specified</option><option value="freshwater">Freshwater</option><option value="saltwater">Saltwater</option><option value="brackish">Brackish</option></select></label><label className="field"><span>Volume (liters)</span><input name="volume_liters" type="number" min="1" step="1" defaultValue={initial?.volume_liters ?? ''} /></label><label className="field"><span>Established on</span><input name="established_on" type="date" defaultValue={initial?.established_on ?? ''} /></label><label className="field"><span>Hero image URL</span><input name="hero_image_url" type="url" defaultValue={initial?.hero_image_url ?? ''} /></label></div><label className="field"><span>Feeding schedule</span><input name="feeding_schedule" defaultValue={initial?.feeding_schedule ?? ''} /></label><label className="field"><span>Public care notes</span><textarea name="public_care_notes" defaultValue={initial?.public_care_notes ?? ''} rows={4} /></label><label className="toggle-field"><input type="checkbox" name="is_public" defaultChecked={initial?.is_public ?? true} /><span aria-hidden="true" /><strong>Public customer page</strong></label></div>
    <button className="sr-only" disabled={busy}>Save tank</button>{busy && <p className="form-progress">Saving tank…</p>}
  </form>;
}

export function TankEditorDrawer({
  open,
  tank,
  customers,
  customersLoading = false,
  customersError = false,
  onRetryCustomers,
  onClose,
  onSaved,
}: {
  open: boolean;
  tank?: Tank;
  customers: Customer[];
  customersLoading?: boolean;
  customersError?: boolean;
  onRetryCustomers?: () => void;
  onClose: () => void;
  onSaved: () => void;
}) {
  const ready = !customersLoading && !customersError;
  return (
    <Drawer
      open={open}
      title={tank ? `Edit ${tank.name}` : 'Add tank'}
      description={
        tank
          ? 'Update tank details and public-page configuration.'
          : 'Register a new tank in the AquaLogic fleet.'
      }
      onClose={onClose}
      footer={
        ready ? (
          <div className="drawer-actions">
            <button className="button button-secondary" type="button" onClick={onClose}>
              Cancel
            </button>
            <button className="button button-primary" type="submit" form="tank-form">
              Save tank
            </button>
          </div>
        ) : undefined
      }
    >
      {tank && (
        <Link
          className="text-link drawer-detail-link"
          to={`/admin/tanks/${tank.id}`}
          onClick={onClose}
        >
          View full tank details <ExternalLink size={14} />
        </Link>
      )}
      {customersLoading ? (
        <LoadingState label="Loading customer options…" />
      ) : customersError ? (
        <ErrorState
          message="Customer options could not be loaded. Editing is disabled to protect the current assignment."
          retry={onRetryCustomers}
        />
      ) : (
        <TankForm initial={tank} customers={customers} onDone={onSaved} />
      )}
    </Drawer>
  );
}
