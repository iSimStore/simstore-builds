#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/env.sh"
mkdir -p "$work/tools" "$work/logs" "$build_root/src"
setup_python
[[ $(xcodebuild -version) == "Xcode $XCODE_VERSION"$'\n'"Build version $XCODE_BUILD_VERSION" ]]
[[ $(xcrun --sdk iphonesimulator --show-sdk-version) == "$SDK_VERSION" ]]
archive="$work/tools/node-v$NODE_VERSION-darwin-arm64.tar.xz"
if [[ ! -f "$archive" ]]; then
  curl --fail --location --retry 3 \
    "https://nodejs.org/dist/v$NODE_VERSION/node-v$NODE_VERSION-darwin-arm64.tar.xz" -o "$archive.partial"
  echo "$NODE_SHA256  $archive.partial" | shasum -a 256 -c -
  mv "$archive.partial" "$archive"
fi
echo "$NODE_SHA256  $archive" | shasum -a 256 -c -
if [[ ! -x "$work/node/bin/node" ]]; then
  mkdir -p "$work/node"
  tar -xf "$archive" -C "$work/node" --strip-components=1
fi
if [[ ! -x "$work/pnpm/bin/pnpm" ]]; then
  npm install --global --prefix "$work/pnpm" "pnpm@$PNPM_VERSION" --no-audit --no-fund
fi
[[ $(node --version) == "v$NODE_VERSION" && $(pnpm --version) == "$PNPM_VERSION" ]]
checkout "$(manifest_field source.repository)" "$(manifest_field source.revision)" "$source_dir"
[[ $(node -p "require('$source_dir/package.json').version") == "$(manifest_field source.version | sed 's/^v//')" ]]
checkout https://chromium.googlesource.com/chromium/tools/depot_tools.git \
  "$DEPOT_TOOLS_REVISION" "$source_dir/vendor/depot_tools"
if [[ ! -x "$source_dir/vendor/depot_tools/vpython3" ]] || \
  [[ ! -f "$source_dir/vendor/depot_tools/.disable_auto_update" ]]; then
  bash "$source_dir/vendor/depot_tools/ensure_bootstrap"
fi
printf '%s\n' "$DEPOT_TOOLS_REVISION" > "$source_dir/vendor/depot_tools/.disable_auto_update"
cat "$app_dir/build.env" > "$source_dir/.env"
printf 'projects_depot_tools_revision=%s\nprojects_chrome_revision=%s\n' \
  "$DEPOT_TOOLS_REVISION" "$CHROMIUM_REVISION" >> "$source_dir/.env"
# Configure sparse checkout before Chromium's first worktree checkout.
if [[ ! -d "$build_root/src/.git" ]]; then
  git init "$build_root/src"
  git -C "$build_root/src" remote add origin https://chromium.googlesource.com/chromium/src.git
  git -C "$build_root/src" config core.sparseCheckout true
  cp "$app_dir/sparse-checkout" "$build_root/src/.git/info/sparse-checkout"
  git -C "$build_root/src" fetch --depth 1 --filter=blob:none origin "$CHROMIUM_REVISION"
  git -C "$build_root/src" checkout --detach FETCH_HEAD
fi
[[ $(git -C "$build_root/src" rev-parse HEAD) == "$CHROMIUM_REVISION" ]]
cd "$source_dir"
pnpm install --frozen-lockfile --store-dir "$work/pnpm-store" \
  2>&1 | tee "$work/logs/pnpm-install.log"
node build/commands/scripts/sync.ts --target_os=ios --target_arch=arm64 --no-history \
  2>&1 | tee "$work/logs/sync.log"
[[ $(git -C "$build_root/src" rev-parse HEAD) == "$CHROMIUM_REVISION" ]]
