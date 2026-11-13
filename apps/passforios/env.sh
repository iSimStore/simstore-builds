#!/bin/bash
app_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$app_dir/../../scripts/build-common.sh"
source_dir="$work/source"
gopenpgp_dir="$work/gopenpgp"
export PATH="$work/go-toolchain/bin:$work/go/bin:$PATH"
export GOPATH="$work/go" GOCACHE="$work/go-cache" GOTOOLCHAIN=local
export GOFLAGS='-mod=readonly -p=2' GOMAXPROCS=2
mkdir -p "$work/tmp"
export TMPDIR="$work/tmp" LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
xcode_settings=(
  -project "$source_dir/pass.xcodeproj" -scheme pass -configuration Release
  -derivedDataPath "$work/derived-data" -packageCachePath "$work/swift-package-cache"
  -packageAuthorizationProvider netrc
)
