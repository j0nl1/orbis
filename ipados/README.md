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

Suggested resolutions are generated from the current iPad window's pixel size,
with smaller alternatives preserving its proportions within pixel rounding.
Suggestions update when the window rotates or resizes; the Settings sheet's own
size does not determine them. Custom dimensions remain available. Settings changes
apply on the next connection. Legacy desktop scale preferences are ignored and
removed on the next save. The iPad uses one remote display.

Orbis keeps the iPad display awake while a remote connection is starting or active
in the foreground. Automatic screen lock is restored when the session ends, the
connection fails, or the app becomes inactive. Returning to an ongoing session
keeps the display awake again. Connection availability checks do not prevent
screen lock.

Trackpad workspace gestures are enabled by default for new connections and can be
disabled in Settings. Swipe two fingers left or right without clicking to switch
workspaces; hold Alt (Option) and swipe up to open Activities. Alt + Shift with a
sideways swipe moves the active window to the neighboring workspace. The adapter
sends GNOME's Super + Page Up/Down, Super, and Super + Shift + Page Up/Down shortcuts.
GNOME's dynamic workspace behavior creates an additional empty workspace when a
window moves into the final empty workspace; Orbis does not create workspaces
through RDP. Customized shortcuts or other Linux desktops may behave differently.

Each continuous swipe selects one direction and triggers at most one action.
Ordinary vertical scrolling and discrete mouse wheels remain remote scrolling;
disabling the option restores horizontal trackpad scrolling. Alt and physical
Shift states are preserved around the generated shortcut. Three-finger trackpad
system gestures remain handled by iPadOS. Tests cover synthetic gesture sequences
and resulting RDP key events; physical trackpad behavior needs device verification.
