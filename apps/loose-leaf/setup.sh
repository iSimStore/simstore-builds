#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/env.sh"
mkdir -p "$work/logs"
setup_python
[[ $(xcodebuild -version) == "Xcode $XCODE_VERSION"$'\n'* ]]
checkout_patched "$(manifest_field source.repository)" "$(manifest_field source.revision)" "$source_dir" \
  "$app_dir/patches/simulator-build.patch"
# Fetch only actual app dependencies; skip the example and code-formatting projects.
# The source patch uses HTTPS, and command-scoped rewrites cover inherited nested GitHub URLs.
git -C "$source_dir" -c submodule.recurse=false -c fetch.recurseSubmodules=false \
  -c url.https://github.com/.insteadOf=git@github.com: \
  submodule update --init --depth 1 -- \
  Submodules/AFNetworking Submodules/ClippingBezier Submodules/ColorWithHex \
  Submodules/FXBlurView Submodules/JotUI Submodules/MMMarkdown Submodules/eppz-kit \
  Submodules/mixpanel Submodules/sskeychain Submodules/touch-chart Submodules/zip-archive
checkout_patched https://github.com/adamwulf/ClippingBezier.git \
  ae80e65942939b19645d82c7dba7e6d2389aeb6b "$clipping" "$app_dir/patches/clipping-bezier.patch"
git -C "$clipping" -c submodule.recurse=false -c fetch.recurseSubmodules=false \
  -c url.https://github.com/.insteadOf=git@github.com: \
  submodule update --init --depth 1 -- Submodules/PerformanceBezier
checkout_patched https://github.com/adamwulf/mixpanel-iphone.git \
  578cfe1f2b143265c86477a3cb787b79ad50a8a4 "$source_dir/Submodules/mixpanel" \
  "$app_dir/patches/mixpanel.patch"
checkout_patched https://github.com/AFNetworking/AFNetworking.git \
  ee89cc988e2709a025908ef952a7377ce7ba83b8 "$source_dir/Submodules/AFNetworking" \
  "$app_dir/patches/afnetworking.patch"
python3 - "$source_dir/Project/LooseLeaf" <<'PY'
from pathlib import Path
import plistlib
import re
import sys

project = Path(sys.argv[1])
template = plistlib.loads((project / 'AppIds-Template.plist').read_bytes())
(project / 'AppIds.plist').write_bytes(plistlib.dumps({key: '' for key in template}))
header = (project / 'AuthConstants-Template.h').read_text()
# All optional service integrations use empty public configuration, without local credentials.
(project / 'AuthConstants.h').write_text(re.sub(r'@"YOUR_[A-Z_]+"', '@""', header))
PY
