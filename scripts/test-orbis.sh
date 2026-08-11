#!/usr/bin/env bash
# SPDX-License-Identifier: MIT

set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
build_dir="${ORBIS_TEST_BUILD_DIR:-$project_root/.build/tests}"

cmake -S "$project_root" -B "$build_dir" -G Ninja -DBUILD_TESTING=ON
cmake --build "$build_dir" --parallel
ctest --test-dir "$build_dir" --output-on-failure "$@"
