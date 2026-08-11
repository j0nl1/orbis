#!/usr/bin/env bash
# SPDX-License-Identifier: MIT

set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
freerdp_source_dir="$("$project_root/scripts/prepare-freerdp.sh")"
build_dir="${ORBIS_BUILD_DIR:-$project_root/.build/ipados/simulator}"
destination="${ORBIS_SIMULATOR_DESTINATION:-generic/platform=iOS Simulator}"

cmake \
  -S "$freerdp_source_dir/client/iOS" \
  -B "$build_dir" \
  -G Xcode \
  -DCMAKE_TOOLCHAIN_FILE="$freerdp_source_dir/cmake/ios.toolchain.cmake" \
  -DPLATFORM=SIMULATORARM64 \
  -DDEPLOYMENT_TARGET=26.0 \
  -DCMAKE_BUILD_TYPE=Debug

env \
  GIT_CONFIG_COUNT=1 \
  GIT_CONFIG_KEY_0=commit.gpgsign \
  GIT_CONFIG_VALUE_0=false \
  PKG_CONFIG_PATH="$build_dir/deps/Frameworks/pkgconfig" \
  xcodebuild \
    -project "$build_dir/iFreeRDP.xcodeproj" \
    -scheme iFreeRDP \
    -configuration Debug \
    -sdk iphonesimulator \
    -destination "$destination" \
    CODE_SIGNING_ALLOWED=YES \
    CODE_SIGNING_REQUIRED=YES \
    CODE_SIGN_IDENTITY=- \
    COMPILER_INDEX_STORE_ENABLE=NO \
    build

app_path="$(find "$build_dir" -type d -name Orbis.app -path '*Debug-iphonesimulator*' -print -quit)"
if [[ -z "$app_path" ]]; then
  echo "Orbis.app was not found after a successful build." >&2
  exit 1
fi

echo "Built simulator app: $app_path"
