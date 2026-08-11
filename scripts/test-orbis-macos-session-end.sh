#!/usr/bin/env bash
# SPDX-License-Identifier: MIT

set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
freerdp_source_dir="$("$project_root/scripts/prepare-freerdp.sh")"
session_controller="$project_root/macos/Sources/OrbisSessionController.m"
remote_view="$freerdp_source_dir/client/Mac/MRDPView.m"
app_delegate="$project_root/macos/Sources/OrbisAppDelegate.m"

fail() {
	printf 'FAIL: %s\n' "$1" >&2
	exit 1
}

grep -Fq 'OrbisSessionEndDispositionForErrorInfo(event->code)' "$session_controller" || \
	fail 'the FreeRDP error handler bypasses the tested session-end policy'

grep -Fq -- '- (void)handleSessionEnded' "$session_controller" || \
	fail 'the normal session-ended handler is missing'

grep -Fq -- '- (void)windowDidExitFullScreen:' "$session_controller" || \
	fail 'ending a session can leave the user in an empty fullscreen Space'

grep -Fq 'NSWindowStyleMaskFullScreen' "$session_controller" || \
	fail 'session teardown does not distinguish a fullscreen remote window'

grep -Fq '[_window toggleFullScreen:nil];' "$session_controller" || \
	fail 'the remote window does not leave fullscreen before it is hidden'

grep -Fq -- '- (void)completeStop' "$session_controller" || \
	fail 'session teardown has no post-fullscreen completion step'

disconnect_body="$(sed -n \
	'/^void mac_post_disconnect/,/^}/p' "$remote_view")"
grep -Fq '@synchronized (view)' <<<"$disconnect_body" || \
	fail 'disconnect can free the framebuffer while AppKit is drawing it'
grep -Fq 'view->bitmap_context = nullptr;' <<<"$disconnect_body" || \
	fail 'disconnect leaves the view attached to the freed framebuffer'

draw_body="$(sed -n '/^- (void)drawRect:/,/^}/p' "$remote_view")"
grep -Fq '@synchronized (self)' <<<"$draw_body" || \
	fail 'drawing is not serialised with framebuffer teardown'

grep -Fq 'action:@selector(disconnectSession:)' "$app_delegate" || \
	fail 'the macOS menu bar has no Disconnect action'
grep -Fq -- '- (void)disconnectSession:' "$app_delegate" || \
	fail 'the macOS Disconnect menu item has no implementation'

printf 'PASS: Orbis macOS session teardown contract\n'
