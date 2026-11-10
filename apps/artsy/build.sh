#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/env.sh"
start_build "$@"
cd "$source_dir"
xcodebuild -workspace ios/Artsy.xcworkspace -scheme Artsy -configuration Store \
  "${simulator_settings[@]}" -derivedDataPath "$work/derived-data" -jobs 2 \
  CODE_SIGN_STYLE=Manual PROVISIONING_PROFILE= PROVISIONING_PROFILE_SPECIFIER= \
  ENABLE_USER_SCRIPT_SANDBOXING=NO MARKETING_VERSION="$version" CURRENT_PROJECT_VERSION=1 \
  DISPLAY_NAME="$(manifest_field name)" \
  build 2>&1 | tee "$work/logs/xcode-store.log"
python3 "$repo_dir/scripts/check_patch.py" "$source_dir" "$app_dir/patches/simulator-build.patch"
git apply --reverse --check --directory=node_modules/react-native "$app_dir/patches/hermes-path.patch"
cmp "$app_dir/Podfile.lock" ios/Podfile.lock
built_app="$work/derived-data/Build/Products/Store-iphonesimulator/Artsy.app"
[[ -s "$built_app/main.jsbundle" ]]
# The prebuilt React Native archives omit execute bits on these framework binaries.
chmod a+x "$built_app/Frameworks/React.framework/React" \
  "$built_app/Frameworks/ReactNativeDependencies.framework/ReactNativeDependencies"
cp LICENSE "$built_app/LICENSE"
finish_build "$built_app" Artsy.app
