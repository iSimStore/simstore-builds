#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/env.sh"
setup_python
[[ $(xcodebuild -version) == "Xcode $XCODE_VERSION"$'\n'* ]] || {
  echo "Requires Xcode $XCODE_VERSION." >&2
  exit 1
}
checkout_clean "$(manifest_field source.repository)" "$(manifest_field source.revision)" "$source_dir"
xcodebuild "${xcode_settings[@]}" -resolvePackageDependencies -onlyUsePackageVersionsFromResolvedFile \
  2>&1 | tee "$work/logs/resolve-packages.log"
git -C "$source_dir" diff --exit-code
