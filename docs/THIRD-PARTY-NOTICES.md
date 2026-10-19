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
- Source archive SHA-256: compute and attest in 0B-03 after verifying the
  official detached PGP signature
- Bundled binary SHA-256: TODO
- Effective license for this build and license text location: intended
  LGPL-2.1-or-later; verify source license and compiled configuration in
  0B-10/12, then ship the matching source license text
- Build configuration: TODO (record the full `./configure` command, enabled
  libraries/codecs, patches, compiler/toolchain and build commands)
- Published corresponding source, patches and configuration URL: TODO
- Additional bundled libraries and their notices: LAME 3.100 encoder and
  zlib 1.3.2 for PNG artwork decoding are selected external sources; verify
  all actually linked libraries and their licenses in 0B-10/12

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

- Redistributed artifact and target platform: planned `libmp3lame` with the
  Gate 0B Windows FFmpeg build; actual linkage requires 0B-10/11 proof
- Exact version: 3.100
- Upstream source: https://sourceforge.net/projects/lame/files/lame/3.100/lame-3.100.tar.gz/download
- Source archive SHA-256: `ddfe36cab873794038ae2c1210557ad34857a4b6bdc515785d1da9e175b1da1e`
- License text: https://lame.sourceforge.io/license.txt; encoder library is
  LGPL, but old mpglib decoding functions are GPL. Exclude the GPL decoder
  from the linked FFmpeg build and verify this in 0B-10/12.
- Bundled library SHA-256 and build configuration: TODO after build
- Published corresponding source, patches and configuration URL: TODO for release

## zlib compression library

- Redistributed artifact and target platform: planned static library linked
  into the Gate 0B Windows FFmpeg build; actual linkage requires 0B-10/11 proof
- Exact version: 1.3.2
- Upstream versioned source: https://zlib.net/fossils/zlib-1.3.2.tar.gz
- Published source archive SHA-256: `bb329a0a2cd0274d05519d61c667c062e06990d72e125ee2dfa8de64f0119d16`
- License: Zlib; https://zlib.net/zlib_license.html and the archive's root
  `LICENSE`. Preserve its copyright and conditions in redistributed source.
- Build dependency plan: use pinned w64devkit GCC/Make and the archive's
  `win32/Makefile.gcc` to build root-library `libz.a`; expose `zlib.h`,
  `zconf.h` and `libz.a` to FFmpeg's PNG decoder probe. Exclude `contrib/`
  programs and examples; confirm the exact flags and linkage in 0B-10/11.
- Bundled library SHA-256 and effective build configuration: TODO after build
- Published corresponding source, patches and configuration URL: TODO for release

For each release, replace every remaining TODO with verified artifact-specific
evidence or mark the component as not redistributed on that target. Record any
other redistributed components in the same format. This source plan is not a
completed redistribution audit.
