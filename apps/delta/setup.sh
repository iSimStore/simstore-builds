#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/env.sh"
mkdir -p "$work/tools" "$work/logs" "$work/tmp"
setup_python
[[ $(xcodebuild -version) == "Xcode $XCODE_VERSION"$'\n'* ]]
setup_cocoapods
archive="$work/tools/git-lfs-v$GIT_LFS_VERSION.zip"
if [[ ! -f "$archive" ]]; then
  curl --fail --location --retry 3 \
    "https://github.com/git-lfs/git-lfs/releases/download/v$GIT_LFS_VERSION/git-lfs-darwin-arm64-v$GIT_LFS_VERSION.zip" -o "$archive.partial"
  echo "$GIT_LFS_SHA256  $archive.partial" | shasum -a 256 -c -
  mv "$archive.partial" "$archive"
fi
echo "$GIT_LFS_SHA256  $archive" | shasum -a 256 -c -
if [[ ! -x "$work/tools/git-lfs/git-lfs-$GIT_LFS_VERSION/git-lfs" ]]; then
  unzip -q "$archive" -d "$work/tools/git-lfs"
fi
[[ $(git-lfs version) == "git-lfs/$GIT_LFS_VERSION "* ]]
checkout "$(manifest_field source.repository)" "$(manifest_field source.revision)" "$source_dir"
if git -C "$source_dir" diff --quiet --ignore-submodules=dirty -- . ':!Pods'; then
  git -C "$source_dir" apply "$app_dir/patches/simulator-build.patch"
else
  check_delta_patch
fi
git -C "$source_dir" submodule sync --recursive
git -c url.https://git.code.sf.net/.insteadOf=git://git.code.sf.net/ \
  -C "$source_dir" submodule update --init --recursive --depth 1
git -C "$source_dir" submodule foreach --recursive '
  if test -f .gitattributes; then
    git lfs install --local --skip-smudge
    env -u GIT_LFS_SKIP_SMUDGE git lfs pull
    git lfs fsck
  fi
'
checkout_patched https://github.com/rileytestut/Harmony.git \
  "$(git -C "$source_dir" rev-parse HEAD:External/Harmony)" "$source_dir/External/Harmony" "$app_dir/patches/harmony.patch"
checkout_patched https://github.com/rileytestut/Harmony-Drive.git \
  "$(git -C "$source_dir/External/Harmony" rev-parse HEAD:Backends/Drive)" \
  "$source_dir/External/Harmony/Backends/Drive" "$app_dir/patches/harmony-drive.patch"
checkout_patched https://github.com/snes9xgit/snes9x.git \
  "$(git -C "$source_dir/Cores/SNESDeltaCore" rev-parse HEAD:snes9x)" \
  "$source_dir/Cores/SNESDeltaCore/snes9x" "$app_dir/patches/snes9x.patch"
checkout_patched https://git.code.sf.net/p/libpng/code \
  "$(git -C "$source_dir/Cores/N64DeltaCore" rev-parse HEAD:Mupen64Plus/libpng)" \
  "$source_dir/Cores/N64DeltaCore/Mupen64Plus/libpng" "$app_dir/patches/libpng.patch"
cmp "$app_dir/Podfile.lock" "$source_dir/Podfile.lock"
cmp "$app_dir/Package.resolved" "$source_dir/Delta.xcworkspace/xcshareddata/swiftpm/Package.resolved"
cmp "$app_dir/Systems.Package.resolved" "$source_dir/Systems/Systems.xcworkspace/xcshareddata/swiftpm/Package.resolved"
(cd "$source_dir" && bundle exec pod install --deployment) 2>&1 | tee "$work/logs/pod-install.log"
xcodebuild "${xcode_settings[@]}" -resolvePackageDependencies 2>&1 | tee "$work/logs/resolve-packages.log"
revenuecat_revision=$(python3 -c 'import json, sys; print(next(pin["state"]["revision"] for pin in json.load(open(sys.argv[1]))["object"]["pins"] if pin["package"] == "RevenueCat"))' "$app_dir/Package.resolved")
checkout_patched https://github.com/RevenueCat/purchases-ios-spm.git "$revenuecat_revision" \
  "$revenuecat_dir" "$app_dir/patches/revenuecat.patch"
check_delta_patch
