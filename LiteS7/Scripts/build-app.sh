#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
project_dir="${script_dir:h}"
output_dir="${project_dir}/dist"
app_dir="${output_dir}/LiteS7.app"

cd "${project_dir}"
"${project_dir}/Scripts/make-icon.sh"
swift build -c release

mkdir -p "${app_dir}/Contents/MacOS" "${app_dir}/Contents/Resources"
cp ".build/release/LiteS7" "${app_dir}/Contents/MacOS/LiteS7"
cp "${project_dir}/Support/AppIcon.icns" "${app_dir}/Contents/Resources/AppIcon.icns"

cp "${project_dir}/Support/Info.plist" "${app_dir}/Contents/Info.plist"

codesign --force --sign - "${app_dir}"
echo "Built ${app_dir}"
