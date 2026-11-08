#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/env.sh"
start_build "$@"
bash "$app_dir/build-cores.sh"
# The widget retains its own iOS 16 minimum; the main app follows the manifest.
ios_settings=()
for setting in "${simulator_settings[@]}"; do
  case "$setting" in
    IPHONEOS_DEPLOYMENT_TARGET=*) ;;
    *) ios_settings+=("$setting") ;;
  esac
done
xcodebuild -project "$source_dir/pkg/apple/RetroArch_iOS13.xcodeproj" \
  -scheme 'RetroArch iOS Release' -configuration Release \
  -derivedDataPath "$work/derived-data" "${ios_settings[@]}" -jobs 4 \
  RA_IPHONEOS_DEPLOYMENT_TARGET="$deployment_target" \
  CODE_SIGN_STYLE=Manual PROVISIONING_PROFILE= PROVISIONING_PROFILE_SPECIFIER= \
  ASSETCATALOG_COMPILER_STANDALONE_ICON_BEHAVIOR=all ENABLE_USER_SCRIPT_SANDBOXING=NO \
  GCC_GENERATE_DEBUGGING_SYMBOLS=NO DEBUG_INFORMATION_FORMAT=dwarf LLVM_LTO=NO \
  build 2>&1 | tee "$work/logs/xcode-release.log"
git -C "$source_dir" diff > "$work/source.patch"
python3 "$repo_dir/scripts/check_patch.py" "$source_dir" "$app_dir/patches/simulator-build.patch"
built_app="$work/derived-data/Build/Products/Release-iphonesimulator/RetroArch.app"
for core in nestopia snes9x mgba; do
  [[ -f "$built_app/Frameworks/$core.libretro.framework/$core.libretro" ]]
done
finish_build "$built_app" RetroArch.app
