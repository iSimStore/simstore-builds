#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/env.sh"
setup_python
[[ $(xcodebuild -version) == "Xcode $XCODE_VERSION"$'\n'* ]]
checkout_patched "$(manifest_field source.repository)" "$(manifest_field source.revision)" \
  "$source_dir" "$app_dir/patches/simulator-build.patch"
# Xcode reads the base configuration reference even for a Release build.
template="$source_dir/BuildConfiguration/Debug.template.xcconfig"
configuration="$source_dir/BuildConfiguration/Debug.xcconfig"
if [[ -e "$configuration" ]]; then
  cmp "$template" "$configuration" || {
    echo 'Unexpected local BookPlayer configuration; refusing to overwrite it.' >&2
    exit 1
  }
else
  cp "$template" "$configuration"
fi
