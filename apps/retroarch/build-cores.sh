#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/env.sh"
minimum=$(manifest_field build.deploymentTarget)
sdk=$(xcrun --sdk iphonesimulator --show-sdk-path)
clang=$(xcrun --sdk iphonesimulator --find clang)
clangxx=$(xcrun --sdk iphonesimulator --find clang++)
modules="$source_dir/pkg/apple/iOS/modules"
mkdir -p "$modules"
make -C "$work/nestopia-core/libretro" -j4 platform=ios-simulator-arm64 \
  CC="$clang" CXX="$clangxx" IOSSDK="$sdk" DEPLOYMENT_TARGET="$minimum" \
  2>&1 | tee "$work/logs/nestopia.log"
cp "$work/nestopia-core/libretro/nestopia_libretro_ios.dylib" "$modules/"
make -C "$work/snes9x/libretro" -j4 platform=ios-simulator-arm64 \
  CC="$clang" CXX="$clangxx" IOSSDK="$sdk" DEPLOYMENT_TARGET="$minimum" \
  2>&1 | tee "$work/logs/snes9x.log"
cp "$work/snes9x/libretro/snes9x_libretro_ios.dylib" "$modules/"
cmake -S "$work/mgba" -B "$work/mgba-build" \
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5 -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_SYSROOT="$sdk" -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET="$minimum" -DCMAKE_C_COMPILER="$clang" -DCMAKE_CXX_COMPILER="$clangxx" \
  -DBUILD_LIBRETRO=ON -DDISABLE_FRONTENDS=ON -DDISABLE_DEPS=ON \
  -DBUILD_SHARED=OFF -DBUILD_STATIC=OFF -DBUILD_GL=OFF -DBUILD_GLES2=OFF -DBUILD_GLES3=OFF \
  -DUSE_LUA=OFF -DUSE_LZMA=OFF -DUSE_ELF=OFF -DUSE_FFMPEG=OFF \
  2>&1 | tee "$work/logs/mgba-configure.log"
cmake --build "$work/mgba-build" --target mgba_libretro --parallel 4 \
  2>&1 | tee "$work/logs/mgba.log"
cp "$work/mgba-build/mgba_libretro.dylib" "$modules/mgba_libretro_ios.dylib"
