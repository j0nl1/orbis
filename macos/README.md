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

Remote audio is redirected to the Mac's default audio output during a session.
The RDP server must support audio output redirection. Playback uses the native
macOS audio backend.

Microphone sharing is off by default. Enable **Settings → Audio → Use Mac
microphone remotely** and save, or use **Session → Microphone** in the menu bar.
Both controls use the same saved preference. Changes apply to the current
session immediately and to future connections. Turning sharing off stops
capture; turning it back on does not require reconnecting.

Orbis asks for microphone access when sharing is first enabled. Denying access
leaves sharing off while the session and remote playback remain available.
Access can be changed under **System Settings → Privacy & Security → Microphone**;
then enable sharing again. The remote server must support RDP audio input and
provide an input device for remote apps such as Discord. Choose that device in
the remote desktop or app's audio settings.

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

## Keyboard modifiers

Mac editing shortcuts such as Command-C send complete remote Control chords.
A standalone Command tap sends the remote Super/Windows key. Keyboard and pointer
actions with Command consume that tap even when modifier events arrive later.
Keys forwarded while Command is held are released when Command is released or
focus cleanup runs; a missing key-up does not keep the remote key pressed, and
a delayed key-up does not release it twice.

## Mouse shortcuts

Open **Settings → Shortcuts…** to assign a middle or side mouse button to an
Orbis action, with or without Shift, Control, Option, or Command. Click the
recording field, keep the pointer over it, and press the mouse button. Primary
and secondary clicks can also be recorded when combined with a modifier.
The first ordinary click activates recording. Save applies the assignments;
Cancel leaves the saved shortcuts unchanged.

With Accessibility and Input Monitoring granted, the active recording field
captures keyboard shortcuts before macOS handles them, including combinations
reserved by the Mac. **Allow Mac shortcut capture…** requests the permissions.
Recording consumes the assigned key press and release, then releases capture.
Changing applications or windows, opening a menu, or closing the editor also
releases it. Without those permissions, ordinary local recording remains available.

If mouse software triggers a Mac action before the recording field receives the
button, use **Mouse…** beside the action. Choose the button and modifiers, click
**Assign**, then **Save**. This assigns the shortcut without physically pressing
the mapped button. Buttons 4 and 5 are commonly the side buttons. Mouse software
must still deliver a matching button event to Orbis during a remote session;
manual assignment does not override a vendor's direct Mac actions.

Mouse shortcuts work in windowed sessions and with fullscreen input capture.
Each press executes the assigned action once and consumes its drag and release,
so it does not also click the remote desktop. Matching uses the exact modifiers;
unassigned combinations retain normal mouse behavior. A key code and mouse
button with the same number are separate shortcuts. Additional mouse buttons
beyond RDP's five-button range can execute assigned actions during capture.

## Fullscreen input capture

Enable **Capture Mac input in full screen** in Settings to forward physical keys
and pointer input to the active remote desktop before macOS handles shortcuts.
This option is off by default and requires both Accessibility and Input
Monitoring in macOS Privacy & Security. Select **Allow input capture…** to
request access, enable Orbis in both categories, and reopen it if macOS asks.
Without Input Monitoring, macOS can create a filter that receives modifiers and
mouse events but no key presses. Orbis keeps capture inactive until keyboard
monitoring is available, so ordinary AppKit input handles complete chords.
Capture starts only with a connected, focused remote window in native fullscreen.
It stops when switching apps, opening a menu or sheet, leaving fullscreen, or
disconnecting, and releases held remote keys, modifiers, and mouse buttons.

Windowed and captured input share one native editing translator. AppKit resolves
Mac text keybindings into word, line, document, and selection actions; Orbis
sends complete remote editing chords. Command-Delete selects to the beginning
of the line and deletes; Command-arrows navigate line or document boundaries.
Menu shortcuts such as Command-C/V retain their remote Control mapping in both
typing modes, including Command-Shift-C/V for terminals. Right Option remains
AltGr in remote-layout mode rather than invoking native Option editing.
Left Option is deferred until a physical chord needs Alt, so native word editing
does not tap Alt and activate a remote menu before sending its editing chord.
Unknown captured Command chords use remote Super/Windows;
a standalone Command tap sends Super. Custom shortcuts take priority over the
standard editing mappings. Remote applications interpret these chords using
their own keybindings; terminal editing conventions can differ from GUI editors.

The input implementation separates the OS filter (`OrbisInputEventTap`), session
focus and routing (`OrbisInputCapture`), and native text/editing translation
(`OrbisKeyboardCompatibility`). The OS adapter verifies the effective event mask
of the specific filter it creates, rather than treating a non-null filter as
permission to capture every requested event. Editing plans use one atomic sender
for both windowed and captured input; layout composition resets when focus changes.

By default, physical keys use the remote
keyboard layout: left Option is Alt and right Option is AltGr. On a Spanish
Ubuntu desktop, right Option + 2 types `@`. ISO keyboards preserve the `<`/`>`
key beside Shift, including third-party keyboards.

Choose **Typing → Mac keyboard layout** in Settings to keep the Mac's characters
while capturing fullscreen shortcuts. This mode translates printable keys,
Option symbols, and dead-key accents using the active Mac layout; Command and
Control shortcuts still reach the remote desktop. **Remote keyboard layout**
restores physical typing with separate Alt and AltGr keys. Macros that generate
keyboard or mouse events follow this routing. Macros that directly run a Mac script, open a Mac app, or invoke a
registered system action do not become Linux commands. RDP supports the first
five mouse buttons; additional buttons can be assigned to Orbis actions in
Shortcuts, or use a macro that generates supported keyboard or mouse events. Media keys and gestures are outside this capture mode.

Press **Control + Option + Command + Esc** to release capture for the current
fullscreen focus episode. Leaving fullscreen or switching away and returning
rearms the option. If macOS disables its event filter, capture stops automatically;
input resumes locally without silently recapturing. Windowed sessions
and sessions with the option off retain their existing Mac shortcut behavior.

Orbis → Export Diagnostics saves a local JSON history of session events, numeric
error codes, display changes, and available MetricKit crash or hang reports.
Nothing is uploaded automatically. See the shared Diagnostics README for storage,
excluded data, OS report delivery, and matching debugging symbols.
