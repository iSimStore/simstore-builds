#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/env.sh"
mkdir -p "$work/tools/bin" "$work/logs" "$work/tmp" "$work/cli"
setup_python
[[ $(xcodebuild -version) == "Xcode $XCODE_VERSION"$'\n'* ]]
archive="$work/tools/node-v$NODE_VERSION-darwin-arm64.tar.xz"
if [[ ! -f "$archive" ]]; then
  curl --fail --location --retry 3 "https://nodejs.org/dist/v$NODE_VERSION/$(basename "$archive")" -o "$archive.partial"
  echo "$NODE_SHA256  $archive.partial" | shasum -a 256 -c -
  mv "$archive.partial" "$archive"
fi
echo "$NODE_SHA256  $archive" | shasum -a 256 -c -
if [[ ! -x "$work/node/bin/node" ]]; then
  mkdir -p "$work/node"
  tar -xf "$archive" -C "$work/node" --strip-components=1
fi
[[ $(node --version) == "v$NODE_VERSION" ]]
corepack enable --install-directory "$work/tools/bin"
ln -sf yarn "$work/tools/bin/yarn2"
cp "$app_dir/cli/package.json" "$app_dir/cli/package-lock.json" "$work/cli/"
(cd "$work/cli" && npm ci --ignore-scripts --no-audit --no-fund) 2>&1 | tee "$work/logs/cli-install.log"
patch -d "$work/cli" -p1 < "$app_dir/patches/cli-simulator.patch"
setup_cocoapods
checkout "$(manifest_field source.repository)" "$(manifest_field source.revision)" "$source_dir"
# Restore only the known lockfile before verifying the source patch.
if cmp -s "$app_dir/yarn.lock" "$source_dir/yarn.lock"; then
  git -C "$source_dir" show HEAD:yarn.lock > "$source_dir/yarn.lock"
fi
checkout_patched "$(manifest_field source.repository)" "$(manifest_field source.revision)" "$source_dir" \
  "$app_dir/patches/simulator-build.patch"
git -C "$source_dir" submodule update --init --recursive
cp "$app_dir/yarn.lock" "$source_dir/yarn.lock"
cd "$source_dir"
yarn install --immutable 2>&1 | tee "$work/logs/yarn-install.log"
