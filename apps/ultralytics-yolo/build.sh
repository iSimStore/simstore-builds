#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/env.sh"
start_build "$@"
cd "$source_dir"
xcodebuild "${xcode_settings[@]}" "${simulator_settings[@]}" -sdk iphonesimulator -jobs 2 \
  DEBUG_INFORMATION_FORMAT= GCC_GENERATE_DEBUGGING_SYMBOLS=NO \
  CODE_SIGN_STYLE=Manual PROVISIONING_PROFILE= PROVISIONING_PROFILE_SPECIFIER= \
  ENABLE_USER_SCRIPT_SANDBOXING=NO \
  build 2>&1 | tee "$work/logs/xcode-release.log"
git diff --exit-code
built_app="$work/derived-data/Build/Products/Release-iphonesimulator/YOLOiOSApp.app"
diff -r "$source_dir/YOLOiOSApp/Models" "$built_app/Models"
cp "$source_dir/LICENSE" "$built_app/Ultralytics-LICENSE.txt"
finish_build "$built_app" YOLOiOSApp.app
