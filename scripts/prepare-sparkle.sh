#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
set -euo pipefail

repository_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
version=2.10.0
digest=c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c
destination="${repository_dir}/.build/dependencies/sparkle-${version}"
archive="${destination}/Sparkle-${version}.tar.xz"

if [[ ! -f "${destination}/.verified-${digest}" ]]; then
  mkdir -p "$destination"
  curl --fail --location --retry 3 \
    "https://github.com/sparkle-project/Sparkle/releases/download/${version}/Sparkle-${version}.tar.xz" \
    --output "$archive" >&2
  printf '%s  %s\n' "$digest" "$archive" | shasum -a 256 --check >&2
  tar -xJf "$archive" -C "$destination"
  touch "${destination}/.verified-${digest}"
fi
[[ -f "${destination}/Sparkle.framework/Sparkle" && -x "${destination}/bin/generate_appcast" ]]
printf '%s\n' "$destination"
