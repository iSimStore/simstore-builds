#!/bin/bash
app_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$app_dir/../../scripts/build-common.sh"
source_dir="$work/source"
xcode_settings=(
  -project "$source_dir/YOLOiOSApp/YOLOiOSApp.xcodeproj" -scheme YOLOiOSApp -configuration Release
  -derivedDataPath "$work/derived-data" -packageCachePath "$work/swift-package-cache"
  -disableAutomaticPackageResolution
)
