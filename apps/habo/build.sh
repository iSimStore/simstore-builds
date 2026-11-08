#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/env.sh"
start_build "$@"
cd "$source_dir"
# Keep the native packages' deployment requirements and the widget's iOS 26.1 minimum.
ios_settings=()
for setting in "${simulator_settings[@]}"; do
  case "$setting" in
    IPHONEOS_DEPLOYMENT_TARGET=*) ;;
    *) ios_settings+=("$setting") ;;
  esac
done
bundle exec xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner -configuration Debug \
  -derivedDataPath "$work/derived-data" "${ios_settings[@]}" -jobs 4 \
  CODE_SIGN_STYLE=Manual PROVISIONING_PROFILE= PROVISIONING_PROFILE_SPECIFIER= \
  ASSETCATALOG_COMPILER_STANDALONE_ICON_BEHAVIOR=all \
  ENABLE_USER_SCRIPT_SANDBOXING=NO FLUTTER_BUILD_MODE=debug \
  build 2>&1 | tee "$work/logs/xcode-debug.log"
git diff > "$work/source.patch"
cmp "$app_dir/patches/simulator-build.patch" "$work/source.patch"
built_app="$work/derived-data/Build/Products/Debug-iphonesimulator/Runner.app"
[[ -s "$built_app/Frameworks/App.framework/flutter_assets/kernel_blob.bin" ]]
[[ -d "$built_app/PlugIns/HaboWidgetExtension.appex" ]]
chmod +x "$built_app/Frameworks/sqlite3.framework/sqlite3"
finish_build "$built_app" Habo.app
