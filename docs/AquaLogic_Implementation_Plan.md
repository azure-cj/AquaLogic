## Plan: AquaLogic Software Implementation

Build AquaLogic as a software-first system that delivers value before hardware integration arrives. The first release should include a FastAPI backend, a Flutter staff app, a React customer web app, a shared database, mock sensor data, a rule-based decision engine, and the scheduling and alert workflows needed for day-to-day operations at JRed Aquatics. Hardware integration with ESP32 and Raspberry Pi is treated as a later extension point and should not block the software core.

**Steps**
1. Lock the scope and system boundaries.
   - Confirm the first delivery includes backend API, staff app, customer web app, authentication, fish information management, alerts, schedules, mock sensors, and live updates.
   - Confirm the first delivery excludes live hardware integration, cloud hosting, customer accounts, and e-commerce.
   - Freeze the stack assumptions so all three clients use the same API contract and data model.
   - Document the non-goals and later-phase hardware handoff expectations before implementation begins.
2. Define the shared architecture and data contract.
   - Establish the canonical domain model for tanks, fish species, tank-fish assignments, sensor readings, alerts, users, schedules, and automation state.
   - Define the API contract for staff endpoints, public tank endpoints, sensor ingestion, alert resolution, and scheduling.
   - Decide how the real-time feed will work for the staff app and whether the customer page needs any live updates or only snapshot reads.
   - Set conventions for authentication, error handling, naming, and pagination so the backend remains stable for both clients.
3. Build the backend foundation first because every client depends on it.
   - Create the FastAPI project structure and application entry point.
   - Add the database layer, ORM models, and migration workflow.
   - Implement the core CRUD endpoints for fish species, tanks, assignments, and staff users.
   - Add JWT-based staff authentication and authorization guards for protected endpoints.
   - Add read-only public endpoints for QR-accessed customer tank pages.
4. Add the rule-based decision engine and alert lifecycle.
   - Implement threshold checks for temperature, pH, turbidity, dissolved oxygen, TDS, and ammonia.
   - Add logic for warning and critical severities based on safe ranges.
   - Prevent duplicate unresolved alerts for the same tank and parameter.
   - Store alert history so staff can review past incidents and resolution timing.
   - Expose alert resolution endpoints for staff use.
5. Add the mock sensor pipeline and real-time delivery path.
   - Create a mock sensor generator that posts realistic readings on a schedule.
   - Make the generator produce mostly safe readings with occasional spikes for test coverage.
   - Add the live update mechanism that the staff app can subscribe to for current tank data.
   - Verify the mock pipeline can drive both alert generation and dashboard updates without manual input.
6. Deliver the React customer web app on top of stable public endpoints.
   - Build the QR-accessible tank page with mobile-first presentation.
   - Show tank name, location, current status, fish species cards, and care guidance.
   - Keep the customer view read-only and free of staff-only controls.
   - Optimize for fast load, simple navigation, and readability on small screens.
7. Deliver the Flutter staff app in a staged sequence.
   - First implement login, token storage, tank overview, and tank detail with live sensor display.
   - Then add alerts, alert resolution, and tank health status indicators.
   - After that add fish management, search, add/edit forms, and tank assignment workflows.
   - Finish with manual control stubs and schedule management for feeding, lighting, and water regulation.
8. Harden the system and prepare for deployment readiness.
   - Seed sample tanks and fish species so the system can be demonstrated end to end.
   - Run functional checks for authentication, CRUD, public pages, alert generation, and alert resolution.
   - Validate responsive behavior on the customer web app and mobile usability on the Flutter app.
   - Document how the software will later accept ESP32 and Raspberry Pi integration without major refactoring.
   - Prepare a release checklist for the first internal demo and a separate checklist for the hardware phase.

**Dependencies**

**Parallel Workstreams**

**Relevant files**

**Verification**
1. Validate backend behavior with endpoint-level tests for auth, tank CRUD, fish CRUD, sensor ingestion, public tank reads, alert generation, and alert resolution.
2. Verify the mock sensor generator can produce realistic data and reliably trigger both safe-state and alert-state scenarios.
3. Confirm the customer web page renders correctly on a phone-sized viewport and does not require authentication.
4. Exercise the Flutter app through login, tank browsing, live readings, alerts, fish management, and schedule workflows.
5. Confirm the end-to-end system works with seeded data before any hardware dependency is introduced.
6. Run a final integration check that the public web app and the staff app both consume the same backend data consistently.

**Decisions**

**Risks and Controls**

**Milestone View**
1. Foundation: backend, database, auth, and domain model.
2. Intelligence: decision engine, alerts, mock sensor feed, live updates.
3. Public experience: customer tank page and QR flow.
4. Staff experience: Flutter login, monitoring, alerts, fish management, and schedules.
5. Stabilization: seed data, integration testing, responsive checks, and hardware handoff documentation.

**Further Considerations**
1. Decide whether the first software demo should show staff operations first or the customer QR page first. Recommendation: demo staff monitoring first because it proves the core system value faster.
2. Decide whether schedules should be tank-specific only in the first release. Recommendation: keep them tank-specific until the data model is proven.
3. Decide how much of the later hardware interface should be stubbed now. Recommendation: document the interface contract now and avoid building unnecessary hardware adapters yet.
