#!/usr/bin/env bash
# SPDX-License-Identifier: MIT

set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
native_arch="$(uname -m)"
build_dir="${ORBIS_TEST_BUILD_DIR:-$project_root/.build/tests}"

ORBIS_MACOS_ARCH="$native_arch" "$project_root/scripts/build-orbis-macos.sh"
cmake -S "$project_root" -B "$build_dir" -G Ninja -DBUILD_TESTING=ON \
  -DORBIS_TEST_FREERDP_BUILD_DIR="$project_root/.build/macos/$native_arch"
cmake --build "$build_dir" --target orbis_keyboard_input_tests --parallel
ctest --test-dir "$build_dir" -R '^integration.macos-keyboard-input$' --output-on-failure "$@"
