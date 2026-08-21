# Tank Species Assignment

Last reviewed: 2026-08-21
Status: Implemented assignment workflow with audit-only history

## 1. Purpose

Maintain the many-to-many relationship between tanks and species so assigned
species can appear in tank details and participate in advisory Species Care
evaluation.

## 2. Related Requirements

- FR-11 Species Care Information
- FR-13 Species Suitability Guidance
- NFR-04 Role-based access control

## 3. Data Model

`TankFish` links `tank_id` and `fish_species_id` through a composite primary key
and records `added_at`. A tank may have many species and a species may be
assigned to many tanks. Assignment metadata is authenticated operational data
and is not part of the approved public species projection.

## 4. Actors and Permissions

- Staff may assign and remove species from tanks.
- Administrators may assign and remove species and also manage the species
  profile itself.
- Public visitors cannot modify assignments.
- Backend authorization remains authoritative even when the web UI hides an
  action.

## 5. Business Rules

- A tank and species must both exist before an assignment is created.
- The same species cannot be assigned to the same tank more than once.
- Duplicate assignment returns `409 Conflict`.
- Missing tank, missing species, or missing assignment returns `404 Not Found`.
- Removing an assignment is allowed for staff and administrators.
- A species with one or more assignments cannot be deleted; assignments must be
  removed first.
- Assignment does not consult compatibility notes or global alert thresholds.

## 6. Main Workflows

1. Staff opens a tank workspace and loads the available species.
2. Staff assigns a species, receiving a conflict if it is already assigned.
3. The tank refreshes its assigned species and derived Species Care result.
4. Staff or an administrator removes an assignment after confirmation.
5. The species directory reflects the updated tank count and assigned-tank
   summary.

## 7. UI Behavior

The tank workspace provides an assigned-species list, assignment control,
per-species care status, and a confirmation dialog before removal. The species
directory shows usage counts and assigned-tank links. Empty assignments show an
explicit prompt to add a species.

## 8. Backend Behavior

- `POST /tanks/{tank_id}/fish` creates an assignment.
- `DELETE /tanks/{tank_id}/fish/{fish_id}` removes an assignment.
- Tank and species reads include the appropriate assignment summaries for
  authenticated staff workflows.
- Assignment changes are committed with audit events.

## 9. History and Audit

Assignment and removal events are recorded as security audit events. This audit
trail is the history surface for the current phase. There is no dedicated
assignment-history endpoint, page, pagination scheme, or assignment event
browser.

## 10. Acceptance Criteria

- Staff can assign and remove species.
- Administrators retain the same assignment access.
- Duplicate assignments are rejected without creating a second link.
- Assigned species cannot be deleted.
- Assignment and removal events are auditable.
- Assignment changes refresh the tank's species list and Species Care result.

## 11. Deferred Scope

- Tank ownership or species ownership restrictions.
- Bulk assignment operations.
- Assignment scheduling or stocking limits.
- Compatibility-based assignment blocking.
- A dedicated assignment-history workspace.
