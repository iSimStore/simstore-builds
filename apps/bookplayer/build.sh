#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/env.sh"
start_build "$@"
# Preserve the deployment requirements of each upstream target.
ios_settings=()
for setting in "${simulator_settings[@]}"; do
  case "$setting" in
    IPHONEOS_DEPLOYMENT_TARGET=*) ;;
    *) ios_settings+=("$setting") ;;
  esac
done
xcodebuild -project "$source_dir/BookPlayer.xcodeproj" -scheme BookPlayer \
  -configuration Release -xcconfig "$app_dir/simulator.xcconfig" "${ios_settings[@]}" \
  -derivedDataPath "$work/derived-data" \
  -clonedSourcePackagesDirPath "$work/swift-packages" -packageCachePath "$work/swift-package-cache" \
  -packageAuthorizationProvider netrc -disableAutomaticPackageResolution \
  -onlyUsePackageVersionsFromResolvedFile -skipMacroValidation -skipPackagePluginValidation \
  -jobs 4 CODE_SIGN_STYLE=Manual PROVISIONING_PROFILE= PROVISIONING_PROFILE_SPECIFIER= \
  ENABLE_USER_SCRIPT_SANDBOXING=NO \
  build 2>&1 | tee "$work/logs/xcode-release.log"
python3 "$repo_dir/scripts/check_patch.py" "$source_dir" "$app_dir/patches/simulator-build.patch"
cmp "$source_dir/BuildConfiguration/Debug.template.xcconfig" "$source_dir/BuildConfiguration/Debug.xcconfig"
built_app="$work/derived-data/Build/Products/Release-iphonesimulator/BookPlayer.app"
cp "$source_dir/LICENSE" "$built_app/"
finish_build "$built_app" BookPlayer.app
