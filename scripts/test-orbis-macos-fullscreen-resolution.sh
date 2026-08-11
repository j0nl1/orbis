#!/usr/bin/env bash
# SPDX-License-Identifier: MIT

set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
controller="$project_root/macos/Sources/OrbisSessionController.m"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

rg --fixed-strings --quiet -- '- (void)windowDidEnterFullScreen:' "$controller" || \
  fail 'the RDP connection is not deferred until native fullscreen is ready'

fullscreen_body="$(sed -n \
  '/^- (void)windowDidEnterFullScreen:/,/^}/p' "$controller")"
grep -Fq '[self beginConnection];' <<<"$fullscreen_body" || \
  fail 'entering fullscreen does not start the RDP negotiation'

start_body="$(sed -n '/^- (BOOL)start/,/^- (BOOL)beginConnection/p' "$controller")"
grep -Fq 'dispatch_after(' <<<"$start_body" || \
  fail 'a missed AppKit fullscreen callback can leave a permanently black window'
grep -Fq 'if (_connectionPending && !_stopping)' <<<"$start_body" || \
  fail 'the fullscreen fallback does not guard against a duplicate connection'
grep -Fq '[self beginConnection];' <<<"$start_body" || \
  fail 'the fullscreen fallback does not start the pending RDP connection'

connection_body="$(sed -n '/^- (BOOL)beginConnection/,/^- (void)handleConnectionResult:/p' "$controller")"
grep -Fq 'NSRect contentBounds = [[_window contentView] bounds];' <<<"$connection_body" || \
  fail 'the requested desktop size is not taken from the final fullscreen content bounds'
grep -Fq 'freerdp_client_start(context)' <<<"$connection_body" || \
  fail 'the deferred connection method does not start FreeRDP'

if rg --fixed-strings --quiet -- 'visible.size.width * 0.84' "$controller"; then
  fail 'Orbis still negotiates the desktop from the temporary window size'
fi

result_body="$(sed -n '/^- (void)handleConnectionResult:/,/^- (void)handleSessionError:/p' "$controller")"
if grep -Fq 'toggleFullScreen:' <<<"$result_body"; then
  fail 'Orbis still enters fullscreen after RDP has already negotiated its resolution'
fi

printf 'PASS: Orbis macOS fullscreen-resolution contract\n'
