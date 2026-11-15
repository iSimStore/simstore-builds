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
built_app="$work/derived-data/Build/Products/Release-iphonesimulator/Fontcase.app"
cmp "$source_dir/xFonts/Help.md" "$built_app/Help.md"
install -m 644 "$source_dir/License.txt" "$built_app/Fontcase-LICENSE.txt"
notices="$built_app/ThirdPartyNotices"
mkdir -p "$notices"
install -m 644 "$source_dir/xFonts/RoutingHTTPServer/LICENSE.txt" "$notices/RoutingHTTPServer.txt"
install -m 644 "$source_dir/xFonts/RoutingHTTPServer/CocoaHTTPServer/LICENSE.txt" "$notices/CocoaHTTPServer.txt"
python3 - "$source_dir" "$notices" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1]) / 'xFonts'
notices = Path(sys.argv[2])
markdown = (source / 'MarkdownAttributedString/NSAttributedString+Markdown.m').read_text()
notice = markdown[markdown.index('/*') + 2:markdown.index('*/')]
(notices / 'MarkdownAttributedString.txt').write_text(notice)
socket = (source / 'RoutingHTTPServer/CocoaHTTPServer/Vendor/CocoaAsyncSocket/GCDAsyncSocket.m').read_text()
(notices / 'CocoaAsyncSocket.txt').write_text(socket.partition('#import')[0])
PY
{
  printf 'Upstream source: %s/tree/%s\n' "$repository" "$revision"
  printf 'Simulator recipe and patches: https://github.com/iSimStore/simstore-builds/tree/%s/apps/%s\n' \
    "$(git -C "$repo_dir" rev-parse HEAD)" "$(manifest_field id)"
  printf 'Modified for the scene lifecycle, arm64 capabilities, and a fixed release build number.\n'
} > "$built_app/Fontcase-SOURCE.txt"
finish_build "$built_app" Fontcase.app
