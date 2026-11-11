#!/bin/bash
app_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$app_dir/../../scripts/build-common.sh"
source_dir="$work/brave-core"
core_dir="$work/out/ios_Release_arm64_simulator"
export PATH="$work/node/bin:$work/pnpm/bin:$PATH"
export npm_config_cache="$work/npm-cache"
export NODE_OPTIONS=--max-old-space-size=4096
export GIT_TERMINAL_PROMPT=0
export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
