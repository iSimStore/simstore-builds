#!/bin/bash
app_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$app_dir/../../scripts/build-common.sh"
source "$repo_dir/scripts/cocoapods-common.sh"
source_dir="$work/source"
export PATH="$work/node/bin:$PATH" NODE_BINARY="$work/node/bin/node"
export npm_config_cache="$work/npm-cache" YARN_CACHE_FOLDER="$work/yarn-cache"
export YARN_NM_MODE=hardlinks-local
export YARN_GLOBAL_FOLDER="$work/yarn-global" COREPACK_ENABLE_DOWNLOAD_PROMPT=0
export RCT_NEW_ARCH_ENABLED=1 RCT_NO_LAUNCH_PACKAGER=1
export RCT_SKIP_CACHES=1
export KEYSFILE=keys.shared.json
export SENTRY_DISABLE_AUTO_UPLOAD=true EXPO_NO_TELEMETRY=1 HUSKY=0
export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 TMPDIR="$work/tmp"
file_limit=$(ulimit -n)
if [[ "$file_limit" != unlimited ]] && (( file_limit < 8192 )); then
  ulimit -n 8192
fi
