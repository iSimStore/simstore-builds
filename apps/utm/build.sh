#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/env.sh"
start_build "$@"
cd "$source_dir"
# The helper extension retains its upstream iOS 26 deployment requirement.
ios_settings=()
for setting in "${simulator_settings[@]}"; do
  case "$setting" in
    IPHONEOS_DEPLOYMENT_TARGET=*) ;;
    *) ios_settings+=("$setting") ;;
  esac
done
xcodebuild -project UTM.xcodeproj -scheme iOS -configuration Release \
  "${ios_settings[@]}" -derivedDataPath "$work/derived-data" \
  -clonedSourcePackagesDirPath "$work/swift-packages" -packageCachePath "$work/swift-package-cache" \
  -packageAuthorizationProvider netrc -disableAutomaticPackageResolution \
  -onlyUsePackageVersionsFromResolvedFile -skipMacroValidation -skipPackagePluginValidation \
  CODE_SIGN_STYLE=Manual PROVISIONING_PROFILE= PROVISIONING_PROFILE_SPECIFIER= \
  ENABLE_HARDENED_RUNTIME=NO ENABLE_USER_SCRIPT_SANDBOXING=NO \
  build 2>&1 | tee "$work/logs/xcode-release.log"
git diff > "$work/source.patch"
python3 "$repo_dir/scripts/check_patch.py" "$source_dir" "$app_dir/patches/simulator-build.patch"
built_app="$work/derived-data/Build/Products/Release-iphonesimulator/UTM.app"
# Framework binaries must retain executable permission when packaged.
while IFS= read -r -d '' framework; do
  chmod +x "$framework/$(basename "${framework%.framework}")"
done < <(find "$built_app" -type d -name '*.framework' -print0)
finish_build "$built_app" UTM.app
