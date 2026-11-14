#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/env.sh"
start_build "$@"
xcodebuild "${xcode_settings[@]}" "${simulator_settings[@]}" -jobs 2 \
  DEBUG_INFORMATION_FORMAT= GCC_GENERATE_DEBUGGING_SYMBOLS=NO \
  COMPILATION_CACHE_ENABLE_CACHING=NO CODE_SIGN_STYLE=Manual \
  PROVISIONING_PROFILE= PROVISIONING_PROFILE_SPECIFIER= ENABLE_USER_SCRIPT_SANDBOXING=NO \
  build 2>&1 | tee "$work/logs/xcode-release.log"
python3 "$repo_dir/scripts/check_patch.py" "$source_dir" "$app_dir/patches/simulator-build.patch"
built_app="$work/derived-data/Build/Products/Release-iphonesimulator/Prey.app"
python3 - "$built_app/Prey" <<'PY'
import subprocess
import sys

dependencies = subprocess.check_output(['xcrun', 'otool', '-L', sys.argv[1]], text=True)
if 'libclang_rt.' in dependencies:
    raise SystemExit('Release app unexpectedly links a sanitizer runtime.')
PY
diff -qr "$source_dir/Prey/ReactViews" "$built_app/ReactViews"
install -m 644 "$source_dir/LICENSE" "$built_app/Prey-LICENSE.txt"
{
  printf 'Upstream source: %s/tree/%s\n' "$repository" "$revision"
  printf 'Simulator recipe and patches: https://github.com/iSimStore/simstore-builds/tree/%s/apps/%s\n' \
    "$(git -C "$repo_dir" rev-parse HEAD)" "$(manifest_field id)"
  printf 'License: %s; see Prey-LICENSE.txt.\n' "$(manifest_field source.license)"
  printf 'The upstream public Simulator configuration excludes the private LocationPushService extension.\n'
} > "$built_app/Prey-SOURCE.txt"
finish_build "$built_app" Prey.app
