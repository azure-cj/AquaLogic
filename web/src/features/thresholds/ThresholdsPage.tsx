import { api } from '@/shared/api/client';
import type { Threshold } from '@/shared/api/models';
import {
  ErrorState,
  LoadingState,
  Notice,
  PageHeader,
  Panel,
  FormField,
} from '@/shared/components/admin-ui';
import { notify } from '@/shared/lib/notify';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import {
  Activity,
  Gauge,
  Settings2,
  Thermometer
} from 'lucide-react';
import {
  FormEvent,
  useState
} from 'react';
import './styles.css';

const VISIBLE_THRESHOLD_PARAMETERS = new Set(['temperature', 'ph', 'turbidity', 'tds']);

export function Thresholds() {
  const client = useQueryClient();
  const query = useQuery({
    queryKey: ['thresholds'],
    queryFn: () => api<Threshold[]>('/thresholds'),
  });
  const [saving, setSaving] = useState('');
  const [error, setError] = useState('');
  const [errorParameter, setErrorParameter] = useState('');
  const save = async (event: FormEvent<HTMLFormElement>, threshold: Threshold) => {
    event.preventDefault();
    setSaving(threshold.parameter);
    setError('');
    setErrorParameter('');
    const form = new FormData(event.currentTarget);
    const numberValue = (name: string) =>
      form.get(name) === '' ? null : Number(form.get(name));
    const bounds = [
      numberValue('critical_min'),
      numberValue('warning_min'),
      numberValue('warning_max'),
      numberValue('critical_max'),
    ].filter((value): value is number => value !== null);
    if (bounds.some((value, index) => index > 0 && bounds[index - 1] >= value)) {
      setError('Bounds must be strictly ordered from critical low to critical high.');
      setErrorParameter(threshold.parameter);
      setSaving('');
      return;
    }
    try {
      await api(`/thresholds/${threshold.parameter}`, {
        method: 'PUT',
        body: JSON.stringify({
          unit: form.get('unit'),
          warning_min: numberValue('warning_min'),
          warning_max: numberValue('warning_max'),
          critical_min: numberValue('critical_min'),
          critical_max: numberValue('critical_max'),
          enabled: form.get('enabled') === 'on',
        }),
      });
      notify.success(`${threshold.parameter.replaceAll('_', ' ')} thresholds saved.`);
      client.invalidateQueries({ queryKey: ['thresholds'] });
      client.invalidateQueries({ queryKey: ['tank-thresholds'] });
      client.invalidateQueries({ queryKey: ['tank-operations'] });
      client.invalidateQueries({ queryKey: ['fleet'] });
      client.invalidateQueries({ queryKey: ['analytics'] });
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : 'Unable to save thresholds');
      setErrorParameter(threshold.parameter);
    } finally {
      setSaving('');
    }
  };
  return (
    <section>
      <PageHeader
        eyebrow="System configuration"
        title="Global threshold defaults"
        description="These settings are inherited by every tank unless an administrator saves a tank override. Changes apply prospectively. Values must pass a configured boundary to trigger Warning or Critical; exact boundary values remain within the Normal range."
      />
      {error && <Notice tone="error">{error}</Notice>}
      {query.isLoading ? (
        <Panel>
          <LoadingState label="Loading thresholds…" />
        </Panel>
      ) : query.isError ? (
        <Panel>
          <ErrorState message="Thresholds could not be loaded." retry={() => query.refetch()} />
        </Panel>
      ) : (
        <div className="threshold-list">
          {query.data?.filter((threshold) => VISIBLE_THRESHOLD_PARAMETERS.has(threshold.parameter)).map((threshold) => (
            <form
              className="threshold-card"
              key={threshold.parameter}
              onSubmit={(event) => save(event, threshold)}
            >
              <header>
                <span className="threshold-icon" aria-hidden="true">
                  {threshold.parameter === 'temperature' ? (
                    <Thermometer size={19} />
                  ) : threshold.parameter === 'ph' ? (
                    <Gauge size={19} />
                  ) : (
                    <Activity size={19} />
                  )}
                </span>
                <span>
                  <h2>{threshold.parameter.replaceAll('_', ' ')}</h2>
                  <small>Warning and critical operating bounds</small>
                </span>
                <label className="toggle-field compact-toggle">
                  <input
                    name="enabled"
                    type="checkbox"
                    defaultChecked={threshold.enabled}
                  />
                  <span aria-hidden="true" />
                  <strong>Enabled</strong>
                </label>
              </header>
              <div className="threshold-fields">
                <FormField label="Unit" className="unit-field" description="Displayed with this parameter.">
                  <input name="unit" defaultValue={threshold.unit} aria-label="Unit" />
                </FormField>
                <FormField label="Critical below" className="critical-field" suffix={threshold.unit} error={errorParameter === threshold.parameter ? error : undefined}>
                  <input
                    name="critical_min"
                    type="number"
                    step="any"
                    defaultValue={threshold.critical_min ?? ''}
                  />
                </FormField>
                <FormField label="Warning below" className="warning-field" suffix={threshold.unit} error={errorParameter === threshold.parameter ? error : undefined}>
                  <input
                    name="warning_min"
                    type="number"
                    step="any"
                    defaultValue={threshold.warning_min ?? ''}
                  />
                </FormField>
                <FormField label="Warning above" className="warning-field" suffix={threshold.unit} error={errorParameter === threshold.parameter ? error : undefined}>
                  <input
                    name="warning_max"
                    type="number"
                    step="any"
                    defaultValue={threshold.warning_max ?? ''}
                  />
                </FormField>
                <FormField label="Critical above" className="critical-field" suffix={threshold.unit} error={errorParameter === threshold.parameter ? error : undefined}>
                  <input
                    name="critical_max"
                    type="number"
                    step="any"
                    defaultValue={threshold.critical_max ?? ''}
                  />
                </FormField>
                <button className="button button-primary" aria-busy={saving === threshold.parameter} disabled={saving === threshold.parameter}>
                  {saving === threshold.parameter ? (
                    'Saving…'
                  ) : (
                    <>
                      <Settings2 size={16} /> Save
                    </>
                  )}
                </button>
              </div>
            </form>
          ))}
        </div>
      )}
    </section>
  );
}

export default Thresholds;
