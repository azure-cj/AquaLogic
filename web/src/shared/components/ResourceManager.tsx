import { api } from '@/shared/api/client';
import {
  ConfirmDialog,
  Drawer,
  EmptyState,
  ErrorState,
  LoadingState,
  Notice,
  PageHeader,
  Panel,
  SearchField
} from '@/shared/components/admin-ui';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import {
  Pencil,
  Plus,
  Trash2
} from 'lucide-react';
import {
  FormEvent,
  ReactNode,
  useCallback,
  useState
} from 'react';
import './resource-manager.css';

export type ManagedRecord = Record<string, unknown> & { id: number; };
export type FieldSpec = {
  key: string;
  label: string;
  type?: 'text' | 'email' | 'url' | 'tel' | 'textarea' | 'checkbox';
  required?: boolean;
};

export function ResourceManager({
  title,
  singular,
  path,
  description,
  fields,
  searchValues,
  renderRecord,
  canManage = true,
}: {
  title: string;
  singular: string;
  path: string;
  description: string;
  fields: FieldSpec[];
  searchValues: (record: ManagedRecord) => string[];
  renderRecord: (record: ManagedRecord) => ReactNode;
  canManage?: boolean;
}) {
  const client = useQueryClient();
  const query = useQuery({
    queryKey: [path],
    queryFn: () => api<ManagedRecord[]>(path),
  });
  const [editing, setEditing] = useState<Partial<ManagedRecord> | null>(null);
  const [search, setSearch] = useState('');
  const [error, setError] = useState('');
  const [notice, setNotice] = useState('');
  const [deleteTarget, setDeleteTarget] = useState<ManagedRecord | null>(null);
  const [busy, setBusy] = useState(false);
  const visible = (query.data ?? []).filter((record) =>
    searchValues(record).some((value) => value.toLowerCase().includes(search.toLowerCase())),
  );
  const closeDrawer = useCallback(() => setEditing(null), []);
  const submit = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    setBusy(true);
    setError('');
    const form = new FormData(event.currentTarget);
    const body = Object.fromEntries(
      fields.map((field) => [
        field.key,
        field.type === 'checkbox'
          ? form.get(field.key) === 'on'
          : form.get(field.key) || null,
      ]),
    );
    try {
      await api(editing?.id ? `${path}/${editing.id}` : path, {
        method: editing?.id ? 'PUT' : 'POST',
        body: JSON.stringify(body),
      });
      setNotice(`${singular} ${editing?.id ? 'updated' : 'created'} successfully.`);
      setEditing(null);
      client.invalidateQueries({ queryKey: [path] });
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : `Unable to save ${singular.toLowerCase()}`);
    } finally {
      setBusy(false);
    }
  };
  const remove = async () => {
    if (!deleteTarget) return;
    setBusy(true);
    try {
      await api(`${path}/${deleteTarget.id}`, { method: 'DELETE' });
      setNotice(`${singular} deleted successfully.`);
      setDeleteTarget(null);
      client.invalidateQueries({ queryKey: [path] });
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : `Unable to delete ${singular.toLowerCase()}`);
    } finally {
      setBusy(false);
    }
  };
  const recordName = (record: Partial<ManagedRecord> | null) =>
    String(record?.name ?? record?.common_name ?? singular);

  return (
    <section>
      <PageHeader
        eyebrow="Directory"
        title={title}
        description={description}
        actions={canManage ? (
          <button
            className="button button-primary"
            type="button"
            onClick={() => {
              setError('');
              setEditing({});
            }}
          >
            <Plus size={17} /> Add {singular.toLowerCase()}
          </button>
        ) : undefined}
      />
      {notice && <Notice>{notice}</Notice>}
      {error && !editing && <Notice tone="error">{error}</Notice>}
      <Panel
        title={title}
        description={`${visible.length} record${visible.length === 1 ? '' : 's'}`}
        action={
          <SearchField
            value={search}
            onChange={setSearch}
            placeholder={`Search ${title.toLowerCase()}…`}
          />
        }
      >
        {query.isLoading ? (
          <LoadingState label={`Loading ${title.toLowerCase()}…`} />
        ) : query.isError ? (
          <ErrorState message={`${title} could not be loaded.`} retry={() => query.refetch()} />
        ) : visible.length ? (
          <div className="resource-list">
            {visible.map((record) => (
              <article className="resource-row" key={record.id}>
                {renderRecord(record)}
                {canManage && <div className="row-actions">
                  <button
                    className="icon-button"
                    type="button"
                    onClick={() => {
                      setError('');
                      setEditing(record);
                    }}
                    aria-label={`Edit ${recordName(record)}`}
                  >
                    <Pencil size={16} />
                  </button>
                  <button
                    className="icon-button icon-danger"
                    type="button"
                    onClick={() => setDeleteTarget(record)}
                    aria-label={`Delete ${recordName(record)}`}
                  >
                    <Trash2 size={16} />
                  </button>
                </div>}
              </article>
            ))}
          </div>
        ) : (
          <EmptyState title={`No ${title.toLowerCase()} found`} message="Try another search." />
        )}
      </Panel>
      <Drawer
        open={Boolean(editing)}
        title={`${editing?.id ? 'Edit' : 'Add'} ${singular.toLowerCase()}`}
        description={`Enter the ${singular.toLowerCase()} details below.`}
        onClose={closeDrawer}
        footer={
          <div className="drawer-actions">
            <button className="button button-secondary" type="button" onClick={closeDrawer}>
              Cancel
            </button>
            <button className="button button-primary" type="submit" form="resource-form">
              {busy ? 'Saving…' : `Save ${singular.toLowerCase()}`}
            </button>
          </div>
        }
      >
        <form id="resource-form" className="drawer-form" onSubmit={submit}>
          {error && <Notice tone="error">{error}</Notice>}
          <div className="form-section">
            {fields.map((field) =>
              field.type === 'checkbox' ? (
                <label className="toggle-field" key={field.key}>
                  <input
                    type="checkbox"
                    name={field.key}
                    defaultChecked={editing?.[field.key] !== false}
                  />
                  <span aria-hidden="true" />
                  <strong>{field.label}</strong>
                </label>
              ) : (
                <label className="field" key={field.key}>
                  <span>{field.label}</span>
                  {field.type === 'textarea' ? (
                    <textarea
                      name={field.key}
                      defaultValue={String(editing?.[field.key] ?? '')}
                      required={field.required}
                      rows={4}
                    />
                  ) : (
                    <input
                      name={field.key}
                      type={field.type ?? 'text'}
                      defaultValue={String(editing?.[field.key] ?? '')}
                      required={field.required}
                    />
                  )}
                </label>
              ),
            )}
          </div>
        </form>
      </Drawer>
      <ConfirmDialog
        open={Boolean(deleteTarget)}
        title={`Delete ${recordName(deleteTarget)}?`}
        message={`This permanently removes the ${singular.toLowerCase()} record and cannot be undone.`}
        confirmLabel={`Delete ${singular.toLowerCase()}`}
        busy={busy}
        onConfirm={remove}
        onClose={() => setDeleteTarget(null)}
      />
    </section>
  );
}
