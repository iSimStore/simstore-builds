#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/env.sh"
start_build "$@"
xcodebuild -project "$source_dir/Edhita.xcodeproj" -scheme Edhita \
  -configuration Release "${simulator_settings[@]}" -derivedDataPath "$work/derived-data" \
  -clonedSourcePackagesDirPath "$work/swift-packages" -packageCachePath "$work/swift-package-cache" \
  -packageAuthorizationProvider netrc -disableAutomaticPackageResolution \
  -onlyUsePackageVersionsFromResolvedFile -skipMacroValidation -skipPackagePluginValidation \
  -jobs 4 CODE_SIGN_STYLE=Manual PROVISIONING_PROFILE= PROVISIONING_PROFILE_SPECIFIER= \
  ENABLE_USER_SCRIPT_SANDBOXING=NO \
  build 2>&1 | tee "$work/logs/xcode-release.log"
python3 "$repo_dir/scripts/check_patch.py" "$source_dir" "$app_dir/patches/simulator-build.patch"
cmp "$app_dir/Constants.swift" "$source_dir/Edhita/Models/Constants.swift"
built_app="$work/derived-data/Build/Products/Release-iphonesimulator/Edhita.app"
cp "$source_dir/LICENSE" "$built_app/"
finish_build "$built_app" Edhita.app
