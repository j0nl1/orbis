#!/usr/bin/env bash
# SPDX-License-Identifier: MIT

set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
expected_freerdp_commit="5370fb26fbf034ecd11d3026b6ad639b5fff493f"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

for flattened_path in client channels libfreerdp winpr packaging ci; do
  [[ ! -e "$project_root/$flattened_path" ]] ||
    fail "$flattened_path leaked out of the FreeRDP submodule"
done

gitlink_mode="$(git -C "$project_root" ls-files --stage vendor/freerdp | awk '{ print $1 }')"
[[ "$gitlink_mode" == "160000" ]] || fail 'vendor/freerdp is not a Git submodule'

actual_commit="$(git -C "$project_root/vendor/freerdp" rev-parse HEAD)"
[[ "$actual_commit" == "$expected_freerdp_commit" ]] ||
  fail "FreeRDP is pinned to $actual_commit instead of $expected_freerdp_commit"

git -C "$project_root/vendor/freerdp" diff --quiet || fail 'the FreeRDP submodule is dirty'

prepared_source="$("$project_root/scripts/prepare-freerdp.sh")"
[[ -f "$prepared_source/client/Mac/MRDPView.m" ]] || fail 'the Mac adapter was not prepared'
[[ -f "$prepared_source/client/iOS/CMakeLists.txt" ]] || fail 'the iOS adapter was not prepared'
[[ -L "$prepared_source/macos" && -L "$prepared_source/ipados" && -L "$prepared_source/shared" ]] ||
  fail 'Orbis sources are not linked into the prepared FreeRDP tree'

printf '%s\n' 'Orbis repository layout checks passed.'
