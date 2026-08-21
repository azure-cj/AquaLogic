# Species Care Profiles

Last reviewed: 2026-08-21
Status: Current behavior; public projection hardening implemented

## 1. Purpose

Maintain the species identity and care information used by authenticated staff
and by derived Species Care guidance. A species profile is reference data; it is
not an operational alert or a stocking recommendation engine.

## 2. Related Requirements

- FR-11 Species Care Information
- FR-12 Searchable and Filterable Species Data
- FR-13 Species Suitability Guidance

## 3. Current Implementation

The authenticated species directory supports grouped species profiles, preferred
water ranges, diet information, care notes, hosted or locally uploaded images,
assigned-tank summaries, tank-usage counts, search, filters, and details views.

The database retains a nullable legacy `ideal_do_min` field. Dissolved oxygen is
not an active bridge or user-facing care workflow and is excluded from the
implemented Phase 03 suitability evaluation.

## 4. Actors

- Staff: view species profiles and assign or remove species from tanks.
- Administrator: create, edit, delete, and upload or replace species images.
- Public visitor: public tank views receive the customer-safe species projection
  described below.

## 5. Data Model

`FishSpecies` contains:

- common name and scientific name;
- care group (`category`);
- hosted or local photo URL;
- description;
- diet details and categorical diet type;
- care tips and free-text compatibility notes;
- preferred temperature, pH, and TDS minimum/maximum values;
- creation timestamp.

`TankFish` links a species to a tank through a composite key and records the
assignment timestamp. Assigned-tank summaries are authenticated management
metadata, not public profile data.

## 6. States

- Complete profile: identity is present and at least one care detail or range is
  configured.
- Partial profile: identity exists but care ranges or written guidance are
  missing.
- Assigned: the species has one or more tank links.
- Unassigned: the species has no tank links.

There is no separate active/inactive species state in the current model.

## 7. Business Rules

- Common and scientific names are required.
- Preferred temperature, pH, and TDS ranges may be one-sided.
- Preferred-range endpoints are inclusive; equal minimum and maximum values are
  valid.
- A minimum greater than its maximum is rejected on create and effective update.
- Missing ranges are valid profile data and are surfaced as unavailable by
  Species Care rather than treated as an operational failure.
- A species assigned to any tank cannot be deleted until all assignments are
  removed.
- Species preferences are separate from global operational alert thresholds.

## 8. Main Workflows

1. An administrator creates or edits a species profile.
2. The directory validates preferred ranges and saves the profile.
3. An administrator may upload a JPG, PNG, or WebP image after the profile
   exists; a hosted HTTPS image URL remains supported.
4. Staff review the profile and assignment count from the species directory or
   tank workspace.
5. Assigned species participate in derived Species Care evaluation against the
   tank's latest supported reading.

## 9. Edge Cases

- One-sided ranges produce “at least” or “at most” guidance.
- Equal range endpoints represent a single acceptable value.
- Missing preference data produces an unavailable check, not a false Suitable
  result.
- Legacy invalid ranges are treated as unavailable by the suitability service.
- Uploaded images are validated by content type and file signature; raw file
  paths and credentials are never exposed.

## 10. UI Behavior

The authenticated Fish species workspace provides grouped and compact views,
search and care-group/diet/usage filters, profile details, preferred-range
editing, image preview/upload, assigned-tank summaries, and confirmation-gated
deletion. Staff see read and assignment-related actions; administrator-only
profile mutations remain hidden and backend-protected for staff.

## 11. Backend Behavior

Authenticated `GET /fish` and `GET /fish/{fish_id}` return the management
profile and safe assigned-tank summaries. Administrator create, update, image
upload, and delete operations are audit logged. Assignment endpoints remain
under the tank resource and are protected by staff authorization.

## 12. Security / Permissions

- Public visitors do not access authenticated species-management routes.
- Staff may read profiles and manage tank assignments.
- Only administrators may mutate species profiles, upload images, or delete
  species.
- A species deletion is rejected while any tank assignment exists.

## 13. History / Audit

Species create, update, image-upload, and delete operations are audit logged.
Tank species assignment and removal are audit logged. There is no dedicated
assignment-history page or endpoint in this phase.

## 14. Public Projection

The public `GET /public/tanks/{public_id}` response contains only:

- common name;
- scientific name;
- photo;
- care group;
- description;
- diet details;
- care tips.

It omits the internal numeric species ID, preferred ranges, `ideal_do_min`,
compatibility notes, tank counts, assigned tanks, and suitability metadata.
This reduced projection is active in the backend and web client. Nullable fields
are omitted when no value is available.

## 15. Deferred Scope

- Pairwise compatibility scoring and stocking recommendations.
- Dissolved-oxygen and ammonia care workflows.
- Species activation/archive states.
- Versioned or curated reference-data import.
- Dedicated assignment-history management.
