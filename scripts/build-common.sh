#!/bin/bash
# Shared environment and build steps; source after setting app_dir.
repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
work="$app_dir/build"
manifest="$app_dir/manifest.yaml"
source "$app_dir/tools.lock"
if [[ $(uname -s) != Darwin || $(uname -m) != arm64 ]]; then
  echo 'Requires Apple Silicon macOS.' >&2
  exit 1
fi
export PATH="$repo_dir/build/python/bin:$PATH"
export PIP_CACHE_DIR="$repo_dir/build/pip-cache"
export PYTHONUNBUFFERED=1 CI=true

setup_python() {
  if [[ ! -x "$repo_dir/build/python/bin/python3" ]]; then
    python3 -m venv "$repo_dir/build/python"
  fi
  "$repo_dir/build/python/bin/python3" -m pip install -r "$repo_dir/requirements.txt"
}

manifest_field() {
  python3 "$repo_dir/scripts/manifest.py" "$manifest" --field "$1"
}

start_build() {
  if [[ $# != 0 ]]; then
    echo 'Usage: bash build.sh' >&2
    exit 2
  fi
  mkdir -p "$work/logs"
  exec > >(tee "$work/logs/build.log") 2>&1
  bash "$app_dir/setup.sh"
  repository=$(manifest_field source.repository)
  revision=$(manifest_field source.revision)
  version=$(manifest_field source.version)
  deployment_target=$(manifest_field build.deploymentTarget)
  strip_symbols=$(manifest_field build.stripSymbols)
  simulator_settings=(
    -destination 'generic/platform=iOS Simulator'
    ARCHS=arm64 ONLY_ACTIVE_ARCH=YES
    IPHONEOS_DEPLOYMENT_TARGET="$deployment_target"
    CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=YES CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=
    COMPILER_INDEX_STORE_ENABLE=NO
  )
  echo "Source revision: $revision"
  xcodebuild -version
}

# Callers check local changes according to their source and patch requirements.
checkout() {
  local url=$1 revision=$2 dest=$3
  if [[ ! -d "$dest" ]]; then
    git init "$dest"
    git -C "$dest" remote add origin "$url"
    git -C "$dest" fetch --depth 1 origin "$revision"
    git -C "$dest" checkout --detach FETCH_HEAD
  fi
  [[ $(git -C "$dest" rev-parse HEAD) == "$revision" ]] || {
    echo "Unexpected revision at $dest; use a separate clean checkout." >&2
    exit 1
  }
}

checkout_clean() {
  checkout "$@"
  local dest=$3
  [[ -z $(git -C "$dest" status --porcelain --untracked-files=normal) ]] || {
    echo "Modified checkout at $dest; refusing to overwrite it." >&2
    exit 1
  }
}

checkout_patched() {
  local url=$1 revision=$2 dest=$3 patch=$4
  checkout "$url" "$revision" "$dest"
  if git -C "$dest" diff --quiet; then
    git -C "$dest" apply "$patch"
  else
    git -C "$dest" diff > "$work/source.patch"
    python3 "$repo_dir/scripts/check_patch.py" "$dest" "$patch" || {
      echo "Source checkout at $dest has unexpected changes; refusing to overwrite them." >&2
      exit 1
    }
  fi
}

finish_build() (
  built_app=$1
  bundle_name=$2
  staging=$(mktemp -d "$work/stage.XXXXXX")
  trap 'rm -rf "$staging"' EXIT
  ditto "$built_app" "$staging/$bundle_name"
  if [[ "$strip_symbols" == true ]]; then
    python3 "$repo_dir/scripts/prepare_app.py" "$staging/$bundle_name" --strip
  else
    python3 "$repo_dir/scripts/prepare_app.py" "$staging/$bundle_name"
  fi
  python3 "$repo_dir/scripts/validate.py" "$staging/$bundle_name" --manifest "$manifest" | tee "$work/logs/validation.log"
  mkdir -p "$work/output"
  # Replace only this recipe's previous output after a successful build/check.
  if [[ -e "$work/output/$bundle_name" ]]; then
    rm -rf "$work/output/$bundle_name"
  fi
  ditto "$staging/$bundle_name" "$work/output/$bundle_name"
  echo "App ready to copy: $work/output/$bundle_name"
  echo 'Local install/launch skipped; run scripts/smoke-test.sh on the target host.'
)
