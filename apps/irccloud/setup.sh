#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/env.sh"
mkdir -p "$work/logs"
setup_python
[[ $(xcodebuild -version) == "Xcode $XCODE_VERSION"$'\n'* ]]
setup_cocoapods
checkout_patched "$(manifest_field source.repository)" "$(manifest_field source.revision)" \
  "$source_dir" "$app_dir/patches/simulator-build.patch"
checkout_clean https://github.com/webmproject/libwebp "$WEBP_REVISION" "$work/webp-source"
grep -Fq "AC_INIT([libwebp], [$WEBP_VERSION]," "$work/webp-source/configure.ac"
cmake -S "$work/webp-source" -B "$work/webp-build" \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_OSX_SYSROOT=iphonesimulator -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET="$(manifest_field build.deploymentTarget)" \
  -DBUILD_SHARED_LIBS=OFF -DWEBP_LINK_STATIC=ON \
  -DWEBP_BUILD_ANIM_UTILS=OFF -DWEBP_BUILD_CWEBP=OFF -DWEBP_BUILD_DWEBP=OFF \
  -DWEBP_BUILD_GIF2WEBP=OFF -DWEBP_BUILD_IMG2WEBP=OFF -DWEBP_BUILD_VWEBP=OFF \
  -DWEBP_BUILD_WEBPINFO=OFF -DWEBP_BUILD_WEBPMUX=OFF -DWEBP_BUILD_EXTRAS=OFF \
  2>&1 | tee "$work/logs/webp-config.log"
cmake --build "$work/webp-build" --parallel 4 2>&1 | tee "$work/logs/webp-build.log"
framework="$work/webp-framework/WebP.framework"
mkdir -p "$framework/Headers"
cp "$work/webp-source/src/webp/"*.h "$framework/Headers/"
xcrun libtool -static -o "$framework/WebP" \
  "$work/webp-build/libwebp.a" "$work/webp-build/libwebpdemux.a" \
  "$work/webp-build/libwebpmux.a" "$work/webp-build/libsharpyuv.a"
cd "$source_dir"
cp "$app_dir/Podfile.lock" Podfile.lock
bundle exec pod install --deployment 2>&1 | tee "$work/logs/pod-install.log"
