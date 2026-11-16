#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/env.sh"
mkdir -p "$work/logs"
setup_python
[[ $(xcodebuild -version) == "Xcode $XCODE_VERSION"$'\n'* ]]
checkout_patched "$(manifest_field source.repository)" "$(manifest_field source.revision)" "$source_dir" \
  "$app_dir/patches/simulator-build.patch"
cmp "$app_dir/Package.resolved" "$resolved"
xcodebuild "${xcode_settings[@]}" -resolvePackageDependencies 2>&1 | tee "$work/logs/resolve-packages.log"
cmp "$app_dir/Package.resolved" "$resolved"
