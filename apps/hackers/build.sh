#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/env.sh"
start_build "$@"
cd "$source_dir"
xcodebuild "${xcode_settings[@]}" "${simulator_settings[@]}" -sdk iphonesimulator \
  CODE_SIGN_STYLE=Manual PROVISIONING_PROFILE= PROVISIONING_PROFILE_SPECIFIER= \
  build 2>&1 | tee "$work/logs/xcode-release.log"
cmp "$app_dir/Package.resolved" "$resolved"
git diff --exit-code
built_app="$work/derived-data/Build/Products/Release-iphonesimulator/Hackers.app"
cp "$source_dir/LICENSE" "$built_app/Hackers-LICENSE.txt"
cp "$work/swift-packages/checkouts/SwiftSoup/LICENSE" "$built_app/SwiftSoup-LICENSE.txt"
finish_build "$built_app" Hackers.app
