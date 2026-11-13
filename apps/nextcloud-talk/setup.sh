#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/env.sh"
setup_python
setup_cocoapods
[[ $(xcodebuild -version) == "Xcode $XCODE_VERSION"$'\n'* ]] || {
  echo "Requires Xcode $XCODE_VERSION." >&2
  exit 1
}
checkout_clean "$(manifest_field source.repository)" "$(manifest_field source.revision)" "$source_dir"
git -C "$source_dir" submodule update --init --depth 1
cp "$app_dir/Podfile.lock" "$source_dir/Podfile.lock"
mkdir -p "$(dirname "$resolved")"
cp "$app_dir/Package.resolved" "$resolved"
cd "$source_dir"
bundle "_${BUNDLER_VERSION}_" exec pod install --deployment 2>&1 | tee "$work/logs/pod-install.log"
# CocoaPods only normalizes empty project lists; retain the committed project layout.
git restore -- NextcloudTalk.xcodeproj/project.pbxproj
cmp "$app_dir/Podfile.lock" "$source_dir/Podfile.lock"
xcodebuild "${xcode_settings[@]}" -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile \
  -resolvePackageDependencies 2>&1 | tee "$work/logs/resolve-packages.log"
cmp "$app_dir/Package.resolved" "$resolved"
