#!/bin/bash
app_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$app_dir/../../scripts/build-common.sh"
source_dir="$work/source"
resolved="$source_dir/Kiwix.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
export PATH="$work/tools/xcodegen/bin:$PATH"
export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
xcode_settings=(
  -project "$source_dir/Kiwix.xcodeproj" -scheme Kiwix -configuration Release
  -derivedDataPath "$work/derived-data"
  -clonedSourcePackagesDirPath "$work/packages" -packageCachePath "$work/swift-package-cache"
  -packageAuthorizationProvider netrc -skipMacroValidation -skipPackagePluginValidation
  -disableAutomaticPackageResolution -skipPackageUpdates -onlyUsePackageVersionsFromResolvedFile
)
