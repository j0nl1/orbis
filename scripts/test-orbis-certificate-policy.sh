#!/usr/bin/env bash
# SPDX-License-Identifier: MIT

set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
freerdp_source_dir="$("$project_root/scripts/prepare-freerdp.sh")"
launcher="$project_root/ipados/Sources/OrbisController.m"
certificate_ui="$freerdp_source_dir/client/iOS/FreeRDP/ios_freerdp_ui.m"
session_ui="$freerdp_source_dir/client/iOS/Controllers/RDPSessionViewController.m"

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
require_literal "$launcher" 'setBool:[profile acceptAllCertificates] forKey:@"accept_all_certificates"' \
  "the selected profile must own the certificate policy" || failures=$((failures + 1))
require_literal "$certificate_ui" 'valueForKey:@"accept_all_certificates"' \
  "the FreeRDP callback must read the profile certificate policy" || failures=$((failures + 1))
require_literal "$certificate_ui" 'return 2;' \
  "automatic acceptance must be session-only" || failures=$((failures + 1))
reject_literal "$certificate_ui" 'return 1;' \
  "Connect Once must never persist a certificate" || failures=$((failures + 1))
require_literal "$launcher" 'discardStoredCertificateForProfile:' \
  "strict profiles must discard legacy persisted trust before connecting" || failures=$((failures + 1))
require_literal "$session_ui" 'actionWithTitle:@"Connect Once"' \
  "the certificate confirmation must describe its session-only scope" || failures=$((failures + 1))
require_literal "$session_ui" 'alertControllerWithTitle:@"Untrusted Certificate"' \
  "untrusted certificates must use a visible confirmation alert" || failures=$((failures + 1))

if ((failures > 0)); then
  exit 1
fi

echo "PASS: Orbis certificate policy contract"
