# Repository layout

Orbis has two native applications over one pinned RDP engine. The dependency
direction is intentionally one-way:

```text
ipados  ─┐
              ├──> shared
macos  ──┘

ipados  ───> patched client/iOS ───> vendor/freerdp
macos   ───> patched client/Mac ───> vendor/freerdp
```

`ipados` and `macos` own product UI and platform session orchestration. `shared` owns only
stable cross-platform application concepts. The native FreeRDP adapters are
owned by upstream and customised through one versioned patch. The pristine,
pinned engine lives in `vendor/freerdp`; prepared sources live only under
`.build/vendor` and never alter the submodule.

## Build and release seams

The scripts below are the public automation interface:

- `scripts/build-orbis-simulator.sh`: iPad simulator development build.
- `scripts/build-orbis-device.sh`: signed or compile-only iPad device build.
- `scripts/build-orbis-macos.sh`: thin or universal native Mac build.
- `scripts/prepare-freerdp.sh`: materialises and patches the pinned dependency.

Future CI should call these entry points rather than reimplementing their CMake
and Xcode options. Signing, notarisation, TestFlight upload, and App Store upload
are release concerns layered after a successful build. Secrets and signing
credentials must stay in the CI provider or Apple Keychain, never in the
repository.

## Sharing rule

Move code to `shared` only after both applications need the same behaviour and
can consume the same interface. A platform-specific implementation behind a
small shared contract is preferable to conditional UI or input logic in the
shared layer.
