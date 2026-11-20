#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/env.sh"
start_build "$@"
xcodebuild "${xcode_settings[@]}" "${simulator_settings[@]}" -jobs 2 \
  DEBUG_INFORMATION_FORMAT= GCC_GENERATE_DEBUGGING_SYMBOLS=NO \
  COMPILATION_CACHE_ENABLE_CACHING=NO CODE_SIGN_STYLE=Manual \
  PROVISIONING_PROFILE= PROVISIONING_PROFILE_SPECIFIER= ENABLE_USER_SCRIPT_SANDBOXING=NO \
  ONLY_ACTIVE_PLATFORM=YES ENABLE_BITCODE=NO VALID_ARCHS=arm64 \
  build 2>&1 | tee "$work/logs/xcode-release.log"
python3 "$repo_dir/scripts/check_patch.py" "$source_dir" "$app_dir/patches/simulator-build.patch"
python3 "$repo_dir/scripts/check_patch.py" "$clipping" "$app_dir/patches/clipping-bezier.patch"
python3 "$repo_dir/scripts/check_patch.py" "$source_dir/Submodules/mixpanel" "$app_dir/patches/mixpanel.patch"
python3 "$repo_dir/scripts/check_patch.py" "$source_dir/Submodules/AFNetworking" "$app_dir/patches/afnetworking.patch"
built_app="$work/derived-data/Build/Products/Release-iphonesimulator/LooseLeaf.app"
# Upstream's history-based scripts race Info.plist processing during incremental builds.
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$built_app/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $version" "$built_app/Info.plist"
install -m 644 "$source_dir/LICENSE" "$built_app/LooseLeaf-LICENSE.txt"
python3 - "$source_dir" "$built_app/ThirdPartyNotices" <<'PY'
from pathlib import Path
import shutil
import sys

source, notices = (Path(value) for value in sys.argv[1:])
paths = list((source / 'Project/LooseLeaf').glob('*.license'))
for root in (source / 'Submodules').iterdir():
    if not (root / '.git').exists():
        continue
    paths.extend(path for path in root.iterdir() if path.is_file() and path.name.lower().startswith(('license', 'licence', 'copying', 'notice')))
performance = source / 'Submodules/ClippingBezier/Submodules/PerformanceBezier'
paths.extend((performance / 'LICENSE', performance / 'README.md'))
paths.extend((source / 'Submodules/ClippingBezier').glob('*.license'))
paths.append(source / 'Submodules/ClippingBezier/ClippingBezier/BezierUtilsLicense')
for path in paths:
    destination = notices / path.relative_to(source)
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(path, destination)
PY
{
  printf 'Upstream source: %s/tree/%s\n' "$repository" "$revision"
  printf 'Simulator recipe and patches: https://github.com/iSimStore/simstore-builds/tree/%s/apps/loose-leaf\n' \
    "$(git -C "$repo_dir" rev-parse HEAD)"
  printf 'PerformanceBezier by Adam Wulf for Loose Leaf app: https://getlooseleaf.com/opensource/\n'
  printf 'PerformanceBezier source: https://github.com/adamwulf/PerformanceBezier/tree/%s\n' \
    "$(git -C "$performance" rev-parse HEAD)"
  printf 'Modified for arm64 iOS Simulator: scene lifecycle, system perspective transform and cache hashing; Pinterest sharing and analytics are omitted.\n'
} > "$built_app/LooseLeaf-SOURCE.txt"
finish_build "$built_app" 'Loose Leaf.app'
