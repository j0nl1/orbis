#!/usr/bin/env bash
# SPDX-License-Identifier: MIT

set -euo pipefail

repository_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
vendor_dir="${repository_dir}/vendor/freerdp"
patch_file="${repository_dir}/patches/freerdp/orbis-apple.patch"
source_dir="${repository_dir}/.build/vendor/freerdp"
stamp_file="${source_dir}/.orbis-source-stamp"

if [[ ! -f "${vendor_dir}/CMakeLists.txt" ]]; then
  git -C "${repository_dir}" submodule update --init vendor/freerdp >&2
fi

vendor_commit="$(git -C "${vendor_dir}" rev-parse HEAD)"
patch_digest="$(shasum -a 256 "${patch_file}" | awk '{ print $1 }')"
expected_stamp="${vendor_commit}:${patch_digest}"

if [[ -f "${stamp_file}" ]] && [[ "$(<"${stamp_file}")" == "${expected_stamp}" ]]; then
  printf '%s\n' "${source_dir}"
  exit 0
fi

cmake -E remove_directory "${source_dir}"
cmake -E make_directory "${source_dir}"
git -C "${vendor_dir}" archive HEAD | tar -x -C "${source_dir}"

relative_source_dir="${source_dir#"${repository_dir}/"}"
git -C "${repository_dir}" apply --check --directory="${relative_source_dir}" "${patch_file}"
git -C "${repository_dir}" apply --directory="${relative_source_dir}" "${patch_file}"

ln -s "${repository_dir}/ipados" "${source_dir}/ipados"
ln -s "${repository_dir}/macos" "${source_dir}/macos"
ln -s "${repository_dir}/shared" "${source_dir}/shared"
printf '%s\n' '3.28.0' > "${source_dir}/.source_tag"
printf '%s\n' "${vendor_commit}" > "${source_dir}/.source_version"
printf '%s\n' "${expected_stamp}" > "${stamp_file}"

printf '%s\n' "${source_dir}"
