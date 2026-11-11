#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/env.sh"
start_build "$@"
xcodebuild "${xcode_settings[@]}" "${simulator_settings[@]}" -sdk iphonesimulator -jobs 2 \
  CODE_SIGN_STYLE=Manual PROVISIONING_PROFILE= PROVISIONING_PROFILE_SPECIFIER= \
  BUGSNAG_API_KEY= ENABLE_USER_SCRIPT_SANDBOXING=NO \
  MARKETING_VERSION="$version" CURRENT_PROJECT_VERSION=1 \
  build 2>&1 | tee "$work/logs/xcode-release.log"
python3 "$repo_dir/scripts/check_patch.py" "$source_dir" "$app_dir/patches/simulator-build.patch"
cmp "$app_dir/Package.resolved" "$resolved"
built_app="$work/derived-data/Build/Products/Release-iphonesimulator/Twine.app"
cp "$source_dir/LICENSE.txt" "$built_app/Twine-LICENSE.txt"
finish_build "$built_app" Twine.app
