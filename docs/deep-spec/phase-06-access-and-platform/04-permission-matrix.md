# Permission Matrix

## Status

**Current behavior reverse-specification** — reviewed 2026-08-21.

This document is the authoritative role-to-capability summary for the current
web and backend application. The backend dependency checks remain the final
authorization authority.

## Implementation checkpoint — 2026-08-21

The two-role matrix is implemented as documented: staff retain fleet, tank,
reading, alert, analytics, fish, customer, threshold-read, alert-resolution,
and species-assignment capabilities; administrator-only writes and security
audit access remain restricted to administrators. Public tank access and
device-key ingestion/actuator boundaries remain separate from browser JWT
authorization.

The complete matrix is covered by the Phase 06 permission and security
regression suites. The web Account Center capability popover reflects this
matrix for user understanding, but backend dependency checks remain the
enforcement boundary.

See [`backend/tests/test_permissions.py`](../../../backend/tests/test_permissions.py)
and [`web/src/features/auth/AccountCenterPage.tsx`](../../../web/src/features/auth/AccountCenterPage.tsx).

## 1. Roles and Trust Boundaries

- **Public:** No staff identity. May read only explicitly public tank content.
- **Staff:** Authenticated active user with a completed password change.
- **Administrator:** Authenticated active user with a completed password change
  and `role == "admin"`.
- **Device bridge:** Authenticated with a registered device key and fixed
  server-side device-to-tank mapping. It is not a staff role.
- **Forced-password-change user:** May use authentication and password setup
  routes, but receives `403` on protected staff resources until completion.

## 2. Capability Matrix

| Capability | Admin | Staff | Public / Device | Current boundary |
|---|---:|---:|---:|---|
| Sign in, refresh, setup password | Yes | Yes | Public flow | Active users, setup token, or refresh cookie |
| Read own account | Yes | Yes | No | `/auth/me` |
| Review/revoke own sessions | Yes | Yes | No | `/auth/sessions` |
| Sign out everywhere | Yes | Yes | No | Current-password confirmation |
| View fleet | Yes | Yes | No | `GET /fleet` |
| View tanks and operations | Yes | Yes | No | `GET /tanks*` |
| Create/update/delete tanks | Yes | No | No | Admin-only writes |
| Upload tank hero image | Yes | No | No | Admin-only |
| View sensor latest/history | Yes | Yes | No | Staff read |
| Submit manual sensor reading | Yes | No | No | Admin-only write |
| View alerts and alert history | Yes | Yes | No | Staff read |
| Resolve alerts | Yes | Yes | No | Confirmed staff capability |
| View analytics | Yes | Yes | No | Staff read |
| Read threshold configuration | Yes | Yes | No | Staff read |
| Update threshold configuration | Yes | No | No | Admin-only write |
| Read fish species profiles | Yes | Yes | No | Staff read |
| Create/update/delete fish profiles | Yes | No | No | Admin-only writes |
| Upload fish species photo | Yes | No | No | Admin-only |
| Assign/remove species from tanks | Yes | Yes | No | Confirmed staff capability |
| Read customer directory | Yes | Yes | No | Staff read |
| Create/update/delete customers | Yes | No | No | Admin-only writes |
| List/create/update staff accounts | Yes | No | No | Admin-only |
| Reset staff passwords | Yes | No | No | Admin-only |
| Provision registered devices | Yes | No | No | Admin-only; key returned once |
| Operate UV, LED, feeder, or pump tests | Yes | No | No | Admin-only actuator boundary |
| View actuator status/history | Yes | No | No | Admin-only |
| View security audit history | Yes | No | No | Administrator-only by product decision |
| Read public tank page | No special role | No special role | Yes | Public ID and visibility rules |
| Ingest sensor readings | No | No | Device only | Registered device key |
| Claim/report actuator commands | No | No | Device only | Registered device key |

## 3. Backend Enforcement Map

The backend uses dependency layers:

- `get_current_user`: validates the JWT, linked session, token version, active
  account, and session expiry.
- `require_password_change_complete`: blocks protected resources while setup is
  required.
- `require_staff`: allows `staff` and `admin`.
- `require_admin`: allows only `admin`.
- Device-key dependencies: resolve one registered device and its fixed tank.

Representative route groups:

| Dependency | Routes / capabilities |
|---|---|
| `require_staff` | Fleet, analytics, tank reads/operations, sensor reads, alerts, alert resolution, fish reads, species suitability, customer reads, threshold reads, species assignments |
| `require_admin` | Tank writes/media, fish writes/media, manual sensor writes, threshold writes, customer writes, user management, device provisioning, actuator browser APIs, security audit |
| Authenticated caller | Own sessions, logout, password change, sign-out everywhere |
| Device key | Sensor ingestion and actuator command lifecycle |

## 4. Rules

- **BR-PERM-001:** The backend must enforce every row in this matrix; hiding a
  navigation item is not authorization.
- **BR-PERM-002:** Staff may resolve alerts and add/remove species assignments.
- **BR-PERM-003:** Staff may not write thresholds, manage users, provision
  devices, submit manual sensor readings, or operate actuators.
- **BR-PERM-004:** All actuator command, state, and history endpoints are
  administrator-only for browser users.
- **BR-PERM-005:** Security audit history is administrator-only. Staff do not
  receive a personal audit feed in the current release.
- **BR-PERM-006:** Public tank routes never grant access to staff resources.
- **BR-PERM-007:** Device-key routes cannot choose a different tank from the
  registered server-side mapping.
- **BR-PERM-008:** A user who must change password is authenticated but cannot
  use staff capabilities until setup is complete.

## 5. Main Workflows

### Staff operational workflow

1. Staff signs in and completes any required password setup.
2. Staff reads fleet, tank, sensor, alert, fish, customer, threshold, and
   analytics data.
3. Staff resolves alerts and manages tank/species assignments.
4. Attempts to use administrator-only writes return `403`.

### Administrator workflow

1. Administrator signs in and completes any required password setup.
2. Administrator may perform all staff capabilities.
3. Administrator may configure operational data, manage staff, inspect audit
   history, provision devices, and operate supported actuators.

### Public workflow

1. Visitor opens a public tank URL using the tank public ID.
2. Backend returns only a tank marked public and its privacy-safe public fields.
3. No staff or administrative capability is granted.

## 6. Edge Cases

- Direct navigation to an administrator route does not bypass backend checks.
- A staff request to an admin-only route returns `403` even if the UI was
  manipulated.
- An inactive user fails authentication checks even if the JWT is unexpired.
- A role change takes effect on subsequent dependency checks because role is read
  from the database rather than trusted from the JWT.
- A forced-password-change user can call `/auth/me` but cannot use routes guarded
  by `require_staff` or `require_admin`.
- Public tank visibility and public-field filtering are separate from staff RBAC.

## 7. Acceptance Criteria

- Every matrix row has a corresponding backend authorization test.
- Staff can resolve alerts and manage tank/species assignments.
- Staff receive `403` for administrator-only configuration, staff-management,
  device, actuator, and audit operations.
- Administrators can perform both staff and administrator capabilities.
- Public and device boundaries cannot be used to reach staff routes.
- UI visibility matches the matrix but is not relied upon for enforcement.

## 8. Open Decisions

- Whether to introduce fine-grained permissions beyond the two roles.
- Whether future staff roles should separate alert resolution from species
  assignment.
- Whether security audit visibility should ever expand beyond administrators.

## 9. Deferred Scope

- Customer login or customer-specific permissions.
- Per-user permission overrides.
- Mobile-client authorization until mobile API integration begins.
