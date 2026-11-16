#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/env.sh"
start_build "$@"
xcodebuild "${xcode_settings[@]}" "${simulator_settings[@]}" -jobs 2 \
  DEBUG_INFORMATION_FORMAT= GCC_GENERATE_DEBUGGING_SYMBOLS=NO \
  COMPILATION_CACHE_ENABLE_CACHING=NO CODE_SIGN_STYLE=Manual \
  PROVISIONING_PROFILE= PROVISIONING_PROFILE_SPECIFIER= ENABLE_USER_SCRIPT_SANDBOXING=NO \
  build 2>&1 | tee "$work/logs/xcode-release.log"
python3 "$repo_dir/scripts/check_patch.py" "$source_dir" "$app_dir/patches/simulator-build.patch"
cmp "$app_dir/Package.resolved" "$resolved"
built_app="$work/derived-data/Build/Products/Release-iphonesimulator/FSNotes iOS.app"
[[ -d "$built_app/PlugIns/FSNotes iOS Share Extension.appex" ]]
[[ -d "$built_app/PlugIns/FSNotes iOS Controls.appex" ]]
diff -qr "$source_dir/Resources/MPreview.bundle" "$built_app/MPreview.bundle"
python3 - "$built_app" <<'PY'
from pathlib import Path
import plistlib
import sys

app = Path(sys.argv[1])
assert not list(app.rglob('AvenirNext*')), 'Restricted fonts must not be bundled'
info = plistlib.loads((app / 'Info.plist').read_bytes())
assert all((app / font).is_file() for font in info['UIAppFonts'])
PY
install -m 644 "$source_dir/LICENSE" "$built_app/FSNotes-LICENSE.txt"
install -m 644 "$source_dir/Logo/License" "$built_app/FSNotes-Logo-LICENSE.txt"
python3 - "$work/packages/artifacts/libssh2prebuild/CSSH/CSSH.xcframework/ios-arm64_x86_64-simulator/Headers/libssh2.h" \
  "$built_app/libssh2-NOTICE.txt" <<'PY'
from pathlib import Path
import sys

notice = Path(sys.argv[1]).read_text().split('*/', 1)[0].removeprefix('/*').strip()
Path(sys.argv[2]).write_text(notice + '\n')
PY
python3 - "$work/packages/checkouts" "$built_app/ThirdPartyNotices" <<'PY'
from pathlib import Path
import shutil
import sys

checkouts = Path(sys.argv[1])
notices = Path(sys.argv[2])
for path in checkouts.rglob('*'):
    if '.git' in path.parts or not path.is_file():
        continue
    if path.name.lower().startswith(('license', 'licence', 'copying', 'notice', 'ofl')):
        destination = notices / path.relative_to(checkouts)
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(path, destination)
PY
{
  printf 'Upstream source: %s/tree/%s\n' "$repository" "$revision"
  printf 'Simulator recipe and patches: https://github.com/iSimStore/simstore-builds/tree/%s/apps/%s\n' \
    "$(git -C "$repo_dir" rev-parse HEAD)" "$(manifest_field id)"
  printf 'Modified to omit bundled proprietary Avenir Next fonts; existing system-font fallbacks are preserved.\n'
} > "$built_app/FSNotes-SOURCE.txt"
finish_build "$built_app" FSNotes.app
