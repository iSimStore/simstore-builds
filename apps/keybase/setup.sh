#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/env.sh"
mkdir -p "$work/tools" "$work/logs" "$work/tmp"
setup_python
[[ $(xcodebuild -version) == "Xcode $XCODE_VERSION"$'\n'* ]] || {
  echo "Requires Xcode $XCODE_VERSION." >&2
  exit 1
}
setup_cocoapods
for tool in node go; do
  if [[ "$tool" == node ]]; then
    archive="$work/tools/node-v$NODE_VERSION-darwin-arm64.tar.xz"
    url="https://nodejs.org/dist/v$NODE_VERSION/$(basename "$archive")"
    digest="$NODE_SHA256"
    destination="$work/node"
  else
    archive="$work/tools/go$GO_VERSION.darwin-arm64.tar.gz"
    url="https://go.dev/dl/$(basename "$archive")"
    digest="$GO_SHA256"
    destination="$work/go-toolchain"
  fi
  if [[ ! -f "$archive" ]]; then
    curl --fail --location --retry 3 "$url" -o "$archive.partial"
    echo "$digest  $archive.partial" | shasum -a 256 -c -
    mv "$archive.partial" "$archive"
  fi
  echo "$digest  $archive" | shasum -a 256 -c -
  if [[ ! -x "$destination/bin/$tool" ]]; then
    mkdir -p "$destination"
    tar -xf "$archive" -C "$destination" --strip-components=1
  fi
done
[[ $(node --version) == "v$NODE_VERSION" ]]
[[ $(go version) == "go version go$GO_VERSION darwin/arm64" ]]
if [[ ! -x "$work/yarn/bin/yarn" ]]; then
  npm install --global --prefix "$work/yarn" "yarn@$YARN_VERSION" --ignore-scripts --no-audit --no-fund
fi
[[ $(yarn --version) == "$YARN_VERSION" ]]
checkout_patched "$(manifest_field source.repository)" "$(manifest_field source.revision)" "$source_dir" \
  "$app_dir/patches/simulator-build.patch"
cd "$source_dir/go"
go mod download
go mod verify
go install golang.org/x/mobile/cmd/gomobile golang.org/x/mobile/cmd/gobind
mkdir -p "$GOPATH/pkg/gomobile"
if [[ ! -f "$source_dir/shared/ios/keybasego.xcframework/ios-arm64-simulator/Keybasego.framework/Keybasego" ]]; then
  gomobile bind -target iossimulator/arm64 -iosversion "$(manifest_field build.deploymentTarget)" \
    -tags 'ios prerelease production' \
    -ldflags "-X github.com/keybase/client/go/libkb.PrereleaseBuild=$(manifest_field source.revision) -s -w" \
    -o "$source_dir/shared/ios/keybasego.xcframework" github.com/keybase/client/go/bind \
    2>&1 | tee "$work/logs/go-build.log"
fi
cd "$source_dir/shared"
yarn install --frozen-lockfile --ignore-optional --ignore-scripts 2>&1 | tee "$work/logs/yarn-install.log"
yarn postinstall 2>&1 | tee "$work/logs/yarn-postinstall.log"
printf 'export NODE_BINARY=%q\n' "$NODE_BINARY" > ios/.xcode.env.local
cp "$app_dir/Podfile.lock" ios/Podfile.lock
(cd ios && bundle "_${BUNDLER_VERSION}_" exec pod install --deployment) 2>&1 | tee "$work/logs/pod-install.log"
cmp "$app_dir/Podfile.lock" ios/Podfile.lock
python3 "$repo_dir/scripts/check_patch.py" "$source_dir" "$app_dir/patches/simulator-build.patch"
