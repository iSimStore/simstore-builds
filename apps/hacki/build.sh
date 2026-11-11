#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/env.sh"
start_build "$@"
bundle exec xcodebuild "${xcode_settings[@]}" "${simulator_settings[@]}" -sdk iphonesimulator -jobs 2 \
  -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile \
  CODE_SIGN_STYLE=Manual PROVISIONING_PROFILE= PROVISIONING_PROFILE_SPECIFIER= \
  ENABLE_USER_SCRIPT_SANDBOXING=NO FLUTTER_BUILD_MODE=debug \
  MARKETING_VERSION="$version" \
  build 2>&1 | tee "$work/logs/xcode-debug.log"
python3 "$repo_dir/scripts/check_patch.py" "$source_dir" "$app_dir/patches/simulator-build.patch"
python3 "$repo_dir/scripts/check_patch.py" "$work/flutter" "$app_dir/patches/flutter-spm.patch"
check_locks
cmp "$source_dir/ios/Podfile.lock" "$source_dir/ios/Pods/Manifest.lock"
built_app="$work/derived-data/Build/Products/Debug-iphonesimulator/Runner.app"
[[ -s "$built_app/Frameworks/App.framework/flutter_assets/kernel_blob.bin" ]]
[[ -d "$built_app/PlugIns/Share Extension.appex" ]]
[[ -d "$built_app/PlugIns/Action Extension.appex" ]]
[[ -d "$built_app/PlugIns/Story Widget Extension.appex" ]]
cp "$source_dir/LICENSE" "$built_app/Hacki-LICENSE"
finish_build "$built_app" Hacki.app
