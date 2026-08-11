# Orbis

Orbis is a native iPadOS 26 and macOS RDP client based on FreeRDP 3.28.0. It is
designed for direct connections to GNOME Remote Login and avoids the RDP
server-redirection interoperability problem observed with Windows App.

The application identifier is `com.dnexus.orbis`.

## Connections

Orbis stores any number of connection profiles. Each profile contains:

- A display name.
- An IPv4 address, local hostname, or DNS name.
- An RDP port and username.
- An optional `Accept all certificates` policy.
- An optional `Connect automatically` policy.

Only one profile can connect automatically. When no profile has that option,
Orbis opens its connection cards and waits for the user to choose one. A new
installation starts empty and does not create a sample connection.

Connections are shown as cards on the main screen. Their status stays beside the
connection identity, and both the card header and its chevron expand or collapse
the connection controls. Technical details stay behind the `Details` action.
Password management is part of `Edit`, so no separate password action is needed.
Expanded cards present Connect, Edit, Details, and Delete as a centered row of
circular iPadOS glass controls. Connect uses the system teal accent as the primary
action; destructive actions remain red.

Orbis requests the native iPad viewport resolution so text and application chrome
remain crisp. Pinch-to-zoom is available as a temporary visual zoom when needed.

Passwords are stored separately per profile in the iPad Keychain. They are not
stored in user defaults, source files, build output, or documentation. Changing
or deleting a profile also removes its corresponding Keychain item. A password
can be saved while creating a profile. When editing a profile with a saved
password, the field shows masked asterisks; selecting its pencil explicitly opens
a replacement field. Saving without selecting that action preserves the existing
password.

`Accept all certificates` suppresses certificate verification only for the
profile where it is enabled. Leave it disabled for public or otherwise untrusted
networks. Automatic acceptance is session-only. With the option disabled, Orbis
discards legacy per-host certificate exceptions before connecting, and an
untrusted certificate requires an explicit `Connect Once` confirmation every
time. Certificates that are already valid through the system trust chain do not
need a warning.

## Remote access through Cloudflare

RDP is a raw TCP protocol, so Cloudflare Access HTTP service-token headers cannot
be attached directly to an RDP connection. The recommended iPad architecture is:

1. Publish the private network through Cloudflare Tunnel.
2. Enrol the iPad in Cloudflare One and connect with WARP.
3. Enter the private hostname or IP address in the Orbis profile.

Orbis then uses an ordinary RDP connection over the authenticated private-network
route. No Cloudflare credentials need to be stored in Orbis. A future macOS
client may additionally support a local `cloudflared access rdp` helper, but that
model is not available to a normal sandboxed iPad application.

References:

- [Cloudflare Tunnel setup](https://developers.cloudflare.com/tunnel/setup/)
- [Private networks with Cloudflare Tunnel](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/private-net/)

## Keyboard behaviour

Physical keyboard shortcuts translate common Mac conventions for the remote
Linux desktop:

| iPad keyboard | Remote desktop |
| --- | --- |
| Command+A/C/F/L/N/P/R/S/T/V/W/X/Z | Control+A/C/F/L/N/P/R/S/T/V/W/X/Z |
| Command+Backspace | Forward Delete |

The Command key itself is not sent as the Windows/Super key. Other physical keys
continue through FreeRDP's normal hardware-keyboard path.

## Prerequisites

- A Mac with Xcode and the Xcode command-line tools.
- CMake and Ninja.
- For a real iPad: an Apple ID configured in Xcode, a development team, a
  trusted USB connection, and Developer Mode enabled on the iPad.

Clone the repository with `--recurse-submodules`, or initialise an existing
checkout with `git submodule update --init` before building.

All third-party source versions are pinned by FreeRDP 3.28.0. The build embeds
the complete runtime library closure in `Orbis.app`; it does not depend on
Homebrew or build-directory libraries at runtime.

## Simulator build

```sh
scripts/build-orbis-simulator.sh
```

The script produces `.build/ipados/simulator/Debug-iphonesimulator/Orbis.app`. To select
a particular simulator, provide an Xcode destination:

```sh
ORBIS_SIMULATOR_DESTINATION='platform=iOS Simulator,name=iPad Pro 13-inch (M5),OS=26.2' \
  scripts/build-orbis-simulator.sh
```

To open the profile picker during UI testing instead of auto-connecting, launch
the simulator app with `ORBIS_DISABLE_AUTOCONNECT=1`.

## Device build and installation

To build for a connected iPad and let Xcode register it in the provisioning
profile, pass the Apple Developer team and device UDID explicitly:

```sh
APPLE_DEVELOPMENT_TEAM=YOUR_TEAM_ID \
  ORBIS_DEVICE_UDID=YOUR_IPAD_UDID \
  scripts/build-orbis-device.sh
```

Install the resulting app with CoreDevice:

```sh
xcrun devicectl device install app \
  --device YOUR_CORE_DEVICE_ID \
  .build/ipados/device/Release-iphoneos/Orbis.app
```

For a compile-only ARM64 device check that produces an un-installable app:

```sh
ORBIS_UNSIGNED_BUILD=1 scripts/build-orbis-device.sh
```

Never pass an RDP password through a build variable or commit it to this
repository.

## macOS build

Orbis for macOS uses AppKit and the native FreeRDP macOS adapter. It does not
launch or require Thincast, Karabiner-Elements, or another RDP application.
Common Command-key editing shortcuts are translated inside the session view.

Build the current host architecture:

```sh
scripts/build-orbis-macos.sh
```

Build one application that runs natively on both Intel and Apple Silicon Macs:

```sh
ORBIS_MACOS_ARCH=universal scripts/build-orbis-macos.sh
```

The universal build requires OpenSSL 3 for each architecture at the standard
Homebrew prefixes (`/opt/homebrew` for Apple Silicon and `/usr/local` for Intel).
It produces `artifacts/macos/Orbis.app`. The build verifies that Orbis, FreeRDP,
WinPR, and OpenSSL all contain both `arm64` and `x86_64` slices and that no
absolute Homebrew runtime paths remain.

Local builds are ad-hoc signed. A future distribution pipeline can replace that
last step with Developer ID or App Store signing without changing the source
layout.

To keep macOS Keychain trust stable across local updates, pass an Apple
Development identity (name or SHA-1 hash):

```sh
ORBIS_MACOS_ARCH=universal \
  ORBIS_MACOS_SIGNING_IDENTITY=YOUR_CODESIGN_IDENTITY \
  scripts/build-orbis-macos.sh
```

## Repository layout

The Orbis-specific code is organised by ownership rather than by build system:

- `ipados`: UIKit application, iPad resources, and touch/session UI.
- `macos`: AppKit application, Mac resources, and native session UI.
- `shared`: platform-neutral connection profiles and Keychain-backed credential
  storage shared by both applications.
- `dependencies`: dependency and packaging policy; third-party source remains in
  the pinned FreeRDP submodule and the reviewed Orbis adapter patch.
- `scripts`: stable local build entry points intended to become CI jobs later.

See `docs/architecture/repository-layout.md` for the dependency boundaries.

## Artwork

- iPad application icon: `ipados/Resources/OrbisIcon.png`
- macOS application icon: `macos/Resources/OrbisMacIcon.png`
