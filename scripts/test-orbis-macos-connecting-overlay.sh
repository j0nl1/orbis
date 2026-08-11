#!/usr/bin/env bash
# SPDX-License-Identifier: MIT

set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
freerdp_source_dir="$("$project_root/scripts/prepare-freerdp.sh")"
session_controller="$project_root/macos/Sources/OrbisSessionController.m"
remote_view_header="$freerdp_source_dir/client/Mac/MRDPView.h"
remote_view="$freerdp_source_dir/client/Mac/MRDPView.m"

fail() {
	printf 'FAIL: %s\n' "$1" >&2
	exit 1
}

grep -Fq 'NSProgressIndicatorStyleSpinning' "$session_controller" || \
	fail 'the macOS connection screen has no native loading indicator'
grep -Fq 'colorWithSRGBRed:24.0 / 255.0' "$session_controller" || \
	fail 'the macOS connection screen does not use Codex black (#181818)'
grep -Fq 'Connecting to %@…' "$session_controller" || \
	fail 'the connection screen does not identify the destination'
grep -Fq 'MRDPViewDidPresentFirstFrameNotification' "$remote_view_header" || \
	fail 'the remote view exposes no first-frame signal'
grep -Fq 'postNotificationName:MRDPViewDidPresentFirstFrameNotification' "$remote_view" || \
	fail 'the remote view never signals that the first frame was drawn'
grep -Fq '@selector(remoteViewDidPresentFirstFrame:)' "$session_controller" || \
	fail 'the loading screen does not wait for the first remote frame'
grep -Fq '[self hideConnectingOverlay];' "$session_controller" || \
	fail 'the loading screen cannot transition to the remote desktop'

printf 'PASS: Orbis macOS first-frame loading screen contract\n'
