#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/env.sh"
start_build "$@"
xcodebuild "${xcode_settings[@]}" "${simulator_settings[@]}" -jobs 2 \
  DEBUG_INFORMATION_FORMAT= GCC_GENERATE_DEBUGGING_SYMBOLS=NO \
  CLANG_CXX_LANGUAGE_STANDARD=c++20 COMPILATION_CACHE_ENABLE_CACHING=NO \
  CODE_SIGN_STYLE=Manual PROVISIONING_PROFILE= PROVISIONING_PROFILE_SPECIFIER= \
  ENABLE_USER_SCRIPT_SANDBOXING=NO build 2>&1 | tee "$work/logs/xcode-release.log"
python3 "$repo_dir/scripts/check_patch.py" "$source_dir" "$app_dir/patches/simulator-build.patch"
built_app="$work/derived-data/Build/Products/Release-iphonesimulator/Notesnook.app"
[[ -s "$built_app/main.jsbundle" ]]
[[ -d "$built_app/build.bundle" ]]
[[ -d "$built_app/PlugIns/Make Note.appex" ]]
[[ -d "$built_app/PlugIns/NotesWidgetExtension.appex" ]]
for framework in React ReactNativeDependencies hermesvm; do
  chmod +x "$built_app/Frameworks/$framework.framework/$framework"
done
install -m 644 "$source_dir/LICENSE" "$built_app/Notesnook-LICENSE.txt"
notices="$built_app/ThirdPartyNotices"
mkdir -p "$notices"
install -m 644 "$mobile_dir/ios/Pods/Target Support Files/Pods-Notesnook/Pods-Notesnook-acknowledgements.plist" \
  "$notices/CocoaPods.plist"
install -m 644 "$work/libsodium-source/LICENSE" "$notices/libsodium.txt"
python3 - "$source_dir" "$notices/npm" <<'PY'
from pathlib import Path
import shutil
import sys

source = Path(sys.argv[1])
notices = Path(sys.argv[2])
roots = [source / 'apps/mobile/node_modules', *source.glob('packages/*/node_modules')]
for modules in roots:
    if not modules.is_dir():
        continue
    packages = []
    for entry in modules.iterdir():
        if entry.name.startswith('@') and entry.is_dir():
            packages.extend(entry.iterdir())
        else:
            packages.append(entry)
    for package in packages:
        if not package.is_dir() or package.name.startswith('.'):
            continue
        for path in package.iterdir():
            if path.is_file() and path.name.lower().startswith(('license', 'licence', 'copying', 'ofl')):
                destination = notices / path.relative_to(source)
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(path, destination)
PY
{
  printf 'Upstream source: %s/tree/%s\n' "$repository" "$revision"
  printf 'Simulator recipe and patches: https://github.com/iSimStore/simstore-builds/tree/%s/apps/%s\n' \
    "$(git -C "$repo_dir" rev-parse HEAD)" "$(manifest_field id)"
  printf 'Modified for the scene lifecycle and explicit Widget shared-container entitlements.\n'
  printf 'libsodium Simulator source: https://github.com/jedisct1/libsodium/tree/%s\n' "$SODIUM_REVISION"
} > "$built_app/Notesnook-SOURCE.txt"
finish_build "$built_app" Notesnook.app
