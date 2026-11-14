#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/env.sh"
mkdir -p "$work/tools" "$work/logs"
setup_python
[[ $(xcodebuild -version) == "Xcode $XCODE_VERSION"$'\n'* ]] || {
  echo "Requires Xcode $XCODE_VERSION." >&2
  exit 1
}
archive="$work/tools/xcodegen-$XCODEGEN_VERSION.zip"
if [[ ! -f "$archive" ]]; then
  curl --fail --location --retry 3 \
    "https://github.com/yonaskolb/XcodeGen/releases/download/$XCODEGEN_VERSION/xcodegen.zip" -o "$archive.partial"
  echo "$XCODEGEN_SHA256  $archive.partial" | shasum -a 256 -c -
  mv "$archive.partial" "$archive"
fi
echo "$XCODEGEN_SHA256  $archive" | shasum -a 256 -c -
if [[ ! -x "$work/tools/xcodegen/bin/xcodegen" ]]; then
  ditto -x -k "$archive" "$work/tools"
fi
xcodegen --version
checkout_clean "$(manifest_field source.repository)" "$(manifest_field source.revision)" "$source_dir"
archive="$work/tools/corekiwix.tar.gz"
if [[ ! -f "$archive" ]]; then
  curl --fail --location --retry 3 \
    "https://download.kiwix.org/release/libkiwix/libkiwix_xcframework-$COREKIWIX_VERSION.tar.gz" -o "$archive.partial"
  echo "$COREKIWIX_SHA256  $archive.partial" | shasum -a 256 -c -
  mv "$archive.partial" "$archive"
fi
echo "$COREKIWIX_SHA256  $archive" | shasum -a 256 -c -
if [[ ! -d "$source_dir/CoreKiwix.xcframework" ]]; then
  tar -xzf "$archive" -C "$source_dir" --strip-components=2
fi
for headers in "$source_dir"/CoreKiwix.xcframework/*/Headers; do
  cp "$source_dir/Support/CoreKiwix.modulemap" "$headers/module.modulemap"
done
cd "$source_dir"
python3 localizations.py validate 2>&1 | tee "$work/logs/localizations.log"
python3 localizations.py generate
xcodegen
mkdir -p "$(dirname "$resolved")"
cp "$app_dir/Package.resolved" "$resolved"
xcodebuild "${xcode_settings[@]}" -resolvePackageDependencies 2>&1 | tee "$work/logs/resolve-packages.log"
cmp "$app_dir/Package.resolved" "$resolved"
