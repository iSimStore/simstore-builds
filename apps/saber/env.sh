#!/bin/bash
app_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$app_dir/../../scripts/build-common.sh"
source "$repo_dir/scripts/flutter-common.sh"
source_dir="$work/source"
resolved="$source_dir/ios/Runner.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
workspace_resolved="$source_dir/ios/Runner.xcworkspace/xcshareddata/swiftpm/Package.resolved"
export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
export RUSTUP_TOOLCHAIN="$RUST_VERSION"
export PATH="$work/rust-bin:$PATH"
xcode_settings=(
  -workspace "$source_dir/ios/Runner.xcworkspace" -scheme Runner -configuration Debug
  -derivedDataPath "$work/derived-data"
  -clonedSourcePackagesDirPath "$source_dir/build/ios/SourcePackages"
  -packageCachePath "$source_dir/build/ios/SwiftPackageCache"
  -packageAuthorizationProvider netrc -skipMacroValidation -skipPackagePluginValidation
)
