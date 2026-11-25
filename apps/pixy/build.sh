#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/env.sh"
start_build "$@"
xcodebuild -workspace "$source_dir/ios/Pixy.xcworkspace" -scheme Pixy -configuration Release \
  -derivedDataPath "$work/derived-data" "${simulator_settings[@]}" -jobs 2 \
  DEBUG_INFORMATION_FORMAT=dwarf GCC_GENERATE_DEBUGGING_SYMBOLS=NO \
  COMPILATION_CACHE_ENABLE_CACHING=NO \
  CODE_SIGN_STYLE=Manual PROVISIONING_PROFILE= PROVISIONING_PROFILE_SPECIFIER= \
  build 2>&1 | tee "$work/logs/xcode-release.log"
built_app="$work/derived-data/Build/Products/Release-iphonesimulator/Pixy.app"
# CocoaPods embeds some prebuilt dylibs without executable permissions.
for framework in "$built_app"/Frameworks/*.framework; do
  executable=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$framework/Info.plist")
  chmod a+x "$framework/$executable"
done
install -m 644 "$source_dir/LICENSE.md" "$built_app/Pixy-LICENSE.txt"
install -m 644 "$work/notices/"*.txt "$built_app/"
install -m 644 "$source_dir/ios/Pods/Target Support Files/Pods-Pixy/Pods-Pixy-acknowledgements.plist" \
  "$built_app/CocoaPods-acknowledgements.plist"
finish_build "$built_app" Pixy.app
