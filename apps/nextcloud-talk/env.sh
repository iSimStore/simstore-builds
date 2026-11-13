#!/bin/bash
app_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$app_dir/../../scripts/build-common.sh"
source "$repo_dir/scripts/cocoapods-common.sh"
source_dir="$work/source"
export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
resolved="$source_dir/NextcloudTalk.xcworkspace/xcshareddata/swiftpm/Package.resolved"
xcode_settings=(
  -workspace "$source_dir/NextcloudTalk.xcworkspace" -scheme NextcloudTalk -configuration Release
  -derivedDataPath "$work/derived-data" -packageCachePath "$work/swift-package-cache"
  -packageAuthorizationProvider netrc
  -skipMacroValidation -skipPackagePluginValidation
)
