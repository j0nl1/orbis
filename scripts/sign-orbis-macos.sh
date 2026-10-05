#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
set -euo pipefail

app_path="${1:?Usage: sign-orbis-macos.sh APP_PATH}"
identity="${ORBIS_MACOS_SIGNING_IDENTITY:-}"
# Keep a local signing identity across rebuilds without committing certificates
# or configuring unrelated applications. An invalid configured identity fails
# signing instead of silently falling back to a new ad-hoc identity.
identity_file="${ORBIS_MACOS_SIGNING_IDENTITY_FILE:-${HOME}/.config/orbis/macos-signing-identity}"
if [[ -z "$identity" && -f "$identity_file" ]]; then
  IFS= read -r identity < "$identity_file" || [[ -n "$identity" ]]
  if [[ -z "$identity" ]]; then
    printf 'The Orbis macOS signing identity file is empty: %s\n' "$identity_file" >&2
    exit 1
  fi
fi
identity="${identity:--}"
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
