#!/usr/bin/env bash
# SPDX-License-Identifier: MIT

set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
freerdp_source_dir="$("$project_root/scripts/prepare-freerdp.sh")"
profile_header="$project_root/shared/Sources/Profiles/OrbisProfile.h"
profile="$project_root/shared/Sources/Profiles/OrbisProfile.m"
editor_header="$project_root/ipados/Sources/OrbisProfileEditorController.h"
editor="$project_root/ipados/Sources/OrbisProfileEditorController.m"
launcher="$project_root/ipados/Sources/OrbisController.m"
session="$freerdp_source_dir/client/iOS/Controllers/RDPSessionViewController.m"
rdp_session="$freerdp_source_dir/client/iOS/Models/RDPSession.m"
freerdp_client="$freerdp_source_dir/client/iOS/FreeRDP/ios_freerdp.m"
events_header="$freerdp_source_dir/client/iOS/FreeRDP/ios_freerdp_events.h"
events_source="$freerdp_source_dir/client/iOS/FreeRDP/ios_freerdp_events.m"

require_literal() {
  local file="$1"
  local literal="$2"
  local description="$3"
  if ! rg --fixed-strings --quiet -- "$literal" "$file"; then
    echo "FAIL: $description" >&2
    return 1
  fi
}

reject_literal() {
  local file="$1"
  local literal="$2"
  local description="$3"
  if rg --fixed-strings --quiet -- "$literal" "$file"; then
    echo "FAIL: $description" >&2
    return 1
  fi
}

failures=0
reject_literal "$profile_header" 'displayScale' \
  "connection profiles must not expose unsupported display scaling" || failures=$((failures + 1))
reject_literal "$profile" 'displayScale' \
  "connection profiles must not persist unsupported display scaling" || failures=$((failures + 1))
reject_literal "$editor_header" '_displayScaleButton' \
  "the profile editor must not retain a display-scale control" || failures=$((failures + 1))
reject_literal "$editor" 'Display scale' \
  "the profile editor must not offer a pixelating scale option" || failures=$((failures + 1))
reject_literal "$launcher" 'orbis_display_scale' \
  "the launcher must not pass an unsupported scale parameter" || failures=$((failures + 1))
reject_literal "$session" 'remoteScale' \
  "the remote resolution must not be reduced and stretched" || failures=$((failures + 1))
require_literal "$session" 'size.width = ceilf(size.width * nativeScale);' \
  "the remote desktop must retain the iPad native pixel width" || failures=$((failures + 1))
require_literal "$session" 'size.height = ceilf(size.height * nativeScale);' \
  "the remote desktop must retain the iPad native pixel height" || failures=$((failures + 1))
reject_literal "$rdp_session" 'FREERDP_MONITOR_OVERRIDE_DESKTOP_SCALE' \
  "the RDP session must not advertise a custom scale override" || failures=$((failures + 1))
require_literal "$events_header" 'ios_events_send_display_resize' \
  "display resize queuing must have one shared entry point" || failures=$((failures + 1))
require_literal "$events_source" 'UINT ios_events_send_display_resize' \
  "the shared display resize event must be implemented" || failures=$((failures + 1))
require_literal "$freerdp_client" 'ios_events_send_display_resize(afc->mfi' \
  "opening Display Control must resend the current monitor layout" || failures=$((failures + 1))

if ((failures > 0)); then
  exit 1
fi

echo "PASS: Orbis native-resolution display contract"
