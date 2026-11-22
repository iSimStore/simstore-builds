#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/env.sh"
start_build "$@"
xcodebuild "${xcode_settings[@]}" "${simulator_settings[@]}" -jobs 2 \
  -disableAutomaticPackageResolution -skipPackageUpdates \
  CODE_SIGN_STYLE=Manual PROVISIONING_PROFILE= PROVISIONING_PROFILE_SPECIFIER= \
  ENABLE_USER_SCRIPT_SANDBOXING=NO FLUTTER_BUILD_MODE=debug \
  build 2>&1 | tee "$work/logs/xcode-debug.log"
python3 "$repo_dir/scripts/check_patch.py" "$source_dir" "$app_dir/patches/simulator.patch"
built_app="$work/derived-data/Build/Products/Debug-iphonesimulator/Runner.app"
[[ -s "$built_app/Frameworks/App.framework/flutter_assets/kernel_blob.bin" ]]
python3 - "$source_dir" "$PUB_CACHE/hosted/pub.dev" "$work/flutter" "$built_app/ThirdPartyNotices" <<'PY'
import shutil
import sys
from pathlib import Path

source, cache, flutter, notices = map(Path, sys.argv[1:])
roots = [(source, "DartPDF"), (flutter, "Flutter")]
roots.extend((p, p.name) for p in cache.iterdir() if p.is_dir())
for root, name in roots:
    for path in root.iterdir():
        if path.is_file() and path.name.lower().startswith(
            ("license", "licence", "copying", "notice")
        ):
            destination = notices / name / path.name
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(path, destination)
fonts = source / "packages/dart_pdf_editor_assets/assets/fonts"
for path in fonts.glob("*LICENSE*"):
    destination = notices / "fonts" / path.name
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(path, destination)
for path in cache.glob("mime-*/third_party/httpd/LICENSE"):
    destination = notices / "mime-httpd" / path.name
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(path, destination)
PY
{
  printf 'Upstream source: %s/tree/%s\n' "$repository" "$revision"
  printf 'Simulator recipe and patches: https://github.com/iSimStore/simstore-builds/tree/%s/apps/dartpdf\n' \
    "$(git -C "$repo_dir" rev-parse HEAD)"
  printf 'Modified to omit native OCR and its unavailable iOS SDK and use Swift Package Manager.\n'
} > "$built_app/DartPDF-SOURCE.txt"
finish_build "$built_app" DartPDF.app
