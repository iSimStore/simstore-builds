#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/env.sh"
setup_python
[[ $(xcodebuild -version) == "Xcode $XCODE_VERSION"$'\n'* ]] || {
  echo "Requires Xcode $XCODE_VERSION." >&2
  exit 1
}
checkout_patched "$(manifest_field source.repository)" "$(manifest_field source.revision)" "$source_dir" \
  "$app_dir/patches/simulator-build.patch"
# Upstream derives its bundle build number from the complete commit history.
if [[ $(git -C "$source_dir" rev-parse --is-shallow-repository) == true ]]; then
  git -C "$source_dir" fetch --unshallow origin "$(manifest_field source.revision)"
fi
release_tag=$(manifest_field source.version)
git -C "$source_dir" fetch origin "refs/tags/$release_tag:refs/tags/$release_tag"
[[ $(git -C "$source_dir" rev-parse "$release_tag^{commit}") == "$(manifest_field source.revision)" ]]
cp "$app_dir/Package.resolved" "$resolved"
xcodebuild "${xcode_settings[@]}" -resolvePackageDependencies 2>&1 | tee "$work/logs/resolve-packages.log"
cmp "$app_dir/Package.resolved" "$resolved"
