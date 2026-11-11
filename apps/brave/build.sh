#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/env.sh"
start_build "$@"
cd "$source_dir"
xcodebuild -project ios/brave-ios/App/Client.xcodeproj -scheme 'Release (No Core)' -configuration Release -scmProvider system \
  "${simulator_settings[@]}" -derivedDataPath "$work/derived-data" -jobs 2 \
  -clonedSourcePackagesDirPath "$work/swift-packages" -packageCachePath "$work/swift-package-cache" \
  -onlyUsePackageVersionsFromResolvedFile -packageAuthorizationProvider netrc \
  -skipMacroValidation -skipPackagePluginValidation \
  CODE_SIGN_STYLE=Manual PROVISIONING_PROFILE= PROVISIONING_PROFILE_SPECIFIER= \
  ENABLE_USER_SCRIPT_SANDBOXING=NO build 2>&1 | tee "$work/logs/xcode-release.log"
finish_build "$work/derived-data/Build/Products/Release-iphonesimulator/Client.app" Brave.app
