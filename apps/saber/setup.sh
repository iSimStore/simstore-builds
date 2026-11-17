#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/env.sh"
mkdir -p "$work/logs"
setup_python
[[ $(xcodebuild -version) == "Xcode $XCODE_VERSION"$'\n'* ]]
setup_cocoapods
setup_rust
mkdir -p "$work/rust-bin"
install -m 755 "$app_dir/rustup-wrapper.sh" "$work/rust-bin/rustup"
shasum -a 256 "$app_dir/rustup-wrapper.sh" "$app_dir/tools.lock" > "$work/rust-hook-inputs.current"
if ! cmp -s "$work/rust-hook-inputs.current" "$work/rust-hook-inputs.installed"; then
  python3 - "$source_dir/.dart_tool/hooks_runner/super_native_extensions" <<'PY'
from pathlib import Path
import sys

for output in Path(sys.argv[1]).glob('*/output.json'):
    output.unlink()
PY
  cp "$work/rust-hook-inputs.current" "$work/rust-hook-inputs.installed"
fi
checkout_patched "$(manifest_field source.repository)" "$(manifest_field source.revision)" "$source_dir" \
  "$app_dir/patches/simulator-build.patch"
checkout_flutter "$app_dir/patches/flutter-spm.patch"
flutter --version --machine > "$work/logs/flutter-version.json"
python3 - "$source_dir" "$FLUTTER_REVISION" <<'PY'
from pathlib import Path
import subprocess
import sys

entry = subprocess.check_output(['git', '-C', sys.argv[1], 'ls-tree', 'HEAD', 'submodules/flutter'], text=True)
assert entry.split()[2] == sys.argv[2], 'Flutter must match the pinned upstream submodule'
PY
cd "$source_dir"
flutter pub get --enforce-lockfile 2>&1 | tee "$work/logs/pub-get.log"
python3 - "$source_dir/.dart_tool/package_config.json" "$RUST_VERSION" <<'PY'
import json
from pathlib import Path
import sys
import tomllib
from urllib.parse import unquote, urljoin, urlparse

config = Path(sys.argv[1])
package = next(p for p in json.loads(config.read_text())['packages'] if p['name'] == 'super_native_extensions')
root = Path(unquote(urlparse(urljoin(config.as_uri(), package['rootUri'])).path))
assert tomllib.loads((root / 'rust/rust-toolchain.toml').read_text())['toolchain']['channel'] == sys.argv[2]
PY
mkdir -p "$(dirname "$resolved")" "$(dirname "$workspace_resolved")"
install -m 644 "$app_dir/Package.resolved" "$resolved"
install -m 644 "$app_dir/Package.resolved" "$workspace_resolved"
install -m 644 "$app_dir/Podfile.lock" ios/Podfile.lock
bundle exec flutter build ios --simulator --debug --config-only --no-codesign --no-pub \
  --dart-define='FLAVOR=App Store' --dart-define='APP_STORE=App Store' --dart-define=UPDATE_CHECK=false \
  2>&1 | tee "$work/logs/flutter-config.log"
rm -f ios/Runner.xcodeproj/project.pbxproj.backup ios/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme.backup
xcodebuild "${xcode_settings[@]}" -resolvePackageDependencies 2>&1 | tee "$work/logs/resolve-packages.log"
cmp "$app_dir/Package.resolved" "$resolved"
cmp "$app_dir/Package.resolved" "$workspace_resolved"
cmp "$app_dir/Podfile.lock" ios/Podfile.lock
