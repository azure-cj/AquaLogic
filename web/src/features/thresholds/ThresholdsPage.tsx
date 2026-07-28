import { api } from '@/shared/api/client';
import type { Threshold } from '@/shared/api/models';
import {
  ErrorState,
  LoadingState,
  Notice,
  PageHeader,
  Panel
} from '@/shared/components/admin-ui';
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

export function Thresholds() {
  const client = useQueryClient();
  const query = useQuery({
    queryKey: ['thresholds'],
    queryFn: () => api<Threshold[]>('/thresholds'),
  });
  const [saving, setSaving] = useState('');
  const [notice, setNotice] = useState('');
  const [error, setError] = useState('');
  const save = async (event: FormEvent<HTMLFormElement>, threshold: Threshold) => {
    event.preventDefault();
    setSaving(threshold.parameter);
    setError('');
    const form = new FormData(event.currentTarget);
    const numberValue = (name: string) =>
      form.get(name) === '' ? null : Number(form.get(name));
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
      setNotice(`${threshold.parameter.replaceAll('_', ' ')} thresholds saved.`);
      client.invalidateQueries({ queryKey: ['thresholds'] });
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : 'Unable to save thresholds');
    } finally {
      setSaving('');
    }
  };
  return (
    <section>
      <PageHeader
        eyebrow="System configuration"
        title="Global thresholds"
        description="Changes apply to the next sensor reading across all tanks."
      />
      {notice && <Notice>{notice}</Notice>}
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
          {query.data?.map((threshold) => (
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
                <label className="field unit-field">
                  <span>Unit</span>
                  <input name="unit" defaultValue={threshold.unit} aria-label="Unit" />
                </label>
                <label className="field critical-field">
                  <span>Critical low</span>
                  <input
                    name="critical_min"
                    type="number"
                    step="any"
                    defaultValue={threshold.critical_min ?? ''}
                  />
                </label>
                <label className="field warning-field">
                  <span>Warning low</span>
                  <input
                    name="warning_min"
                    type="number"
                    step="any"
                    defaultValue={threshold.warning_min ?? ''}
                  />
                </label>
                <label className="field warning-field">
                  <span>Warning high</span>
                  <input
                    name="warning_max"
                    type="number"
                    step="any"
                    defaultValue={threshold.warning_max ?? ''}
                  />
                </label>
                <label className="field critical-field">
                  <span>Critical high</span>
                  <input
                    name="critical_max"
                    type="number"
                    step="any"
                    defaultValue={threshold.critical_max ?? ''}
                  />
                </label>
                <button className="button button-primary" disabled={saving === threshold.parameter}>
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
