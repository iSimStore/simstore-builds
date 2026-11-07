#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/env.sh"
start_build "$@"
(cd "$source_dir/Ring/CollabEditor" && npm test) 2>&1 | tee "$work/logs/editor-tests.log"
bash "$app_dir/build-frameworks.sh" 2>&1 | tee "$work/logs/frameworks-build.log"
cd "$source_dir"
bash ./compile-ios.sh --platform=iPhoneSimulator --arch=arm64 --release 2>&1 | tee "$work/logs/daemon-build.log"
xcodebuild "${xcode_settings[@]}" "${simulator_settings[@]}" -jobs 4 \
  CODE_SIGN_STYLE=Manual PROVISIONING_PROFILE= PROVISIONING_PROFILE_SPECIFIER= \
  ENABLE_USER_SCRIPT_SANDBOXING=NO build 2>&1 | tee "$work/logs/xcode-release.log"
git diff > "$work/source.patch"
cmp "$app_dir/patches/simulator-build.patch" "$work/source.patch"
git -C daemon diff > "$work/daemon.patch"
cmp "$app_dir/patches/daemon-simulator.patch" "$work/daemon.patch"
cmp "$app_dir/Package.resolved" Ring/Ring.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
finish_build "$work/derived-data/Build/Products/Release-iphonesimulator/Ring.app" Jami.app
