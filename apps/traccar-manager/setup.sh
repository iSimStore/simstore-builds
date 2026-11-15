#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/env.sh"
mkdir -p "$work/logs"
setup_python
[[ $(xcodebuild -version) == "Xcode $XCODE_VERSION"$'\n'* ]]
checkout_patched "$(manifest_field source.repository)" "$(manifest_field source.revision)" \
  "$source_dir" "$app_dir/patches/simulator-build.patch"
checkout_flutter "$app_dir/patches/flutter-spm.patch"
flutter --version --machine > "$work/logs/flutter-version.json"
cd "$source_dir"
install -m 644 "$app_dir/pubspec.lock" pubspec.lock
flutter pub get --enforce-lockfile 2>&1 | tee "$work/logs/pub-get.log"
flutter build ios --simulator --debug --config-only --no-codesign --no-pub \
  2>&1 | tee "$work/logs/flutter-config.log"
xcodebuild "${xcode_settings[@]}" -resolvePackageDependencies \
  2>&1 | tee "$work/logs/resolve-packages.log"
