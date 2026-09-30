#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
set -euo pipefail

arm_app="${1:?Usage: merge-orbis-macos.sh ARM_APP INTEL_APP OUTPUT_APP}"
intel_app="${2:?Missing Intel app}"
output_app="${3:?Missing output app}"
[[ ! -e "$output_app" ]] || { printf 'Output app already exists: %s\n' "$output_app" >&2; exit 1; }
cmp "${arm_app}/Contents/Info.plist" "${intel_app}/Contents/Info.plist"
ditto "$arm_app" "$output_app"

# Sparkle is already universal. Merge only the Orbis and FreeRDP/OpenSSL binaries.
while IFS= read -r -d '' binary; do
  relative="${binary#"${arm_app}/"}"
  chmod u+w "${output_app}/${relative}"
  lipo -create "$binary" "${intel_app}/${relative}" -output "${output_app}/${relative}"
done < <(find "${arm_app}/Contents/MacOS" "${arm_app}/Contents/Frameworks" \
  -path '*/Sparkle.framework' -prune -o -type f \
  \( -path '*/MacOS/*' -o -name '*.dylib' \) -print0)

while IFS= read -r -d '' binary; do
  if file -b "$binary" | grep -q 'Mach-O'; then
    lipo "$binary" -verify_arch arm64 x86_64
    if otool -L "$binary" | awk 'NR > 1 { print $1 }' | grep -Eq '^/(opt/homebrew|usr/local)/'; then
      printf 'Build-machine dependency in %s\n' "$binary" >&2
      exit 1
    fi
  fi
done < <(find "${output_app}/Contents" -type f -print0)
