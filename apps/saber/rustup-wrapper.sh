#!/bin/bash
# Installed as build/rust-bin/rustup: hooks filter the parent Rust environment.
set -euo pipefail
work=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$work/../tools.lock"
export RUSTUP_HOME="$work/rustup" CARGO_HOME="$work/cargo" RUSTUP_TOOLCHAIN="$RUST_VERSION"
# Rust 1.97's LLVM stripping can misalign Apple LINKEDIT data; packaging uses Apple's strip.
export CARGO_PROFILE_DEV_STRIP=none CARGO_PROFILE_RELEASE_STRIP=none
exec "$CARGO_HOME/bin/rustup" "$@"
