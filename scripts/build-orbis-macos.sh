#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
set -euo pipefail

repository_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
freerdp_source_dir="$("${repository_dir}/scripts/prepare-freerdp.sh")"
requested_arch="${ORBIS_MACOS_ARCH:-$(uname -m)}"
configuration="${ORBIS_CONFIGURATION:-Release}"
artifact_dir="${repository_dir}/artifacts/macos"
signing_identity="${ORBIS_MACOS_SIGNING_IDENTITY:--}"

cmake_options=(
  -G Ninja
  "-DCMAKE_BUILD_TYPE=${configuration}"
  -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0
  -DWITH_CLIENT=ON
  -DWITH_CLIENT_COMMON=ON
  -DWITH_CLIENT_MAC=ON
  -DWITH_ORBIS_MACOS=ON
  -DWITH_MACFREERDP_CLI=OFF
  -DWITH_SERVER=OFF
  -DWITH_PROXY=OFF
  -DWITH_PROXY_APP=OFF
  -DWITH_SAMPLE=OFF
  -DWITH_WINPR_TOOLS_CLI=OFF
  -DWITH_X11=OFF
  -DWITH_WAYLAND=OFF
  -DWITH_CLIENT_SDL=OFF
  -DWITH_FFMPEG=OFF
  -DWITH_VIDEO_FFMPEG=OFF
  -DWITH_DSP_FFMPEG=OFF
  -DWITH_SWSCALE=OFF
  -DWITH_CAIRO=OFF
  -DWITH_OPENH264=OFF
  -DWITH_OPUS=OFF
  -DWITH_JPEG=OFF
  -DWITH_WEBP=OFF
  -DWITH_CUPS=OFF
  -DWITH_PCSC=OFF
  -DWITH_KRB5=OFF
  -DWITH_FUSE=OFF
  -DWITH_URIPARSER=OFF
  -DWITH_SYSTEMD=OFF
  -DWITH_PULSE=OFF
  -DWITH_ALSA=OFF
  -DWITH_JSON_DISABLED=ON
  -DWITH_INTERNAL_MD4=ON
  -DWITH_INTERNAL_RC4=ON
  -DWITH_SMARTCARD_EMULATE=OFF
  -DCHANNEL_URBDRC=OFF
  -DCHANNEL_SMARTCARD=OFF
)

openssl_root_for_arch() {
  case "$1" in
    arm64) printf '%s\n' /opt/homebrew/opt/openssl@3 ;;
    x86_64) printf '%s\n' /usr/local/opt/openssl@3 ;;
    *)
      printf 'Unsupported macOS architecture: %s\n' "$1" >&2
      return 1
      ;;
  esac
}

rewrite_openssl_reference() {
  local binary="$1"
  local library_name="$2"
  local dependency_path
  dependency_path="$(otool -L "$binary" | awk -v name="$library_name" '$1 ~ ("/" name "$") { print $1; exit }')"
  if [[ -n "$dependency_path" && "$dependency_path" != "@rpath/${library_name}" ]]; then
    install_name_tool -change "$dependency_path" "@rpath/${library_name}" "$binary"
  fi
}

bundle_openssl() {
  local app_path="$1"
  local openssl_root="$2"
  local frameworks_dir="${app_path}/Contents/Frameworks"
  local binary

  mkdir -p "$frameworks_dir"
  chmod u+w "${frameworks_dir}/libssl.3.dylib" \
    "${frameworks_dir}/libcrypto.3.dylib" 2>/dev/null || true
  cp -f "${openssl_root}/lib/libssl.3.dylib" "${frameworks_dir}/libssl.3.dylib"
  cp -f "${openssl_root}/lib/libcrypto.3.dylib" "${frameworks_dir}/libcrypto.3.dylib"
  chmod u+w "${frameworks_dir}/libssl.3.dylib" "${frameworks_dir}/libcrypto.3.dylib"
  install_name_tool -id @rpath/libssl.3.dylib "${frameworks_dir}/libssl.3.dylib"
  install_name_tool -id @rpath/libcrypto.3.dylib "${frameworks_dir}/libcrypto.3.dylib"

  while IFS= read -r binary; do
    rewrite_openssl_reference "$binary" libssl.3.dylib
    rewrite_openssl_reference "$binary" libcrypto.3.dylib
  done < <(
    find "${app_path}/Contents/MacOS" "$frameworks_dir" -type f \
      \( -path '*/MacOS/*' -o -name '*.dylib' \) -print
  )

  codesign --force --deep --sign "$signing_identity" "$app_path"
}

bundle_binaries() {
  local app_path="$1"
  find "${app_path}/Contents/MacOS" "${app_path}/Contents/Frameworks" -type f \
    \( -path '*/MacOS/*' -o -name '*.dylib' \) -print
}

verify_bundle() {
  local app_path="$1"
  shift
  local binary
  local architecture
  local architectures
  local dependency

  while IFS= read -r binary; do
    architectures="$(lipo -archs "$binary")"
    for architecture in "$@"; do
      if [[ " ${architectures} " != *" ${architecture} "* ]]; then
        printf '%s is missing the %s architecture. Found: %s\n' \
          "$binary" "$architecture" "$architectures" >&2
        return 1
      fi
    done

    while IFS= read -r dependency; do
      case "$dependency" in
        /opt/homebrew/* | /usr/local/*)
          printf '%s contains a build-machine dependency: %s\n' \
            "$binary" "$dependency" >&2
          return 1
          ;;
      esac
    done < <(otool -L "$binary" | awk 'NR > 1 { print $1 }')
  done < <(bundle_binaries "$app_path")

  codesign --verify --deep --strict "$app_path"
}

build_arch() {
  local architecture="$1"
  local build_dir="${repository_dir}/.build/macos/${architecture}"
  local openssl_root
  local package_prefix
  openssl_root="$(openssl_root_for_arch "$architecture")"
  package_prefix="$(dirname "$(dirname "$openssl_root")")"

  if [[ ! -f "${openssl_root}/lib/libssl.3.dylib" ]]; then
    printf 'OpenSSL 3 for %s was not found at %s\n' "$architecture" "$openssl_root" >&2
    return 1
  fi

  PKG_CONFIG_PATH="${openssl_root}/lib/pkgconfig:${package_prefix}/lib/pkgconfig" \
    cmake -S "$freerdp_source_dir" -B "$build_dir" \
      "${cmake_options[@]}" \
      "-DCMAKE_OSX_ARCHITECTURES=${architecture}" \
      "-DOPENSSL_ROOT_DIR=${openssl_root}" \
      "-DOPENSSL_INCLUDE_DIR=${openssl_root}/include" \
      "-DOPENSSL_SSL_LIBRARY=${openssl_root}/lib/libssl.dylib" \
      "-DOPENSSL_CRYPTO_LIBRARY=${openssl_root}/lib/libcrypto.dylib" || return 1
  # FreeRDP's ThinLTO Objective-C archive can otherwise retain a previously
  # linked dylib even after Ninja recompiles one of its bitcode objects.
  # A clean target keeps the distributable framework aligned with its sources.
  cmake --build "$build_dir" --target clean || return 1
  cmake --build "$build_dir" --target OrbisMac --parallel || return 1
  bundle_openssl "${build_dir}/macos/Orbis.app" "$openssl_root" || return 1
  printf '%s\n' "${build_dir}/macos/Orbis.app"
}

package_single_arch() {
  local architecture="$1"
  local built_app
  built_app="$(build_arch "$architecture" | tail -n 1)"
  mkdir -p "$artifact_dir"
  cmake -E remove_directory "${artifact_dir}/Orbis.app"
  ditto "$built_app" "${artifact_dir}/Orbis.app"
  verify_bundle "${artifact_dir}/Orbis.app" "$architecture"
  printf 'Built %s Orbis app: %s\n' "$architecture" "${artifact_dir}/Orbis.app"
}

package_universal() {
  local arm_app
  local intel_app
  local relative_path
  arm_app="$(build_arch arm64 | tail -n 1)"
  intel_app="$(build_arch x86_64 | tail -n 1)"

  mkdir -p "$artifact_dir"
  cmake -E remove_directory "${artifact_dir}/Orbis.app"
  ditto "$arm_app" "${artifact_dir}/Orbis.app"
  while IFS= read -r relative_path; do
    chmod u+w "${artifact_dir}/Orbis.app/${relative_path}"
    lipo -create \
      "${arm_app}/${relative_path}" \
      "${intel_app}/${relative_path}" \
      -output "${artifact_dir}/Orbis.app/${relative_path}"
  done < <(
    cd "$arm_app"
    bundle_binaries .
  )
  codesign --force --deep --sign "$signing_identity" "${artifact_dir}/Orbis.app"
  verify_bundle "${artifact_dir}/Orbis.app" arm64 x86_64
  printf 'Built universal Orbis app: %s\n' "${artifact_dir}/Orbis.app"
}

case "$requested_arch" in
  arm64 | x86_64) package_single_arch "$requested_arch" ;;
  universal) package_universal ;;
  *)
    printf 'ORBIS_MACOS_ARCH must be arm64, x86_64, or universal.\n' >&2
    exit 2
    ;;
esac
