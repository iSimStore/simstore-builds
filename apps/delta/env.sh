#!/bin/bash
app_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$app_dir/../../scripts/build-common.sh"
source "$repo_dir/scripts/cocoapods-common.sh"
source_dir="$work/source"
export PATH="$work/tools/git-lfs/git-lfs-$GIT_LFS_VERSION:$PATH"
export GIT_LFS_SKIP_SMUDGE=1
export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 TMPDIR="$work/tmp"
export DELTA_SYSTEMS_DERIVED_DATA="$work/systems-derived-data"
export DELTA_SYSTEMS_PACKAGES="$work/systems-packages"
export DELTA_PACKAGE_CACHE="$work/package-cache"
revenuecat_dir="$work/source-packages/checkouts/purchases-ios-spm"

check_delta_patch() {
  # Upstream tracks Pods; their regenerated contents are verified by the lockfile.
  git -C "$source_dir" diff --full-index --ignore-submodules=dirty -- . ':!Pods' > "$work/source.patch"
  cmp "$app_dir/patches/simulator-build.patch" "$work/source.patch"
}

xcode_settings=(
  -workspace "$source_dir/Delta.xcworkspace" -scheme Delta -configuration Release
  -derivedDataPath "$work/derived-data" -clonedSourcePackagesDirPath "$work/source-packages"
  -packageCachePath "$DELTA_PACKAGE_CACHE"
  -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile
)
