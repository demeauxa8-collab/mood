# MatrixSDKCrypto — pinned official source

- Repository: https://github.com/matrix-org/matrix-rust-sdk
- Tag: `matrix-sdk-crypto-ffi-0.17.0`
- Commit: `cf099deb272f2ef44a0b8b8f7afd96004c3a822a`
- Rust: `1.93.0` (workspace MSRV: 1.93), UniFFI: 0.31.0, vodozemac: 0.10.0.
- No cryptographic source modifications. `memory-store.patch` only exposes the official MemoryStore
  through an additional UniFFI constructor for tests. The script checks the entire source diff.
  The tag is not signed; the exact commit is pinned.
- Generated Swift is committed with an automatic import-only shim for Swift
  `MemberImportVisibility` (imports all three defining FFI modules). No generated logic is changed.
  The static XCFramework is ignored (>50 MB).
- Rebuild from repository root: `./scripts/build-crypto.sh`.
- Isolated Rust homes: `~/mood-toolchains/{rustup,cargo}`. No global PATH changes.
- First install: download https://sh.rustup.rs, inspect it, then run with
  `RUSTUP_HOME="$HOME/mood-toolchains/rustup" CARGO_HOME="$HOME/mood-toolchains/cargo" sh rustup-init.sh -y --no-modify-path --profile minimal --default-toolchain 1.93.0`.
- Expected file hashes: `SHA256SUMS`; generated build manifest: `SHA256SUMS.generated`.
  Compare with `diff -u SHA256SUMS SHA256SUMS.generated`. Rust artifacts can vary with
  absolute source path, Apple SDK/linker and environment; this is a pinned-source build,
  not a claim of reproducibility across arbitrary machines.
- Based on upstream `bindings/apple/build_crypto_xcframework.sh`: static libraries,
  library-mode UniFFI generation, C headers/modulemap, `xcodebuild -create-xcframework`.
  Replaced Intel/macOS slices with arm64 Mac Catalyst; all Cargo commands use `--locked`.
- Static archive: linked into mood's executable, **do not embed** an extra dynamic framework.
- License: upstream Apache-2.0 (`LICENSE`). Transitive licenses remain those of upstream dependencies.
