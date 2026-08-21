# Authentication

## Status

**Current behavior reverse-specification** — reviewed 2026-08-21.

This document records the authentication behavior already implemented in the
FastAPI backend and React web client. It is not approval for new authentication
features.

## Implementation checkpoint — 2026-08-21

The Phase 06 authentication hardening is implemented and regression-tested. The
current release covers active-user checks, forced-password-change gating,
rotating refresh sessions, setup-link expiry/replacement/replay protection,
login throttling, cookie/security-header behavior, and session invalidation on
password and account lifecycle changes. The web Account Center also presents
the current role capability summary through an accessible popover; this is an
explanation layer only and does not change authorization.

Relevant implementation and coverage are in
[`backend/app/routes/auth.py`](../../../backend/app/routes/auth.py),
[`web/src/features/auth/AccountCenterPage.tsx`](../../../web/src/features/auth/AccountCenterPage.tsx),
and [`backend/tests/test_security_hardening.py`](../../../backend/tests/test_security_hardening.py).

## 1. Purpose

Provide secure staff and administrator sign-in, short-lived browser access,
revocable long-lived sessions, and administrator-mediated account setup and
password reset.

## 2. Related Requirements

- Staff authentication and password-change flow.
- Backend-enforced authorization for staff and administrator operations.
- Local-first operation with no browser persistence of authentication material.

## 3. Actors

- **Unauthenticated visitor:** May submit login, refresh a cookie-backed session,
  or consume a one-time setup link.
- **Authenticated staff member:** May use staff routes after completing a
  required password change.
- **Authenticated administrator:** May use staff routes and administrator-only
  routes after completing a required password change.
- **Invited or reset user:** Has an active account but must set a new password
  before accessing staff resources.

The public tank experience and device-key bridge are separate trust boundaries;
they do not use staff passwords or browser JWTs.

## 4. Data Model

- `User`: normalized email, password hash, role, activation state,
  `must_change_password`, token version, password-change timestamp, and audit
  relationships.
- `AuthSession`: one browser/device session with expiry, revocation state,
  hashed client IP, user-agent summary, authentication method, and last-seen
  timestamp.
- `RefreshToken`: SHA-256 hash of one opaque rotating refresh token, linked to a
  session and carrying consumed/replaced/expiry state.
- `AccountSetupToken`: SHA-256 hash of a one-time invite or reset token with a
  30-minute expiry.
- `AuthThrottle`: database-backed account and IP failure counters.
- `SecurityAuditEvent`: append-only security event metadata. Raw passwords,
  refresh tokens, setup tokens, and raw client IP addresses are not stored.

## 5. States

### Account state

```text
active + password ready ──password reset/setup──> active + password change required
active + password change required ──successful change──> active + password ready
active ──administrator deactivation──> inactive
inactive ──administrator activation──> active
```

### Session state

```text
created/active ──logout or revocation──> revoked
created/active ──expiry──> expired
created/active ──password change/reset/logout-all──> revoked
```

### Refresh token state

```text
unconsumed ──refresh──> consumed and replaced
unconsumed ──expiry──> invalid
consumed token replay outside the short grace window ──> session revoked
```

### Setup token state

```text
issued ──successful setup──> consumed
issued ──30-minute expiry──> invalid
issued ──replacement setup/reset link──> consumed
```

## 6. Business Rules

- **BR-001:** Login normalizes email by trimming whitespace and lowercasing it.
- **BR-002:** Only an existing, active user with a valid password may create a
  session. Invalid credentials use the same public error regardless of whether
  the email exists.
- **BR-003:** Passwords are stored using the current Argon2id password library.
  Legacy PBKDF2 hashes may be verified once and upgraded after successful login.
- **BR-004:** Access JWTs expire after 15 minutes and include subject, session,
  token-version, issuer, audience, issued-at, expiry, unique ID, and
  authentication-method claims.
- **BR-005:** The web client keeps the access token in module memory only. The
  seven-day refresh token is opaque, stored only as a hash, and delivered in a
  `HttpOnly`, `SameSite=Strict` cookie. The cookie is secure in production.
- **BR-006:** Every authenticated request checks the JWT, user activation state,
  user token version, linked session, session revocation, and session expiry.
- **BR-007:** Refresh rotates the token. A replayed consumed token is tolerated
  only inside the short implementation grace window; replay outside that window
  revokes the session and clears the refresh cookie.
- **BR-008:** Password changes, administrator password resets, setup completion,
  and sign-out-everywhere increment the user token version and revoke existing
  sessions before creating the replacement session where applicable.
- **BR-009:** A user who must change password may authenticate and use the
  password-change flow, but protected staff resources return `403` until the
  change is complete.
- **BR-010:** Setup links are fragment URLs so the raw token is not sent in the
  initial page request. The token is single-use, expires after 30 minutes, and is
  stored server-side only as a hash.
- **BR-011:** Login failures are throttled per account and per client IP using
  database state. The current limits are five failures per account and twenty
  failures per IP within a 15-minute window.
- **BR-012:** Logout revokes the current session and clears refresh cookies. The
  browser also clears its in-memory access token and broadcasts sign-out to other
  tabs.

## 7. Main Workflows

### Login

1. Client submits email and password to `POST /auth/login`.
2. Backend checks throttles, verifies the password, and rejects inactive users.
3. Backend creates an `AuthSession`, refresh token record, and access JWT.
4. Backend records a security audit event and returns the access token plus user
   summary and password-change flag.
5. The web client routes password-change-required users to the change-password
   screen; other users enter the staff application.

### Refresh

1. Client submits the HttpOnly refresh cookie to `POST /auth/refresh`.
2. Backend validates the linked session and rotates the refresh token.
3. Backend returns a new access JWT and replacement cookie when rotation occurs.
4. The web client performs one single-flight refresh and retries the failed
   authenticated request once.

### Password setup or change

- `POST /auth/setup-password` consumes an invite/reset token and creates a new
  authenticated session.
- `POST /auth/change-password` verifies the current password, rejects reuse of
  the current password, revokes existing sessions, and creates a new session.

### Session termination

- `POST /auth/logout` revokes the current session.
- `POST /auth/logout-all` requires the current password, increments the token
  version, revokes every active session, and clears the current refresh cookie.
- `GET /auth/sessions` lists the caller's active sessions.
- `DELETE /auth/sessions/{session_id}` revokes a session owned by the caller.

## 8. Edge Cases

- Missing, malformed, expired, legacy, or token-version-mismatched JWTs return
  `401`.
- Inactive users cannot refresh or use existing access tokens.
- An expired, consumed, or replaced setup token returns `400`.
- Incorrect current passwords return `400` for password change and sign-out
  everywhere.
- A setup or new password shorter than 12 characters is rejected by schema
  validation.
- Refresh failure clears both the current and legacy refresh-cookie paths.
- A stopped API must not leave the web client indefinitely waiting for a session
  check; the client uses a ten-second request timeout.

## 9. UI Behavior

- `/admin/login` provides email/password sign-in and password visibility control.
- `/admin/setup-password` reads the fragment token once, removes it from the
  visible URL, and provides the account activation form.
- `/admin/change-password` is the forced-password-change route.
- Access tokens are never placed in local storage, session storage, or the
  non-sensitive theme preference.
- Refresh failure clears React Query data and broadcasts sign-out across tabs.

## 10. Backend Behavior

Authentication routes:

| Method | Route | Access | Purpose |
|---|---|---|---|
| POST | `/auth/login` | Public | Create a session from valid credentials |
| POST | `/auth/refresh` | Refresh cookie | Rotate a refresh session |
| POST | `/auth/logout` | Authenticated | Revoke the current session |
| POST | `/auth/logout-all` | Authenticated | Revoke every session after password confirmation |
| GET | `/auth/me` | Authenticated | Return the current user |
| POST | `/auth/change-password` | Authenticated | Change the current password |
| POST | `/auth/setup-password` | Setup token | Activate or reset an account |
| GET | `/auth/sessions` | Authenticated | List the caller's active sessions |
| DELETE | `/auth/sessions/{session_id}` | Authenticated | Revoke a caller-owned session |

`require_staff` and `require_admin` add role and completed-password checks on
protected routes. `GET /auth/me` remains available while a forced password
change is pending so the web shell can route the user correctly.

## 11. Security / Permissions

- Staff and administrators use the same authentication mechanism; role checks
  happen after authentication and are enforced by the backend.
- Customer accounts, self-service email recovery, MFA, SSO, and social login are
  not implemented.
- Device ingestion uses a separate fixed device key boundary and never accepts
  browser JWTs or staff credentials.

## 12. History / Audit

The backend records successful and failed login, refresh, logout, password,
session, user-management, and related security events. Audit records retain
hashed IP metadata and bounded user-agent text. Records older than 180 days are
removed during audit-event writes. The administrator security screen groups
routine refresh events so meaningful account changes remain readable.

## 13. Acceptance Criteria

- Valid active users can log in and receive a claim-complete short-lived access
  token plus a secure refresh cookie.
- Invalid credentials do not reveal whether an email exists.
- Access tokens fail after session revocation, account deactivation, token-version
  change, or expiry.
- Refresh rotation rejects replay outside the grace window and revokes the
  affected session.
- Setup links are one-time, hashed at rest, and expire after 30 minutes.
- Forced-password-change users cannot access staff resources until completion.
- Password changes and administrator resets invalidate previous sessions.
- Authentication tests cover staff/admin behavior, throttling, cookie flags,
  replay, setup links, and session ownership.

## 14. Open Decisions

- Whether to add self-service password recovery, MFA, or SSO in a future phase.
- Whether the refresh grace window should remain fixed or become configurable.
- Whether security audit retention should remain 180 days for production.

## 15. Deferred Scope

- Email delivery of setup or recovery links.
- Customer authentication.
- MFA, SSO, social login, passwordless login, and device trust scoring.
- Mobile authentication until the Flutter client is reconciled with the API.
