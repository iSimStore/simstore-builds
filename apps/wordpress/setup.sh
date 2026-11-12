#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/env.sh"
setup_python
python3 -m unittest discover -s "$app_dir" -p 'test_*.py' -v
[[ $(xcodebuild -version) == "Xcode $XCODE_VERSION"$'\n'* ]] || {
  echo "Requires Xcode $XCODE_VERSION." >&2
  exit 1
}
checkout_patched "$(manifest_field source.repository)" "$(manifest_field source.revision)" \
  "$source_dir" "$app_dir/patches/simulator-build.patch"
mkdir -p "$work/downloads" "$work/logs"
python3 - "$source_dir/Scripts/download-gutenberg-xcframeworks.sh" "$GUTENBERG_VERSION" <<'PY'
from pathlib import Path
import re
import sys

match = re.search(r'^VERSION="([^"]+)"$', Path(sys.argv[1]).read_text(), re.MULTILINE)
if match is None or match[1] != sys.argv[2]:
    sys.exit('Gutenberg version does not match the pinned upstream release')
PY
archive="$work/downloads/Gutenberg-$GUTENBERG_VERSION.tar.gz"
if [[ ! -f "$archive" ]]; then
  curl --fail --location --retry 3 --remove-on-error \
    "https://cdn.a8c-ci.services/gutenberg-mobile/Gutenberg-$GUTENBERG_VERSION.tar.gz" -o "$archive"
fi
echo "$GUTENBERG_SHA256  $archive" | shasum -a 256 -c -
frameworks="$source_dir/WordPress/Frameworks"
mkdir -p "$frameworks"
tar -xzf "$archive" -C "$frameworks" --strip-components=1
mkdir -p "$frameworks/hermes.xcframework/ios-arm64/dSYMs" \
  "$frameworks/hermes.xcframework/ios-arm64_x86_64-simulator/dSYMs"
# Xcode lists this optional input even when the public template is selected.
local_secrets="$source_dir/WordPress/Credentials/Secrets.swift"
example_secrets="$source_dir/WordPress/Credentials/Secrets-example.swift"
if [[ -e "$local_secrets" ]]; then
  cmp "$example_secrets" "$local_secrets"
else
  cp "$example_secrets" "$local_secrets"
fi
mkdir -p "$(dirname "$resolved")"
if [[ -e "$resolved" ]]; then
  cmp "$app_dir/Package.resolved" "$resolved"
else
  cp "$app_dir/Package.resolved" "$resolved"
fi
cd "$source_dir"
xcodebuild "${xcode_settings[@]}" -resolvePackageDependencies 2>&1 | tee "$work/logs/resolve-packages.log"
cmp "$app_dir/Package.resolved" "$resolved"
