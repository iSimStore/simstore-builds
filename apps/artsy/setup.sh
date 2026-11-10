#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/env.sh"
mkdir -p "$work/tools" "$work/logs" "$work/tmp" "$work/pod-tmp"
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
checkout_patched "$(manifest_field source.repository)" "$(manifest_field source.revision)" \
  "$source_dir" "$app_dir/patches/simulator-build.patch"
cd "$source_dir"
[[ $(cat .nvmrc) == "$NODE_VERSION" ]]
[[ $(node -p 'require("./package.json").engines.yarn') == "$YARN_VERSION" ]]
[[ $(node -p 'require("./app.json").version') == "$(manifest_field source.version)" ]]
[[ $(node --version) == "v$NODE_VERSION" ]]
[[ $(node .yarn/releases/yarn-"$YARN_VERSION".cjs --version) == "$YARN_VERSION" ]]
node .yarn/releases/yarn-"$YARN_VERSION".cjs install --immutable --mode=skip-build 2>&1 | tee "$work/logs/yarn-install.log"
if ! git apply --reverse --check --directory=node_modules/react-native "$app_dir/patches/hermes-path.patch" 2>/dev/null; then
  git apply --directory=node_modules/react-native "$app_dir/patches/hermes-path.patch"
fi
cp metaflags.example.json metaflags.json
cp "$app_dir/Echo.json" ios/Artsy/App/EchoNew.json
python3 - <<'PY'
from pathlib import Path
import json
import plistlib

keys = json.loads(Path('keys.example.json').read_text())
# Release JavaScript uses the PROD fields, while Simulator endpoints use staging.
for field in ('CLIENT_KEY', 'CLIENT_SECRET'):
    keys['secure'][f'ARTSY_PROD_API_{field}'] = keys['secure'][f'ARTSY_DEV_API_{field}']
Path('keys.shared.json').write_text(json.dumps(keys, indent=2) + '\n')
Path('ios/Artsy/GoogleService-Info.plist').write_bytes(plistlib.dumps({}))
PY
printf 'export NODE_BINARY=%q\n' "$NODE_BINARY" > ios/.xcode.env.local
node .yarn/releases/yarn-"$YARN_VERSION".cjs relay 2>&1 | tee "$work/logs/relay.log"
cmp "$app_dir/Podfile.lock" ios/Podfile.lock
(cd ios && TMPDIR="$work/pod-tmp" bundle exec pod install --deployment) 2>&1 | tee "$work/logs/pod-install.log"
for patch in ios/patches/*.diff; do
  git apply --reverse --check --directory=ios/Pods -p2 "$patch"
done
