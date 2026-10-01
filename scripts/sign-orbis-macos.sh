#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
set -euo pipefail

app_path="${1:?Usage: sign-orbis-macos.sh APP_PATH}"
identity="${ORBIS_MACOS_SIGNING_IDENTITY:--}"
options=(--force --sign "$identity")
if [[ "$identity" != - ]]; then
  options+=(--options runtime --timestamp)
fi

# Sign frameworks and helpers before the app. Signing the bundle signs its
# main executable last; signing it first can fail on unsigned Intel libraries.
# Sparkle's helpers retain their original entitlements when re-signed.
while IFS= read -r -d '' binary; do
  if file -b "$binary" | grep -q 'Mach-O'; then
    codesign "${options[@]}" --preserve-metadata=entitlements "$binary"
  fi
done < <(find "${app_path}/Contents/Frameworks" -type f -print0)
while IFS= read -r -d '' bundle; do
  codesign "${options[@]}" --preserve-metadata=entitlements "$bundle"
done < <(find "${app_path}/Contents" -depth -type d \
  \( -name '*.app' -o -name '*.xpc' -o -name '*.framework' \) -print0)
codesign "${options[@]}" "$app_path"
codesign --verify --deep --strict "$app_path"
