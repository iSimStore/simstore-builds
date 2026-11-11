#!/bin/bash
app_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$app_dir/../../scripts/build-common.sh"
build_root="$work/source"
source_dir="$build_root/src/brave"
export PATH="$work/tools/bin:$work/node/bin:$work/pnpm/bin:$repo_dir/build/python/bin:$source_dir/vendor/depot_tools:$PATH"
export npm_config_cache="$work/npm-cache"
export NODE_OPTIONS=--max-old-space-size=4096
export DEPOT_TOOLS_UPDATE=0 GIT_TERMINAL_PROMPT=0
export VPYTHON_VIRTUALENV_ROOT="$work/vpython"
export CIPD_CACHE_DIR="$build_root/cipd-cache"
export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
