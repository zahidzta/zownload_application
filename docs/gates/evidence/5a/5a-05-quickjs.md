<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
<!-- SPDX-FileCopyrightText: 2026 zahidzta -->

# Gate 5A-05 — Android QuickJS build evidence

## Locked input and build

The clean build used the unmodified upstream QuickJS `2026-06-04` archive at
`https://bellard.org/quickjs/quickjs-2026-06-04.tar.xz`. Its SHA-256 was
`b376e839b322978313d929fd20663b11ba58b75df5a46c126dd19ea2fa70ad2a`, matching
the Gate 0B source lock and the approved 5A-02 Android runtime lock. The
runtime lock pairs it with yt-dlp `2026.08.19` and EJS `0.8.0`.

Verification command, run from Windows PowerShell:

```powershell
powershell -NoProfile -File scripts/gate-5a/verify.ps1 -Case quickjs
```

The verifier passed on Ubuntu 24.04.5 LTS x86_64 under WSL. Host GCC was
`13.3.0`; GNU Make was `4.3`; Android NDK was `30.0.16248370` with Clang
`21.0.0` (LLVM revision `9f872551d3c681d06fd303b36f16ed5c274735eb`). The
target was `aarch64-linux-android24` (`arm64-v8a`, minimum API 24). No source
patch was applied.

Make inputs were `HOST_CC=gcc-13`,
`CC=<NDK Clang> --target=aarch64-linux-android24`, `CONFIG_LTO=`,
`CONFIG_TEMPORAL_INTL=y`, `CROSS_PREFIX=android-`, and `LIBS=-lm -ldl`. The
host compiler generated `repl.c`; NDK Clang built the target executable. The
Android link has no `libpthread` dependency; pthread functions are provided by
`libc`.

## Output and ELF inspection

The build produced
`work/engine/build/quickjs/android-arm64/qjs`, 5,404,776 bytes, SHA-256
`65ebedfeaa87856788ae8ee508f9ed7836dbec5f7c616b88490a5edee3881ffd`. The
ELF is AArch64, uses `/system/bin/linker64`, and lists only `libm.so`,
`libdl.so`, and `libc.so` in `DT_NEEDED`. The compiler command embeds
`CONFIG_VERSION="2026-06-04"`.

QuickJS is built with debug information containing the absolute checkout
path. The Gate 0B CI output hash is
`4db3b8aeba709b4907da59a87f1ab3f94585bae3a95f7b02c946b7732cd20185`; this
WSL checkout has a different path and therefore a different artifact hash.
The source archive hash, compiler versions, target, flags, ELF interpreter,
and dependencies are pinned and verified independently of that debug-path
difference.

The earlier [Gate 0B YouTube analysis](../0b/analyze.txt) observed yt-dlp
`2026.08.19` with bundled EJS `0.8.0` and QuickJS `2026-06-04` as its only
enabled JavaScript runtime. Those YouTube responses did not require an EJS
solver challenge. Android device challenge execution remains for Gate 5A-09,
after the adapter is wired; the executable is not staged into the APK in this
task. See the [QuickJS MIT notice](../../../THIRD-PARTY-NOTICES.md#quickjs)
and the [build recipe](../../../engine-builds.md#5a-05-android-arm64-v8a-quickjs-2026-06-04).
