# Staff and Roles

## Status

**Current behavior reverse-specification** — reviewed 2026-08-21.

## Implementation checkpoint — 2026-08-21

The account lifecycle workspace is implemented. Administrator user summaries
derive `account_status`, `password_changed_at`, `active_session_count`, and
`last_activity_at` without a new user table column. Administrator-only detail,
session-list, and revoke-all-session endpoints are available, and the response
surface excludes passwords, refresh tokens, token hashes, raw IP data, and
other secrets.

The web Staff & roles route provides lifecycle-aware status labels, search and
role/status/activity filters, confirmation-gated lifecycle actions, and a
keyboard-accessible detail drawer for overview, access, sessions, and filtered
audit activity. The drawer initially renders five sessions and five meaningful
activity events, groups routine refreshes, and offers progressive load-more or
show-fewer controls from bounded responses. This is client-side progressive
rendering; it does not add server-side pagination.

Relevant implementation and coverage are in
[`backend/app/routes/management.py`](../../../backend/app/routes/management.py),
[`web/src/features/staff/StaffPage.tsx`](../../../web/src/features/staff/StaffPage.tsx),
and [`backend/tests/test_account_lifecycle.py`](../../../backend/tests/test_account_lifecycle.py).

## 1. Purpose

Define the administrator-controlled lifecycle of AquaLogic staff accounts and
the two currently supported access roles.

## 2. Related Requirements

- FR-02 Role-Based Access.
- FR-14 Customer and Staff Management.
- NFR-02 Authorization.

## 3. Actors

- **Administrator:** Creates users, assigns roles, activates/deactivates users,
  and issues password-reset links.
- **Staff member:** Uses staff operations but cannot manage accounts or roles.
- **Invited user:** Receives a one-time setup link through an administrator.
- **Unauthenticated visitor:** Cannot access staff management routes.

## 4. Data Model

`User` contains:

- numeric ID
- name
- normalized unique email
- Argon2id or legacy-compatible password hash
- role: `admin` or `staff`
- `is_active`
- `must_change_password`
- token version and password-change timestamp
- creation timestamp

The system does not store plaintext temporary passwords. Setup and reset links
are represented by hashed, expiring `AccountSetupToken` records.

## 5. States

```text
new user ──administrator creates──> active + setup required
active + setup required ──setup link consumed──> active + password ready
active ──administrator deactivates──> inactive
inactive ──administrator activates──> active
active ──administrator reset──> active + setup required
```

Role state is either `staff` or `admin`. Role changes affect subsequent
backend authorization checks because authorization reads the current database
role.

## 6. Business Rules

- **BR-STAFF-001:** Only administrators may list or mutate staff accounts.
- **BR-STAFF-002:** Only `admin` and `staff` are valid roles.
- **BR-STAFF-003:** User email is normalized before duplicate checking and
  persistence.
- **BR-STAFF-004:** Creating a user generates a random unusable initial password,
  marks the account as requiring setup, and returns a one-time setup URL.
- **BR-STAFF-005:** Setup URLs expire after 30 minutes and are shown once by the
  web UI. The administrator must share them through a secure channel.
- **BR-STAFF-006:** Administrators may update a user's name, role, and activation
  state.
- **BR-STAFF-007:** An administrator cannot demote or deactivate their own
  account.
- **BR-STAFF-008:** The system requires at least one active administrator. A
  change that would remove the final active administrator returns `409`.
- **BR-STAFF-009:** Deactivation takes effect immediately because every
  authenticated request checks `User.is_active`.
- **BR-STAFF-010:** A password reset replaces the account's unusable password,
  requires setup, increments the token version, revokes existing sessions, and
  returns a new one-time setup URL.
- **BR-STAFF-011:** Staff may perform operational actions explicitly assigned to
  the staff role, including resolving alerts and assigning/removing species.
- **BR-STAFF-012:** Staff cannot manage staff accounts, thresholds, devices,
  actuators, or other administrator-only configuration.
- **BR-STAFF-013:** There is no staff-account deletion route. Deactivation is the
  current lifecycle mechanism.

## 7. Main Workflows

### Create a staff account

1. Administrator opens `/admin/staff` and selects Add staff.
2. Administrator submits name, email, and role.
3. Backend validates the role and unique normalized email.
4. Backend creates the account with setup required and issues a one-time setup
   URL.
5. UI displays the URL once with a copy action and invalidates the staff list.

### Change role or activation state

1. Administrator changes the role or selects Activate/Deactivate.
2. Backend validates self-account and last-active-admin rules.
3. Backend persists the update and records an audit event.
4. Existing requests are re-evaluated against the current account state.

### Reset a password

1. Administrator selects Reset password for a user.
2. Backend invalidates the previous password/session state and issues a setup
   link.
3. UI displays the link once and explains the 30-minute expiry.
4. User consumes the link and chooses a new password.

## 8. Edge Cases

- Duplicate email returns `409`.
- Invalid role returns `422`.
- An administrator cannot deactivate or demote themselves.
- Removing the final active administrator returns `409`.
- A deactivated user's access and refresh session fail even if a token has not
  reached its nominal expiry.
- A reset link invalidates previous setup links for that user.
- A user with `must_change_password` may authenticate but cannot access protected
  staff resources until setup is complete.
- Staff may still read and perform the staff-authorized operational workflows;
  UI visibility is not the authorization boundary.

## 9. UI Behavior

- `/admin/account` shows Staff & roles only to administrators.
- `/admin/staff` lists name, email, role, active state, and account actions.
- Role changes use an inline selector.
- Deactivation requires confirmation.
- New-account and reset links appear in a temporary drawer and are not persisted
  by the browser application.
- Staff users who navigate directly to administrator routes receive a restricted
  state or backend error; the backend remains authoritative.
- The drawer's activity view uses the administrator audit endpoint with a user
  filter. It does not expose a staff user's audit history to staff themselves.

## 10. Backend Behavior

| Method | Route | Access | Purpose |
|---|---|---|---|
| GET | `/users` | Administrator | List users |
| GET | `/users/{user_id}` | Administrator | View derived account detail |
| GET | `/users/{user_id}/sessions` | Administrator | List the user's active sessions |
| POST | `/users/{user_id}/revoke-sessions` | Administrator | Revoke all sessions for another user |
| POST | `/users` | Administrator | Create a user and return setup link |
| PUT | `/users/{user_id}` | Administrator | Update name, role, or activation |
| POST | `/users/{user_id}/reset-password` | Administrator | Revoke sessions and issue setup link |

User responses omit password hashes and setup-token material. The backend
enforces all role and lifecycle rules independently of the web route visibility.
The administrator revoke-all endpoint cannot target the current administrator;
administrators use their personal password-confirmed sign-out-everywhere flow.

## 11. Security / Permissions

- Administrators manage staff accounts; staff do not.
- Administrator-only operations require a completed password change.
- Password reset and account deactivation invalidate access immediately.
- Setup links are hashed at rest and are never returned again after the initial
  creation/reset response.
- The current role set is intentionally limited to `admin` and `staff`.

## 12. History / Audit

The backend records successful user creation, user updates, and administrator
password-reset issuance. The administrator-only security activity feed renders
these events in a readable form.

## 13. Acceptance Criteria

- Only administrators can list, create, update, or reset users.
- Staff users receive `403` for all staff-management endpoints.
- New users receive no plaintext password and must use a single-use setup link.
- Role and activation changes obey self-account and last-admin protections.
- Deactivation and password reset invalidate existing access.
- Staff can resolve alerts and manage species assignments as confirmed product
  behavior.
- Web tests cover role visibility, confirmations, setup-link display, and error
  handling.

## 14. Open Decisions

- Whether additional roles should be introduced in a future release.
- Whether staff should receive a narrower custom permission set than the current
  shared `staff` role.
- Whether administrator password resets should require an additional
  administrator confirmation or reason.

## 15. Deferred Scope

- Customer accounts and customer editing access.
- Self-service recovery email delivery.
- Fine-grained per-user permissions.
- Staff-account deletion and archival history.
