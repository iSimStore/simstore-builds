#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/env.sh"
mkdir -p "$work/tools" "$work/logs" "$work/out"
setup_python
[[ $(xcodebuild -version) == "Xcode $XCODE_VERSION"$'\n'"Build version $XCODE_BUILD_VERSION" ]]
[[ $(xcrun --sdk iphonesimulator --show-sdk-version) == "$SDK_VERSION" ]]
download() {
  local url=$1 destination=$2 digest=$3
  if [[ ! -f "$destination" ]]; then
    curl --fail --location --retry 3 "$url" -o "$destination.partial"
    mv "$destination.partial" "$destination"
  fi
  echo "$digest  $destination" | shasum -a 256 -c -
}
archive="$work/tools/node-v$NODE_VERSION-darwin-arm64.tar.xz"
download "https://nodejs.org/dist/v$NODE_VERSION/node-v$NODE_VERSION-darwin-arm64.tar.xz" "$archive" "$NODE_SHA256"
if [[ ! -x "$work/node/bin/node" ]]; then
  mkdir -p "$work/node"
  tar -xf "$archive" -C "$work/node" --strip-components=1
fi
if [[ ! -x "$work/pnpm/bin/pnpm" ]]; then
  npm install --global --prefix "$work/pnpm" "pnpm@$PNPM_VERSION" --no-audit --no-fund
fi
[[ $(node --version) == "v$NODE_VERSION" && $(pnpm --version) == "$PNPM_VERSION" ]]
checkout_patched "$(manifest_field source.repository)" "$(manifest_field source.revision)" \
  "$source_dir" "$app_dir/source.patch"
[[ $(node -p 'require(process.argv[1]).version' "$source_dir/package.json") == "${CORE_VERSION#v}" ]]
archive="$work/tools/brave-core-$CORE_VERSION.tar.bz2"
download "https://github.com/iSimStore/simstore-builds/releases/download/brave-core/$CORE_VERSION/brave-core.tar.bz2" \
  "$archive" "$CORE_SHA256"
if [[ ! -f "$core_dir/.archive-sha256" ]] || [[ $(cat "$core_dir/.archive-sha256") != "$CORE_SHA256" ]]; then
  staging=$(mktemp -d "$work/core.XXXXXX")
  trap 'rm -rf "$staging"' EXIT
  tar -xjf "$archive" -C "$staging"
  for framework in BraveCore NalaAssets PartitionAllocSupport; do
    [[ -f "$staging/$framework.xcframework/Info.plist" ]]
  done
  [[ -f "$staging/args.xcconfig" ]]
  printf '%s\n' "$CORE_SHA256" > "$staging/.archive-sha256"
  rm -rf "$core_dir"
  mv "$staging" "$core_dir"
  trap - EXIT
fi
ln -sfn "$(basename "$core_dir")" "$work/out/ios_current_link"
cd "$source_dir"
pnpm install --frozen-lockfile --store-dir "$work/pnpm-store" \
  2>&1 | tee "$work/logs/pnpm-install.log"
pnpm exec webpack --config ios/brave-ios/webpack.config.js \
  2>&1 | tee "$work/logs/webpack.log"
