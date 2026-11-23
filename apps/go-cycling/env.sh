#!/bin/bash
app_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$app_dir/../../scripts/build-common.sh"
source_dir="$work/source"
export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
# SwiftPM creates the working copy from its local Git cache.
export GIT_ALLOW_PROTOCOL=https:file
xcode_settings=(
  -project "$source_dir/Go Cycling.xcodeproj" -scheme "Go Cycling" -configuration Release
  -derivedDataPath "$work/derived-data"
  -clonedSourcePackagesDirPath "$work/packages"
  -packageCachePath "$work/swift-package-cache"
  -scmProvider system -packageAuthorizationProvider netrc
  -onlyUsePackageVersionsFromResolvedFile
)
