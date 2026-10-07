# Testing Orbis

Orbis uses CTest as its test runner. Objective-C behavior is exercised with
XCTest, while small platform-independent policies are compiled as ordinary C
test executables. This keeps the fast suite independent from the much larger
FreeRDP build.

Run everything from the repository root:

```sh
scripts/test-orbis.sh
```

The script configures `.build/tests`, builds the test targets, and runs CTest
with failed output enabled. Additional CTest arguments are passed through:

```sh
scripts/test-orbis.sh -L unit
scripts/test-orbis.sh -L xctest
scripts/test-orbis.sh -R session-end
scripts/test-orbis.sh --repeat until-fail:20
```

## Test layers

| Label | Purpose |
| --- | --- |
| `unit`, `pure-c` | Deterministic policies with no UI or I/O |
| `unit`, `xctest`, `shared` | Shared profile and acknowledgement behavior |
| `integration`, `xctest`, `appkit` | Native AppKit view hierarchy and layout |
| `integration`, `repository` | Submodule pinning and prepared-source layout |
| `contract`, `legacy-source-check` | Temporary source-level regression checks |

The source-level contract scripts predate the native runner. They remain useful
while behavior is still embedded inside the FreeRDP adapters, but they are not
the target architecture. Replace each script when the behavior gains a small
Orbis-owned interface and an executable test. Do not add new assertions to the
legacy category when a behavior test is possible.

## Adding tests

- Put pure policy tests beside their owning macOS, iPadOS, or shared module.
- Test observable results through the module interface rather than matching its
  implementation text.
- Use XCTest for Foundation, AppKit, UIKit, and asynchronous Apple-platform
  behavior.
- Keep shell tests for repository layout, signing, architecture, and packaged
  artifact checks.
- Keep live RDP tests separate from the default suite because they require a
  reachable server, credentials, and a graphical login session.

## Native keyboard input

Run `scripts/test-orbis-macos-keyboard-input.sh` on a Mac to exercise AppKit
keyboard events through the actual patched FreeRDP view. The script builds the
native runtime first, then enables the `integration.macos-keyboard-input` test
using `ORBIS_TEST_FREERDP_BUILD_DIR`. Only the outgoing RDP input functions are
replaced with a recorder; the event handlers and modifier state run unchanged.
The test covers Option symbols, Shift+Option symbols, repeats, key release
ordering, Alt+Tab, and Command+C. It needs no remote server or credentials.

This test is optional in the default suite because it requires the full FreeRDP
build. Once enabled in a test build directory, subsequent CTest runs include it.

CTest registration lives in `tests/CMakeLists.txt`. Application builds continue
to use the platform scripts and the pinned FreeRDP source tree.

## iPadOS simulator tests

Run `scripts/test-orbis-ipados.sh` on macOS with an available iPad simulator.
The script builds the full iPad application and an optional app-hosted XCTest
bundle, then runs it through Xcode. `ORBIS_SIMULATOR_DESTINATION` selects a
specific simulator; `ORBIS_BUILD_DIR` selects the simulator build directory. XCTest result bundles are saved outside the repository
under `~/.codex/artifacts/reports/orbis-ipados`; set
`ORBIS_IPADOS_TEST_RESULT_PATH` to choose another result path.

The suite exercises the actual UIKit profile editor and patched session adapter.
It checks direct profiles, tunnel URL validation, hostname-bound credential
preservation, logical RDP identity, asynchronous preparation, cancellation,
transport errors, and the bundled changelog. Hardware-keyboard tests replace
only the outgoing session input boundary, covering Command shortcuts,
Option-Backspace, Option symbols, and Alt+Tab without a live remote desktop.
Shared shortcut tests cover empty defaults, exact modifier matching, platform
separation, persistence, invalid preferences, and duplicate rejection. Native
input tests exercise explicitly configured workspace and screenshot chords,
repeat suppression, late releases, and held modifier restoration.

Display-control tests cover both capability/viewport arrival orders, simultaneous
callers, failed sends, pending sizes, and channel replacement. Session recovery
tests retain native error snapshots and exercise the actual connection controller,
Retry presentation, one-attempt limit, timer cancellation, missing credentials,
and ambiguous remote logoff codes. These deterministic checks do not reproduce
GNOME's intermittent PipeWire buffer failure; physical connection trials are
needed to establish whether coordinated resize requests reduce that failure.

Availability tests use local TCP fixtures to exercise fragmented RDP negotiation,
non-RDP services on open ports, protocol rejection, direct and prepared transport
destinations, timeouts, and cancellation. Library tests cover status after
disconnecting, rechecking availability, and suspending checks while inactive.

These tests are separate from the default macOS CTest suite because they require
the full iPadOS dependency build and an installed simulator runtime.

## macOS virtual display tests

Build the native runtime with `scripts/build-orbis-macos.sh`, then configure the
native test build with
`-DORBIS_TEST_FREERDP_BUILD_DIR=$PWD/.build/macos/arm64` (use `x86_64` on Intel).
This enables the existing keyboard boundary tests and
`integration.macos-virtual-display`. The display test uses the real session
controller and windows with a captured Display Control channel and simulated
framebuffer resize notifications, without opening a remote connection.

Coverage includes all four arrangements, unequal resolutions, signed monitor
positions, normalized framebuffer regions, adding/removing windows, server monitor
and area limits, and rollback on timeout. AppKit input tests exercise a secondary
view's keyboard, pointer coordinates, and cropped rendering. Captured pointer
sequences also cross between both real AppKit output views in either direction
for all four arrangements, checking one button press, movement
on the destination monitor, and one release. Native menu tests cover availability
and dispatch of Add Virtual Display. Editor and profile
tests cover manual dimensions, validation, automatic defaults, copying, and
persistence. These fixtures do not establish server interoperability; validate
adding and closing a second display against a live remote login before release.

## macOS clipboard and microphone tests

With `ORBIS_TEST_FREERDP_BUILD_DIR` configured, `integration.macos-clipboard`
exercises concurrent multi-megabyte text copies through the real pasteboard
observer, RDP callbacks, and WinPR clipboard storage. Only the OS pasteboard is
replaced, so the test leaves the user's clipboard intact. It checks complete
remote text, main-thread publication, suppressed echo, and rejected responses.

`integration.macos-microphone` exercises the patched native capture adapter with
simulated macOS authorization and audio queues. It checks default-off negotiation
without permission or hardware access, mono/stereo PCM, invalid formats, live
capture start/stop, and blocked forwarding after mute without recording audio.
Native settings/menu tests cover the shared preference, Save/Cancel behavior,
scrollable settings, and permission completion after capture is disabled. Live server tests are
needed to verify playback and microphone availability in remote applications.
