#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/env.sh"
start_build "$@"
xcodebuild "${xcode_settings[@]}" "${simulator_settings[@]}" -jobs 2 \
  DEBUG_INFORMATION_FORMAT= GCC_GENERATE_DEBUGGING_SYMBOLS=NO \
  CODE_SIGN_STYLE=Manual PROVISIONING_PROFILE= PROVISIONING_PROFILE_SPECIFIER= \
  build 2>&1 | tee "$work/logs/xcode-release.log"
python3 "$repo_dir/scripts/check_patch.py" "$source_dir" "$app_dir/patches/simulator.patch"
built_app="$work/derived-data/Build/Products/Release-iphonesimulator/Impress.app"
notices="$built_app/ThirdPartyNotices"
mkdir -p "$notices"
install -m 644 "$source_dir/ios/iosremote/licenses.html" "$notices/LibreOffice.html"
install -m 644 "$source_dir/ios/iosremote/InAppSettingsKit/Controllers/IASKAppSettingsViewController.m" "$notices/InAppSettingsKit.m"
install -m 644 "$source_dir/ios/iosremote/SWRevealViewController/SWRevealViewController.h" "$notices/SWRevealViewController.h"
install -m 644 "$source_dir/ios/iosremote/PopoverView/PopoverView.h" "$notices/PopoverView.h"
finish_build "$built_app" 'LibreOffice Impress Remote.app'
