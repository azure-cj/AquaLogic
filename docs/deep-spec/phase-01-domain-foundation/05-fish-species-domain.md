# Fish Species Domain

## Status

**Current behavior; no new Phase 01 schema work approved** — reviewed 2026-08-21.

## 1. Purpose
Define the species-care information AquaLogic stores and uses operationally.

## 2. Related Requirements
- FR-11 Fish Information Management
- FR-12 Fish Search and Filtering
- FR-13 Species Suitability Guidance

## 3. Current Implementation
**Implemented**

Current species profiles visibly include:

- common name
- scientific name
- care group
- care summary
- preferred temperature range
- preferred pH range
- preferred TDS range
- diet type
- feeding details
- compatibility/care note
- care tips
- assigned tanks

Species suitability remains derived from current tank readings. The current
species model may retain a dissolved-oxygen preference for compatibility, but
that value is unavailable while dissolved oxygen is deferred from the current
hardware and user-facing workflow.

## 4. Business Rules
- BR-001: Species-care data should support tank-side suitability evaluation.
- BR-002: Missing care data must produce an unavailable/insufficient result instead of a false suitable result.
- BR-003: Deleting a species already assigned to tanks must be handled safely.
- BR-004: Species assignment uniqueness and deletion protection remain owned by
  the tank/species relationship; Phase 01 will not add fish-to-fish
  compatibility rules.

## 5. Known Gap
The current Compatibility field is descriptive care information, not yet a complete fish-to-fish compatibility engine.

## 6. Deferred Scope
- Breeding-specific management is deferred.
- Do not add breeding records, breeding pair management, or fry tracking unless later approved.
- A complete fish-to-fish compatibility engine remains deferred.
- New species fields or uniqueness constraints require a separate failing-case
  and migration review.
