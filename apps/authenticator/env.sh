#!/bin/bash
app_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$app_dir/../../scripts/build-common.sh"
source_dir="$work/source"
export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
xcode_settings=(
  -workspace "$source_dir/Authenticator.xcworkspace" -scheme Authenticator -configuration Release
  -derivedDataPath "$work/derived-data"
)
