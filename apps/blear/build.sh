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
cmp "$app_dir/Package.resolved" "$resolved"
built_app="$work/derived-data/Build/Products/Release-iphonesimulator/Blear.app"
diff -qr "$source_dir/Blear/Bundled Photos" "$built_app/Bundled Photos"
install -m 644 "$source_dir/license" "$built_app/Blear-LICENSE.txt"
install -m 644 "$work/packages/checkouts/Defaults/license" "$built_app/Defaults-LICENSE.txt"
python3 - "$source_dir/Vendor/UIImageEffects/UIImageEffects.m" "$built_app/UIImageEffects-NOTICE.txt" <<'PY'
import sys
from pathlib import Path

notice = Path(sys.argv[1]).read_text().split('*/', 1)[0].removeprefix('/*').strip()
Path(sys.argv[2]).write_text(notice + '\n')
PY
{
  printf 'Upstream source: %s/tree/%s\n' "$repository" "$revision"
  printf 'Simulator recipe and patches: https://github.com/iSimStore/simstore-builds/tree/%s/apps/%s\n' \
    "$(git -C "$repo_dir" rev-parse HEAD)" "$(manifest_field id)"
  printf 'License: %s; see Blear-LICENSE.txt.\n' "$(manifest_field source.license)"
} > "$built_app/Blear-SOURCE.txt"
finish_build "$built_app" Blear.app
