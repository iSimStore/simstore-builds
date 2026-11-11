#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/env.sh"
mkdir -p "$work/logs" "$work/tmp"
setup_python
setup_cocoapods
[[ $(xcodebuild -version) == "Xcode $XCODE_VERSION"$'\n'* ]]
checkout_patched "$(manifest_field source.repository)" "$(manifest_field source.revision)" \
  "$source_dir" "$app_dir/patches/simulator-build.patch"
checkout_flutter "$app_dir/patches/flutter-spm.patch"
[[ $(git -C "$source_dir" rev-parse HEAD:submodules/flutter) == "$FLUTTER_REVISION" ]]
flutter --version --machine > "$work/logs/flutter-version.json"
check_locks
cd "$source_dir"
bundle exec flutter pub get --enforce-lockfile 2>&1 | tee "$work/logs/pub-get.log"
bundle exec flutter build ios --simulator --debug --config-only --no-codesign --no-pub \
  2>&1 | tee "$work/logs/flutter-config.log"
xcodebuild "${xcode_settings[@]}" -resolvePackageDependencies \
  -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile \
  2>&1 | tee "$work/logs/resolve-packages.log"
check_locks
