#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/env.sh"
setup_python
setup_cocoapods
[[ $(xcodebuild -version) == "Xcode $XCODE_VERSION"$'\n'* ]]
checkout_patched "$(manifest_field source.repository)" "$(manifest_field source.revision)" \
  "$source_dir" "$app_dir/patches/simulator-build.patch"
checkout_flutter
flutter --version --machine > "$work/logs/flutter-version.json"
cd "$source_dir"
cp .env.rb .env
flutter pub get --enforce-lockfile 2>&1 | tee "$work/logs/pub-get.log"
dart run flutter_iconpicker:generate_packs --packs fontAwesomeIcons \
  2>&1 | tee "$work/logs/icon-packs.log"
# Download Rive's pinned native libraries before Xcode computes its input graph.
dart run rive_native:setup --platform ios --verbose 2>&1 | tee "$work/logs/rive-setup.log"
IPHONEOS_DEPLOYMENT_TARGET="$(manifest_field build.deploymentTarget)" \
  bundle exec flutter build ios --simulator --debug --config-only --no-codesign --no-pub \
  2>&1 | tee "$work/logs/flutter-config.log"
