#!/bin/bash
app_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$app_dir/../../scripts/build-common.sh"
source_dir="$work/source"
resolved="$source_dir/iOS/DuckDuckGo-iOS.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
xcode_settings=(
  -project "$source_dir/iOS/DuckDuckGo-iOS.xcodeproj" -scheme 'iOS Browser' -configuration Release
  -derivedDataPath "$work/derived-data" -packageCachePath "$work/swift-package-cache"
  -packageAuthorizationProvider netrc
  -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile
  -skipMacroValidation -skipPackagePluginValidation
)
