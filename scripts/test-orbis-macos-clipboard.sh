#!/usr/bin/env bash
# SPDX-License-Identifier: MIT

set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
freerdp_source_dir="$("$project_root/scripts/prepare-freerdp.sh")"
clipboard="$freerdp_source_dir/client/Mac/Clipboard.m"
build_script="$project_root/scripts/build-orbis-macos.sh"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

response_body="$(sed -n \
  '/^mac_cliprdr_server_format_data_response/,/^static UINT$/p' "$clipboard")"
[[ -n "$response_body" ]] || fail 'the macOS clipboard response callback was not found'

failure_body="$(awk '
  /formatDataResponse->common.msgFlags & CB_RESPONSE_FAIL/ { capture = 1 }
  capture { print }
  capture && /^\t}/ { exit }
' <<<"$response_body")"

grep -Fq 'SetEvent(mfc->clipboardRequestEvent)' <<<"$failure_body" || \
  fail 'a rejected clipboard response does not wake the waiting request'
grep -Fq 'return CHANNEL_RC_OK;' <<<"$failure_body" || \
  fail 'a normal clipboard-data rejection is still treated as a fatal channel error'

rg --fixed-strings --quiet -- 'cmake --build "$build_dir" --target clean' "$build_script" || \
  fail 'the macOS package can retain a stale ThinLTO FreeRDP framework'
rg --fixed-strings --quiet -- \
  'cmake --build "$build_dir" --target OrbisMac --parallel || return 1' "$build_script" || \
  fail 'a failed native build can still be packaged as if it had succeeded'
rg --fixed-strings --quiet -- \
  'cmake -E remove_directory "${artifact_dir}/Orbis.app"' "$build_script" || \
  fail 'the macOS artifact is merged with a stale app bundle instead of replaced'

printf 'PASS: Orbis macOS clipboard rejection contract\n'
