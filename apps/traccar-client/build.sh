#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/env.sh"
start_build "$@"
cd "$source_dir"
ios_settings=()
for setting in "${simulator_settings[@]}"; do
  case "$setting" in
    IPHONEOS_DEPLOYMENT_TARGET=*) ;;
    *) ios_settings+=("$setting") ;;
  esac
done
xcodebuild "${xcode_settings[@]}" "${ios_settings[@]}" -jobs 2 \
  -disableAutomaticPackageResolution -skipPackageUpdates -onlyUsePackageVersionsFromResolvedFile \
  DEBUG_INFORMATION_FORMAT= GCC_GENERATE_DEBUGGING_SYMBOLS=NO \
  LD_GENERATE_MAP_FILE=YES ENABLE_DEBUG_DYLIB=NO \
  COMPILATION_CACHE_ENABLE_CACHING=NO CODE_SIGN_STYLE=Manual \
  PROVISIONING_PROFILE= PROVISIONING_PROFILE_SPECIFIER= ENABLE_USER_SCRIPT_SANDBOXING=NO \
  FLUTTER_BUILD_MODE=debug build 2>&1 | tee "$work/logs/xcode-debug.log"
cmp pubspec.lock "$app_dir/pubspec.lock"
python3 "$repo_dir/scripts/check_patch.py" "$source_dir" "$app_dir/patches/simulator-build.patch"
built_app="$work/derived-data/Build/Products/Debug-iphonesimulator/Runner.app"
[[ -s "$built_app/Frameworks/App.framework/flutter_assets/kernel_blob.bin" ]]
python3 - "$work/derived-data/Build/Intermediates.noindex" <<'PY'
from pathlib import Path
import sys

maps = list(Path(sys.argv[1]).rglob('Runner-LinkMap-*-arm64.txt'))
assert len(maps) == 1, f'Expected one app link map, found {len(maps)}'
objects = maps[0].read_bytes().partition(b'# Sections:')[0]
for forbidden in (b'firebase_analytics', b'/FirebaseAnalytics', b'/GoogleAppMeasurement', b'/GoogleAdsOnDeviceConversion'):
    assert forbidden not in objects, f'Non-open-source Analytics code was linked: {forbidden}'
assert b'TraccarClientSDK' in objects, 'The tracking SDK is missing from the app link map'
print('Tracking SDK linked; no Firebase Analytics or Google measurement/conversion objects linked.')
PY
install -m 644 "$source_dir/LICENSE.txt" "$built_app/TraccarClient-LICENSE.txt"
notices="$built_app/ThirdPartyNotices"
mkdir -p "$notices"
for dependency in "$source_dir/build/ios/SourcePackages/checkouts/"*; do
  for name in LICENSE LICENSE.txt LICENSE.md NOTICE NOTICE.txt; do
    if [[ -f "$dependency/$name" ]]; then
      install -m 644 "$dependency/$name" "$notices/$(basename "$dependency")-$name"
    fi
  done
done
{
  printf 'Upstream source: %s/tree/%s\n' "$repository" "$revision"
  printf 'Simulator recipe and patches: https://github.com/iSimStore/simstore-builds/tree/%s/apps/%s\n' \
    "$(git -C "$repo_dir" rev-parse HEAD)" "$(manifest_field id)"
  printf 'Modified to omit the non-open-source Firebase Analytics dependency and skip Simulator symbol uploads.\n'
} > "$built_app/TraccarClient-SOURCE.txt"
finish_build "$built_app" TraccarClient.app
