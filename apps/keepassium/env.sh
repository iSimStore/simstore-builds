#!/bin/bash
app_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$app_dir/../../scripts/build-common.sh"
source_dir="$work/source"
export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
resolved="$source_dir/KeePassium.xcworkspace/xcshareddata/swiftpm/Package.resolved"
xcode_settings=(
  -workspace "$source_dir/KeePassium.xcworkspace" -scheme KeePassium -configuration Release
  -derivedDataPath "$work/derived-data" -packageCachePath "$work/swift-package-cache"
  -clonedSourcePackagesDirPath "$work/packages" -packageAuthorizationProvider netrc
)
