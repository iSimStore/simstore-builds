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
bundle exec xcodebuild "${xcode_settings[@]}" "${ios_settings[@]}" -jobs 2 \
  DEBUG_INFORMATION_FORMAT= GCC_GENERATE_DEBUGGING_SYMBOLS=NO ENABLE_DEBUG_DYLIB=NO \
  COMPILATION_CACHE_ENABLE_CACHING=NO CODE_SIGN_STYLE=Manual \
  PROVISIONING_PROFILE= PROVISIONING_PROFILE_SPECIFIER= ENABLE_USER_SCRIPT_SANDBOXING=NO \
  FLUTTER_BUILD_MODE=debug build 2>&1 | tee "$work/logs/xcode-debug.log"
python3 "$repo_dir/scripts/check_patch.py" "$source_dir" "$app_dir/patches/simulator-build.patch"
cmp "$app_dir/Package.resolved" "$resolved"
cmp "$app_dir/Package.resolved" "$workspace_resolved"
cmp "$app_dir/Podfile.lock" ios/Podfile.lock
built_app="$work/derived-data/Build/Products/Debug-iphonesimulator/Runner.app"
[[ -s "$built_app/Frameworks/App.framework/flutter_assets/kernel_blob.bin" ]]
chmod +x "$built_app/Frameworks/PDFium.framework/PDFium"
python3 - "$source_dir" "$built_app" <<'PY'
from pathlib import Path
import sys
import yaml

source = Path(sys.argv[1])
assets = Path(sys.argv[2]) / 'Frameworks/App.framework/flutter_assets'
assert (assets / 'shaders/pencil.frag').stat().st_size > 0
for family in yaml.safe_load((source / 'pubspec.yaml').read_text())['flutter']['fonts']:
    for font in family['fonts']:
        relative = font['asset']
        assert (assets / relative).read_bytes() == (source / relative).read_bytes(), relative
for license in (source / 'assets/google_fonts').glob('*/OFL.txt'):
    assert (assets / license.relative_to(source)).read_bytes() == license.read_bytes()
PY
install -m 644 "$source_dir/LICENSE.md" "$built_app/Saber-LICENSE.txt"
notices="$built_app/ThirdPartyNotices"
mkdir -p "$notices"
install -m 644 "$source_dir/packages/onyxsdk_pen/LICENSE" "$notices/onyxsdk-pen.txt"
python3 - "$source_dir/.dart_tool/package_config.json" "$notices/pub" <<'PY'
import json
from pathlib import Path
import shutil
import sys
from urllib.parse import unquote, urljoin, urlparse

config = Path(sys.argv[1])
notices = Path(sys.argv[2])
for package in json.loads(config.read_text())['packages']:
    root = Path(unquote(urlparse(urljoin(config.as_uri(), package['rootUri'])).path))
    for path in root.iterdir():
        if path.is_file() and path.name.lower().startswith(('license', 'licence', 'copying', 'notice')):
            destination = notices / package['name'] / path.name
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(path, destination)
PY
python3 - "$CARGO_HOME" "$RUSTUP_HOME" "$notices/rust" <<'PY'
from pathlib import Path
import shutil
import sys

cargo = Path(sys.argv[1])
rustup = Path(sys.argv[2])
notices = Path(sys.argv[3])
roots = [(root, root.name) for root in cargo.glob('registry/src/*/*')]
roots.extend((root, 'toolchain') for root in rustup.glob('toolchains/*/share/doc/rust'))
for root, name in roots:
    for path in root.iterdir():
        if path.is_file() and path.name.lower().startswith(('license', 'licence', 'copying', 'notice', 'copyright')):
            destination = notices / name / path.name
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(path, destination)
PY
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
  printf 'Modified to configure Swift Package Manager integration for Simulator builds.\n'
} > "$built_app/Saber-SOURCE.txt"
finish_build "$built_app" Saber.app
