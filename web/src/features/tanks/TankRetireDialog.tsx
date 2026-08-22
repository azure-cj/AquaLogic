import { ConfirmDialog } from '@/shared/components/admin-ui';
import { useEffect, useState } from 'react';

export function TankRetireDialog({
  tankName,
  open,
  busy,
  onConfirm,
  onClose,
}: {
  tankName: string;
  open: boolean;
  busy?: boolean;
  onConfirm: (note: string | null) => void;
  onClose: () => void;
}) {
  const [note, setNote] = useState('');

  useEffect(() => {
    if (!open) setNote('');
  }, [open]);

  return (
    <ConfirmDialog
      open={open}
      title={`Retire ${tankName}?`}
      message="This removes the tank from live operations and public access. Registered devices will be disabled, while readings, alerts, assignments, equipment history, configuration, and media remain available to authorized staff. Follow the hardware decommissioning checklist first."
      confirmLabel="Retire tank"
      busy={busy}
      onConfirm={() => onConfirm(note.trim() || null)}
      onClose={onClose}
    >
      <label className="field retirement-note-field">
        <span>Retirement note (optional)</span>
        <textarea
          value={note}
          maxLength={500}
          rows={3}
          placeholder="Why is this tank leaving live operations?"
          onChange={(event) => setNote(event.target.value)}
        />
        <small>{note.length}/500</small>
      </label>
    </ConfirmDialog>
  );
}
