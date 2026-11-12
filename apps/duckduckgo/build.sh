#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/env.sh"
start_build "$@"
cd "$source_dir"
# The upstream WebKit overlay check needs an OS version even for a generic destination.
simulator_sdk_version=$(xcrun --sdk iphonesimulator --show-sdk-version)
SKIP_STRINGS=1 xcodebuild "${xcode_settings[@]}" "${simulator_settings[@]}" -sdk iphonesimulator -jobs 2 \
  TARGET_DEVICE_OS_VERSION="$simulator_sdk_version" \
  DEBUG_INFORMATION_FORMAT= GCC_GENERATE_DEBUGGING_SYMBOLS=NO \
  COMPILATION_CACHE_ENABLE_CACHING=NO \
  CODE_SIGN_STYLE=Manual PROVISIONING_PROFILE= PROVISIONING_PROFILE_SPECIFIER= \
  ENABLE_USER_SCRIPT_SANDBOXING=NO \
  build 2>&1 | tee "$work/logs/xcode-release.log"
cmp "$app_dir/Package.resolved" "$resolved"
python3 "$repo_dir/scripts/check_patch.py" "$source_dir" "$app_dir/patches/public-build.patch"
built_app="$work/derived-data/Build/Products/Release-iphonesimulator/DuckDuckGo.app"
cp "$source_dir/LICENSE.md" "$built_app/DuckDuckGo-LICENSE.md"
finish_build "$built_app" DuckDuckGo.app
