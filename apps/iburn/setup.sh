#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/env.sh"
setup_python
[[ $(xcodebuild -version) == "Xcode $XCODE_VERSION"$'\n'* ]] || {
  echo "Requires Xcode $XCODE_VERSION." >&2
  exit 1
}
checkout_patched "$(manifest_field source.repository)" "$(manifest_field source.revision)" \
  "$source_dir" "$app_dir/patches/simulator.patch"
git -C "$source_dir" submodule sync -- Submodules/ASDayPicker Submodules/DOFavoriteButton \
  Submodules/PermissionScope Submodules/YapDatabase
git -C "$source_dir" -c submodule.recurse=false -c fetch.recurseSubmodules=false \
  submodule update --init --depth 1 -- Submodules/ASDayPicker Submodules/DOFavoriteButton \
  Submodules/PermissionScope Submodules/YapDatabase
data_dir="$source_dir/Submodules/iBurn-Data"
data_revision=$(git -C "$source_dir" rev-parse HEAD:Submodules/iBurn-Data)
if [[ ! -e "$data_dir/.git" ]]; then
  git init "$data_dir"
  git -C "$data_dir" remote add origin https://github.com/iBurnApp/iBurn-Data.git
  git -C "$data_dir" sparse-checkout init --cone
  git -C "$data_dir" sparse-checkout set data/2026
  git -C "$data_dir" -c fetch.recurseSubmodules=false -c submodule.recurse=false \
    fetch --filter=blob:none --depth 1 origin "$data_revision"
  git -C "$data_dir" -c submodule.recurse=false checkout --detach FETCH_HEAD
fi
[[ $(git -C "$data_dir" rev-parse HEAD) == "$data_revision" ]]
[[ -z $(git -C "$data_dir" status --porcelain) ]]
[[ ! -e "$data_dir/data/2026/APIData/APIData.bundle/MOCK_LOCATIONS" ]]
geocoder_revision=$(git -C "$data_dir" rev-parse HEAD:scripts/BlackRockCityPlanner)
checkout_clean https://github.com/iBurnApp/BlackRockCityPlanner.git "$geocoder_revision" "$work/geocoder-source"
if [[ ! -e "$work/geocoder-notices/.complete-with-process" ]]; then
  python3 "$app_dir/prepare_notices.py" "$work/geocoder-source/package-lock.json" "$work/geocoder-notices" \
    "$GEOCODER_PROCESS_VERSION" "$GEOCODER_PROCESS_SHA512"
  touch "$work/geocoder-notices/.complete-with-process"
fi
setup_cocoapods
cd "$source_dir"
bundle "_${BUNDLER_VERSION}_" exec pod install --deployment
xcodebuild "${xcode_settings[@]}" -resolvePackageDependencies \
  -onlyUsePackageVersionsFromResolvedFile 2>&1 | tee "$work/logs/resolve.log"
maplibre_version=$(python3 - "$source_dir/iBurn.xcworkspace/xcshareddata/swiftpm/Package.resolved" <<'PY'
import json
import sys
from pathlib import Path

pins = json.loads(Path(sys.argv[1]).read_text())["pins"]
print(
    next(
        pin["state"]["version"]
        for pin in pins
        if pin["identity"] == "maplibre-gl-native-distribution"
    )
)
PY
)
curl --fail --location --silent --show-error \
  "https://raw.githubusercontent.com/maplibre/maplibre-native/ios-v$maplibre_version/platform/ios/LICENSE.md" \
  -o "$work/maplibre-LICENSE.md"
printf '%s  %s\n' "$MAPLIBRE_NOTICE_SHA256" "$work/maplibre-LICENSE.md" | shasum -a 256 -c -
