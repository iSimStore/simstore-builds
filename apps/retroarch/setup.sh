#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/env.sh"
setup_python
[[ $(xcodebuild -version) == "Xcode $XCODE_VERSION"$'\n'* ]]
command -v cmake >/dev/null
checkout_patched "$(manifest_field source.repository)" "$(manifest_field source.revision)" \
  "$source_dir" "$app_dir/patches/simulator-build.patch"
checkout_patched "$NESTOPIA_REPOSITORY" "$NESTOPIA_REVISION" \
  "$work/nestopia-core" "$app_dir/patches/nestopia-simulator.patch"
checkout_patched "$SNES9X_REPOSITORY" "$SNES9X_REVISION" \
  "$work/snes9x" "$app_dir/patches/snes9x-simulator.patch"
checkout_clean "$MGBA_REPOSITORY" "$MGBA_REVISION" "$work/mgba"
