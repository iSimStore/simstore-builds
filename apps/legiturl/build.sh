#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/env.sh"
start_build "$@"
xcodebuild "${xcode_settings[@]}" "${simulator_settings[@]}" -jobs 2 \
  DEBUG_INFORMATION_FORMAT= GCC_GENERATE_DEBUGGING_SYMBOLS=NO \
  COMPILATION_CACHE_ENABLE_CACHING=NO \
  CODE_SIGN_STYLE=Manual PROVISIONING_PROFILE= PROVISIONING_PROFILE_SPECIFIER= \
  ENABLE_USER_SCRIPT_SANDBOXING=NO \
  build 2>&1 | tee "$work/logs/xcode-release.log"
git -C "$source_dir" diff --exit-code
cmp "$app_dir/Package.resolved" "$resolved"
built_app="$work/derived-data/Build/Products/Release-iphonesimulator/LegitURL.app"
cmp "$source_dir/Sources/Models/DataBase/public_suffix_list.sqlite" "$built_app/public_suffix_list.sqlite"
cmp "$source_dir/Sources/Views/Screens/HelpGlossary/glossary.json" "$built_app/glossary.json"
cp "$source_dir/LICENSE.md" "$built_app/LegitURL-LICENSE.md"
{
  printf 'Upstream source: %s/tree/%s\n' "$repository" "$revision"
  printf 'Simulator recipe and patches: https://github.com/iSimStore/simstore-builds/tree/%s/apps/%s\n' \
    "$(git -C "$repo_dir" rev-parse HEAD)" "$(manifest_field id)"
  printf 'License: %s; see LegitURL-LICENSE.md.\n' "$(manifest_field source.license)"
} > "$built_app/LegitURL-SOURCE.txt"
finish_build "$built_app" LegitURL.app
