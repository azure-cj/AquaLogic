# AquaLogic Operations Documentation

This area contains procedures and boundaries used to operate or validate the
local-first system. It is not a replacement for the canonical architecture,
API, domain, or development-status documents.

- [`hardware/`](hardware/): hardware contract, bridge integration notes, and
  safe local sensor/actuator testing.
- [`../WORKFLOWS.md#documentation-validation`](../WORKFLOWS.md#documentation-validation):
  Markdown-link and documentation cleanup checks.
- [`../WORKFLOWS.md`](../WORKFLOWS.md): database, browser, deployment, tank
  lifecycle, and device-movement workflows.

Physical validation remains subject to the safety limits and manual checks in
the hardware runbook. Software tests cannot prove physical command timing,
dispense volume, or emergency-stop behavior.
