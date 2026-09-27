import { api } from '@/shared/api/client';
import type { TankThreshold } from '@/shared/api/models';
import {
  ConfirmDialog,
  ErrorState,
  FormField,
  LoadingState,
  Notice,
  Panel,
} from '@/shared/components/admin-ui';
import { useMe } from '@/shared/hooks/useMe';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { FormEvent, useState } from 'react';
import './threshold-overrides.css';

const VISIBLE_PARAMETERS = [
  ['temperature', 'Temperature'],
  ['ph', 'pH'],
  ['turbidity', 'Turbidity'],
  ['tds', 'TDS'],
] as const;

const displayBound = (value: number | null, unit: string) =>
  value == null ? 'Not configured' : `${value} ${unit}`;

type ThresholdValues = Pick<
  TankThreshold,
  'critical_min' | 'warning_min' | 'warning_max' | 'critical_max' | 'enabled'
>;

type PendingConfirmation =
  | { kind: 'save'; parameter: string; label: string; unit: string; values: ThresholdValues }
  | { kind: 'reset'; parameter: string; label: string; unit: string };

export function TankThresholdsPanel({
  tankId,
  tankName,
  active,
}: {
  tankId: number;
  tankName: string;
  active: boolean;
}) {
  const client = useQueryClient();
  const me = useMe();
  const isAdmin = me.data?.role === 'admin';
  const query = useQuery({
    queryKey: ['tank-thresholds', tankId],
    queryFn: () => api<TankThreshold[]>(`/tanks/${tankId}/thresholds`),
  });
  const [editing, setEditing] = useState('');
  const [busy, setBusy] = useState('');
  const [error, setError] = useState('');
  const [confirmation, setConfirmation] = useState<PendingConfirmation | null>(null);

  const save = (event: FormEvent<HTMLFormElement>, parameter: string, label: string) => {
    event.preventDefault();
    setError('');
    const form = new FormData(event.currentTarget);
    const numberValue = (name: string) =>
      form.get(name) === '' ? null : Number(form.get(name));
    const bounds = [
      numberValue('critical_min'),
      numberValue('warning_min'),
      numberValue('warning_max'),
      numberValue('critical_max'),
    ];
    if (bounds.some((value) => value !== null && !Number.isFinite(value))) {
      setError('Use a valid number for each limit you enter.');
      return;
    }
    const present = bounds.filter((value): value is number => value !== null);
    if (present.some((value, index) => index > 0 && present[index - 1] >= value)) {
      setError('Enter limits from lowest to highest: critical low, warning low, warning high, then critical high.');
      return;
    }

    setConfirmation({
      kind: 'save',
      parameter,
      label,
      unit: query.data?.find((item) => item.parameter === parameter)?.unit ?? '',
      values: {
        critical_min: numberValue('critical_min'),
        warning_min: numberValue('warning_min'),
        warning_max: numberValue('warning_max'),
        critical_max: numberValue('critical_max'),
        enabled: form.get('enabled') === 'on',
      },
    });
  };

  const requestReset = (parameter: string, label: string, unit: string) => {
    setError('');
    setConfirmation({ kind: 'reset', parameter, label, unit });
  };

  const confirmChange = async () => {
    if (!confirmation) return;
    const pending = confirmation;
    setBusy(pending.parameter);
    setError('');
    try {
      if (pending.kind === 'save') {
        await api(`/tanks/${tankId}/thresholds/${pending.parameter}`, {
          method: 'PUT',
          body: JSON.stringify(pending.values),
        });
      } else {
        await api(`/tanks/${tankId}/thresholds/${pending.parameter}`, { method: 'DELETE' });
      }
      setEditing('');
      setConfirmation(null);
      await client.invalidateQueries({ queryKey: ['tank-thresholds', tankId] });
      client.invalidateQueries({ queryKey: ['tank-operations', tankId] });
      client.invalidateQueries({ queryKey: ['fleet'] });
      client.invalidateQueries({ queryKey: ['analytics'] });
    } catch (caught) {
      setConfirmation(null);
      setError(caught instanceof Error ? caught.message : pending.kind === 'save'
        ? 'Could not save these limits. Please try again.'
        : 'Could not restore the standard limits. Please try again.');
    } finally {
      setBusy('');
    }
  };

  return (
    <Panel
      title="Water-quality limits"
      description="Tanks use the standard water limits unless custom limits are set. A reading exactly on a limit is considered normal."
      className="tank-threshold-panel"
    >
      {error && <Notice tone="error">{error}</Notice>}
      {query.isLoading ? (
        <LoadingState label="Loading water limits…" />
      ) : query.isError ? (
        <ErrorState
          message="Water limits could not be loaded."
          retry={() => query.refetch()}
        />
      ) : (
        <div className="tank-threshold-list">
          {VISIBLE_PARAMETERS.map(([parameter, label]) => {
            const threshold = query.data?.find((item) => item.parameter === parameter);
            if (!threshold) return null;
            const isEditing = editing === parameter;
            return (
              <article className="tank-threshold-item" key={parameter}>
                <header>
                  <div>
                    <h3>{label}</h3>
                    <span className={`threshold-source threshold-source-${threshold.source}`}>
                      {threshold.source === 'global' ? 'Standard limits' : 'Custom for this tank'}
                    </span>
                    {!threshold.enabled && <span className="threshold-disabled">Disabled</span>}
                  </div>
                  {isAdmin && active && !isEditing && (
                    <button
                      className="button button-secondary"
                      type="button"
                      onClick={() => setEditing(parameter)}
                    >
                      {threshold.source === 'global' ? 'Set custom limits' : 'Edit custom limits'}
                    </button>
                  )}
                </header>

                {isEditing && isAdmin && active ? (
                  <form className="tank-threshold-form" onSubmit={(event) => save(event, parameter, label)}>
                    <p>These values set all limits for this measure. Leave a boundary blank if it does not apply; units stay fixed at {threshold.unit}.</p>
                    <div className="tank-threshold-fields">
                      <FormField label="Critical below" suffix={threshold.unit}>
                        <input name="critical_min" type="number" step="any" defaultValue={threshold.critical_min ?? ''} />
                      </FormField>
                      <FormField label="Warning below" suffix={threshold.unit}>
                        <input name="warning_min" type="number" step="any" defaultValue={threshold.warning_min ?? ''} />
                      </FormField>
                      <FormField label="Warning above" suffix={threshold.unit}>
                        <input name="warning_max" type="number" step="any" defaultValue={threshold.warning_max ?? ''} />
                      </FormField>
                      <FormField label="Critical above" suffix={threshold.unit}>
                        <input name="critical_max" type="number" step="any" defaultValue={threshold.critical_max ?? ''} />
                      </FormField>
                    </div>
                    <label className="toggle-field compact-toggle">
                      <input name="enabled" type="checkbox" defaultChecked={threshold.enabled} />
                      <span aria-hidden="true" />
                      <strong>Enabled</strong>
                    </label>
                    <div className="tank-threshold-actions">
                      <button className="button button-primary" type="submit" disabled={busy === parameter}>
                        {busy === parameter ? 'Saving…' : 'Save custom limits'}
                      </button>
                      <button className="button button-secondary" type="button" disabled={busy === parameter} onClick={() => { setEditing(''); setError(''); }}>
                        Cancel
                      </button>
                    </div>
                  </form>
                ) : (
                  <dl className="tank-threshold-values">
                    <div><dt>Critical below</dt><dd>{displayBound(threshold.critical_min, threshold.unit)}</dd></div>
                    <div><dt>Warning below</dt><dd>{displayBound(threshold.warning_min, threshold.unit)}</dd></div>
                    <div><dt>Warning above</dt><dd>{displayBound(threshold.warning_max, threshold.unit)}</dd></div>
                    <div><dt>Critical above</dt><dd>{displayBound(threshold.critical_max, threshold.unit)}</dd></div>
                  </dl>
                )}

                {isAdmin && active && threshold.source === 'tank' && !isEditing && (
                  <button
                    className="text-link tank-threshold-reset"
                    type="button"
                    disabled={busy === parameter}
                    onClick={() => requestReset(parameter, label, threshold.unit)}
                  >
                    {busy === parameter ? 'Restoring…' : 'Use standard limits'}
                  </button>
                )}
              </article>
            );
          })}
        </div>
      )}
      <ConfirmDialog
        open={confirmation !== null}
        title={confirmation?.kind === 'reset'
          ? `Use standard ${confirmation.label} limits for ${tankName}?`
          : `Save ${confirmation?.label ?? 'tank'} limits for ${tankName}?`}
        message={confirmation?.kind === 'reset'
          ? 'This removes this tank’s custom limits for this measure and restores the current global defaults.'
          : `Review the proposed limits for ${tankName}. They override shared defaults for this tank only and apply prospectively.`}
        confirmLabel={confirmation?.kind === 'reset' ? 'Use standard limits' : 'Save custom limits'}
        tone="primary"
        busy={Boolean(confirmation && busy === confirmation.parameter)}
        onConfirm={() => { void confirmChange(); }}
        onClose={() => { if (!busy) setConfirmation(null); }}
      >
        {confirmation?.kind === 'save' && (
          <dl className="threshold-confirm-summary">
            <div><dt>Tank</dt><dd>{tankName}</dd></div>
            <div><dt>Measure</dt><dd>{confirmation.label}</dd></div>
            <div><dt>Critical below</dt><dd>{displayBound(confirmation.values.critical_min, confirmation.unit)}</dd></div>
            <div><dt>Warning below</dt><dd>{displayBound(confirmation.values.warning_min, confirmation.unit)}</dd></div>
            <div><dt>Warning above</dt><dd>{displayBound(confirmation.values.warning_max, confirmation.unit)}</dd></div>
            <div><dt>Critical above</dt><dd>{displayBound(confirmation.values.critical_max, confirmation.unit)}</dd></div>
            <div><dt>Status</dt><dd>{confirmation.values.enabled ? 'Enabled' : 'Disabled'}</dd></div>
          </dl>
        )}
        {confirmation?.kind === 'reset' && (
          <dl className="threshold-confirm-summary">
            <div><dt>Tank</dt><dd>{tankName}</dd></div>
            <div><dt>Measure</dt><dd>{confirmation.label}</dd></div>
            <div><dt>Current unit</dt><dd>{confirmation.unit}</dd></div>
            <div><dt>Result</dt><dd>Use current global defaults</dd></div>
          </dl>
        )}
      </ConfirmDialog>
    </Panel>
  );
}
