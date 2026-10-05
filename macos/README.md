# macOS application

This directory contains the native AppKit Orbis client for macOS 15 and later.

`scripts/build-orbis-macos.sh` is the supported entry point. Set
`ORBIS_MACOS_ARCH` to `arm64`, `x86_64`, or `universal`. Release pipelines should
call the same script. GitHub releases use a local ad-hoc code signature and a
free Sparkle Ed25519 signature for update verification. A stable Apple signing
identity can be supplied with `ORBIS_MACOS_SIGNING_IDENTITY` or the local
`~/.config/orbis/macos-signing-identity` file. See the update guide for Keychain
continuity across local builds.

See [the update guide](../docs/macos-updates.md) for the release workflow,
signing key setup, and updater-enabled source builds.

About Orbis includes an offline copy of [the changelog](../CHANGELOG.md).
Add user-visible changes under `Unreleased`, and move them into a versioned
section when preparing a release. The application displays that section as
`Latest changes`. Use second-level headings for releases, third-level headings
for change categories, and one-line bullet entries; the About view formats those
elements for reading.

## Virtual displays

Each connection starts with one display. Open **Settings** beside **New connection**
to choose an automatic or manual initial resolution for each display. Drag either
monitor in the arrangement diagram to match your Mac screens, including staggered
alignment. The primary display has a white menu bar. Arrow keys place the second
display on a side; Shift + arrows adjust alignment. Settings apply to all
connections when a new session starts. Existing connection-specific display
options migrate once; subsequent connections use the global settings. Manual dimensions
are pixels, from 200 to 8192, with an even width. Automatic sizing uses the local
screen's dimensions in points, preserving the existing default.

The **Session → Add Virtual Display** menu action requests a second remote
monitor using the same RDP session. The second window opens after the server
confirms the combined desktop size; move it to another Mac screen or use native
fullscreen. Window resizing scales the image without changing its saved remote
resolution. Closing the second window requests monitor removal and keeps the
primary session open; the window disappears when removal is confirmed.

In windowed mode, the native macOS title bar keeps the close, minimize, and
fullscreen controls above the remote desktop. Automatic resolution sizing uses
the content area below the title bar.

The action requires the server's Display Control channel and support for at least
two monitors. Advertised monitor area limits are checked before sending a layout.
A ten-second resize deadline reports unsupported changes and requests the previous
layout again. No physical monitor is needed on a server that supports virtual
remote displays. Live server validation is still required for this implementation.

Pointer drags remain in the same remote session when crossing between the two
Orbis windows, including native fullscreen windows on separate Mac screens.
The captured drag uses the output under the cursor, preserving the button press
until its release in either window. Match the saved monitor arrangement to the
Mac screens for a continuous transition between adjacent remote displays.

During a connected session, **Window → Resolution** changes the focused remote
window's resolution without reconnecting. The submenu identifies Display 1 or
Display 2, shows its current dimensions, and marks the active preset. Common
presets range from 1280 × 720 to 3840 × 2160; **Match Mac Screen** uses the screen
containing that window. With two remote displays, the other display's resolution
and the current arrangement are retained. These changes last for the current
session; Settings continues to define initial resolutions for future connections.

Resolution choices require the server's Display Control channel and stay disabled
while a layout request is pending or a non-remote window is focused. Presets that
exceed the advertised monitor area are disabled. The current resolution changes
only after the server restarts its graphics pipeline or confirms a desktop resize;
a timeout requests the previous layout and leaves the session open. See
[Microsoft's Display Control overview](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-rdpedisp/bdc90b21-4b14-43bc-9c03-b7fecbfc6a1f)
for the server response sequence.

**Window → Resolution → Automatically Match Window** keeps the focused remote
display at its window's content size, including native fullscreen on another Mac
monitor. Automatic initial sizing enables this mode when a session starts.
Choosing a fixed resolution disables it for that display. Each remote display
has its own mode. Resize events are coalesced after the drag ends, and a size
change received while the server is responding is applied after confirmation.
Requests respect the same server limits as manual changes and retain the other
remote display's resolution and arrangement.
