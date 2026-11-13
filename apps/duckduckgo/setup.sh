#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/env.sh"
setup_python
[[ $(xcodebuild -version) == "Xcode $XCODE_VERSION"$'\n'* ]] || {
  echo "Requires Xcode $XCODE_VERSION." >&2
  exit 1
}
# Public builds use the upstream-supported system-font fallback instead of Duck Sans.
checkout_patched "$(manifest_field source.repository)" "$(manifest_field source.revision)" \
  "$source_dir" "$app_dir/patches/public-build.patch"
cmp "$app_dir/Package.resolved" "$resolved"
cd "$source_dir"
xcodebuild "${xcode_settings[@]}" -resolvePackageDependencies 2>&1 | tee "$work/logs/resolve-packages.log"
cmp "$app_dir/Package.resolved" "$resolved"
