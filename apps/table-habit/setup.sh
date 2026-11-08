#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/env.sh"
setup_python
[[ $(xcodebuild -version) == "Xcode $XCODE_VERSION"$'\n'* ]]
checkout_clean "$(manifest_field source.repository)" "$(manifest_field source.revision)" "$source_dir"
checkout_flutter "$app_dir/patches/flutter-spm.patch"
python3 - "$source_dir/.fvmrc" "$FLUTTER_VERSION" <<'PY'
import json
from pathlib import Path
import sys

assert json.loads(Path(sys.argv[1]).read_text())['flutterSdkVersion'] == sys.argv[2]
PY
flutter --version --machine > "$work/logs/flutter-version.json"
flutter config --no-analytics
cd "$source_dir"
flutter pub get --enforce-lockfile 2>&1 | tee "$work/logs/pub-get.log"
flutter build ios --simulator --debug --flavor f_generic --config-only --no-codesign --no-pub \
  2>&1 | tee "$work/logs/flutter-config.log"
xcodebuild "${xcode_settings[@]}" -resolvePackageDependencies \
  2>&1 | tee "$work/logs/resolve-packages.log"
