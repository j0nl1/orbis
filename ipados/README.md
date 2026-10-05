# iPadOS application

This directory owns the Orbis iPadOS 26 product surface: UIKit controllers,
iPad-specific resources, touch input, and the Metal-backed Remote Desktop view.

The pristine FreeRDP iOS adapter lives in `vendor/freerdp/client/iOS`. The build
applies the reviewed Orbis adapter patch only to an ignored copy under `.build`.
Shared profile and credential APIs live under `shared`.

Build through `scripts/build-orbis-simulator.sh` or
`scripts/build-orbis-device.sh`; do not invoke dependency builds independently.

The connection editor offers Direct RDP and Cloudflare Access service-token
connections. RDP passwords and hostname-bound Access tokens use separate Keychain
items. Session transport preparation is asynchronous, cancellation closes the
prepared session, and transport or authentication failures return to the library
with an explanatory alert.

Library indicators show service availability rather than session state. Checks
run when the library returns to the foreground and every 30 seconds while it is
visible. Each check uses the configured direct or Cloudflare transport, waits up
to eight seconds for an RDP negotiation response, and closes its socket and
tunnel without logging in. Account authentication and certificate validation
still happen when connecting. Checks stop when leaving the library or when the
app becomes inactive; an unavailable result does not disable Connect.

About Orbis includes the bundled offline changelog. Hardware keyboards translate
Command editing shortcuts, Option-Backspace, and Option symbols while preserving
remote Alt+Tab.

Run `scripts/test-orbis-ipados.sh` on a Mac for app-hosted XCTest coverage in an
available iPad simulator. Set `ORBIS_SIMULATOR_DESTINATION` to select a specific
simulator. Tests use synthetic input and transports; live RDP servers and service
tokens are not required.
