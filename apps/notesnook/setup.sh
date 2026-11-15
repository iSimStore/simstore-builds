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
[[ $(node --version) == "v$NODE_VERSION" ]]
checkout_patched "$(manifest_field source.repository)" "$(manifest_field source.revision)" \
  "$source_dir" "$app_dir/patches/simulator-build.patch"
cd "$source_dir"
python3 - "$NODE_VERSION" <<'PY'
import json
from pathlib import Path
import sys

assert json.loads(Path('package.json').read_text())['volta']['node'] == sys.argv[1]
PY
{
  git ls-files -z '*package.json' '*package-lock.json' '*/patches/*.patch' 'scripts/bootstrap.mjs' 'scripts/execute.mjs' | xargs -0 shasum -a 256
  shasum -a 256 "$app_dir/tools.lock"
} > "$work/npm-inputs.current"
if [[ ! -d "$mobile_dir/node_modules" ]] || ! cmp -s "$work/npm-inputs.current" "$work/npm-inputs.installed"; then
  rm -f "$work/npm-inputs.installed"
  npm ci --ignore-scripts --no-audit --no-fund 2>&1 | tee "$work/logs/npm-root.log"
  npm run bootstrap -- --scope=mobile 2>&1 | tee "$work/logs/npm-bootstrap.log"
  cp "$work/npm-inputs.current" "$work/npm-inputs.installed"
fi
npm run tx mobile:build 2>&1 | tee "$work/logs/workspace-build.log"
# Lingui extracts untranslated strings before compiling; retain only generated output.
git restore --source=HEAD -- packages/intl/locale
bash "$app_dir/build-sodium.sh"
printf 'export NODE_BINARY=%q\n' "$NODE_BINARY" > "$mobile_dir/ios/.xcode.env.local"
cd "$mobile_dir/ios"
bundle exec pod install --deployment 2>&1 | tee "$work/logs/pod-install.log"
