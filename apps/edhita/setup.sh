#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/env.sh"
setup_python
[[ $(xcodebuild -version) == "Xcode $XCODE_VERSION"$'\n'* ]]
checkout_patched "$(manifest_field source.repository)" "$(manifest_field source.revision)" \
  "$source_dir" "$app_dir/patches/simulator-build.patch"
constants="$source_dir/Edhita/Models/Constants.swift"
if [[ -e "$constants" ]]; then
  cmp "$app_dir/Constants.swift" "$constants" || {
    echo 'Unexpected local Edhita configuration; refusing to overwrite it.' >&2
    exit 1
  }
else
  cp "$app_dir/Constants.swift" "$constants"
fi
