#!/bin/bash
app_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$app_dir/../../scripts/build-common.sh"
source "$repo_dir/scripts/flutter-common.sh"
source_dir="$work/source"
export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 TMPDIR="$work/tmp"
xcode_settings=(
  -workspace "$source_dir/ios/Runner.xcworkspace" -scheme Runner -configuration Debug
  -derivedDataPath "$work/derived-data"
  -clonedSourcePackagesDirPath "$source_dir/build/ios/SourcePackages"
  -packageCachePath "$source_dir/build/ios/SwiftPackageCache"
  -packageAuthorizationProvider netrc -skipMacroValidation -skipPackagePluginValidation
)

check_locks() {
  cmp "$app_dir/pubspec.lock" "$source_dir/pubspec.lock"
  cmp "$app_dir/Podfile.lock" "$source_dir/ios/Podfile.lock"
  cmp "$app_dir/Package.resolved" "$source_dir/ios/Runner.xcworkspace/xcshareddata/swiftpm/Package.resolved"
  cmp "$app_dir/Package.resolved" "$source_dir/ios/Runner.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
}
