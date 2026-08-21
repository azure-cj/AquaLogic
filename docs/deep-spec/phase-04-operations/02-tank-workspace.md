# Tank Workspace

Last reviewed: 2026-08-21
Status: Implemented current staff workspace; equipment expansion owned by Phase 05

## 1. Purpose

Give staff and administrators one tank-centered workspace for understanding
current operations, assigned species care, readings, alerts, and authorized
management actions.

## 2. Related Requirements

- FR-03 Tank Management
- FR-04 Water Quality Monitoring
- FR-08 Operations Dashboard
- FR-13 Species Suitability Guidance
- FR-16 Actuator Status and Control
- NFR-04 Role-Based Access Control

## 3. Current Implementation

The authenticated web route is `/admin/tanks/:tankId`. It uses the tank
resource and operations snapshot to present:

- tank name, location, public profile metadata, water type, volume, habitat,
  establishment date, and optional customer summary;
- latest supported reading and parameter states;
- Normal, Warning, Critical, or Offline operational status;
- reporting age and observation-time context;
- unresolved tank alerts;
- assigned species and derived Species Care results;
- assignment and removal controls;
- a compact actuator snapshot with navigation to the dedicated Phase 05 control
  center where authorized.

Customer assignment remains internal operational metadata. It does not create a
customer login, customer portal, or tank-ownership restriction.

## 4. Actors and Permissions

- Staff may read tank details and operations, review species care, and assign or
  remove species.
- Administrators may do everything staff can do and may create, update, delete,
  and publish tanks, manage public tank imagery, submit manual readings, and
  perform other administrator-owned mutations.
- Actuator commands, state, and history remain administrator-only under Phase
  05.
- Public viewers receive only the separate privacy-safe public tank projection.

## 5. Data and Status Rules

The tank workspace selects the latest reading by server `received_at` and uses
the Phase 02 90-second freshness window. Observation `timestamp` remains
available for historical and hardware-clock context.

Operational status follows the worst-severity rule across present, fresh,
enabled values. Missing values are Unavailable; if no usable fresh value exists,
the tank is Offline. Deferred dissolved oxygen and ammonia fields may remain in
internal compatibility responses, but they are not active bridge, threshold, or
user-facing workflows.

Species Care compares the latest fresh reading with assigned-species preferences
for temperature, pH, and TDS. It is advisory and never creates, resolves, or
modifies operational alerts.

## 6. Main Workflows

### Review a tank

1. Staff opens a tank from Fleet Overview or the tank directory.
2. The workspace loads the tank record and operations snapshot.
3. Staff reviews status, freshness, readings, alerts, and Species Care.
4. Staff follows the relevant alert, species, or actuator workspace when more
   detail is needed.

### Manage species assignments

1. Staff selects an available species.
2. The backend creates the many-to-many assignment or returns `409` when it
   already exists.
3. Staff may remove an assignment after confirmation.
4. The workspace refreshes the assigned species and derived Species Care result.

### Manage tank metadata

1. An administrator opens the configuration drawer.
2. The administrator edits approved tank and public-profile fields.
3. Validation and confirmation guard destructive or visibility-changing actions.
4. The backend records the appropriate audit event.

## 7. Backend Interfaces

The workspace consumes the following staff routes:

- `GET /tanks`
- `GET /tanks/{tank_id}`
- `GET /tanks/{tank_id}/operations`
- `GET /tanks/{tank_id}/species-suitability`
- `POST /tanks/{tank_id}/fish`
- `DELETE /tanks/{tank_id}/fish/{fish_id}`
- `GET /tanks/{tank_id}/alerts`

Administrator mutations remain on the tank, sensor, media, threshold, device,
and actuator routes owned by their respective specifications. No new tank
workspace route is introduced by this documentation pass.

## 8. UI States and Edge Cases

- Loading states appear while tank data, species, or suitability is fetched.
- A missing tank returns a not-found state.
- A tank without readings displays Offline and unavailable parameter context.
- A stale reading remains visible as historical context but cannot produce a
  confident Normal or Suitable result.
- An empty species assignment list prompts staff to add a species.
- Duplicate assignments, missing resources, and failed mutations show explicit
  backend errors.
- Destructive, public-visibility, assignment-removal, and actuator actions use
  confirmation where applicable.

## 9. History and Audit

Tank metadata changes, public-visibility changes, species assignments/removals,
manual readings, alert resolution, and actuator actions are audited by the
owning backend workflows. The tank workspace is not a separate history store.

## 10. Approved Hardening

- Keep receipt-time freshness and latest-reading behavior consistent across tank
  detail, fleet, analytics, and Species Care.
- Keep internal operational fields separate from the public tank projection.

## 11. Deferred Scope

- Tank ownership restrictions and customer accounts.
- Bulk tank operations and bulk species assignment.
- Dedicated assignment-history pages or pagination.
- Tank-level threshold overrides.
- Full actuator behavior beyond the Phase 05 control center.
- Predictive or automated care recommendations.
