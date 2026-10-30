#!/usr/bin/env bash
# RUNS ON: Linux x86_64 CI runner (NOT on Termux, NOT on device).
# Build librust_pty (Android aarch64) for bun-pty inline sessions:
# sursaone/bun-pty at $BUN_PTY_VERSION, rust-pty crate. Bun's compile-time
# require embeds librust_pty_arm64.so, so the bionic build just overwrites
# bun-pty's glibc file before the CLI build.
#
# The opencode-pty daemon is NOT built here anymore: upstream ships a static
# musl platform package (@opencode/pty-linux-arm64-musl) that runs on bionic,
# and patches/daemon-pty-socket-android.patch points its socket root at
# $TMPDIR. vendor/opencode-pty-* remain as legacy daemons for older tags.
#
# Env: REPO_ROOT (this repo), BUN_PTY_VERSION, NDK_DIR, ANDROID_API.
# Requires: cargo + rustup target aarch64-linux-android + NDK clang.
set -euo pipefail

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
BUN_PTY_VERSION="${BUN_PTY_VERSION:-0.4.11}"
ANDROID_API="${ANDROID_API:-29}"
NDK_DIR="${NDK_DIR:-/opt/android-ndk}"
WORK="${WORK:-$REPO_ROOT/work}"
OUT="${OUT:-$REPO_ROOT/out}"
TARGET="aarch64-linux-android"

mkdir -p "$WORK" "$OUT"

command -v cargo >/dev/null || { echo "cargo missing" >&2; exit 1; }
# NOTE: do not gate on `rustup target list` here: source checkouts may pin
# their own toolchain via rust-toolchain.toml, which shadows the default
# toolchain the target was installed for. The build dir installs it itself.

TOOLCHAIN="$NDK_DIR/toolchains/llvm/prebuilt/linux-x86_64/bin"
test -x "$TOOLCHAIN/aarch64-linux-android${ANDROID_API}-clang" || \
  { echo "no NDK clang at $TOOLCHAIN" >&2; exit 1; }
export CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER="$TOOLCHAIN/aarch64-linux-android${ANDROID_API}-clang"
export CC_aarch64_linux_android="$TOOLCHAIN/aarch64-linux-android${ANDROID_API}-clang"
export AR_aarch64_linux_android="$TOOLCHAIN/llvm-ar"
export CFLAGS_aarch64_linux_android="--sysroot=$NDK_DIR/toolchains/llvm/prebuilt/linux-x86_64/sysroot"

echo "==> bun-pty v${BUN_PTY_VERSION} (librust_pty cdylib)"
if [ ! -d "$WORK/bun-pty-${BUN_PTY_VERSION}/.git" ]; then
  git clone --depth 1 --branch "v${BUN_PTY_VERSION}" https://github.com/sursaone/bun-pty.git "$WORK/bun-pty-${BUN_PTY_VERSION}"
fi
# portable-pty 0.8 pulls termios/serial (no Android target); 0.9 uses serial2.
# The rust-pty code compiles unchanged (verified on-device).
if git -C "$WORK/bun-pty-${BUN_PTY_VERSION}" apply --reverse --check "$REPO_ROOT/patches/bun-pty-portable09.patch" 2>/dev/null; then
  echo "bun-pty-portable09.patch already applied, skipping"
else
  git -C "$WORK/bun-pty-${BUN_PTY_VERSION}" apply --check "$REPO_ROOT/patches/bun-pty-portable09.patch"
  git -C "$WORK/bun-pty-${BUN_PTY_VERSION}" apply "$REPO_ROOT/patches/bun-pty-portable09.patch"
fi
(
  cd "$WORK/bun-pty-${BUN_PTY_VERSION}/rust-pty"
  rustup target add "$TARGET"
  cargo build --release --target "$TARGET"
)
CDYLIB="$WORK/bun-pty-${BUN_PTY_VERSION}/rust-pty/target/$TARGET/release/librust_pty.so"
test -f "$CDYLIB"
cp -v "$CDYLIB" "$OUT/librust_pty_arm64.so"
ls -lh "$OUT/librust_pty_arm64.so"

echo "==> verify bionic (no glibc NEEDED)"
if command -v readelf >/dev/null 2>&1; then READELF=readelf; else READELF=llvm-readelf; fi
"$READELF" -d "$OUT/librust_pty_arm64.so" | grep NEEDED
if "$READELF" -d "$OUT/librust_pty_arm64.so" | grep -q "libc.so.6"; then
  echo "glibc-linked cdylib leaked into android build" >&2; exit 1
fi
echo "librust_pty android artifact OK"
