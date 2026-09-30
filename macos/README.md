# macOS application

This directory contains the native AppKit Orbis client for macOS 15 and later.

`scripts/build-orbis-macos.sh` is the supported entry point. Set
`ORBIS_MACOS_ARCH` to `arm64`, `x86_64`, or `universal`. Release pipelines should
call the same script. GitHub releases use a local ad-hoc code signature and a
free Sparkle Ed25519 signature for update verification. An Apple distribution
identity can optionally be supplied with `ORBIS_MACOS_SIGNING_IDENTITY`.

See [the update guide](../docs/macos-updates.md) for the release workflow,
signing key setup, and updater-enabled source builds.
