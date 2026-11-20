#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/env.sh"
start_build "$@"
xcodebuild "${xcode_settings[@]}" "${simulator_settings[@]}" -jobs 2 \
  DEBUG_INFORMATION_FORMAT= GCC_GENERATE_DEBUGGING_SYMBOLS=NO \
  ENABLE_THREAD_SANITIZER=NO CLANG_ENABLE_CODE_COVERAGE=NO \
  COMPILATION_CACHE_ENABLE_CACHING=NO CODE_SIGN_STYLE=Manual \
  PROVISIONING_PROFILE= PROVISIONING_PROFILE_SPECIFIER= ENABLE_USER_SCRIPT_SANDBOXING=NO \
  build 2>&1 | tee "$work/logs/xcode-release.log"
cmp "$app_dir/Package.resolved" "$resolved"
python3 "$repo_dir/scripts/check_patch.py" "$source_dir" "$app_dir/patches/simulator-build.patch"
python3 "$repo_dir/scripts/check_patch.py" "$work/packages/checkouts/swift-perception" \
  "$app_dir/patches/swift-perception-availability.patch"
built_app="$work/derived-data/Build/Products/Release-iphonesimulator/Critical Maps.app"
install -m 644 "$source_dir/LICENSE" "$built_app/CriticalMaps-LICENSE.txt"
python3 - "$app_dir/Package.resolved" "$work/packages/checkouts" "$built_app" <<'PY'
import json
import shutil
import sys
from pathlib import Path

lock, checkouts, bundle = map(Path, sys.argv[1:])
pins = json.loads(lock.read_text())['pins']
for pin in pins:
    checkout = checkouts / pin['identity']
    license_path = next(path for name in ('LICENSE', 'LICENSE.txt')
                        if (path := checkout / name).is_file())
    shutil.copyfile(license_path, bundle / f"{pin['identity']}-LICENSE.txt")
    for notice in checkout.glob('NOTICE*'):
        if notice.is_file():
            shutil.copyfile(notice, bundle / f"{pin['identity']}-{notice.name}")
(bundle / 'CriticalMaps-DEPENDENCIES.txt').write_text(''.join(
    f"{pin['identity']}: {pin['location'].removesuffix('.git')}/tree/{pin['state']['revision']}\n"
    for pin in pins
))
PY
finish_build "$built_app" 'Critical Maps.app'
