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

The icon-only Settings action beside New connection stores global display defaults
for all computers on this iPad. Automatic resolution follows the native viewport,
including rotation and window resizing. A preset or custom resolution remains
fixed; Match iPad Resolution in the session menu enables automatic sizing for
that session.
Manual dimensions must be 200–8192 pixels, with an even width.

Linux display scale defaults to 100%, with 125%, 150%, 175%, and 200% options.
New connections request this remote desktop scale through RDP. The server decides
whether to apply it to text and applications; local pinch zoom and image fitting
remain independent. Settings changes apply on the next connection. The iPad uses
one remote display.
