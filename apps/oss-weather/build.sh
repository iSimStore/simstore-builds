#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/env.sh"
start_build "$@"
cd "$source_dir"
yarn test 2>&1 | tee "$work/logs/upstream-tests.log"
ns --profile-dir "$work/ns-profile" package-manager set yarn2
if [[ ! -d "$source_dir/platforms/ios" ]]; then
  ns --profile-dir "$work/ns-profile" platform add ios
fi
cp "$app_dir/Podfile.lock" "$source_dir/platforms/ios/Podfile.lock"
resolved="$source_dir/platforms/ios/ossweather.xcworkspace/xcshareddata/swiftpm/Package.resolved"
mkdir -p "$(dirname "$resolved")"
cp "$app_dir/Package.resolved" "$resolved"
bundle "_${BUNDLER_VERSION}_" exec ns --profile-dir "$work/ns-profile" prepare ios --release \
  --env.adhoc --env.playStoreBuild=0 --env.sentry=0 --env.uploadSentry=0 \
  2>&1 | tee "$work/logs/prepare.log"
xcodebuild -workspace "$source_dir/platforms/ios/ossweather.xcworkspace" -scheme ossweather \
  -configuration Release -derivedDataPath "$work/derived-data" "${simulator_settings[@]}" -jobs 2 \
  -clonedSourcePackagesDirPath "$work/packages" -packageCachePath "$work/swift-package-cache" \
  -disableAutomaticPackageResolution -skipPackageUpdates -onlyUsePackageVersionsFromResolvedFile \
  -skipMacroValidation -skipPackagePluginValidation -packageAuthorizationProvider netrc \
  DEBUG_INFORMATION_FORMAT= GCC_GENERATE_DEBUGGING_SYMBOLS=NO \
  COMPILATION_CACHE_ENABLE_CACHING=NO CODE_SIGN_STYLE=Manual \
  PROVISIONING_PROFILE= PROVISIONING_PROFILE_SPECIFIER= ENABLE_USER_SCRIPT_SANDBOXING=NO \
  build 2>&1 | tee "$work/logs/xcode-release.log"
cmp "$app_dir/yarn.lock" "$source_dir/yarn.lock"
cmp "$app_dir/Package.resolved" "$resolved"
python3 - "$app_dir/Podfile.lock" "$source_dir/platforms/ios/Podfile.lock" <<'PY'
import sys
from pathlib import Path

import yaml

expected, actual = (yaml.safe_load(Path(path).read_text()) for path in sys.argv[1:])
# NativeScript puts the absolute checkout path in generated Podfile comments.
expected.pop('PODFILE CHECKSUM', None)
actual.pop('PODFILE CHECKSUM', None)
if expected != actual:
    raise SystemExit('CocoaPods changed the locked dependencies.')
PY
git -C "$source_dir" show HEAD:yarn.lock > "$source_dir/yarn.lock"
python3 "$repo_dir/scripts/check_patch.py" "$source_dir" "$app_dir/patches/simulator-build.patch"
cp "$app_dir/yarn.lock" "$source_dir/yarn.lock"
built_app="$work/derived-data/Build/Products/Release-iphonesimulator/ossweather.app"
cp "$source_dir/LICENSE" "$built_app/OSSWeather-LICENSE.txt"
{
  printf 'Upstream source: %s/tree/%s\n' "$repository" "$revision"
  printf 'Simulator recipe and patches: https://github.com/iSimStore/simstore-builds/tree/%s/apps/%s\n' \
    "$(git -C "$repo_dir" rev-parse HEAD)" "$(manifest_field id)"
  printf 'License: %s; see OSSWeather-LICENSE.txt.\n' "$(manifest_field source.license)"
} > "$built_app/OSSWeather-SOURCE.txt"
finish_build "$built_app" OSSWeather.app
