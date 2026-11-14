#!/bin/bash
app_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$app_dir/../../scripts/build-common.sh"
source "$repo_dir/scripts/cocoapods-common.sh"
source_dir="$work/source"
export PATH="$work/node/bin:$work/tools/bin:$work/cli/node_modules/.bin:$PATH"
export npm_config_cache="$work/npm-cache" COREPACK_HOME="$work/corepack"
export YARN_CACHE_FOLDER="$work/yarn-cache" YARN_GLOBAL_FOLDER="$work/yarn-global"
export YARN_NM_MODE=hardlinks-local YARN_ENABLE_TELEMETRY=0
export XDG_CONFIG_HOME="$work/config" TMPDIR="$work/tmp"
export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
export APP_ID=com.akylas.weather IOS_APP_ID=1499117252
export NS_CLI_ANALYTICS=0 SENTRYCLI_SKIP_DOWNLOAD=1
export OWM_DEFAULT_KEY= ATMO_DEFAULT_KEY= MAPTILER_KEY= MF_API_KEY=
