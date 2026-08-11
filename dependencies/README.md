# Dependency policy

Orbis pins FreeRDP 3.28.0 as the `vendor/freerdp` Git submodule. The submodule
always remains an unmodified upstream checkout. `scripts/prepare-freerdp.sh`
creates an ignored build copy and applies `patches/freerdp/orbis-apple.patch`
there, keeping Orbis integration changes reviewable and upgrades reproducible.
OpenSSL and the iPad codec libraries are resolved by the platform build scripts.

This directory records dependency ownership and is reserved for future package
manifests that are specific to Orbis. Do not duplicate third-party source here.
All release artifacts must bundle their runtime library
closure and must not depend on Homebrew paths from the build machine.
