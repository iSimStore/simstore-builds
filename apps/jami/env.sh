#!/bin/bash
app_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$app_dir/../../scripts/build-common.sh"
source "$repo_dir/scripts/rust-common.sh"
source_dir="$work/source"
export PATH="$work/tools/bin:$work/node/bin:$(brew --prefix make)/libexec/gnubin:$PATH"
export RUSTUP_TOOLCHAIN="$RUST_VERSION"
export npm_config_cache="$work/npm-cache"
export NPROC=4 CMAKE_BUILD_PARALLEL_LEVEL=4 CARGO_BUILD_JOBS=4
export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 TMPDIR="$work/tmp"
export CFFIXED_USER_HOME="$work/carthage-home"
xcode_settings=(
  -project "$source_dir/Ring/Ring.xcodeproj" -scheme Ring -configuration Release
  -derivedDataPath "$work/derived-data"
  -clonedSourcePackagesDirPath "$work/swift-packages" -packageCachePath "$work/swift-package-cache"
  -packageAuthorizationProvider netrc -disableAutomaticPackageResolution -skipPackageUpdates
  -onlyUsePackageVersionsFromResolvedFile -skipMacroValidation -skipPackagePluginValidation
)
