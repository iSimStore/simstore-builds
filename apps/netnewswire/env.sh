#!/bin/bash
app_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$app_dir/../../scripts/build-common.sh"
source_dir="$work/source"
export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8

xcode_settings=(
  -project "$source_dir/NetNewsWire.xcodeproj" -scheme NetNewsWire-iOS -configuration Release
  -derivedDataPath "$work/derived-data" -clonedSourcePackagesDirPath "$work/swift-packages"
  -packageCachePath "$work/swift-package-cache"
  -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile
)

check_locks() {
  cmp "$app_dir/Package.resolved" "$source_dir/NetNewsWire.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
  cmp "$app_dir/Account.Package.resolved" "$source_dir/Modules/Account/Package.resolved"
}
