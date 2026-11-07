#!/bin/bash
app_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$app_dir/../../scripts/build-common.sh"
source "$repo_dir/scripts/cocoapods-common.sh"
source_dir="$work/source"
export PATH="$work/node/bin:$work/pnpm/bin:$PATH" NODE_BINARY="$work/node/bin/node"
export npm_config_cache="$work/npm-cache"
export RCT_NEW_ARCH_ENABLED=1 RCT_NO_LAUNCH_PACKAGER=1
# Expo's precompiled Core pod embeds local cache paths in its checksum.
export EXPO_USE_PRECOMPILED_MODULES=0
export EXTRA_PACKAGER_ARGS='--max-workers 4'
export SENTRY_DISABLE_AUTO_UPLOAD=true EXPO_NO_TELEMETRY=1 HUSKY=0
export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 TMPDIR="$work/tmp"
xcode_settings=(
  -workspace "$source_dir/ios/Chatwoot.xcworkspace" -scheme Chatwoot -configuration Release
  -derivedDataPath "$work/derived-data"
  -clonedSourcePackagesDirPath "$work/swift-packages" -packageCachePath "$work/swift-package-cache"
  -packageAuthorizationProvider netrc -disableAutomaticPackageResolution
)
