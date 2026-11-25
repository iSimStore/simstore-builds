#!/bin/bash
app_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$app_dir/../../scripts/build-common.sh"
source "$repo_dir/scripts/cocoapods-common.sh"
source_dir="$work/source"
bun_dir="$work/toolchain/bun-darwin-aarch64"
export PATH="$bun_dir:$work/node/bin:$PATH" NODE_BINARY="$work/node/bin/node"
export BUN_INSTALL_CACHE_DIR="$work/bun-cache" TMPDIR="$work/tmp"
export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
export EXPO_PUBLIC_APP_VARIANT=production EXPO_NO_TELEMETRY=1 EXPO_NO_GIT_STATUS=1
export EXPO_NO_DOTENV=1 RCT_NO_LAUNCH_PACKAGER=1 RCT_SKIP_CACHES=1
unset EXPO_PUBLIC_SUPERWALL_ANDROID_API_KEY EXPO_PUBLIC_SUPERWALL_IOS_API_KEY
export GIT_ALLOW_PROTOCOL=https GIT_TERMINAL_PROMPT=0 GIT_CONFIG_COUNT=1
export GIT_CONFIG_KEY_0=core.logAllRefUpdates GIT_CONFIG_VALUE_0=false
