#!/bin/bash
app_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$app_dir/../../scripts/build-common.sh"
source_dir="$work/source"
clipping="$source_dir/Submodules/ClippingBezier"
performance="$clipping/Submodules/PerformanceBezier"
export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
xcode_settings=(
  -workspace "$source_dir/LooseLeaf.xcworkspace" -scheme LooseLeaf -configuration Release
  -derivedDataPath "$work/derived-data"
)
