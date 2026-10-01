# Changelog

## Unreleased

### Added
- An offline changelog in About Orbis, alongside open-source acknowledgements.
- Standard macOS editing shortcuts in connection forms, including Command-V for Cloudflare Access tokens and passwords.

### Improved
- A simpler connections toolbar with a labeled New connection action.
- A compact connection status icon beside the computer name.
- Vertically centered text in connection fields, including passwords and service tokens.
- Grouped connection and account fields, with Save and Cancel always visible.
- Tunnel URL entry, connection editor dismissal, and return to the library after disconnecting.
- Option-key text input and remote keyboard shortcut handling.
- Automatic signed macOS releases after changes reach main.

### Fixed
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
