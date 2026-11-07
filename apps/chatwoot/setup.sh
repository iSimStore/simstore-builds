#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/env.sh"
mkdir -p "$work/tools" "$work/logs" "$work/tmp"
setup_python
[[ $(xcodebuild -version) == "Xcode $XCODE_VERSION"$'\n'* ]]
setup_cocoapods
archive="$work/tools/node-v$NODE_VERSION-darwin-arm64.tar.xz"
if [[ ! -f "$archive" ]]; then
  curl --fail --location --retry 3 \
    "https://nodejs.org/dist/v$NODE_VERSION/node-v$NODE_VERSION-darwin-arm64.tar.xz" -o "$archive.partial"
  echo "$NODE_SHA256  $archive.partial" | shasum -a 256 -c -
  mv "$archive.partial" "$archive"
fi
echo "$NODE_SHA256  $archive" | shasum -a 256 -c -
if [[ ! -x "$NODE_BINARY" ]]; then
  mkdir -p "$work/node"
  tar -xf "$archive" -C "$work/node" --strip-components=1
fi
if [[ ! -x "$work/pnpm/bin/pnpm" ]]; then
  npm install --global --prefix "$work/pnpm" "pnpm@$PNPM_VERSION" --no-audit --no-fund
fi
[[ $(node --version) == "v$NODE_VERSION" && $(pnpm --version) == "$PNPM_VERSION" ]]
node --version
pnpm --version
checkout_patched "$(manifest_field source.repository)" "$(manifest_field source.revision)" \
  "$source_dir" "$app_dir/patches/simulator-build.patch"
cd "$source_dir"
[[ $(node -p 'require("./package.json").packageManager') == "pnpm@$PNPM_VERSION" ]]
pnpm install --frozen-lockfile --prod=false --store-dir "$work/pnpm-store" \
  2>&1 | tee "$work/logs/pnpm-install.log"
# Keep the Hermes pod checksum independent of the checkout's absolute path.
if ! git apply --reverse --check --directory=node_modules/react-native "$app_dir/patches/hermes-path.patch" 2>/dev/null; then
  git apply --directory=node_modules/react-native "$app_dir/patches/hermes-path.patch"
fi
if ! git apply --reverse --check --directory=node_modules/@react-native-firebase/messaging "$app_dir/patches/firebase-optional.patch" 2>/dev/null; then
  git apply --directory=node_modules/@react-native-firebase/messaging "$app_dir/patches/firebase-optional.patch"
fi
cp .env.example .env
shasum -a 256 package.json pnpm-lock.yaml app.config.ts .env.example \
  "$app_dir/manifest.yaml" "$app_dir/tools.lock" "$app_dir/env.sh" "$app_dir/setup.sh" \
  "$app_dir/Gemfile.lock" "$app_dir/Podfile.lock" "$app_dir/patches/"*.patch \
  "$app_dir/chatwoot-ffmpeg-kit-ios-https.podspec" > "$work/native-inputs.current"
# Expo regenerates the native directory; reuse it when its inputs and Pods are unchanged.
if [[ ! -d ios/Chatwoot.xcworkspace ]] || ! cmp -s "$work/native-inputs.current" "$work/native-inputs.installed" \
  || ! cmp -s "$app_dir/Podfile.lock" ios/Podfile.lock || ! cmp -s ios/Podfile.lock ios/Pods/Manifest.lock; then
  rm -f "$work/native-inputs.installed"
  pnpm exec expo prebuild --platform ios --no-install 2>&1 | tee "$work/logs/expo-prebuild.log"
  if ! git apply --reverse --check --directory=ios "$app_dir/patches/scene-lifecycle.patch" 2>/dev/null; then
    git apply --directory=ios "$app_dir/patches/scene-lifecycle.patch"
  fi
  cp "$app_dir/chatwoot-ffmpeg-kit-ios-https.podspec" ios/
  printf 'export NODE_BINARY=%q\n' "$NODE_BINARY" > ios/.xcode.env.local
  cp "$app_dir/Podfile.lock" ios/Podfile.lock
  (cd ios && bundle exec pod install --deployment) 2>&1 | tee "$work/logs/pod-install.log"
  cp "$work/native-inputs.current" "$work/native-inputs.installed"
fi
