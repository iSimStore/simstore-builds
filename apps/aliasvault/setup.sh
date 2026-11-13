#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/env.sh"
setup_python
setup_cocoapods
setup_rust
rustup target add aarch64-apple-ios --toolchain "$RUST_VERSION"
[[ $(xcodebuild -version) == "Xcode $XCODE_VERSION"$'\n'* ]] || {
  echo "Requires Xcode $XCODE_VERSION." >&2
  exit 1
}
mkdir -p "$work/tools" "$work/node"
archive="$work/tools/node-v$NODE_VERSION-darwin-arm64.tar.xz"
if [[ ! -f "$archive" ]]; then
  curl --fail --location --retry 3 \
    "https://nodejs.org/dist/v$NODE_VERSION/node-v$NODE_VERSION-darwin-arm64.tar.xz" -o "$archive"
fi
echo "$NODE_SHA256  $archive" | shasum -a 256 -c -
if [[ ! -x "$NODE_BINARY" ]]; then
  tar -xf "$archive" -C "$work/node" --strip-components=1
fi
[[ $(node --version) == "v$NODE_VERSION" ]]
checkout_clean "$(manifest_field source.repository)" "$(manifest_field source.revision)" "$source_dir"
# Install linked packages from their committed locks before upstream build/preinstall hooks run.
for package in models vault i18n client; do
  (cd "$source_dir/core/$package" && npm ci) 2>&1 | tee "$work/logs/npm-core-$package.log"
done
(cd "$source_dir/core" && bash build-and-distribute.sh --ios) 2>&1 | tee "$work/logs/core-build.log"
cd "$mobile_dir"
npm ci 2>&1 | tee "$work/logs/npm-mobile.log"
cd ios
bundle "_${BUNDLER_VERSION}_" exec pod install --deployment 2>&1 | tee "$work/logs/pod-install.log"
git -C "$source_dir" diff --exit-code
