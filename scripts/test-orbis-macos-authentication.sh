#!/usr/bin/env bash
# SPDX-License-Identifier: MIT

set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
freerdp_source_dir="$("$project_root/scripts/prepare-freerdp.sh")"
adapter="$freerdp_source_dir/client/Mac/MRDPView.m"
build_script="$project_root/scripts/build-orbis-macos.sh"
session_controller="$project_root/macos/Sources/OrbisSessionController.m"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

authentication_body="$(sed -n \
  '/^static BOOL mac_authenticate_raw/,/^BOOL mac_authenticate_ex/p' "$adapter")"

grep -Fq 'if (!*username && !pinOnly)' <<<"$authentication_body" || \
  fail 'the Mac NLA callback does not require a username'

grep -Fq 'else if (!*password)' <<<"$authentication_body" || \
  fail 'the Mac NLA callback does not require a password'

if grep -Fq '!*domain' <<<"$authentication_body"; then
  fail 'the Mac NLA callback incorrectly requires a domain for local accounts'
fi

grep -Fq -- '-DWITH_INTERNAL_MD4=ON' "$build_script" || \
  fail 'the macOS build does not bundle the MD4 implementation required by NTLM'

grep -Fq -- '-DWITH_INTERNAL_RC4=ON' "$build_script" || \
  fail 'the macOS build does not bundle the RC4 implementation required by NTLM'

grep -Fq 'width -= width % 2;' "$session_controller" || \
  fail 'the requested RDP desktop width is not normalised for GNOME Remote Desktop'

printf 'PASS: Orbis macOS authentication contract\n'
