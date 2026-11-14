#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/env.sh"
setup_python
[[ $(xcodebuild -version) == "Xcode $XCODE_VERSION"$'\n'* ]] || {
  echo "Requires Xcode $XCODE_VERSION." >&2
  exit 1
}
checkout_patched "$(manifest_field source.repository)" "$(manifest_field source.revision)" "$source_dir" \
  "$app_dir/patches/simulator-build.patch"
cp "$app_dir/Package.resolved" "$resolved"
xcodebuild "${xcode_settings[@]}" -resolvePackageDependencies 2>&1 | tee "$work/logs/resolve-packages.log"
cmp "$app_dir/Package.resolved" "$resolved"
kingfisher_revision=$(python3 - "$app_dir/Package.resolved" <<'PY'
import json
from pathlib import Path
import sys

pins = json.loads(Path(sys.argv[1]).read_text())['pins']
print(next(pin['state']['revision'] for pin in pins if pin['identity'] == 'kingfisher'))
PY
)
checkout_patched https://github.com/onevcat/Kingfisher.git "$kingfisher_revision" \
  "$work/packages/checkouts/Kingfisher" "$app_dir/patches/kingfisher-swiftui.patch"
