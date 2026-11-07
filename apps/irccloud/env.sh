#!/bin/bash
app_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$app_dir/../../scripts/build-common.sh"
source "$repo_dir/scripts/cocoapods-common.sh"
source_dir="$work/source"
xcode_settings=(
  -workspace "$source_dir/IRCCloud.xcworkspace" -scheme IRCCloud -configuration Release
  -derivedDataPath "$work/derived-data"
)
