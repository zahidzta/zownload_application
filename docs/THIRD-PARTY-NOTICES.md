# Third-party notices and Gate 0B source plan

Zownload's own source is licensed under the MIT License in [`../LICENSE`](../LICENSE).
No engine binary or source archive is tracked in this repository. The source
choices below were locked in 0B-01; binary-specific fields remain for the
0B-12 audit. Keep actual upstream license texts, notices and corresponding
source with each redistributed release. The machine-readable URLs and known
hashes are in [`engine-sources.md`](engine-sources.md).

## FFmpeg

- Redistributed artifact and target platform: TODO
- Exact version and source revision: 8.1.3 upstream release
- Upstream source: https://ffmpeg.org/releases/ffmpeg-8.1.3.tar.xz
- Upstream license guidance: https://ffmpeg.org/legal.html
- Exact corresponding source archive URL: https://ffmpeg.org/releases/ffmpeg-8.1.3.tar.xz
- Source archive SHA-256: `7138d28c96d9d3e3af4ee3d8cad72741f8ffb40da90c1112235dea3ecd3178a3`;
  detached PGP signature verified in 0B-03
- Bundled binary SHA-256: TODO
- Effective license for the 0B-10 configuration: FFmpeg reports LGPL-2.1-or-later;
  `CONFIG_GPL=0`, `CONFIG_NONFREE=0`, `CONFIG_VERSION3=0`. Source text is
  `COPYING.LGPLv2.1`; 0B-11/12 must verify the built binary and release notices.
- Build configuration: [`engine-builds.md`](engine-builds.md#0b-10--windows-x64-lgpl-ffmpeg-configuration)
  records the exact source recipe, pinned Windows toolchain, compiler flags and
  enabled features. No source patches were applied in 0B-10.
- Published corresponding source, patches and configuration URL: TODO
- External libraries selected by configuration: only LAME 3.100 encoder and
  zlib 1.3.2 for PNG artwork decoding. The actual executable linkage and
  relinking materials remain for 0B-11/12.

FFmpeg must be built without `--enable-gpl` and `--enable-nonfree` under the
project's LGPL-compatible distribution plan. Verify the effective license of
the complete build, including enabled external libraries, before release.

## QuickJS

- Redistributed artifact and target platform: TODO
- Exact version and source revision: upstream 2026-06-04
- Upstream source: https://bellard.org/quickjs/
- Upstream source license: MIT (https://bellard.org/quickjs/); exact source
  archive `LICENSE` must be inspected in 0B-03
- Exact corresponding source archive URL: https://bellard.org/quickjs/quickjs-2026-06-04.tar.xz
- Source archive SHA-256: compute and attest in 0B-03; upstream does not
  publish a checksum on its download page
- Bundled binary SHA-256: TODO
- Effective license and license text location: MIT per the upstream download
  page; verify the exact archive's `LICENSE` in 0B-03
- Build configuration: TODO (record build commands, compiler/toolchain, flags
  and patches)
- Published corresponding source, patches and configuration URL: TODO
- Additional bundled libraries and their notices: TODO

## yt-dlp

- Redistributed artifact and target platform: TODO
- Exact version and source revision: 2026.08.19,
  `3a08beaf031ab68f966401ead017ac81fe8486cf`
- Upstream source: https://github.com/yt-dlp/yt-dlp
- Upstream source license: Unlicense (https://github.com/yt-dlp/yt-dlp/blob/master/LICENSE)
- Bundled dependency license inventory: https://github.com/yt-dlp/yt-dlp/blob/2026.08.19/THIRD_PARTY_LICENSES.txt
- Exact corresponding source archive URL: https://github.com/yt-dlp/yt-dlp/releases/download/2026.08.19/yt-dlp.tar.gz
- Source archive SHA-256: `072aad4f2a7604e92155f61a275a4752dc64046c8f6d90df3710525d94cd37c1`
- Bundled binary SHA-256: TODO
- Effective license and license text location: yt-dlp's own code is Unlicense,
  but its [tagged README](https://github.com/yt-dlp/yt-dlp/blob/2026.08.19/README.md#licensing)
  states that official PyInstaller executables are GPLv3+ combined works.
  Include the matching GPL and complete platform-specific third-party texts
  from the tagged inventory; inspect the acquired artifact in 0B-12.
- Build configuration: TODO (record packaging method, commands, toolchain,
  dependency versions and patches)
- Published corresponding source, patches and configuration URL: TODO
- Additional bundled libraries and their notices: matching EJS 0.8.0,
  Meriyah (ISC) and Astring (MIT) are identified upstream; 0B-12 must
  complete the full platform-specific bundle inventory

## yt-dlp-ejs

- Redistributed artifact and target platform: bundled in the official desktop
  yt-dlp binaries; separate Python wheel is a locked input for later packaging
- Exact version and source revision: 0.8.0,
  `4fb477f4af56880cfd324c48bd4294a2d2294e50`; yt-dlp 2026.08.19
  explicitly pins this EJS version in `pyproject.toml`
- Upstream source and license: https://github.com/yt-dlp/ejs/tree/0.8.0;
  own source is Unlicense, while packaged solver scripts also contain
  Meriyah ISC and Astring MIT code
- Exact corresponding source archive URL: https://files.pythonhosted.org/packages/d3/e6/cceb9530e8f4e5940f6f7822d90e9d94f1b85343329a16baaf47bbbb3de1/yt_dlp_ejs-0.8.0.tar.gz
- Source archive SHA-256: `d5fa1639f63b5c4af8d932495f60689d5370f1a095782c944f7f62a303eb104e`
- Wheel SHA-256: `79300e5fca7f937a1eeede11f0456862c1b41107ce1d726871e0207424f4bdb4`
- Bundled binary SHA-256 and exact contents: audit with each yt-dlp artifact
  in 0B-12
- License texts: https://github.com/yt-dlp/ejs/blob/0.8.0/LICENSE and
  https://github.com/yt-dlp/ejs/blob/0.8.0/README.md#licensing;
  verify included ISC/MIT texts against the acquired wheel
- Published corresponding source and build configuration: TODO for release

## LAME MP3 encoder library

- Redistributed artifact and target platform: static `libmp3lame.a` configured
  for the Gate 0B Windows FFmpeg build; executable linkage requires 0B-11 proof
- Exact version: 3.100
- Upstream source: https://sourceforge.net/projects/lame/files/lame/3.100/lame-3.100.tar.gz/download
- Source archive SHA-256: `ddfe36cab873794038ae2c1210557ad34857a4b6bdc515785d1da9e175b1da1e`
- License text: https://lame.sourceforge.io/license.txt; encoder library is
  LGPL, but old mpglib decoding functions are GPL. Exclude the GPL decoder
  from the linked FFmpeg build and verify this in 0B-10/12.
- Configured static library SHA-256:
  `fa25a11fa88fd2cada753ccc8e8d59be1be69e2730fa872697958afeec8f7a30`;
  build configuration is in
  [`engine-builds.md`](engine-builds.md#0b-10--windows-x64-lgpl-ffmpeg-configuration).
  `HAVE_MPGLIB` is undefined; the GPL decoder directory is not built.
- Published corresponding source, patches and configuration URL: TODO for release

## zlib compression library

- Redistributed artifact and target platform: static `libz.a` configured for
  the Gate 0B Windows FFmpeg build; executable linkage requires 0B-11 proof
- Exact version: 1.3.2
- Upstream versioned source: https://zlib.net/fossils/zlib-1.3.2.tar.gz
- Published source archive SHA-256: `bb329a0a2cd0274d05519d61c667c062e06990d72e125ee2dfa8de64f0119d16`
- License: Zlib; https://zlib.net/zlib_license.html and the archive's root
  `LICENSE`. Preserve its copyright and conditions in redistributed source.
- Build configuration: pinned w64devkit GCC/Make runs
  `make.exe -f win32/Makefile.gcc libz.a`. The root `zlib.h`, `zconf.h` and
  `libz.a` pass FFmpeg's PNG decoder probe. `contrib/` programs and examples
  are excluded; 0B-11 verifies executable linkage.
- Configured static library SHA-256:
  `ed44fb031978eacc1a6baac366f53f8d0ad6ea16fb6635992659ec0e1f854e7f`
- Published corresponding source, patches and configuration URL: TODO for release

For each release, replace every remaining TODO with verified artifact-specific
evidence or mark the component as not redistributed on that target. Record any
other redistributed components in the same format. This source plan is not a
completed redistribution audit.
