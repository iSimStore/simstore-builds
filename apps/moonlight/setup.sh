#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/env.sh"
setup_python
[[ $(xcodebuild -version) == "Xcode $XCODE_VERSION"$'\n'* ]]
checkout_patched "$(manifest_field source.repository)" "$(manifest_field source.revision)" \
  "$source_dir" "$app_dir/patches/simulator-build.patch"
git -C "$source_dir" submodule update --init --recursive
git -C "$source_dir" submodule foreach --recursive \
  'test -z "$(git status --porcelain --untracked-files=normal)"'
