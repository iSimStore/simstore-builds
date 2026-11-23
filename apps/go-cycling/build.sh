#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/env.sh"
start_build "$@"
xcodebuild "${xcode_settings[@]}" "${simulator_settings[@]}" -jobs 2 \
  -disableAutomaticPackageResolution -skipPackageUpdates \
  DEBUG_INFORMATION_FORMAT=dwarf GCC_GENERATE_DEBUGGING_SYMBOLS=NO \
  COMPILATION_CACHE_ENABLE_CACHING=NO CODE_SIGN_STYLE=Manual \
  PROVISIONING_PROFILE= PROVISIONING_PROFILE_SPECIFIER= \
  build 2>&1 | tee "$work/logs/xcode-release.log"
python3 "$repo_dir/scripts/check_patch.py" "$source_dir" "$app_dir/patches/simulator.patch"
built_app="$work/derived-data/Build/Products/Release-iphonesimulator/Go Cycling.app"
install -m 644 "$source_dir/LICENSE" "$built_app/GoCycling-LICENSE.txt"
install -m 644 "$work/packages/checkouts/SwiftSDK/LICENSE" "$built_app/TelemetryDeck-LICENSE.txt"
finish_build "$built_app" "Go Cycling.app"
