#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/env.sh"
start_build "$@"
cd "$source_dir"
xcodebuild "${xcode_settings[@]}" "${simulator_settings[@]}" -jobs 4 \
  CODE_SIGN_STYLE=Manual PROVISIONING_PROFILE= PROVISIONING_PROFILE_SPECIFIER= \
  ENABLE_USER_SCRIPT_SANDBOXING=NO build 2>&1 | tee "$work/logs/xcode-release.log"
git diff > "$work/source.patch"
cmp "$app_dir/patches/simulator-build.patch" "$work/source.patch"
cmp "$app_dir/Podfile.lock" ios/Podfile.lock
built_app="$work/derived-data/Build/Products/Release-iphonesimulator/Chatwoot.app"
[[ -s "$built_app/main.jsbundle" ]]
# These precompiled archives omit executable permission on their framework binaries.
for framework in TwilioVoice React ReactNativeDependencies; do
  chmod +x "$built_app/Frameworks/$framework.framework/$framework"
done
finish_build "$built_app" Chatwoot.app
