#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/env.sh"
[[ $# == 0 ]]
archive="$work/tools/libsodium-$SODIUM_VERSION.tar.gz"
if [[ ! -f "$archive" ]]; then
  curl --fail --location --retry 3 \
    "https://download.libsodium.org/libsodium/releases/old/unsupported/libsodium-$SODIUM_VERSION.tar.gz" -o "$archive.partial"
  echo "$SODIUM_SHA256  $archive.partial" | shasum -a 256 -c -
  mv "$archive.partial" "$archive"
fi
echo "$SODIUM_SHA256  $archive" | shasum -a 256 -c -
if [[ ! -f "$work/libsodium-source/configure" ]]; then
  mkdir -p "$work/libsodium-source"
  tar -xzf "$archive" -C "$work/libsodium-source" --strip-components=1
fi
python3 - "$mobile_dir" "$SODIUM_VERSION" <<'PY'
from pathlib import Path
import re
import sys

header = Path(sys.argv[1]) / 'node_modules/@ammarahmed/react-native-sodium/libsodium/libsodium-ios/include/sodium/version.h'
assert re.search(r'#define SODIUM_VERSION_STRING "([^"]+)"', header.read_text())[1] == sys.argv[2]
PY
minimum=$(manifest_field build.deploymentTarget)
{
  shasum -a 256 "$app_dir/tools.lock" "$manifest" "$app_dir/build-sodium.sh"
  xcodebuild -version
  xcrun --sdk iphonesimulator --show-sdk-build-version
} > "$work/sodium-inputs.current"
if [[ ! -f "$work/libsodium-simulator/lib/libsodium.a" ]] || ! cmp -s "$work/sodium-inputs.current" "$work/sodium-inputs.installed"; then
  rm -rf "$work/libsodium-build" "$work/libsodium-simulator"
  mkdir -p "$work/libsodium-build"
  export SDKROOT="$(xcrun --sdk iphonesimulator --show-sdk-path)"
  export CC='xcrun --sdk iphonesimulator clang'
  export CFLAGS="-target arm64-apple-ios${minimum}-simulator -O2 -fPIC"
  cd "$work/libsodium-build"
  "$work/libsodium-source/configure" --host=aarch64-apple-darwin --build="$("$work/libsodium-source/build-aux/config.guess")" \
    --disable-shared --enable-static --with-pic --prefix="$work/libsodium-simulator" \
    > "$work/logs/sodium-configure.log" 2>&1
  make -j2 > "$work/logs/sodium-build.log" 2>&1
  make install > "$work/logs/sodium-install.log" 2>&1
  cp "$work/sodium-inputs.current" "$work/sodium-inputs.installed"
fi
python3 - "$work/libsodium-simulator/lib/libsodium.a" <<'PY'
import re
import subprocess
import sys

library = sys.argv[1]
assert subprocess.check_output(['xcrun', 'lipo', '-archs', library], text=True).strip() == 'arm64'
loads = subprocess.check_output(['xcrun', 'otool', '-l', library], text=True)
assert set(re.findall(r'\bplatform\s+(\d+)', loads)) == {'7'}, 'libsodium must target IOSSIMULATOR'
print('libsodium validated: arm64 IOSSIMULATOR')
PY
install -m 644 "$work/libsodium-simulator/lib/libsodium.a" \
  "$mobile_dir/node_modules/@ammarahmed/react-native-sodium/libsodium/libsodium-ios/lib/libsodium.a"
