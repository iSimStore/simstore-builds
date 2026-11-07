#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/env.sh"
setup_python
[[ $(xcodebuild -version) == "Xcode $XCODE_VERSION"$'\n'* ]]
checkout_clean "$(manifest_field source.repository)" "$(manifest_field source.revision)" "$source_dir"
# Zulip uses Flutter main. Keep enough history and an official tag for version detection,
# without checking out the engine sources bundled in the Flutter monorepo.
if [[ ! -d "$work/flutter" ]]; then
  git init "$work/flutter"
  git -C "$work/flutter" remote add origin https://github.com/flutter/flutter
  git -C "$work/flutter" sparse-checkout init --no-cone
  git -C "$work/flutter" sparse-checkout set '/*' '!/engine/'
  git -C "$work/flutter" fetch --filter=blob:none --depth 512 origin "$FLUTTER_REVISION" \
    "refs/tags/$FLUTTER_BASE_TAG:refs/tags/$FLUTTER_BASE_TAG"
  git -C "$work/flutter" switch -C main "$FLUTTER_REVISION"
fi
checkout_clean https://github.com/flutter/flutter "$FLUTTER_REVISION" "$work/flutter"
flutter --version 2>&1 | tee "$work/logs/flutter-bootstrap.log"
flutter --version --machine > "$work/logs/flutter-version.json"
python3 - "$work/logs/flutter-version.json" "$FLUTTER_VERSION" "$FLUTTER_REVISION" <<'PY'
import json
from pathlib import Path
import sys

version = json.loads(Path(sys.argv[1]).read_text())
assert version['frameworkVersion'] == sys.argv[2], version
assert version['frameworkRevision'] == sys.argv[3], version
PY
setup_cocoapods
cd "$source_dir"
flutter pub get --enforce-lockfile 2>&1 | tee "$work/logs/pub-get.log"
bundle exec flutter build ios --simulator --debug --config-only --no-codesign --no-pub \
  2>&1 | tee "$work/logs/flutter-config.log"
cd ios
bundle exec pod install --deployment 2>&1 | tee "$work/logs/pod-install.log"
