#!/usr/bin/env bash
# SPDX-License-Identifier: MIT

set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
freerdp_source_dir="$("$project_root/scripts/prepare-freerdp.sh")"
build_dir="${ORBIS_BUILD_DIR:-$project_root/.build/ipados/device}"
unsigned_build="${ORBIS_UNSIGNED_BUILD:-0}"
development_team="${APPLE_DEVELOPMENT_TEAM:-}"
device_udid="${ORBIS_DEVICE_UDID:-}"
destination="generic/platform=iOS"

if [[ -n "$device_udid" ]]; then
  destination="id=$device_udid"
fi

cmake \
  -S "$freerdp_source_dir/client/iOS" \
  -B "$build_dir" \
  -G Xcode \
  -DCMAKE_TOOLCHAIN_FILE="$freerdp_source_dir/cmake/ios.toolchain.cmake" \
  -DPLATFORM=OS64 \
  -DDEPLOYMENT_TARGET=26.0 \
  -DCMAKE_BUILD_TYPE=Release

xcode_args=(
  -project "$build_dir/iFreeRDP.xcodeproj"
  -scheme iFreeRDP
  -configuration Release
  -sdk iphoneos
  -destination "$destination"
  COMPILER_INDEX_STORE_ENABLE=NO
)

if [[ "$unsigned_build" == "1" ]]; then
  xcode_args+=(CODE_SIGNING_ALLOWED=NO)
else
	if [[ -z "$development_team" ]]; then
		echo "APPLE_DEVELOPMENT_TEAM is required for a signed device build." >&2
		exit 2
	fi
  xcode_args+=(
    -allowProvisioningUpdates
    DEVELOPMENT_TEAM="$development_team"
    CODE_SIGN_STYLE=Automatic
    CODE_SIGNING_ALLOWED=YES
    CODE_SIGNING_REQUIRED=YES
  )

  if [[ -n "$device_udid" ]]; then
    xcode_args+=(-allowProvisioningDeviceRegistration)
  fi
fi

env \
  GIT_CONFIG_COUNT=1 \
  GIT_CONFIG_KEY_0=commit.gpgsign \
  GIT_CONFIG_VALUE_0=false \
  PKG_CONFIG_PATH="$build_dir/deps/Frameworks/pkgconfig" \
  xcodebuild "${xcode_args[@]}" build

app_path="$(find "$build_dir" -type d -name Orbis.app -path '*Release-iphoneos*' -print -quit)"
if [[ -z "$app_path" ]]; then
  echo "Orbis.app was not found after a successful build." >&2
  exit 1
fi

echo "Built device app: $app_path"
if [[ "$unsigned_build" == "1" ]]; then
  echo "This compile-only app cannot be installed on an iPad."
fi
