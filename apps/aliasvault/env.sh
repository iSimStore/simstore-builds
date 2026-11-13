#!/bin/bash
app_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$app_dir/../../scripts/build-common.sh"
source "$repo_dir/scripts/cocoapods-common.sh"
source "$repo_dir/scripts/rust-common.sh"
source_dir="$work/source"
mobile_dir="$source_dir/apps/mobile-app"
export PATH="$work/node/bin:$PATH" NODE_BINARY="$work/node/bin/node"
export RUSTUP_TOOLCHAIN="$RUST_VERSION" CARGO_BUILD_JOBS=2
export npm_config_cache="$work/npm-cache" npm_config_audit=false npm_config_fund=false
export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
mkdir -p "$work/tmp"
export TMPDIR="$work/tmp" XDG_CACHE_HOME="$work/cache"
export EXPO_NO_TELEMETRY=1 USE_CCACHE=0
xcode_settings=(
  -workspace "$mobile_dir/ios/AliasVault.xcworkspace" -scheme AliasVault -configuration Release
  -derivedDataPath "$work/derived-data"
)
