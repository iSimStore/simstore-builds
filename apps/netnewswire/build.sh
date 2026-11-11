#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/env.sh"
start_build "$@"
xcodebuild "${xcode_settings[@]}" "${simulator_settings[@]}" -sdk iphonesimulator -jobs 2 \
  CODE_SIGN_STYLE=Manual PROVISIONING_PROFILE= PROVISIONING_PROFILE_SPECIFIER= \
  DEVELOPER_ENTITLEMENTS=-dev ENABLE_USER_SCRIPT_SANDBOXING=NO \
  MARKETING_VERSION="$version" \
  build 2>&1 | tee "$work/logs/xcode-release.log"
python3 "$repo_dir/scripts/check_patch.py" "$source_dir" "$app_dir/patches/simulator-build.patch"
check_locks
built_app="$work/derived-data/Build/Products/Release-iphonesimulator/NetNewsWire.app"
cp "$source_dir/LICENSE" "$built_app/NetNewsWire-LICENSE"
finish_build "$built_app" NetNewsWire.app
