#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/env.sh"
start_build "$@"
cd "$source_dir"
xcodebuild "${xcode_settings[@]}" "${simulator_settings[@]}" -jobs 4 \
  CODE_SIGN_STYLE=Manual PROVISIONING_PROFILE= PROVISIONING_PROFILE_SPECIFIER= \
  ENABLE_USER_SCRIPT_SANDBOXING=NO FLUTTER_BUILD_MODE=debug \
  build 2>&1 | tee "$work/logs/xcode-debug.log"
git diff --exit-code -- pubspec.lock ios/Podfile.lock
built_app="$work/derived-data/Build/Products/Debug-iphonesimulator/Runner.app"
[[ -s "$built_app/Frameworks/App.framework/flutter_assets/kernel_blob.bin" ]]
# The sqlite3 native-assets hook downloads its binary without executable permission.
chmod +x "$built_app/Frameworks/sqlite3.framework/sqlite3"
finish_build "$built_app" Zulip.app
