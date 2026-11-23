#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/env.sh"
setup_python
[[ $(xcodebuild -version) == "Xcode $XCODE_VERSION"$'\n'* ]] || {
  echo "Requires Xcode $XCODE_VERSION." >&2
  exit 1
}
checkout_patched "$(manifest_field source.repository)" "$(manifest_field source.revision)" \
  "$source_dir" "$app_dir/patches/simulator.patch"
xcodebuild "${xcode_settings[@]}" -resolvePackageDependencies
