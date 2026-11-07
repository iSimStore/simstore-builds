#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/env.sh"
checkouts="$source_dir/Ring/Carthage/Checkouts"
products="$work/framework-products"
destination="$source_dir/Ring/Carthage/Build"
mkdir -p "$products" "$destination"

build_framework() {
  local project=$1 scheme=$2
  echo "Building $scheme for arm64 iOS Simulator"
  xcodebuild -project "$checkouts/$project" -scheme "$scheme" -configuration Release \
    -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -jobs 4 \
    -derivedDataPath "$work/framework-derived-data" -xcconfig "$app_dir/simulator.xcconfig" \
    CONFIGURATION_BUILD_DIR="$products" FRAMEWORK_SEARCH_PATHS="$products \$(inherited)" \
    COMPILER_INDEX_STORE_ENABLE=NO build
}

build_framework RxSwift/Rx.xcodeproj RxCocoa
build_framework RxSwift/Rx.xcodeproj RxBlocking
build_framework RxDataSources/RxDataSources.xcodeproj RxDataSources
build_framework Reusable/Example/Pods/Pods.xcodeproj Reusable-iOS
build_framework SwiftyBeaver/SwiftyBeaver.xcodeproj SwiftyBeaver-Package
build_framework AMPopTip/AMPopTip.xcodeproj AMPopTip
build_framework GSKStretchyHeaderView/GSKStretchyHeaderView/GSKStretchyHeaderView.xcodeproj GSKStretchyHeaderView
build_framework SQLite.swift/SQLite.xcodeproj 'SQLite iOS'

for framework in "$products/"*.framework; do
  name=$(basename "$framework" .framework)
  rm -rf "$destination/$name.xcframework"
  xcodebuild -create-xcframework -framework "$framework" -output "$destination/$name.xcframework"
done
