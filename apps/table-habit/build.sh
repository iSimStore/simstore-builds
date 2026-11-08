#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/env.sh"
start_build "$@"
cd "$source_dir"
# Preserve the native packages' minimums and the widget extension's iOS 17 minimum.
ios_settings=()
for setting in "${simulator_settings[@]}"; do
  case "$setting" in
    IPHONEOS_DEPLOYMENT_TARGET=*) ;;
    *) ios_settings+=("$setting") ;;
  esac
done
xcodebuild "${xcode_settings[@]}" "${ios_settings[@]}" -jobs 4 \
  -disableAutomaticPackageResolution -skipPackageUpdates -onlyUsePackageVersionsFromResolvedFile \
  CODE_SIGN_STYLE=Manual PROVISIONING_PROFILE= PROVISIONING_PROFILE_SPECIFIER= \
  ASSETCATALOG_COMPILER_STANDALONE_ICON_BEHAVIOR=all \
  ENABLE_USER_SCRIPT_SANDBOXING=NO FLUTTER_BUILD_MODE=debug \
  build 2>&1 | tee "$work/logs/xcode-debug.log"
git diff --exit-code
built_app="$work/derived-data/Build/Products/Debug-f_generic-iphonesimulator/Runner.app"
[[ -s "$built_app/Frameworks/App.framework/flutter_assets/kernel_blob.bin" ]]
[[ -d "$built_app/PlugIns/HabitWidgetExtension.appex" ]]
# The sqlite3 native-assets download does not retain its executable permission.
chmod +x "$built_app/Frameworks/sqlite3.framework/sqlite3"
finish_build "$built_app" TableHabit.app
