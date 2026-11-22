#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/env.sh"
setup_python
[[ $(xcodebuild -version) == "Xcode $XCODE_VERSION"$'\n'* ]]
checkout_patched "$(manifest_field source.repository)" "$(manifest_field source.revision)" \
  "$source_dir" "$app_dir/patches/simulator.patch"
checkout_flutter
python3 - "$source_dir/.fvmrc" "$FLUTTER_VERSION" <<'PY'
import json
import sys
from pathlib import Path

assert json.loads(Path(sys.argv[1]).read_text())["flutter"] == sys.argv[2]
PY
cd "$source_dir"
plugin_version=$(python3 - "$source_dir/pubspec.lock" <<'PY'
import sys
from pathlib import Path

import yaml

print(
    yaml.safe_load(Path(sys.argv[1]).read_text())["packages"]["onnxruntime"]["version"]
)
PY
)
dart pub cache add onnxruntime --version "$plugin_version"
plugin_dir="$PUB_CACHE/hosted/pub.dev/onnxruntime-$plugin_version"
chmod u+w "$plugin_dir/pubspec.yaml"
if patch -s -f -N -F 0 -p1 --dry-run -d "$plugin_dir" < "$app_dir/patches/onnxruntime-no-ios.patch" >/dev/null 2>&1; then
  patch -s -f -N -F 0 -p1 -d "$plugin_dir" < "$app_dir/patches/onnxruntime-no-ios.patch"
else
  patch -s -f -R -F 0 -p1 --dry-run -d "$plugin_dir" < "$app_dir/patches/onnxruntime-no-ios.patch"
fi
flutter pub get --enforce-lockfile 2>&1 | tee "$work/logs/pub-get.log"
cd "$source_dir/app"
flutter build ios --simulator --debug --config-only --no-codesign --no-pub \
  2>&1 | tee "$work/logs/flutter-config.log"
python3 - "$source_dir/app/.flutter-plugins-dependencies" <<'PY'
import json
import sys
from pathlib import Path

plugins = json.loads(Path(sys.argv[1]).read_text())["plugins"]["ios"]
assert all(p["name"] != "onnxruntime" for p in plugins)
PY
xcodebuild "${xcode_settings[@]}" -resolvePackageDependencies \
  2>&1 | tee "$work/logs/resolve-packages.log"
