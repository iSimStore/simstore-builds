#!/bin/bash
app_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$app_dir/../../scripts/build-common.sh"
source "$repo_dir/scripts/cocoapods-common.sh"
source_dir="$work/source"
mobile_dir="$source_dir/apps/mobile"
export PATH="$work/node/bin:$PATH" NODE_BINARY="$work/node/bin/node"
export npm_config_cache="$work/npm-cache"
export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 TMPDIR="$work/tmp"
export HUSKY=0 THREADS=4 RCT_NO_LAUNCH_PACKAGER=1
export NN_PREBUILT_THIRD_PARTY=0
export EXTRA_PACKAGER_ARGS='--max-workers 2'
export SENTRY_DISABLE_AUTO_UPLOAD=true
export GIT_CONFIG_COUNT=2 GIT_TERMINAL_PROMPT=0
export GIT_CONFIG_KEY_0=url.https://github.com/.insteadOf GIT_CONFIG_VALUE_0=ssh://git@github.com/
export GIT_CONFIG_KEY_1=url.https://github.com/.insteadOf GIT_CONFIG_VALUE_1=git@github.com:
xcode_settings=(
  -workspace "$mobile_dir/ios/Notesnook.xcworkspace" -scheme Notesnook -configuration Release
  -derivedDataPath "$work/derived-data"
)
