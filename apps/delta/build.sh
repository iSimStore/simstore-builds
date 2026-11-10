#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/env.sh"
start_build "$@"
xcodebuild "${xcode_settings[@]}" "${simulator_settings[@]}" -sdk iphonesimulator -jobs 2 \
  CODE_SIGN_STYLE=Manual PROVISIONING_PROFILE= PROVISIONING_PROFILE_SPECIFIER= \
  ENABLE_USER_SCRIPT_SANDBOXING=NO MARKETING_VERSION="$version" CURRENT_PROJECT_VERSION=1 \
  build 2>&1 | tee "$work/logs/xcode-release.log"
check_delta_patch
python3 "$repo_dir/scripts/check_patch.py" "$source_dir/External/Harmony" "$app_dir/patches/harmony.patch"
python3 "$repo_dir/scripts/check_patch.py" "$source_dir/External/Harmony/Backends/Drive" "$app_dir/patches/harmony-drive.patch"
python3 "$repo_dir/scripts/check_patch.py" "$source_dir/Cores/SNESDeltaCore/snes9x" "$app_dir/patches/snes9x.patch"
python3 "$repo_dir/scripts/check_patch.py" "$source_dir/Cores/N64DeltaCore/Mupen64Plus/libpng" "$app_dir/patches/libpng.patch"
python3 "$repo_dir/scripts/check_patch.py" "$revenuecat_dir" "$app_dir/patches/revenuecat.patch"
cmp "$app_dir/Podfile.lock" "$source_dir/Podfile.lock"
cmp "$source_dir/Podfile.lock" "$source_dir/Pods/Manifest.lock"
cmp "$app_dir/Package.resolved" "$source_dir/Delta.xcworkspace/xcshareddata/swiftpm/Package.resolved"
cmp "$app_dir/Systems.Package.resolved" "$source_dir/Systems/Systems.xcworkspace/xcshareddata/swiftpm/Package.resolved"
built_app="$work/derived-data/Build/Products/Release-iphonesimulator/Delta.app"
cp "$source_dir/README.md" "$built_app/Delta-README.md"
finish_build "$built_app" Delta.app
