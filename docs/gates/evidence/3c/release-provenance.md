<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
<!-- SPDX-FileCopyrightText: 2026 zahidzta -->

# Gate 3C — Windows desktop release provenance

This record maps the Windows x64 packages verified by [V1](3c-02.md#signed-production-v1-rerun-with-downloadbootstrapper--passed) to their bundled desktop engine inputs. The hashes below identify audited engine outputs and source archives; they are not hashes of the complete installers.

## Engine versions, hashes, and source inputs

| Component | Windows x64 output SHA-256 | Corresponding source and SHA-256 | Reproducible build command |
|---|---|---|---|
| FFmpeg 8.1.3 `ffmpeg.exe` | `fa050630ddf5b7c3303d8dab5e5a42e7023547fb78ec9b90b5be0a4f788a7e66` | `ffmpeg-8.1.3.tar.xz` — `7138d28c96d9d3e3af4ee3d8cad72741f8ffb40da90c1112235dea3ecd3178a3` | `powershell -NoProfile -File scripts/gate-0b/build-ffmpeg.ps1 -Verify` |
| FFmpeg 8.1.3 `ffprobe.exe` | `bf44a50347aaba3e433c34c8c881d67eeaca41001577482ce3ba69b780824ec7` | Same FFmpeg source archive and build | Same FFmpeg command |
| QuickJS 2026-06-04 `qjs.exe` | `bec67f8f87fa22958d3ab8be5508088116b8bff90032323d82c94545e1698b83` | `quickjs-2026-06-04.tar.xz` — `b376e839b322978313d929fd20663b11ba58b75df5a46c126dd19ea2fa70ad2a` | `powershell -NoProfile -File scripts/gate-0b/build-quickjs.ps1 -Target windows-x64 -Verify` |
| yt-dlp 2026.08.19 `yt-dlp.exe` | `66674953fe251b89f4d08c5f0e35e0728679bd67ab3d7d05c0562af101dd3e7a` | Locked source identity and published checksum/signature are recorded in [engine-sources.md](../../../engine-sources.md) and [source hashes](../0b/source-hashes.txt). | Staging and verification procedure: [toolchain notes](../../../toolchain.md#2b-02-windows-engine-resource-staging-2026-10-25). |

The full dependency source hashes, license texts, build flags, notices, and relinking materials are tracked in [third-party notices](../../../THIRD-PARTY-NOTICES.md), [engine source locks](../../../engine-sources.md), and [engine build records](../../../engine-builds.md). Gate 0B's [FFmpeg evidence](../0b/ffmpeg-windows.txt) records `CONFIG_GPL=0`, `CONFIG_NONFREE=0`, `CONFIG_VERSION3=0`, and omission of `--enable-gpl`, `--enable-nonfree`, and `--enable-version3`. Its [QuickJS evidence](../0b/quickjs-windows.txt) records the compiler, flags, link command, source hash, output hash, and repeat-build hash.

## Distribution boundary

The verified V1 assets remain in the owner-created `app-v0.0.1` draft; no release was published. The draft does not contain a versioned source/compliance bundle. Before a public release, assemble that bundle with the corresponding source archives, required notices, build and relinking materials, and a SHA-256 manifest as specified in [third-party notices](../../../THIRD-PARTY-NOTICES.md). The Android source/build provenance gap and transitive license audit remain open; see the [release blocker](../../../STATE.md#release-blocker--android-distribution).
