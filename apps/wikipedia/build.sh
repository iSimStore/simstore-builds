#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/env.sh"
start_build "$@"
cd "$source_dir"
xcodebuild "${xcode_settings[@]}" "${simulator_settings[@]}" -sdk iphonesimulator -jobs 2 \
  DEBUG_INFORMATION_FORMAT= GCC_GENERATE_DEBUGGING_SYMBOLS=NO \
  CODE_SIGN_STYLE=Manual PROVISIONING_PROFILE= PROVISIONING_PROFILE_SPECIFIER= \
  ENABLE_USER_SCRIPT_SANDBOXING=NO \
  build 2>&1 | tee "$work/logs/xcode-release.log"
cmp "$app_dir/Package.resolved" "$resolved"
git diff --exit-code
built_app="$work/derived-data/Build/Products/Release-iphonesimulator/Wikipedia.app"
# Upstream CI stamps the date-based release version; source plists contain 0.0.0.
shopt -s nullglob
for info in "$built_app/Info.plist" "$built_app"/PlugIns/*.appex/Info.plist; do
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$info"
done
cp "$source_dir/LICENSE.txt" "$built_app/Wikipedia-LICENSE.txt"
finish_build "$built_app" Wikipedia.app
