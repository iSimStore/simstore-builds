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
built_app="$work/derived-data/Build/Products/Release-iphonesimulator/OwnTracks.app"
for schema in message messages encryption; do
  cmp "$source_dir/OwnTracks/OwnTracks/$schema.json" "$built_app/$schema.json"
done
install -m 644 "$source_dir/LICENSE" "$built_app/OwnTracks-LICENSE.txt"
install -m 644 "$work/packages/checkouts/swift-sodium/LICENSE" "$built_app/Sodium-LICENSE.txt"
install -m 644 "$work/packages/checkouts/JSONSchemaValidation/LICENSE" "$built_app/JSONSchemaValidation-LICENSE.txt"
install -m 644 "$app_dir/licenses/EPL-1.0.txt" "$built_app/MQTTClient-EPL-1.0.txt"
python3 - "$work/packages/checkouts/MQTTClient/Sources/MQTTClient/MQTTMessage.m" \
  "$app_dir/Package.resolved" "$built_app" <<'PY'
import json
import sys
from pathlib import Path

source, lock, bundle = map(Path, sys.argv[1:])
notice = source.read_text().split('#import', 1)[0].strip()
(bundle / 'MQTTClient-NOTICE.txt').write_text(notice + '\n')
dependencies = json.loads(lock.read_text())['pins']
(bundle / 'OwnTracks-DEPENDENCIES.txt').write_text(''.join(
    f"{pin['identity']}: {pin['location'].removesuffix('.git')}/tree/{pin['state']['revision']}\n"
    for pin in dependencies
))
PY
{
  printf 'Upstream source: %s/tree/%s\n' "$repository" "$revision"
  printf 'Simulator recipe and patches: https://github.com/iSimStore/simstore-builds/tree/%s/apps/%s\n' \
    "$(git -C "$repo_dir" rev-parse HEAD)" "$(manifest_field id)"
  printf 'License: %s; see OwnTracks-LICENSE.txt.\n' "$(manifest_field source.license)"
} > "$built_app/OwnTracks-SOURCE.txt"
finish_build "$built_app" OwnTracks.app
