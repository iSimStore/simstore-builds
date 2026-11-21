#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/env.sh"
start_build "$@"
xcodebuild "${xcode_settings[@]}" "${simulator_settings[@]}" -jobs 2 \
  DEBUG_INFORMATION_FORMAT= GCC_GENERATE_DEBUGGING_SYMBOLS=NO \
  COMPILATION_CACHE_ENABLE_CACHING=NO CODE_SIGN_STYLE=Manual \
  PROVISIONING_PROFILE= PROVISIONING_PROFILE_SPECIFIER= \
  build 2>&1 | tee "$work/logs/xcode-release.log"
[[ -z $(git -C "$source_dir" status --porcelain --untracked-files=normal) ]] || {
  echo 'Unexpected changes in the source checkout.' >&2
  exit 1
}
built_app="$work/derived-data/Build/Products/Release-iphonesimulator/Sill.app"
install -m 644 "$source_dir/LICENSE" "$built_app/Sill-LICENSE.txt"
finish_build "$built_app" Sill.app
