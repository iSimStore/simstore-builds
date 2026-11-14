#!/bin/bash
app_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$app_dir/../../scripts/build-common.sh"
source "$repo_dir/scripts/cocoapods-common.sh"
source_dir="$work/source"
export PATH="$work/node/bin:$work/yarn/bin:$work/go-toolchain/bin:$work/go/bin:$PATH"
export NODE_BINARY="$work/node/bin/node"
export GOPATH="$work/go" GOCACHE="$work/go-cache" GOTOOLCHAIN=local
export npm_config_cache="$work/npm-cache" YARN_CACHE_FOLDER="$work/yarn-cache"
export TMPDIR="$work/tmp" LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
export RCT_NEW_ARCH_ENABLED=1 RCT_NO_LAUNCH_PACKAGER=1
export EXPO_NO_TELEMETRY=1 ELECTRON_SKIP_BINARY_DOWNLOAD=1
export CGO_CFLAGS_ALLOW='-fmodules|-fblocks'
xcode_settings=(
  -workspace "$source_dir/shared/ios/Keybase.xcworkspace" -scheme Keybase -configuration Release
  -derivedDataPath "$work/derived-data"
)
