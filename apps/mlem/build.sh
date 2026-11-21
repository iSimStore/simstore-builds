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
built_app="$work/derived-data/Build/Products/Release-iphonesimulator/Mlem.app"
install -m 644 "$source_dir/LICENSE" "$built_app/Mlem-LICENSE.txt"
install -m 644 "$source_dir/Mlem/Packages/MlemMiddleware/LICENSE" "$built_app/MlemMiddleware-LICENSE.txt"
install -m 644 "$source_dir/Mlem/App/Data/Licenses.swift" "$built_app/Mlem-ThirdPartyNotices.swift"
python3 - "$app_dir/Package.resolved" "$work/packages/checkouts" "$built_app" "$source_dir" \
  "$repository" "$revision" <<'PY'
import json
import shutil
import subprocess
import sys
from pathlib import Path

lock, checkouts, bundle, source = map(Path, sys.argv[1:5])
repository, revision = sys.argv[5:7]
pins = json.loads(lock.read_text())['pins']
for pin in pins:
    checkout = checkouts / pin['identity']
    names = ('README.md',) if pin['identity'] in ('opengraph', 'libwebp-xcode') else (
        'LICENSE', 'LICENSE.txt', 'LICENSE.md'
    )
    license_path = next(path for name in names if (path := checkout / name).is_file())
    shutil.copyfile(license_path, bundle / f"{pin['identity']}-{license_path.name}")
for name in ('COPYING', 'PATENTS', 'AUTHORS'):
    shutil.copyfile(checkouts / 'libwebp-xcode/libwebp' / name, bundle / f'libwebp-{name}')
shutil.copyfile(checkouts / 'highlightswift/Sources/HighlightSwift/HighlightJS/LICENSE.md',
                bundle / 'HighlightJS-LICENSE.md')
api_source = source / 'Mlem/Packages/MlemMiddleware/Sources/MlemMiddleware/MlemApiTypes'
api_revision = subprocess.check_output(['git', '-C', str(api_source), 'rev-parse', 'HEAD'], text=True).strip()
(bundle / 'Mlem-SOURCES.txt').write_text(
    'Modified for arm64 iOS Simulator on 2026-11-20: optional developer SwiftLint build phase removed.\n'
    f'Application source: {repository}/tree/{revision}\n'
    'Build scripts and patches: https://github.com/iSimStore/simstore-builds/tree/main/apps/mlem\n'
    f'Generated API source: https://github.com/mlemgroup/MlemApiTypes/tree/{api_revision}\n'
    + ''.join(f"{pin['identity']}: {pin['location'].removesuffix('.git')}/tree/{pin['state']['revision']}\n"
              for pin in pins)
)
PY
finish_build "$built_app" Mlem.app
