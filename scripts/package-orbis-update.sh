#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
set -euo pipefail

repository_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app_path="${1:?Usage: package-orbis-update.sh APP_PATH TAG OUTPUT_DIRECTORY}"
tag="${2:?Missing release tag}"
output_dir="${3:?Missing output directory}"
: "${ORBIS_SPARKLE_PRIVATE_KEY_FILE:?Set the path to the exported Sparkle private key}"
sparkle_root="$("${repository_dir}/scripts/prepare-sparkle.sh")"
python3 "${repository_dir}/scripts/orbis-release-version.py" "$tag" >/dev/null
[[ ! -e "$output_dir" ]] || { printf 'Output directory already exists: %s\n' "$output_dir" >&2; exit 1; }
[[ -f "${app_path}/Contents/Frameworks/Sparkle.framework/Sparkle" ]]
lipo "${app_path}/Contents/MacOS/Orbis" -verify_arch arm64 x86_64
lipo "${app_path}/Contents/Frameworks/Sparkle.framework/Sparkle" -verify_arch arm64 x86_64
codesign --verify --deep --strict "$app_path"
mkdir -p "$output_dir"
archive_name="Orbis-${tag}-macos-universal.zip"
ditto -c -k --sequesterRsrc --keepParent "$app_path" "${output_dir}/${archive_name}"
"${sparkle_root}/bin/generate_appcast" \
  --ed-key-file "$ORBIS_SPARKLE_PRIVATE_KEY_FILE" \
  --download-url-prefix "https://github.com/${ORBIS_GITHUB_REPOSITORY:-j0nl1/orbis}/releases/download/${tag}/" \
  --maximum-deltas 0 --maximum-versions 1 \
  --link "https://github.com/${ORBIS_GITHUB_REPOSITORY:-j0nl1/orbis}/releases/tag/${tag}" \
  "$output_dir"

# Fail closed if generation did not sign the archive or the feed, or if it
# generated an entry for a different bundle version or signing key.
python3 "${repository_dir}/scripts/verify-orbis-appcast.py" \
  "${app_path}/Contents/Info.plist" "${output_dir}/appcast.xml" "${output_dir}/${archive_name}" "$tag"
"${sparkle_root}/bin/sign_update" --verify --ed-key-file "$ORBIS_SPARKLE_PRIVATE_KEY_FILE" \
  "${output_dir}/appcast.xml"
signature="$(python3 - "${output_dir}/appcast.xml" <<'PY'
import sys
import xml.etree.ElementTree as ET
root = ET.parse(sys.argv[1]).getroot()
print(root.find('./channel/item/enclosure').get('{http://www.andymatuschak.org/xml-namespaces/sparkle}edSignature'))
PY
)"
"${sparkle_root}/bin/sign_update" --verify --ed-key-file "$ORBIS_SPARKLE_PRIVATE_KEY_FILE" \
  "${output_dir}/${archive_name}" "$signature"
shasum -a 256 "${output_dir}/${archive_name}" | \
  awk '{print $1 "  " "'"${archive_name}"'"}' > "${output_dir}/SHA256SUMS"
