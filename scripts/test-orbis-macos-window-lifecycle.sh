#!/usr/bin/env bash
# SPDX-License-Identifier: MIT

set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
delegate="$project_root/macos/Sources/OrbisAppDelegate.m"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

reopen_body="$(awk '
  /^- \(BOOL\)applicationShouldHandleReopen:/ { capture = 1 }
  capture { print }
  capture && /^}/ { exit }
' "$delegate")"

[[ -n "$reopen_body" ]] || \
  fail 'the macOS app delegate does not handle a Dock/Finder reopen event'

grep -Fq '[self showLibraryWindow];' <<<"$reopen_body" || \
  fail 'reopening Orbis does not restore its library window'

rg --fixed-strings --quiet -- '[_window deminiaturize:nil];' "$delegate" || \
  fail 'the library-window presenter does not restore a minimised window'

rg --fixed-strings --quiet -- '[_window makeKeyAndOrderFront:nil];' "$delegate" || \
  fail 'the library-window presenter does not order the window onscreen'

rg --fixed-strings --quiet -- 'NSWindowCollectionBehaviorMoveToActiveSpace' "$delegate" || \
  fail 'the library window does not follow Orbis to the active macOS Space'

rg --fixed-strings --quiet -- 'NSImageNameCaution' "$delegate" || \
  fail 'macOS errors do not use the native warning artwork'

printf 'PASS: Orbis macOS window lifecycle contract\n'
