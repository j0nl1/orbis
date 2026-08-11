#!/usr/bin/env bash
# SPDX-License-Identifier: MIT

set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
policy_header="$project_root/macos/Sources/OrbisConnectionRetryPolicy.h"
policy_source="$project_root/macos/Sources/OrbisConnectionRetryPolicy.c"
policy_test="$project_root/macos/Tests/OrbisConnectionRetryPolicyTests.c"
session_controller="$project_root/macos/Sources/OrbisSessionController.m"

fail() {
	printf 'FAIL: %s\n' "$1" >&2
	exit 1
}

[[ -f "$policy_header" && -f "$policy_source" ]] || \
	fail 'the transient connection retry policy is missing'

test_dir="$(mktemp -d "${TMPDIR:-/tmp}/orbis-retry-test.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT

clang -std=c11 -Wall -Wextra -Werror \
	-I"$project_root/macos/Sources" \
	"$policy_source" "$policy_test" \
	-o "$test_dir/orbis-retry-policy-test"
"$test_dir/orbis-retry-policy-test"

grep -Fq 'OrbisConnectionRetryDecisionForError(' "$session_controller" || \
	fail 'the session controller does not apply the tested retry policy'
grep -Fq 'lastError, _transientConnectRetryCount' "$session_controller" || \
	fail 'the session controller does not apply retries to the actual FreeRDP error'
grep -Fq -- '- (void)retryCurrentConnection' "$session_controller" || \
	fail 'the session controller cannot rebuild a failed initial connection'

printf 'PASS: Orbis macOS uses its bounded retry policy\n'
