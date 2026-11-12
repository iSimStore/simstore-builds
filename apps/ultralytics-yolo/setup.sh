#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/env.sh"
setup_python
[[ $(xcodebuild -version) == "Xcode $XCODE_VERSION"$'\n'* ]] || {
  echo "Requires Xcode $XCODE_VERSION." >&2
  exit 1
}
checkout_clean "$(manifest_field source.repository)" "$(manifest_field source.revision)" "$source_dir"
mkdir -p "$work/downloads" "$source_dir/Tests/YOLOTests/Resources"
cd "$work/downloads"
while read -r checksum archive; do
  if [[ ! -f "$archive" ]]; then
    curl -fL --retry 3 --connect-timeout 15 "$MODEL_BASE_URL/$archive" -o "$archive"
  fi
  echo "$checksum  $archive" | shasum -a 256 -c -
  ditto -x -k "$archive" "$source_dir/Tests/YOLOTests/Resources"
done < "$app_dir/models.sha256"
cd "$source_dir"
bash scripts/download-models.sh
