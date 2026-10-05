# Changelog

## Unreleased

### Added
- macOS virtual second displays in a separate window, using the existing RDP session when the server supports Display Control.
- Per-connection initial resolutions and monitor arrangement for macOS displays.
- Cloudflare Access service-token connections on iPadOS, using the shared transport adapters and separate hostname-bound Keychain credentials.
- An offline changelog in iPadOS About Orbis and a simulator XCTest suite for connection editing, transport lifecycle, and hardware keyboard input.
- An offline changelog in About Orbis, alongside open-source acknowledgements.
- Standard macOS editing shortcuts in connection forms, including Command-V for Cloudflare Access tokens and passwords.

### Improved
- iPadOS connection forms group endpoint, Access token, account, and connection options, accept tunnel HTTPS URLs, and preserve saved credentials.
- iPadOS hardware keyboards support Option-Backspace word deletion and Option symbols while retaining remote Alt+Tab.
- The iPadOS library has a labeled New connection action, and failed connections show transport or authentication details after returning to the library.
- Option-Backspace now deletes the previous word in remote Linux text fields by sending Control-Backspace.
- A simpler connections toolbar with a labeled New connection action.
- A compact connection status icon beside the computer name.
- Vertically centered text in connection fields, including passwords and service tokens.
- Grouped connection and account fields, with Save and Cancel always visible.
- Tunnel URL entry, connection editor dismissal, and return to the library after disconnecting.
- Option-key text input and remote keyboard shortcut handling.
- Automatic signed macOS releases after changes reach main.

### Fixed
- iPadOS connection indicators check RDP availability independently of session state, including after disconnecting.
- iPadOS Command-Backspace sends Forward Delete without Control, including when Command is released before Backspace.
- OpenH264 simulator builds use the simulator SDK and target consistently and remain compatible with the supported CMake version.
- GitHub release lookup in the automatic release workflow.

### Removed
- The redundant Refresh connections action.

## 2026.10.01.3

### Added
- Cloudflare Tunnel connections using Access service tokens.
- Separate Keychain storage for tunnel credentials, bound to the tunnel hostname.
- Direct and Cloudflare transport adapters that preserve the logical RDP server identity.

## 2026.10.01.2

### Fixed
- Code signing of bundled Intel dependencies before signing the application.

## 2026.10.01.1

### Added
- Signed macOS updates from GitHub Releases, with Check for Updates in the Orbis menu.
- Universal application packaging for Apple Silicon and Intel Macs.

### Fixed
- Clipboard synchronization starting after the remote connection is established.

## Initial development

### Added
- Native macOS and iPadOS Remote Desktop clients based on FreeRDP.
- Saved connection profiles, Keychain passwords, and optional automatic connection.
- Native remote display, keyboard, mouse, and clipboard integration.
