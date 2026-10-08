# Tank Console — Display and Control modes

Last reviewed: 2026-10-08. Branch `feat/console-display-mode`. Builds on
[Phase 2B](TANK_CONSOLE_PHASE_2B.md); firmware, gateway, backend and web are
unchanged. Physical validation on the mounted tablet is pending (checklist below).

## Target device

Samsung Galaxy Tab A 8.0 (2019), model SM-T290: 1280×800 px at default density
213, about **960×600 logical pixels** in landscape. Layout is reviewed at that
size with `test/console_capture_test.dart`:

```powershell
$env:AQUALOGIC_CONSOLE_CAPTURE = "<output folder>"
flutter test test/console_capture_test.dart
```

It writes Display mode, Control mode and the Lighting, Feeder and Pump A panels
as PNGs. Without the variable the test only checks for layout exceptions.

## Modes

| | Display mode (default) | Control mode |
|---|---|---|
| Purpose | Read the tank from across the room | Staff operate equipment at arm's length |
| Shows | Large readings, water-quality banner, one-line equipment summary | Smaller readings, banner, five control tiles, settings |
| Enter | Starts here; idle timeout; tap **Lock** | Hold the lock chip about 0.9 s |
| Touches | Any tap shows "Hold the lock to use controls"; nothing is sent | Normal |

Control mode returns to Display mode after **60 seconds** without a touch. It
never relocks while a panel is open or a command is still pending; the timer
restarts once that clears.

The lock prevents accidental touches (wiping the glass, leaning on the tank).
It is **not** an authorization boundary: there is no PIN, and the Console has
no user identity. Staff-only placement is the access control.

## Tiles

| Tile | Tap | Other |
|---|---|---|
| Lighting, UV | Toggles once. Shows "Turning on…/off…" until the device confirms; the new state is never shown early. | "⋯" opens the panel. |
| Feeder | Shows "Hold for 1 second to feed". | Hold 1 s (bottom fill) feeds once; releasing early sends nothing. "⋯" opens the panel. |
| Pump A/B | Opens the panel. Dispense, retract and refill keep their confirmation dialogs. | — |

A failed, rejected or unknown outcome turns the tile amber with the outcome as
its caption, and stays until that tile's panel is opened. While flagged, a tap
opens the panel instead of acting. An unconfirmed equipment state or an
unavailable command also routes to the panel, which explains why.

## Panels

Every panel follows: current state → control → last command → details.

- **Lighting / UV:** Off/On switch; the lit side moves only on device confirmation.
- **Feeder:** Hold to feed. Device reports: feed count, last fed, portion
  (angle and duration) and the three schedule slots. Portion and schedule are
  read-only here and edited in the web app.
- **Pumps:** status, syringe volume gauge, dose, next eligible, clock, and the
  device-reported dose count, last dose, next scheduled dose and schedule event.

Device-reported values come from `/feeder/status` and `/syringe*/status`, which
the firmware already returns. Blank or missing values show "Not reported"; a
schedule is shown only when all three slots are valid.

There is no Console command history. Each panel shows its last command, and
device reports cover what the hardware did regardless of who triggered it. The
web app keeps the full backend history.

## Physical checklist (mounted tablet)

Install the release APK (`mobile_app/build/app/outputs/flutter-apk/app-release.apk`)
over the existing app, open More → Tank Console with the live ESP32 connected.
Use water or empty syringes only for pump steps. Send one photo per step.

1. **Display size:** Settings → Display → Screen zoom and font size at default.
2. **Display mode from about 2 m:** readings, banner and equipment line readable.
3. **Accidental touch:** tap the readings while locked. Hint appears; nothing changes.
4. **Unlock:** hold the lock chip. Tiles appear; release early once first to confirm it stays locked.
5. **Lighting tap:** tile shows "Turning off…", then "Off" only after the light actually changes. Tap again to restore.
6. **Feeder:** tap once (nothing happens), then hold 1 s. One feed cycle; feed count and last fed update in the panel.
7. **Feeder panel:** schedule and portion match the web app.
8. **Pump A panel:** values shown; open Retract or Refill confirmation and cancel. Do not dose unless supervised.
9. **Idle relock:** leave it untouched for 60 s. It returns to Display mode.
10. **Enclosure fit:** footer and tile bottoms fully visible inside the cutout.

Record results in the table below.

| Step | Result | Notes |
|---|---|---|
| 1–10 | Pending | |
