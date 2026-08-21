# Account Security

## Status

**Current behavior reverse-specification** — reviewed 2026-08-21.

## Implementation checkpoint — 2026-08-21

Personal session management and administrator-only security investigation are
implemented. The security screen supports account, event, outcome, and date
filters; keeps routine refresh and bridge telemetry grouped in the default
feed; and provides bounded older-page loading through the audit cursor. The
administrator Staff & roles drawer reuses the administrator audit boundary for
per-user activity and initially renders five meaningful events, with progressive
show-more controls for the bounded response.

The drawer controls are a presentation limit, not server-side pagination: active
sessions remain returned by the current session endpoint, while the per-user
audit request is bounded before the UI reveals additional records. Larger-scale
server pagination remains a separate follow-up.

See [`web/src/features/auth/SecurityPage.tsx`](../../../web/src/features/auth/SecurityPage.tsx),
[`web/src/features/staff/StaffPage.tsx`](../../../web/src/features/staff/StaffPage.tsx),
and [`backend/tests/test_account_lifecycle.py`](../../../backend/tests/test_account_lifecycle.py).

## 1. Purpose

Allow an authenticated user to review active sessions and remove unrecognized
device access. Provide administrators with a security activity feed while
keeping the feed administrator-only for the current release.

## 2. Actors

- **Authenticated staff member:** Reviews and revokes their own sessions and may
  sign out every session after confirming the current password.
- **Authenticated administrator:** Has the same personal controls and may also
  read the administrator security audit feed.
- **Unauthenticated visitor:** Has no access to session or audit data.

## 3. Data Model

- `AuthSession` stores the session identifier, owner, creation time, last-seen
  time, expiry, revocation state, bounded user-agent text, and hashed client IP.
- `SecurityAuditEvent` stores event type, outcome, actor/target references,
  request ID, bounded user-agent text, hashed client IP, and creation time.
- Refresh tokens are not returned by session or audit endpoints.

## 4. Current Implementation

The web Account Center links to `/admin/security`. The security screen provides:

- active signed-in device cards
- current-device labeling
- browser/platform summaries derived from the user-agent
- technical user-agent details behind an expandable disclosure
- explicit confirmation before revoking another session
- password-confirmed sign-out everywhere
- an administrator-only security activity feed

The audit feed can be filtered by account, event type, outcome, and date range.
Routine refresh and bridge telemetry records are grouped in the unfiltered
view so account-changing activity remains scannable; explicit event filters can
be used when those categories need investigation.

The backend provides:

- `GET /auth/sessions`
- `DELETE /auth/sessions/{session_id}`
- `POST /auth/logout-all`
- `GET /security/audit-events` for administrators only

The current UI does not expose a revoke button for the current session, though
the authenticated API scopes session deletion to the caller's own sessions and
does not add a separate current-session prohibition.

## 5. States

```text
active session ──user revokes──> revoked session
active session ──logout-all──> revoked session
active session ──expiry──> expired session
```

Only active, non-revoked sessions are returned by the session list. The current
session is marked with `current: true`.

## 6. Business Rules

- **BR-SEC-001:** A user may read only sessions belonging to that user.
- **BR-SEC-002:** A user may revoke only a session belonging to that user.
- **BR-SEC-003:** Revoke actions require explicit UI confirmation.
- **BR-SEC-004:** Sign-out everywhere requires the current password and revokes
  all active sessions for the user.
- **BR-SEC-005:** Sign-out everywhere also increments the user's token version,
  invalidating access tokens issued before the operation.
- **BR-SEC-006:** The security audit feed is administrator-only. Staff users do
  not receive a personal or global audit feed in the current release.
- **BR-SEC-007:** Audit pagination is newest-first and uses an optional `before_id`
  cursor with a bounded limit of 1–100 records.
- **BR-SEC-008:** Raw refresh tokens, setup tokens, passwords, and raw client IP
  addresses are never returned by these endpoints.
- **BR-SEC-009:** Routine refresh events may be present in the backend audit
  response but are grouped by the administrator UI rather than shown as
  individual meaningful activity items.

## 7. Main Workflows

### Review devices

1. The user opens `/admin/security`.
2. The client requests `/auth/sessions`.
3. The backend verifies the current session and returns the caller's active
   sessions.
4. The UI identifies the current device and presents other devices with revoke
   actions.

### Revoke a device

1. The user selects Revoke access for another device.
2. The UI opens a confirmation dialog.
3. After confirmation, the client sends `DELETE /auth/sessions/{session_id}`.
4. The backend verifies ownership, marks the session revoked, records an audit
   event, and returns no content.
5. The UI refreshes the active-session list.

### Sign out everywhere

1. The user opens the sign-out-everywhere form.
2. The UI asks for the current password only after the user expresses intent.
3. The client submits `POST /auth/logout-all`.
4. The backend verifies the password, increments the token version, revokes all
   sessions, records the event, and clears the refresh cookie.
5. The client clears its access token and broadcasts sign-out to other tabs.

### Review administrator activity

1. An administrator opens the security screen.
2. The client requests the newest audit events in bounded pages.
3. The UI renders meaningful events and summarizes routine refreshes.
4. The administrator may load older pages using the `before_id` cursor.

## 8. Edge Cases

- A session ID belonging to another user returns `404` rather than exposing
  whether another account owns it.
- Revoking a session immediately prevents it from refreshing or using its access
  token.
- A wrong sign-out-everywhere password leaves sessions unchanged.
- A staff user receiving `403` from the audit endpoint must not see audit data in
  the UI.
- Missing or stale user-agent text falls back to a generic device description.
- No active sessions produces an explicit empty state.
- Audit events with unknown event types use a readable fallback label.

## 9. UI Behavior

- Account Center shows Security for staff and administrators.
- Account Center shows Staff & roles only to administrators.
- The security page exposes readable device summaries and keeps the raw
  user-agent behind Technical details.
- Revoke and sign-out-everywhere actions require explicit confirmation.
- The audit feed is rendered only when the current user is an administrator.

## 10. Backend Behavior

| Method | Route | Access | Purpose |
|---|---|---|---|
| GET | `/auth/sessions` | Authenticated caller | List active sessions owned by the caller |
| DELETE | `/auth/sessions/{session_id}` | Authenticated caller | Revoke a caller-owned session |
| POST | `/auth/logout-all` | Authenticated caller | Password-confirmed global revocation |
| GET | `/security/audit-events` | Administrator | Read bounded security audit history |

The backend remains authoritative even when the web UI hides an action.

## 11. Security / Permissions

- Session metadata is visible only to the session owner.
- Security audit history is administrator-only by explicit product decision.
- Session and audit responses omit token hashes, passwords, and IP hashes.
- Revocation is enforced in `get_current_user` and refresh-session validation.

## 12. History / Audit

Session revocation and sign-out-everywhere actions are recorded with actor,
target session where applicable, outcome, request ID, and timestamp. Audit
records are retained for up to 180 days under the current cleanup behavior.

## 13. Acceptance Criteria

- Staff and administrators can see only their own active sessions.
- A revoked session cannot refresh or use an existing access token.
- Sign-out everywhere requires the correct current password and ends all active
  sessions.
- Staff receive `403` for the security audit endpoint.
- Administrators can page through audit events and see meaningful activity while
  routine refreshes are grouped in the UI.
- Security UI tests cover ownership, confirmation, role visibility, and error
  states.

## 14. Open Decisions

- Whether the API should explicitly reject deletion of the current session rather
  than relying on the UI to omit that action.
- Whether production audit retention should remain 180 days.
- Whether a future release should expose a staff member's own activity feed.

## 15. Deferred Scope

- Email or push notifications for unfamiliar sign-ins.
- IP reputation, geolocation, or device trust scoring.
- Staff-facing personal audit history.
- MFA, SSO, and recovery-code management.
