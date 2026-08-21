# Public Tank Pages

Last reviewed: 2026-08-21
Status: Implemented privacy-safe public tank view and timestamp wording

## 1. Purpose

Provide a read-only, customer-safe tank page that can be opened from a public
identifier or QR link without exposing internal operations data.

## 2. Related Requirements

- FR-15 Public Tank Pages
- FR-04 Water Quality Monitoring
- FR-11 Species Care Information
- NFR-04 Data Protection

## 3. Current Implementation

The public backend route is:

```text
GET /public/tanks/{public_id}
```

It returns only tanks with `is_public` enabled. The web route is
`/tank/:publicId` and requires no staff authentication. The page polls the
public endpoint every 30 seconds and provides loading, unavailable, sharing,
and responsive states.

## 4. Public Tank Projection

The response may include:

- public identifier and tank name;
- public display location;
- public description, habitat label, water type, volume, and establishment
  date;
- approved hero image URL;
- public care notes;
- reduced public species profiles;
- latest public reading;
- public parameter statuses and overall status.

Public species entries contain only common name, scientific name, photo, care
group, description, diet details, and care tips.

Public readings contain only:

```text
timestamp
temperature
ph
turbidity
tds
```

The internal numeric tank/species IDs, tank code, private location,
feeding schedule, customer data, preferred ranges, compatibility notes,
assigned-tank metadata, suitability metadata, device identifiers, receipt
metadata, threshold configuration, and alert history are omitted.

## 5. Freshness and Status

The backend selects the latest reading by server `received_at` and evaluates
freshness using the Phase 02 90-second window. The public contract intentionally
does not expose `received_at`.

Public status uses only temperature, pH, turbidity, and TDS:

- Normal, Warning, or Critical reflects the worst usable fresh supported value.
- Missing or stale data produces Offline at the overall level.
- Missing supported values are Unavailable at the parameter level.
- Deferred dissolved oxygen and ammonia cannot affect public status.

The returned public `timestamp` is the observation timestamp. The web copy
labels it “Observed” so it is not confused with server receipt time. No public
receipt timestamp is exposed.

## 6. Public UI Behavior

The page presents:

- tank identity and public metadata;
- overall water status and current update/observation context;
- active supported water metrics;
- an explanatory Offline or unavailable state when readings are missing or
  stale;
- fish species cards with care-safe descriptions, diet, and care tips;
- public care notes and visitor-facing aquarium guidance.

It does not present operational alert messages, alert counts, threshold values,
internal species suitability results, or staff actions.

## 7. Security and Privacy Rules

- Only public tanks are returned.
- Unknown and private public identifiers return not found.
- A bearer staff token is not required and does not expand the public projection.
- Public image URLs must satisfy the configured image-host policy.
- No credentials, device keys, raw audit data, internal IDs, or private customer
  information are serialized.

## 8. Edge Cases

- A public tank with no reading still exposes approved tank and species
  information while showing unavailable metrics.
- A stale latest reading remains available as context while overall status is
  Offline.
- Missing optional care copy is omitted or replaced by safe visitor-facing copy.
- A failed request shows a generic unavailable page without revealing backend
  details.
- Deferred sensor fields remain absent from the public response and UI.

## 9. Implemented Hardening

- The public projection remains privacy-safe and separate from authenticated
  operations responses.
- The public timestamp presentation now uses “Observed” without adding receipt
  metadata to the public API.

## 10. Deferred Scope

- Public alert history, alert acknowledgements, or operational response details.
- Public live streaming or WebSocket updates.
- Public customer accounts, tank ownership, or private customer dashboards.
- Public threshold or Species Care suitability disclosure.
- External public notifications and visitor analytics.
