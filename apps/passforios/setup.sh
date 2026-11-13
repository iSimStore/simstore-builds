#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/env.sh"
setup_python
[[ $(xcodebuild -version) == "Xcode $XCODE_VERSION"$'\n'* ]] || {
  echo "Requires Xcode $XCODE_VERSION." >&2
  exit 1
}
mkdir -p "$work/tools" "$work/go-toolchain"
archive="$work/tools/go$GO_VERSION.darwin-arm64.tar.gz"
if [[ ! -f "$archive" ]]; then
  curl --fail --location --retry 3 "https://go.dev/dl/go$GO_VERSION.darwin-arm64.tar.gz" -o "$archive"
fi
echo "$GO_SHA256  $archive" | shasum -a 256 -c -
if [[ ! -x "$work/go-toolchain/bin/go" ]]; then
  tar -xf "$archive" -C "$work/go-toolchain" --strip-components=1
fi
[[ $(go version) == "go version go$GO_VERSION darwin/arm64" ]]
checkout_patched "$(manifest_field source.repository)" "$(manifest_field source.revision)" "$source_dir" \
  "$app_dir/patches/scene-lifecycle.patch"
checkout_patched https://github.com/mssun/gopenpgp.git "$GOPENPGP_REVISION" "$gopenpgp_dir" \
  "$app_dir/patches/gopenpgp-mobile.patch"
cd "$gopenpgp_dir"
go mod download all
go mod verify
go install golang.org/x/mobile/cmd/gomobile golang.org/x/mobile/cmd/gobind
# iOS needs the pinned gobind, not gomobile init's unconditional gobind@latest download.
mkdir -p "$GOPATH/pkg/gomobile" "$source_dir/go/dist"
gomobile bind -tags mobile -target iossimulator/arm64 -iosversion "$(manifest_field build.deploymentTarget)" \
  -v -ldflags='-s -w' -o "$source_dir/go/dist/Gopenpgp.xcframework" \
  github.com/ProtonMail/gopenpgp/v2/crypto github.com/ProtonMail/gopenpgp/v2/armor \
  github.com/ProtonMail/gopenpgp/v2/constants github.com/ProtonMail/gopenpgp/v2/models \
  github.com/ProtonMail/gopenpgp/v2/subtle github.com/ProtonMail/gopenpgp/v2/helper \
  2>&1 | tee "$work/logs/gopenpgp-build.log"
python3 "$repo_dir/scripts/check_patch.py" "$gopenpgp_dir" "$app_dir/patches/gopenpgp-mobile.patch"
xcodebuild "${xcode_settings[@]}" -resolvePackageDependencies -onlyUsePackageVersionsFromResolvedFile \
  2>&1 | tee "$work/logs/resolve-packages.log"
python3 "$repo_dir/scripts/check_patch.py" "$source_dir" "$app_dir/patches/scene-lifecycle.patch"
