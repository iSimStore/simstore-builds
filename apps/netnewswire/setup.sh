#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/env.sh"
setup_python
[[ $(xcodebuild -version) == "Xcode $XCODE_VERSION"$'\n'* ]]
checkout_patched "$(manifest_field source.repository)" "$(manifest_field source.revision)" \
  "$source_dir" "$app_dir/patches/simulator-build.patch"
check_locks
# SwiftPM must see generated sources when it first constructs the package graph.
PROJECT_DIR="$source_dir" bash "$source_dir/buildscripts/updateSecrets.sh"
xcodebuild "${xcode_settings[@]}" -resolvePackageDependencies 2>&1 | tee "$work/logs/resolve-packages.log"
check_locks
