# Vendored natives

`libopentui-<version>-android-aarch64.so`: true bionic builds produced once
(see `../scripts/build-libopentui-ci.sh` + the original CI logs), then reused
by every build for that opentui version.

To support a new `@opentui/core` version: build it with
`scripts/build-vendors.sh --vendors libopentui --commit`
(locally: without `--commit`; needs Zig 0.16 + NDK r28 — or trigger the
`build-vendors` workflow by hand), verify (`NEEDED libm/libc/libdl`, no
`__errno_location`, 425/425 dlopen symbols per `docs/REPORT.md`), and drop it
here as `libopentui-<version>-android-aarch64.so`.

`opencode-pty-<version>-android-aarch64`: **legacy** bionic daemon binaries
(`anomalyco/opencode-pty` + `patches/opencode-pty-socket-tmpdir.patch`,
built by the old `scripts/build-pty-android-ci.sh`; patches and script are in
git history). Kept only so `workflow_dispatch` rebuilds of pre-`0.3.3` tags
still embed a daemon whose socket root honours `$TMPDIR`. Current releases
embed upstream's static musl package instead: `@opencode/pty-linux-arm64-musl`
runs on bionic, `patches/daemon-pty-socket-android.patch` points its socket
root at `$TMPDIR`, and nothing is rebuilt here.

`librust_pty-<bun-pty-version>-android-aarch64.so`: bionic cdylib
(`sursaone/bun-pty` rust-pty crate, `scripts/build-rust-pty-android-ci.sh`
with cargo + NDK r28). Overwrites bun-pty's glibc
`librust_pty_arm64.so` pre-build (no source change needed: the loader picks
that filename for arm64, including Android).

Lib selection order in the build workflow: `scripts/build-vendors.sh` uses the
vendored file when present (verified by `.sha256`) and builds from source
otherwise, committing the result straight back to `vendor/` (same job, no
loop: the release workflow has no push trigger). So a new bun-pty version
costs one source build ever; every later run reuses the committed file.
`.github/workflows/build-vendors.yml` is the manual counterpart (dispatch it
to rebuild selected natives, with `force` to rebuild even when cached).
