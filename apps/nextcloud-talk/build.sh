#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/env.sh"
start_build "$@"
cd "$source_dir"
xcodebuild "${xcode_settings[@]}" "${simulator_settings[@]}" -sdk iphonesimulator -jobs 2 \
  -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile \
  DEBUG_INFORMATION_FORMAT= GCC_GENERATE_DEBUGGING_SYMBOLS=NO \
  CODE_SIGN_STYLE=Manual PROVISIONING_PROFILE= PROVISIONING_PROFILE_SPECIFIER= \
  ENABLE_USER_SCRIPT_SANDBOXING=NO \
  build 2>&1 | tee "$work/logs/xcode-release.log"
cmp "$app_dir/Podfile.lock" "$source_dir/Podfile.lock"
cmp "$app_dir/Package.resolved" "$resolved"
git diff --exit-code
built_app="$work/derived-data/Build/Products/Release-iphonesimulator/NextcloudTalk.app"
cp "$source_dir/LICENSE" "$built_app/NextcloudTalk-LICENSE.txt"
cp "$source_dir/COPYING.iOS" "$built_app/NextcloudTalk-COPYING.iOS"
finish_build "$built_app" NextcloudTalk.app
