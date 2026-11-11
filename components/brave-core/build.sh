#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/env.sh"
[[ $# == 0 ]]
mkdir -p "$work/logs" "$work/artifacts"
exec > >(tee "$work/logs/build.log") 2>&1
printf 'Preparation started: %s\n' "$(date -u +%FT%TZ)"
/usr/bin/time -l bash "$app_dir/setup.sh"
df -k "$work"
printf 'Core compilation started: %s\n' "$(date -u +%FT%TZ)"
cd "$source_dir"
/usr/bin/time -l pnpm run build Release --target_os=ios --target_arch=arm64 \
  --target_environment=simulator --target=brave_ios --ninja=local_jobs:2 \
  2>&1 | tee "$work/logs/core-build.log"
printf 'Core compilation finished: %s\n' "$(date -u +%FT%TZ)"
df -k "$work"
python3 "$app_dir/package_core.py" "$build_root/src/out/ios_Release_arm64_simulator"
