#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
sign_script="${ORBIS_TEST_SIGN_SCRIPT:-${project_root}/scripts/sign-orbis-macos.sh}"
artifact_root="${HOME}/.codex/artifacts/research/orbis-signing-tests"
mkdir -p "$artifact_root"
fixture_root="$(mktemp -d "${artifact_root}/unsigned-intel.XXXXXX")"
trap 'rm -r "$fixture_root"' EXIT
app_path="${fixture_root}/Orbis.app"
mkdir -p "${app_path}/Contents/MacOS" "${app_path}/Contents/Frameworks"

cat > "${fixture_root}/library.c" <<'C'
int fixture_value(void) { return 0; }
C
cat > "${fixture_root}/main.c" <<'C'
extern int fixture_value(void);
int main(void) { return fixture_value(); }
C
cat > "${app_path}/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.dnexus.orbis.signing-test</string>
<key>CFBundleExecutable</key><string>Orbis</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
</dict></plist>
PLIST

# Intel libraries may arrive unsigned. Signing the app executable before its
# dependencies must not prevent distribution of this valid bundle.
xcrun clang -arch x86_64 -dynamiclib "${fixture_root}/library.c" \
  -install_name @rpath/libOrbisSigningFixture.dylib \
  -o "${app_path}/Contents/Frameworks/libOrbisSigningFixture.dylib"
xcrun clang -arch x86_64 "${fixture_root}/main.c" \
  -L "${app_path}/Contents/Frameworks" -lOrbisSigningFixture \
  -Wl,-rpath,@executable_path/../Frameworks -o "${app_path}/Contents/MacOS/Orbis"
if codesign --display "${app_path}/Contents/Frameworks/libOrbisSigningFixture.dylib" 2>/dev/null; then
  codesign --remove-signature "${app_path}/Contents/Frameworks/libOrbisSigningFixture.dylib"
fi
ORBIS_MACOS_SIGNING_IDENTITY=- "$sign_script" "$app_path"
codesign --verify --deep --strict "$app_path"
# A configured identity persists without affecting an explicit ad-hoc override.
printf '%s\n' - > "$fixture_root/identity"
ORBIS_MACOS_SIGNING_IDENTITY= ORBIS_MACOS_SIGNING_IDENTITY_FILE="$fixture_root/identity" "$sign_script" "$app_path"
printf '%s\n' 'missing-orbis-signing-test-identity' > "$fixture_root/identity"
if ORBIS_MACOS_SIGNING_IDENTITY= ORBIS_MACOS_SIGNING_IDENTITY_FILE="$fixture_root/identity" \
    "$sign_script" "$app_path" > "$fixture_root/missing-identity.log" 2>&1; then
  printf '%s\n' 'A missing configured identity must fail instead of changing the app identity.' >&2
  exit 1
fi
ORBIS_MACOS_SIGNING_IDENTITY=- ORBIS_MACOS_SIGNING_IDENTITY_FILE="$fixture_root/identity" "$sign_script" "$app_path"
codesign --verify --deep --strict "$app_path"
printf '%s\n' 'PASS: dependencies, persistent identity, and explicit ad-hoc override'
