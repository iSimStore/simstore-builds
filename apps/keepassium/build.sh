#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/env.sh"
start_build "$@"
xcodebuild "${xcode_settings[@]}" "${simulator_settings[@]}" \
  -sdk iphonesimulator -jobs 2 -disableAutomaticPackageResolution \
  -onlyUsePackageVersionsFromResolvedFile \
  DEBUG_INFORMATION_FORMAT= GCC_GENERATE_DEBUGGING_SYMBOLS=NO \
  COMPILATION_CACHE_ENABLE_CACHING=NO \
  CODE_SIGN_STYLE=Manual PROVISIONING_PROFILE= PROVISIONING_PROFILE_SPECIFIER= \
  ENABLE_USER_SCRIPT_SANDBOXING=NO \
  build 2>&1 | tee "$work/logs/xcode-release.log"
git -C "$source_dir" diff --exit-code
built_app="$work/derived-data/Build/Products/Release-iphonesimulator/KeePassium.app"
cp "$source_dir/LICENSE.txt" "$built_app/KeePassium-LICENSE.txt"
finish_build "$built_app" KeePassium.app
