# macOS application

This directory contains the native AppKit Orbis client for macOS 15 and later.

`scripts/build-orbis-macos.sh` is the supported entry point. Set
`ORBIS_MACOS_ARCH` to `arm64`, `x86_64`, or `universal`. Release pipelines should
call the same script and replace the local ad-hoc signature with the appropriate
Apple distribution identity.
