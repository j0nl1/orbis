#!/usr/bin/env bash
# SPDX-License-Identifier: MIT

set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
freerdp_source_dir="$("$project_root/scripts/prepare-freerdp.sh")"
adapter="$freerdp_source_dir/client/Mac/MRDPView.m"
session_controller="$project_root/macos/Sources/OrbisSessionController.m"
compatibility="$project_root/macos/Sources/OrbisKeyboardCompatibility.m"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

shortcut_body="$(sed -n \
  '/^- (BOOL)sendMappedEditingEvent:/,/^}/p' "$adapter")"

[[ -n "$shortcut_body" ]] || \
  fail 'the macOS client has no atomic Command-shortcut sender'

grep -Fq 'KBD_FLAGS_DOWN' <<<"$shortcut_body" || \
  fail 'a mapped Command shortcut does not press its remote key'
grep -Fq 'KBD_FLAGS_RELEASE' <<<"$shortcut_body" || \
  fail 'a mapped Command shortcut can leave its remote key held down'
grep -Fq 'updateFlagStates(input, locks, modifiers)' <<<"$shortcut_body" || \
  fail 'a mapped Command shortcut can leave Control or Shift held down'
grep -Fq 'lastMappedShortcutTimestamp' <<<"$shortcut_body" || \
  fail 'duplicate key-down injection from a remote macOS hop is not suppressed'
grep -Fq 'OrbisKeyboardPlanForEvent' <<<"$shortcut_body" || \
  fail 'mapped input bypasses the shared native editing translator'

grep -Fq '@"deleteToBeginningOfLine:"' "$compatibility" || \
  fail 'Command-Backspace is not translated to a complete remote line deletion'

flags_body="$(sed -n '/^- (void)flagsChanged:/,/^- (BOOL)sendMappedEditingEvent:/p' "$adapter")"
grep -Fq 'commandTapPending' <<<"$flags_body" || \
  fail 'a standalone Command tap cannot be deferred without affecting shortcuts'
grep -Fq 'RDP_SCANCODE_LWIN' <<<"$flags_body" || \
  fail 'a standalone Command tap is not translated to the remote Super key'

key_down_body="$(sed -n '/^- (void)keyDown:/,/^- (void)keyUp:/p' "$adapter")"
grep -Fq 'if ([self sendMappedEditingEvent:event])' <<<"$key_down_body" || \
  fail 'keyDown does not route Command shortcuts through the atomic sender'

rg --fixed-strings --quiet -- \
  'addLocalMonitorForEventsMatchingMask:NSEventMaskFlagsChanged' "$session_controller" || \
  fail 'AppKit can consume a standalone Command event before the RDP view sees it'
rg --fixed-strings --quiet -- '[focusedView flagsChanged:event];' "$session_controller" || \
  fail 'application-level modifier events are not forwarded to the RDP view'
rg --fixed-strings --quiet -- '[NSEvent removeMonitor:_modifierEventMonitor];' "$session_controller" || \
  fail 'the application-level modifier monitor leaks past the RDP session'
rg --fixed-strings --quiet -- \
  'CGEventSourceFlagsState(kCGEventSourceStateCombinedSessionState)' "$session_controller" || \
  fail 'standalone Command taps consumed by AppKit are not observed through CoreGraphics'
rg --fixed-strings --quiet -- '[view setCommandKeyDown:commandIsDown];' \
  "$session_controller" || \
  fail 'the global Command state is not forwarded to the RDP keyboard state machine'
rg --fixed-strings --quiet -- '[_modifierPollTimer invalidate];' "$session_controller" || \
  fail 'the global modifier poller leaks past the RDP session'

printf 'PASS: Orbis macOS keyboard release contract\n'
