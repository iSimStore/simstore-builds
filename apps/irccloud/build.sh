#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/env.sh"
start_build "$@"
cd "$source_dir"
xcodebuild "${xcode_settings[@]}" "${simulator_settings[@]}" -jobs 4 \
  CODE_SIGN_STYLE=Manual PROVISIONING_PROFILE= PROVISIONING_PROFILE_SPECIFIER= \
  FRAMEWORK_SEARCH_PATHS="$work/webp-framework \$(inherited)" \
  CLANG_ALLOW_NON_MODULAR_INCLUDES_IN_FRAMEWORK_MODULES=YES \
  ENABLE_USER_SCRIPT_SANDBOXING=NO build 2>&1 | tee "$work/logs/xcode-release.log"
git diff > "$work/source.patch"
cmp "$app_dir/patches/simulator-build.patch" "$work/source.patch"
cmp "$app_dir/Podfile.lock" Podfile.lock
finish_build "$work/derived-data/Build/Products/Release-iphonesimulator/IRCCloud.app" IRCCloud.app
