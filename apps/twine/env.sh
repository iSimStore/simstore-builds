#!/bin/bash
app_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$app_dir/../../scripts/build-common.sh"
source_dir="$work/source"
export JAVA_HOME="$work/jdk/Contents/Home"
export PATH="$JAVA_HOME/bin:$PATH"
export GRADLE_USER_HOME="$work/gradle-home"
export KONAN_DATA_DIR="$work/konan"
export JAVA_TOOL_OPTIONS="-Duser.home=$work/java-home -XX:ActiveProcessorCount=2"
export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
unset ANDROID_HOME ANDROID_SDK_ROOT
resolved="$source_dir/iosApp/iosApp.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
xcode_settings=(
  -project "$source_dir/iosApp/iosApp.xcodeproj" -scheme iosApp -configuration Release
  -derivedDataPath "$work/derived-data" -clonedSourcePackagesDirPath "$work/swift-packages"
  -packageCachePath "$work/swift-package-cache"
  -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile
)
