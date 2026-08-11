#!/usr/bin/env bash
# SPDX-License-Identifier: MIT

set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/orbis-layout-test.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT

xcrun clang -fno-objc-arc -fblocks \
  -framework AppKit \
  -framework Foundation \
  -framework Security \
  -I "$project_root/macos/Sources" \
	-I "$project_root/shared/Sources/About" \
  -I "$project_root/shared/Sources/Profiles" \
  -I "$project_root/shared/Sources/Security" \
  "$project_root/macos/Tests/OrbisLibraryLayoutTests.m" \
  "$project_root/macos/Sources/OrbisLibraryViewController.m" \
	"$project_root/macos/Sources/OrbisAboutController.m" \
  "$project_root/macos/Sources/OrbisProfileEditorController.m" \
  "$project_root/shared/Sources/Profiles/OrbisProfile.m" \
  "$project_root/shared/Sources/Security/OrbisCredentialStore.m" \
	"$project_root/shared/Sources/About/OrbisAcknowledgements.m" \
  -o "$test_dir/orbis-library-layout-tests"

"$test_dir/orbis-library-layout-tests"
