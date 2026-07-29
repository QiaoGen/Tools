#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
project_dir="${script_dir:h}"
source_icon="${project_dir}/Assets/AppIcon-1024.png"
output_icon="${project_dir}/Support/AppIcon.icns"
work_dir="$(mktemp -d)"
iconset_dir="${work_dir}/AppIcon.iconset"

trap 'rm -rf "${work_dir}"' EXIT

if [[ ! -f "${source_icon}" ]]; then
    echo "Missing ${source_icon}" >&2
    exit 1
fi

mkdir -p "${iconset_dir}"

sips -z 16 16 "${source_icon}" --out "${iconset_dir}/icon_16x16.png" >/dev/null
sips -z 32 32 "${source_icon}" --out "${iconset_dir}/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "${source_icon}" --out "${iconset_dir}/icon_32x32.png" >/dev/null
sips -z 64 64 "${source_icon}" --out "${iconset_dir}/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "${source_icon}" --out "${iconset_dir}/icon_128x128.png" >/dev/null
sips -z 256 256 "${source_icon}" --out "${iconset_dir}/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "${source_icon}" --out "${iconset_dir}/icon_256x256.png" >/dev/null
sips -z 512 512 "${source_icon}" --out "${iconset_dir}/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "${source_icon}" --out "${iconset_dir}/icon_512x512.png" >/dev/null
sips -z 1024 1024 "${source_icon}" --out "${iconset_dir}/icon_512x512@2x.png" >/dev/null

iconutil -c icns "${iconset_dir}" -o "${output_icon}"
echo "Built ${output_icon}"
