#!/bin/bash
app_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$app_dir/../../scripts/build-common.sh"
source_dir="$work/source"
resolved="$source_dir/WordPress.xcworkspace/xcshareddata/swiftpm/Package.resolved"
xcode_settings=(
  -workspace "$source_dir/WordPress.xcworkspace" -scheme WordPress -configuration Release
  -derivedDataPath "$work/derived-data" -clonedSourcePackagesDirPath "$work/swift-packages"
  -packageCachePath "$work/swift-package-cache" -packageAuthorizationProvider netrc
  -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile
  -skipMacroValidation -skipPackagePluginValidation
)
