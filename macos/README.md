# macOS application

This directory contains the native AppKit Orbis client for macOS 15 and later.

`scripts/build-orbis-macos.sh` is the supported entry point. Set
`ORBIS_MACOS_ARCH` to `arm64`, `x86_64`, or `universal`. Release pipelines should
call the same script. GitHub releases use a local ad-hoc code signature and a
free Sparkle Ed25519 signature for update verification. An Apple distribution
identity can optionally be supplied with `ORBIS_MACOS_SIGNING_IDENTITY`.

See [the update guide](../docs/macos-updates.md) for the release workflow,
signing key setup, and updater-enabled source builds.

About Orbis includes an offline copy of [the changelog](../CHANGELOG.md).
Add user-visible changes under `Unreleased`, and move them into a versioned
section when preparing a release. The application displays that section as
`Latest changes`. Use second-level headings for releases, third-level headings
for change categories, and one-line bullet entries; the About view formats those
elements for reading.

## Virtual displays

Each connection starts with one display. In the connection editor's Options,
choose an automatic or manual initial resolution for each display and place the
second display to the right, left, above, or below the primary. Manual dimensions
are pixels, from 200 to 8192, with an even width. Automatic sizing uses the local
screen's dimensions in points, preserving the existing default.

The **Session → Add Virtual Display** menu action requests a second remote
monitor using the same RDP session. The second window opens after the server
confirms the combined desktop size; move it to another Mac screen or use native
fullscreen. Window resizing scales the image without changing its saved remote
resolution. Closing the second window requests monitor removal and keeps the
primary session open; the window disappears when removal is confirmed.

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
