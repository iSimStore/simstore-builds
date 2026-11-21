#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/env.sh"
start_build "$@"
xcodebuild "${xcode_settings[@]}" "${simulator_settings[@]}" -jobs 2 \
  DEBUG_INFORMATION_FORMAT= GCC_GENERATE_DEBUGGING_SYMBOLS=NO \
  COMPILATION_CACHE_ENABLE_CACHING=NO CODE_SIGN_STYLE=Manual \
  PROVISIONING_PROFILE= PROVISIONING_PROFILE_SPECIFIER= ENABLE_USER_SCRIPT_SANDBOXING=NO \
  build 2>&1 | tee "$work/logs/xcode-release.log"
cmp "$app_dir/Package.resolved" "$resolved"
python3 "$repo_dir/scripts/check_patch.py" "$source_dir" "$app_dir/patches/simulator-build.patch"
built_app="$work/derived-data/Build/Products/Release-iphonesimulator/WooCommerce.app"
install -m 644 "$source_dir/LICENSE" "$built_app/WooCommerce-LICENSE.txt"
python3 - "$app_dir/Package.resolved" "$work/packages/checkouts" "$built_app" "$repository" "$revision" \
  "$(git -C "$repo_dir" rev-parse HEAD)" <<'PY'
import json
import shutil
import sys
from pathlib import Path

lock, checkouts, bundle = map(Path, sys.argv[1:4])
repository, revision = sys.argv[4:6]
recipe_revision = sys.argv[6]
directories = {path.name.lower(): path for path in checkouts.iterdir() if path.is_dir()}
pins = json.loads(lock.read_text())['pins']
for pin in pins:
    checkout = directories[pin['identity']]
    for source in checkout.iterdir():
        if source.is_file() and source.name.upper().startswith(('LICENSE', 'LICENCE', 'COPYING', 'NOTICE', 'THIRD_PARTY_NOTICES')):
            shutil.copyfile(source, bundle / f"{pin['identity']}-{source.name}")
(bundle / 'WooCommerce-SOURCES.txt').write_text(
    'Modified for arm64 iOS Simulator on 2026-11-20: removed card-present SDKs, Star printer SDK and Zendesk integration; disabled developer lint and watchOS embedding; public self-hosted configuration.\n'
    f'Application source: {repository}/tree/{revision}\n'
    f'Build scripts and patches: https://github.com/iSimStore/simstore-builds/tree/{recipe_revision}/apps/woocommerce\n'
    + ''.join(f"{pin['identity']}: {pin['location'].removesuffix('.git')}/tree/{pin['state']['revision']}\n"
              for pin in pins)
)
PY
finish_build "$built_app" WooCommerce.app
