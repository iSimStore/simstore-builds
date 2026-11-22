#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/env.sh"
start_build "$@"
xcodebuild "${xcode_settings[@]}" "${simulator_settings[@]}" -jobs 2 \
  -disableAutomaticPackageResolution -skipPackageUpdates \
  CODE_SIGN_ENTITLEMENTS= CODE_SIGN_STYLE=Manual \
  PROVISIONING_PROFILE= PROVISIONING_PROFILE_SPECIFIER= \
  ENABLE_USER_SCRIPT_SANDBOXING=NO COMPILATION_CACHE_ENABLE_CACHING=NO \
  DEBUG_INFORMATION_FORMAT=dwarf GCC_GENERATE_DEBUGGING_SYMBOLS=NO \
  build 2>&1 | tee "$work/logs/xcode-release.log"
python3 "$repo_dir/scripts/check_patch.py" "$source_dir" "$app_dir/patches/simulator.patch"
built_app="$work/derived-data/Build/Products/Release-iphonesimulator/iBurn.app"
python3 - "$source_dir" "$work/packages/checkouts" "$built_app/ThirdPartyNotices" <<'PY'
import shutil
import sys
from pathlib import Path

source, packages, notices = map(Path, sys.argv[1:])
roots = [
    source,
    *(source / "Submodules").iterdir(),
    *(source / "Pods").iterdir(),
    *packages.iterdir(),
]
for root in roots:
    if not root.is_dir():
        continue
    for path in root.iterdir():
        if path.is_file() and path.name.lower().startswith(
            ("license", "licence", "copying", "notice")
        ):
            destination = notices / root.name / path.name
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(path, destination)
shutil.copyfile(source / "README.md", notices / "iBurn-README.md")
PY
install -m 644 "$work/maplibre-LICENSE.md" "$built_app/ThirdPartyNotices/MapLibre-iOS-LICENSE.md"
ditto "$work/geocoder-notices" "$built_app/ThirdPartyNotices/geocoder"
rm -f "$built_app/ThirdPartyNotices/geocoder/.complete" "$built_app/ThirdPartyNotices/geocoder/.complete-with-process"
install -m 644 "$work/geocoder-source/LICENSE" "$built_app/ThirdPartyNotices/geocoder/LICENSE"
{
  printf 'Upstream source: %s/tree/%s\n' "$repository" "$revision"
  printf 'Simulator recipe and patches: https://github.com/iSimStore/simstore-builds/tree/%s/apps/iburn\n' \
    "$(git -C "$repo_dir" rev-parse HEAD)"
  printf 'Modified on 2026-11-22 for Simulator lifecycle and standalone configuration; Firebase integrations omitted.\n'
  printf 'Bundled data and geocoder source: https://github.com/iBurnApp/iBurn-Data/tree/%s\n' \
    "$(git -C "$source_dir/Submodules/iBurn-Data" rev-parse HEAD)"
  printf 'Geocoder implementation and dependency source lock: https://github.com/iBurnApp/BlackRockCityPlanner/tree/%s\n' \
    "$(git -C "$work/geocoder-source" rev-parse HEAD)"
} > "$built_app/iBurn-SOURCE.txt"
finish_build "$built_app" iBurn.app
