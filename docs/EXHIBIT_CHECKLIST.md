# Exhibit checklist (October 13, 2026)

Short version of the [Exhibit runbook](WORKFLOWS.md#exhibit-runbook). All
times in UTC; Philippine time (PHT) is UTC+8.

## 1. Enable the exhibit writer — Oct 8 to Oct 11

The deadline may be at most 7 days ahead, so do this **after Oct 8, 08:00 PHT**.

On the Railway backend service, set these variables, then redeploy:

```text
DEMO_EXHIBIT_DATE=2026-10-13
EXHIBIT_DEMO_UNTIL=2026-10-14T23:59:00Z
DEMO_SENSOR_ENABLED=true
DEMO_SENSOR_INSTANCE=true
```

Only one instance may have `DEMO_SENSOR_INSTANCE=true`.

## 2. Seed the showcase tanks — right after step 1, by Oct 12

Open a shell on the Railway backend service (for example `railway ssh`), then
from `backend/`:

```bash
python -m app.cli.exhibit_demo status
python -m app.cli.exhibit_demo seed --days 10
python -m app.cli.exhibit_demo status
```

Seed **after** the writer is running, so live readings continue the seeded
history without a gap. The second `status` should list seven `SHOW-*` tanks
with latest readings a few seconds old.

## 3. Check — the day before

Open the web app, Analytics → Tank insights. Confirm:

- the showcase tanks have fresh readings;
- one of the warming tanks shows "may reach the upper warning bound";
- "Showcase · Variable pH" shows "More variable than usual" (from Oct 12 PHT afternoon);
- "Showcase · Species Range Conflict" shows the Discus/Corydoras conflict.

Decide whether push notifications stay on: live showcase alerts push to staff phones.

## 4. Exhibit day — Oct 13

- Power on the real tank and bridge **as early as possible** and leave them on.
  The real tank gets its own trends/projections after about 6 hours.
- Demo flow: real tank live → its honest "not enough data" state → showcase
  tanks with full insights → "How is this calculated?" → Dashboard "Needs attention".

## 5. After the exhibit — Oct 15 or later

1. Remove `DEMO_SENSOR_ENABLED`, `DEMO_SENSOR_INSTANCE`, `EXHIBIT_DEMO_UNTIL`,
   `DEMO_EXHIBIT_DATE` on Railway and redeploy.
2. From `backend/`: `python -m app.cli.exhibit_demo cleanup`.

The writer stops by itself at the deadline, and a restart with leftover
variables does not take the API down.
