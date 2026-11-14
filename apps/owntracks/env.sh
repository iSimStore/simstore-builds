#!/bin/bash
app_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$app_dir/../../scripts/build-common.sh"
source_dir="$work/source"
resolved="$source_dir/OwnTracks/OwnTracks.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
xcode_settings=(
  -project "$source_dir/OwnTracks/OwnTracks.xcodeproj" -scheme OwnTracks -configuration Release
  -derivedDataPath "$work/derived-data"
  -clonedSourcePackagesDirPath "$work/packages" -packageCachePath "$work/swift-package-cache"
  -packageAuthorizationProvider netrc -skipMacroValidation -skipPackagePluginValidation
  -disableAutomaticPackageResolution -skipPackageUpdates -onlyUsePackageVersionsFromResolvedFile
)
