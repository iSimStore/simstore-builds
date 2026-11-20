#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/env.sh"
mkdir -p "$work/logs"
setup_python
[[ $(xcodebuild -version) == "Xcode $XCODE_VERSION"$'\n'* ]] || {
  echo "Requires Xcode $XCODE_VERSION." >&2
  exit 1
}
checkout_patched "$(manifest_field source.repository)" "$(manifest_field source.revision)" "$source_dir" \
  "$app_dir/patches/simulator-build.patch"
cmp "$app_dir/Package.resolved" "$resolved"
xcodebuild "${xcode_settings[@]}" -resolvePackageDependencies 2>&1 | tee "$work/logs/resolve-packages.log"
cmp "$app_dir/Package.resolved" "$resolved"
read -r perception_url perception_revision < <(python3 - "$app_dir/Package.resolved" <<'PY'
import json
import sys
from pathlib import Path

pins = json.loads(Path(sys.argv[1]).read_text())['pins']
pin = next(pin for pin in pins if pin['identity'] == 'swift-perception')
print(pin['location'], pin['state']['revision'])
PY
)
checkout_patched "$perception_url" "$perception_revision" "$work/packages/checkouts/swift-perception" \
  "$app_dir/patches/swift-perception-availability.patch"
