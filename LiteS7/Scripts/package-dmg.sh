#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
project_dir="${script_dir:h}"
output_dmg="${project_dir}/dist/LiteS7-0.1.0.dmg"
staging_dir="$(mktemp -d)"

trap 'rm -rf "${staging_dir}"' EXIT

"${project_dir}/Scripts/build-app.sh"
ditto "${project_dir}/dist/LiteS7.app" "${staging_dir}/LiteS7.app"
ln -s /Applications "${staging_dir}/Applications"

if [[ -f "${output_dmg}" ]]; then
    rm "${output_dmg}"
fi

hdiutil create \
    -volname "LiteS7" \
    -srcfolder "${staging_dir}" \
    -format UDZO \
    -imagekey zlib-level=9 \
    "${output_dmg}" >/dev/null

echo "Built ${output_dmg}"
