# Third-party notices template

Zownload's own source is licensed under the MIT License in [`../LICENSE`](../LICENSE).
No engine binary or source archive is included by Gate 0A. Complete the fields
below for each redistributed version and platform before publishing a release.
Keep the actual upstream license texts and required notices with the release.

## FFmpeg

- Redistributed artifact and target platform: TODO
- Exact version and source revision: TODO
- Upstream source: https://ffmpeg.org/download.html
- Upstream license guidance: https://ffmpeg.org/legal.html
- Exact corresponding source archive URL: TODO
- Source archive SHA-256: TODO
- Bundled binary SHA-256: TODO
- Effective license for this build and license text location: TODO
- Build configuration: TODO (record the full `./configure` command, enabled
  libraries/codecs, patches, compiler/toolchain and build commands)
- Published corresponding source, patches and configuration URL: TODO
- Additional bundled libraries and their notices: TODO

FFmpeg must be built without `--enable-gpl` and `--enable-nonfree` under the
project's LGPL-compatible distribution plan. Verify the effective license of
the complete build, including enabled external libraries, before release.

## QuickJS

- Redistributed artifact and target platform: TODO
- Exact version and source revision: TODO
- Upstream source: https://bellard.org/quickjs/
- Upstream source license: MIT (https://github.com/bellard/quickjs/blob/master/LICENSE)
- Exact corresponding source archive URL: TODO
- Source archive SHA-256: TODO
- Bundled binary SHA-256: TODO
- Effective license and license text location: TODO (verify against the exact source)
- Build configuration: TODO (record build commands, compiler/toolchain, flags
  and patches)
- Published corresponding source, patches and configuration URL: TODO
- Additional bundled libraries and their notices: TODO

## yt-dlp

- Redistributed artifact and target platform: TODO
- Exact version and source revision: TODO
- Upstream source: https://github.com/yt-dlp/yt-dlp
- Upstream source license: Unlicense (https://github.com/yt-dlp/yt-dlp/blob/master/LICENSE)
- Bundled dependency license inventory: https://github.com/yt-dlp/yt-dlp/blob/master/THIRD_PARTY_LICENSES.txt
- Exact corresponding source archive URL: TODO
- Source archive SHA-256: TODO
- Bundled binary SHA-256: TODO
- Effective license and license text location: TODO (include licenses of bundled
  Python packages and other dependencies)
- Build configuration: TODO (record packaging method, commands, toolchain,
  dependency versions and patches)
- Published corresponding source, patches and configuration URL: TODO
- Additional bundled libraries and their notices: TODO

For each release, replace every TODO with verified artifact-specific evidence
or mark the component as not redistributed on that target. Record any other
redistributed components in the same format.
