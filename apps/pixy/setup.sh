#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/env.sh"
mkdir -p "$work/tools" "$work/logs" "$TMPDIR"
setup_python
[[ $(xcodebuild -version) == "Xcode $XCODE_VERSION"$'\n'* ]]

download_verified() {
  local url=$1 archive=$2 checksum=$3
  if [[ ! -f "$archive" ]]; then
    curl --fail --location --retry 3 "$url" -o "$archive.partial"
    printf '%s  %s\n' "$checksum" "$archive.partial" | shasum -a 256 -c -
    mv "$archive.partial" "$archive"
  fi
  printf '%s  %s\n' "$checksum" "$archive" | shasum -a 256 -c -
}

bun_archive="$work/tools/bun-$BUN_VERSION.zip"
download_verified "https://github.com/oven-sh/bun/releases/download/bun-v$BUN_VERSION/bun-darwin-aarch64.zip" \
  "$bun_archive" "$BUN_SHA256"
if [[ ! -x "$bun_dir/bun" ]]; then
  unzip -q "$bun_archive" -d "$work/toolchain"
fi
[[ $(bun --version) == "$BUN_VERSION" ]]

node_archive="$work/tools/node-v$NODE_VERSION-darwin-arm64.tar.xz"
download_verified "https://nodejs.org/dist/v$NODE_VERSION/$(basename "$node_archive")" "$node_archive" "$NODE_SHA256"
if [[ ! -x "$NODE_BINARY" ]]; then
  mkdir -p "$work/node"
  tar -xf "$node_archive" -C "$work/node" --strip-components=1
fi
[[ $(node --version) == "v$NODE_VERSION" ]]

revision=$(manifest_field source.revision)
repository=$(manifest_field source.repository)
archive="$work/tools/source-$revision.tar.gz"
download_verified "https://codeload.github.com/${repository#https://github.com/}/tar.gz/$revision" \
  "$archive" "$SOURCE_SHA256"

mkdir -p "$work/notices"
for notice in "${NATIVE_NOTICES[@]}"; do
  read -r name url checksum <<< "$notice"
  download_verified "$url" "$work/notices/$name" "$checksum"
done
aom_archive="$work/tools/libaom-3.0.0.tar.gz"
download_verified "https://storage.googleapis.com/aom-releases/$(basename "$aom_archive")" \
  "$aom_archive" "$AOM_SOURCE_SHA256"
tar -xOf "$aom_archive" LICENSE > "$work/notices/libaom-LICENSE.txt"
tar -xOf "$aom_archive" PATENTS > "$work/notices/libaom-PATENTS.txt"

inputs=$(shasum -a 256 "$app_dir/tools.lock" "$app_dir/patches/simulator.patch" "$app_dir/bun.lock")
if [[ ! -d "$source_dir" || ! -f "$work/source-inputs" || $(cat "$work/source-inputs") != "$inputs" ]]; then
  staging=$(mktemp -d "$work/source.XXXXXX")
  trap 'rm -rf "$staging"' EXIT
  tar -xzf "$archive" -C "$staging" --strip-components=1
  patch -d "$staging" -p1 --batch --forward < "$app_dir/patches/simulator.patch"
  cp "$app_dir/bun.lock" "$staging/bun.lock"
  rm -rf "$source_dir"
  mv "$staging" "$source_dir"
  printf '%s\n' "$inputs" > "$work/source-inputs"
fi

cd "$source_dir"
bun install --frozen-lockfile --ignore-scripts 2>&1 | tee "$work/logs/bun-install.log"
bun run licenses
node_modules/.bin/expo prebuild --clean --platform ios --no-install 2>&1 | tee "$work/logs/prebuild.log"
/usr/libexec/PlistBuddy -c 'Delete :aps-environment' ios/Pixy/Pixy.entitlements
printf 'export NODE_BINARY=%q\n' "$NODE_BINARY" > ios/.xcode.env.local

setup_cocoapods
cp "$app_dir/Podfile.lock" ios/Podfile.lock
cd ios
bundle exec pod install 2>&1 | tee "$work/logs/pod-install.log"
# These podspecs embed the absolute checkout path in their build scripts.
diff -u \
  <(sed -E '/^  (ExpoModulesCore|ExpoWidgets): [[:xdigit:]]{40}$/d' "$app_dir/Podfile.lock") \
  <(sed -E '/^  (ExpoModulesCore|ExpoWidgets): [[:xdigit:]]{40}$/d' Podfile.lock)
