# Tank Deletion and Hardware Decommissioning

Classification: **Implemented cleanup and decommissioning record**, with permanent deletion bounded by the approved packet 08 lifecycle
Status: Implemented cleanup, warning, decommissioning documentation, and retirement-before-delete boundary  
Last reviewed: 2026-08-22

## Objective

Keep the current tested hard-delete implementation while the approved retired
tank lifecycle is implemented separately, making deletion consequences accurate,
cleaning AquaLogic-owned local media, and documenting that database deletion
does not erase device-resident state.

## Verified current behavior

`DELETE /tanks/{tank_id}` is administrator-only. The relational model cascades
tank-owned records including sensor readings, alerts, tank-species assignments,
registered devices, actuator commands, current actuator state, and actuator
state history. Integrity coverage exists in
`backend/tests/test_data_integrity.py`.

Security audit records survive because they use plain target identifiers rather
than a foreign key to the tank. There is no in-app undelete.

Tank hero uploads are stored below `settings.media_root/tanks` and recorded as
`/api/media/tanks/...`. Replacing an uploaded hero safely removes the prior
owned local file through `_remove_local_hero_image()`. Permanent tank deletion
does not currently call that helper, leaving the file orphaned. Hosted external
hero URLs are not owned by AquaLogic.

Before Goal 2, the web deletion dialogs said only:

> This permanently removes the tank and cannot be undone.

Goal 2 now uses the expanded warning below in both deletion entry points:

> Permanently delete this tank? Its sensor readings, alerts, equipment command
> and state history, device registrations, species assignments, uploaded tank
> image, and public tank page will also be removed. This cannot be undone.

Deleting the database row does not communicate with the ESP32 and therefore
does not prove that device-resident UV/LED/feeder schedules or current physical
state were cleared.

## Work item A — local-media cleanup

On permanent deletion:

1. capture the tank's current `hero_image_url` before deleting the row;
2. commit the database deletion and audit event first;
3. only after a successful commit, attempt removal through the existing safe
   local-media helper;
4. ignore external URLs and any path outside the configured media root;
5. do not roll back a committed relational deletion because a best-effort file
   removal fails;
6. handle a missing file idempotently;
7. log an operationally useful, non-secret warning on filesystem failure.

Database-first ordering avoids deleting the file if the relational delete
rolls back. Reuse the helper's resolved-path containment check; do not implement
deletion from arbitrary user-supplied paths.

Likely touchpoints:

- `backend/app/routes/tanks.py`
- `backend/tests/test_tank_media.py`
- possibly shared logging configuration if the route currently has no logger

Required tests:

- deleting a tank removes its owned uploaded hero file;
- external HTTPS hero URLs are never treated as filesystem targets;
- a missing owned file does not make deletion fail;
- a simulated database commit failure leaves the file in place;
- a simulated post-commit unlink failure does not resurrect or report the tank
  as undeleted;
- path traversal or a non-owned media path cannot delete outside media root;
- staff cannot delete a tank or its media.

## Work item B — accurate permanent-deletion warning

Update both tank deletion entry points:

- `web/src/features/tanks/TanksPage.tsx`
- `web/src/features/tanks/TankDetailPage.tsx`

Recommended copy, adjusted only to match the final verified cascade list:

> Permanently delete this tank? Its sensor readings, alerts, equipment command
> and state history, device registrations, species assignments, uploaded tank
> image, and public tank page will also be removed. This cannot be undone.

Do not claim that security audit events are deleted. Do not claim that ESP32
schedules or physical equipment state are cleared.

Add or update component tests to assert the material consequences, not just the
presence of a dialog.

## Work item C — hardware decommissioning runbook

Document deletion as an operational procedure, not a remote teardown protocol.
The administrator should complete this sequence before permanent deletion when
the tank has registered equipment:

```text
1. Identify every registered device and attached actuator for the tank.
2. Keep the bridge online and physically inspect the correct hardware.
3. Disable device-resident schedules using the existing controls where safe.
4. Stop active equipment and verify the physical result locally.
5. Record any configuration that must be preserved for another tank.
6. Deactivate the old registered device/key.
7. Confirm no fresh readings or commands are still arriving under that identity.
8. Permanently delete the tank only after hardware cleanup is complete.
9. If hardware is reused, follow the [canonical move/reprovisioning
   workflow](../../WORKFLOWS.md#moving-equipment-to-another-tank) and provision
   a new registration for its destination.
```

If the equipment cannot be reached, deletion must not imply cleanup occurred.
The operator should defer deletion or explicitly accept the limitation after
physical follow-up. Do not add automatic remote teardown, firmware reset, or
schedule-erasure endpoints in this pass.

The durable runbook is the [canonical move/reprovisioning workflow](../../WORKFLOWS.md#moving-equipment-to-another-tank)
in `docs/WORKFLOWS.md`. The deletion UI and this packet must not imply that
deactivation or deletion clears firmware state; physical cleanup remains a
manual operator step.

## Retired-lifecycle boundary

Retired tanks are not part of this implementation packet. The owner-approved
two-state lifecycle is specified in
[`08-retired-tank-lifecycle.md`](08-retired-tank-lifecycle.md) and will
eventually require retirement before permanent deletion.

This goal therefore:

- keeps the current hard-delete route and cascade;
- does not add `retired_at`, lifecycle statuses, archive filters, or restore;
- does not weaken the existing cascade tests; and
- makes the warning and operational workflow honest about the future retirement
  boundary and the absence of remote hardware teardown.

## Acceptance criteria

- Permanent deletion removes AquaLogic-owned local tank hero media safely.
- External/shared resources are untouched.
- The UI names the major deleted operational records and irreversibility.
- The UI/docs do not say database deletion clears device-resident configuration.
- A practical pre-deletion hardware cleanup procedure exists and points to the
  move/reprovisioning workflow.
- No archive feature is introduced without recorded client approval.

## Non-goals

- Tank archival, retirement, undelete, or restore.
- Remote factory reset or generalized decommissioning protocol.
- Deleting external image-host resources.
- Preserving relational tank history after hard deletion.
