#!/bin/bash
# Builds and runs a standalone CLI; never launches Mood or touches server configuration.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BASE="${MOOD_TOOLCHAINS:-$HOME/mood-toolchains}"
export RUSTUP_HOME="$BASE/rustup" CARGO_HOME="$BASE/cargo" RUSTUP_TOOLCHAIN=1.93.0
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export PATH="$CARGO_HOME/bin:$PATH" CARGO_TARGET_DIR="$BASE/crypto-target"
SRC="$BASE/matrix-rust-sdk"
[ "$(git -C "$SRC" rev-parse HEAD)" = cf099deb272f2ef44a0b8b8f7afd96004c3a822a ]
git -C "$SRC" diff --binary | cmp - "$ROOT/mood/Vendor/MatrixSDKCrypto/memory-store.patch"
[ -z "$(git -C "$SRC" ls-files --others --exclude-standard)" ]
cd "$SRC"
cargo build --locked --release -p matrix-sdk-crypto-ffi --lib
mkdir -p "$ROOT/build/O1"
SWIFT_SOURCES=()
while IFS= read -r -d '' source; do SWIFT_SOURCES+=("$source"); done < <(find "$ROOT/mood/Vendor/MatrixSDKCrypto" -maxdepth 1 -name '*.swift' -print0)
xcrun swiftc -swift-version 5 -parse-as-library \
  "${SWIFT_SOURCES[@]}" "$ROOT/server/e2ee-check.swift" \
  -I "$BASE/crypto-generated/headers" "$CARGO_TARGET_DIR/release/libmatrix_sdk_crypto_ffi.a" \
  -framework Security -framework SystemConfiguration -lresolv -liconv \
  -o "$ROOT/build/O1/e2ee-check"
"$ROOT/build/O1/e2ee-check"
