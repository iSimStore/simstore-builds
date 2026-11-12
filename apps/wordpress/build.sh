#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/env.sh"
start_build "$@"
cd "$source_dir"
# Preserve dependency deployment floors: RNTAztecView's iOS 15 interface imports Aztec.
# The app/extensions still use the upstream iOS 17 settings, checked against the manifest.
native_settings=()
for setting in "${simulator_settings[@]}"; do
  case "$setting" in
    IPHONEOS_DEPLOYMENT_TARGET=*) continue ;;
  esac
  native_settings+=("$setting")
done
xcodebuild "${xcode_settings[@]}" "${native_settings[@]}" -sdk iphonesimulator -jobs 2 \
  CLANG_ENABLE_CODE_COVERAGE=NO \
  DEBUG_INFORMATION_FORMAT= GCC_GENERATE_DEBUGGING_SYMBOLS=NO \
  CODE_SIGN_STYLE=Manual PROVISIONING_PROFILE= PROVISIONING_PROFILE_SPECIFIER= \
  ENABLE_USER_SCRIPT_SANDBOXING=NO \
  build 2>&1 | tee "$work/logs/xcode-release.log"
python3 "$repo_dir/scripts/check_patch.py" "$source_dir" "$app_dir/patches/simulator-build.patch"
cmp "$app_dir/Package.resolved" "$resolved"
built_app="$work/derived-data/Build/Products/Release-iphonesimulator/WordPress.app"
cp "$source_dir/LICENSE" "$built_app/WordPress-LICENSE.txt"
# Populate the upstream acknowledgement UI without a host-installed Swift tool.
python3 "$app_dir/prepare_notices.py" "$app_dir/Package.resolved" \
  "$work/swift-packages/checkouts" "$built_app" \
  --allow-missing-license automatticabout-swift --allow-missing-license gutenbergkit
ditto "$app_dir/licenses/gutenberg" "$built_app/ThirdPartyNotices/Gutenberg"
finish_build "$built_app" WordPress.app
