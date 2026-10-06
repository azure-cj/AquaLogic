# Firmware contract fixtures

Synthetic representative responses from root `esp32` at commit `248c698`,
Git blob `df25c0b22407b303ed410b1d975b0e5c0da92a20`. Keys and types match
the six status handlers. Both LED and UV intentionally emit `led_on`.
Three schedule entries are included. These are not physical recordings.
Failure tests mutate these responses; those mutations are not new contracts.

Phase 2B adds `commands.json` containing the 13 enabled actions' exact HTTP 200
JSON bodies. Rejection fixtures in socket tests match dispense/refill handler
409/503 branches. Syringe capacities in responses.json are corrected to the
source's 5 mL; earlier 10 mL examples were not a configurable firmware contract.

Socket tests use real HTTP on an ephemeral loopback server. Only a test-only
HttpClient connection factory redirects the validated private test destination
to that server. Production validation remains unchanged. These tests require
no hardware, LAN interface or port 80 and do not verify Android networking,
mDNS resolution, or the flashed firmware.
