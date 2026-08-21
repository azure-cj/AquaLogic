# Species Compatibility

Last reviewed: 2026-08-21
Status: Notes-only; pairwise compatibility deferred

## 1. Purpose

Capture human-authored compatibility guidance without presenting an unsupported
automated compatibility score or stocking recommendation.

## 2. Current Implementation

`FishSpecies.compatibility_notes` is a nullable free-text field maintained by
administrators and shown in authenticated species details. It is descriptive
reference information only. It does not generate a compatibility status, alter
tank assignments, or affect Species Care suitability.

## 3. Approved Behavior

- Compatibility notes may describe temperament, predation risk, schooling,
  territorial behavior, size, or tank-space considerations.
- Notes are not parsed into structured rules.
- Notes do not prevent staff from assigning a species to a tank.
- Notes do not create alerts or notifications.
- Pairwise results are not shown as Compatible, Caution, Not Recommended, or
  Insufficient Information in the current product.

## 4. Visibility

Compatibility notes are part of the authenticated staff profile today. The
active reduced public species projection omits compatibility notes, preferred
ranges, assignment metadata, and suitability metadata.

## 5. Deferred Scope

- Pairwise compatibility scoring.
- Structured temperament, predation, schooling, territorial, or space models.
- Tank stocking calculations.
- Compatibility-based assignment blocking.
- Breeding compatibility and breeding management.
