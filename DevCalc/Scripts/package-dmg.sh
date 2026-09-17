#!/bin/zsh
# 打包拖装 DMG：dist/DevCalc-0.1.0.dmg
set -euo pipefail

script_dir="${0:A:h}"
project_dir="${script_dir:h}"
output_dmg="${project_dir}/dist/DevCalc-0.1.0.dmg"
staging_dir="$(mktemp -d)"

trap 'rm -rf "${staging_dir}"' EXIT

"${project_dir}/Scripts/make-app.sh"
ditto "${project_dir}/dist/DevCalc.app" "${staging_dir}/DevCalc.app"
ln -s /Applications "${staging_dir}/Applications"

if [[ -f "${output_dmg}" ]]; then
    rm "${output_dmg}"
fi

hdiutil create \
    -volname "DevCalc" \
    -srcfolder "${staging_dir}" \
    -format UDZO \
    -imagekey zlib-level=9 \
    "${output_dmg}" >/dev/null

echo "Built ${output_dmg}"
