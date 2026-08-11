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

CTest registration lives in `tests/CMakeLists.txt`. Application builds continue
to use the platform scripts and the pinned FreeRDP source tree.
