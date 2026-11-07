#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/env.sh"
mkdir -p "$work/tools/bin" "$work/logs" "$work/tmp" "$CFFIXED_USER_HOME/Library/Caches"
setup_python
[[ $(xcodebuild -version) == "Xcode $XCODE_VERSION"$'\n'* ]]
missing=()
for formula in cmake ninja meson make autoconf automake libtool pkg-config nasm yasm; do
  brew list --versions "$formula" >/dev/null 2>&1 || missing+=("$formula")
done
if [[ ${#missing[@]} -gt 0 ]]; then
  brew install "${missing[@]}"
fi
setup_rust

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
[[ $(node --version) == "v$NODE_VERSION" ]]

archive="$work/tools/Carthage-$CARTHAGE_VERSION.pkg"
if [[ ! -f "$archive" ]]; then
  curl --fail --location --retry 3 \
    "https://github.com/Carthage/Carthage/releases/download/$CARTHAGE_VERSION/Carthage.pkg" -o "$archive.partial"
  echo "$CARTHAGE_SHA256  $archive.partial" | shasum -a 256 -c -
  mv "$archive.partial" "$archive"
fi
echo "$CARTHAGE_SHA256  $archive" | shasum -a 256 -c -
if [[ ! -d "$work/tools/carthage-package" ]]; then
  pkgutil --expand-full "$archive" "$work/tools/carthage-package"
fi
ln -sf ../carthage-package/CarthageApp.pkg/Payload/usr/local/bin/carthage "$work/tools/bin/carthage"
[[ $(carthage version) == "$CARTHAGE_VERSION" ]]
gas="$work/tools/bin/gas-preprocessor.pl"
if [[ ! -f "$gas" ]]; then
  curl --fail --location --retry 3 \
    "https://raw.githubusercontent.com/libav/gas-preprocessor/$GAS_PREPROCESSOR_REVISION/gas-preprocessor.pl" \
    -o "$gas.partial"
  echo "$GAS_PREPROCESSOR_SHA256  $gas.partial" | shasum -a 256 -c -
  mv "$gas.partial" "$gas"
fi
echo "$GAS_PREPROCESSOR_SHA256  $gas" | shasum -a 256 -c -
chmod +x "$gas"

checkout "$(manifest_field source.repository)" "$(manifest_field source.revision)" "$source_dir"
# The daemon's pinned revision and patch are checked separately below.
git -C "$source_dir" config diff.ignoreSubmodules dirty
checkout_patched "$(manifest_field source.repository)" "$(manifest_field source.revision)" \
  "$source_dir" "$app_dir/patches/simulator-build.patch"
[[ $(git -C "$source_dir" rev-parse HEAD:daemon) == "$DAEMON_REVISION" ]]
git -C "$source_dir" submodule update --init --depth 1 daemon
checkout_patched https://review.jami.net/jami-daemon "$DAEMON_REVISION" \
  "$source_dir/daemon" "$app_dir/patches/daemon-simulator.patch"
cd "$source_dir/Ring"
# Carthage's build action requires an installed runtime; checkout needs only its lockfile.
carthage bootstrap --no-build --platform iOS --no-use-binaries
mkdir -p Ring.xcodeproj/project.xcworkspace/xcshareddata/swiftpm
cp "$app_dir/Package.resolved" Ring.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
xcodebuild "${xcode_settings[@]}" -resolvePackageDependencies
cd CollabEditor
npm ci --no-audit --no-fund
