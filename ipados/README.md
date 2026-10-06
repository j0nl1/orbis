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
remote Alt+Tab. Plain Delete/Backspace removes the previous character.
Command-Delete/Backspace sends Shift-Home followed by Backspace to delete to the
start of the line in editors that support those keys. Shift-Delete/Backspace sends
normal Forward Delete without remote Shift, allowing selected files to be moved
to the trash where supported by the remote file manager. These two translated
shortcuts trigger once per press, consume repeats/releases, and restore held
physical Shift keys. Native Forward Delete remains unchanged. Terminal and other
applications with different Home/selection bindings may interpret the text
shortcut differently.

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

Settings → Keyboard shortcuts configures Activities, previous/next workspace,
remote screen capture, and remote window capture. All actions start unassigned.
Record a combination and save, or clear it to restore ordinary key forwarding.
Duplicate combinations are rejected. Custom shortcuts may override typing,
editing, or system functions; iPadOS may reserve some combinations. Each action
runs once per press, consuming repeats and late releases while restoring held
modifiers. Screenshots stay on the remote computer. Customized GNOME bindings
or other Linux desktops may behave differently.

Trackpad swipes and discrete mouse wheels always scroll the remote desktop,
including horizontal scrolling. Workspace swipe recognition and its preferences
have been removed. Three-finger system gestures remain handled by iPadOS.
Tests cover synthetic keyboard input, modifier restoration, and wheel events;
physical keyboard behavior needs device verification.

Settings → Diagnostics → Export Diagnostics shares the local JSON history, with
recent session events, numeric error codes, and available MetricKit crash or hang
reports. Disconnection records distinguish requested disconnects from unexpected
ones and include native RDP error state before teardown. Scene state and memory
warnings provide context. If the app disappears with an active session, the next
launch records an interrupted session; this alone does not confirm a crash.
Nothing is uploaded automatically. See the shared Diagnostics README for
retention, excluded data, OS report delivery, and matching debugging symbols.

Settings → Remote display → Black screen border controls an 8-point black margin
around the remote desktop. It is enabled by default and applies to new connections.
The margin helps reach remote screen edges away from iPadOS resizing corners.
Automatic resolution follows the inset viewport; manually configured resolutions
remain unchanged. The connection screen shows the computer name and a neutral
native Cancel button.

Text clipboard redirection works in both directions. Copying remotely updates the
iPad system pasteboard while Orbis is in the foreground. Command-V, Control-V (including
Control-Shift-V), or the session menu's Paste command publishes local text before
sending the remote paste shortcut. Access follows iPadOS paste permissions; the
app does not poll another app's clipboard. Transfers preserve Unicode and support
up to 8 MiB of UTF-8 text. Images, rich text, and files are not redirected.
Clipboard contents are excluded from local diagnostics.

When its scene enters the background, an active remote session requests that the
server pause display updates and asks iPadOS for limited additional execution
time. Returning restores display updates on the same connection. Expiration of
that time ends the background task without requesting a disconnect. iPadOS can
still suspend or terminate Orbis, and a server or network timeout can end the
connection; several minutes of background connectivity are not guaranteed.

After an established session, the remote server's disconnect/logout signals return
to the library without a Retry dialog. Explicit transport, graphics, wait, and
connection-start failures retain recovery. FreeRDP may synthesize LOGOFF_BY_USER
from a server disconnect message; this does not prove which server action caused
the close. Orbis records a remote-close event and raw native codes without labeling
it as a local Disconnect click. Server failures reported only through that generic
logout signal also return quietly and remain available in diagnostics.
