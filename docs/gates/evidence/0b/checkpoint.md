# Gate 0B checkpoint evidence — task 0B-21

Prepared 2026-10-20 for owner review. This record freezes the tested Windows
CLI commands in [the command matrix](../../../ytdlp-commands.md). It does not
record owner acceptance. The task verifier checks local artifacts and evidence;
it does not redownload media or replace the owner's playback review.

## Source, builds and redistribution

| Requirement | Recorded proof |
|---|---|
| Immutable sources, versions and signatures | [Source lock](../../../engine-sources.md), [15 acquired-file SHA-256 values](source-hashes.txt), and the passing `verify-downloads.ps1` attestation. The signed yt-dlp checksum manifest and FFmpeg source signature were checked against their locked signer fingerprints. QuickJS's upstream archive has no published digest; its acquired SHA-256 is recorded. |
| Matching JavaScript runtime | Official yt-dlp stable@2026.08.19 bundles yt-dlp-ejs 0.8.0; [analysis](analyze.txt) found only upstream QuickJS 2026-06-04 enabled. The YouTube responses did not issue a JS challenge, so solver execution speed is unmeasured. |
| Reproducible QuickJS targets | [Build recipes](../../../engine-builds.md) and target records: [Windows x64](quickjs-windows.txt), [Linux x64](quickjs-linux.txt), [macOS x64](quickjs-macos-x64.txt), [macOS arm64](quickjs-macos-arm64.txt), [Android arm64](quickjs-android.txt). The four non-Windows outputs were built and inspected in CI; Android device execution belongs to Gate 0C. |
| LGPL-compatible FFmpeg and codecs | [Windows build and smoke encodes](ffmpeg-windows.txt) show FFmpeg 8.1.3 and ffprobe 8.1.3, `CONFIG_GPL=0`, `CONFIG_NONFREE=0`, `CONFIG_VERSION3=0`, no `--enable-gpl`/`--enable-nonfree`, encoder-only LAME 3.100 and zlib 1.3.2. Actual MP3 and AAC outputs are inspected below. |
| Notices and corresponding sources | [Redistribution audit](license-audit.txt), [notice and per-release source plan](../../../THIRD-PARTY-NOTICES.md). The official bundled yt-dlp binaries are GPL-3.0-or-later combined works; Zownload's own source remains MIT. Transitive source packaging, LGPL relinking materials and Microsoft runtime entitlement remain release obligations, not completed Gate 0B artifacts. |

The SHA-256 values below identify outputs used for this checkpoint. Source and
download hashes are in [source-hashes.txt](source-hashes.txt); the complete
target and configuration details are in the linked records above.

| Artifact | SHA-256 |
|---|---|
| yt-dlp.exe Windows x64 | `66674953fe251b89f4d08c5f0e35e0728679bd67ab3d7d05c0562af101dd3e7a` |
| QuickJS Windows x64 | `bec67f8f87fa22958d3ab8be5508088116b8bff90032323d82c94545e1698b83` |
| QuickJS Linux x64 | `50263177cb921024aabc0807a31d71be7fa3c22f0c5824c3c6a2d1cf920f300c` |
| QuickJS macOS x64 | `554102a8a9c0d0c5e24cd138ad7a790f330fd926310c01009265589a446ef90a` |
| QuickJS macOS arm64 | `fba79a316a53ed58a17709a39c173218f8bc825831094b6033ce0510a713bb43` |
| QuickJS Android arm64 | `4db3b8aeba709b4907da59a87f1ab3f94585bae3a95f7b02c946b7732cd20185` |
| FFmpeg Windows x64 | `fa050630ddf5b7c3303d8dab5e5a42e7023547fb78ec9b90b5be0a4f788a7e66` |
| ffprobe Windows x64 | `bf44a50347aaba3e433c34c8c881d67eeaca41001577482ce3ba69b780824ec7` |

## Required CLI capability review (`PROJECT.md:752`)

| Capability | Passing probe and inspected result | Media fetch and FFmpeg input |
|---|---|---|
| Singles, pure playlists, mixed video/list and QuickJS registration | [0B-13 analysis](analyze.txt): three expected JSON shapes, yt-dlp/EJS identity and QuickJS-only debug lines; no JS challenge in that run. | Metadata requests only; no media or FFmpeg. |
| MP3 single presets 320/256/192/128 | [0B-14](mp3-singles.txt): four distinct MP3 outputs from Vorbis, ffprobe exact stream bitrates, automated VLC playback. | yt-dlp HTTP fetched WebM; FFmpeg read local WebM. |
| MP3 playlist Max/Min and per-entry commands | [0B-15](mp3-playlist.txt): three WAV originals, three 320K and three 128K outputs, plus three matching per-entry Max outputs; automated VLC playback. | yt-dlp HTTP fetched WAV; FFmpeg read local WAV. |
| MP4 Max/Min playlist and bounded single | [0B-16](mp4.txt): three Max, three Min and one bounded MP4 with expected heights/streams and automated VLC video decode. | yt-dlp HTTP fetched Max and audio; yt-dlp `hlsnative` fetched Min video; twelve merge inputs were local `file:` paths. |
| MP4 non-AAC audio conversion | [0B-17](aac.txt): retained H.264/Opus sources and H.264/AAC final MP4, automated VLC video playback. | yt-dlp HTTP fetched sources; FFmpeg merged two local `file:` inputs. |
| Title, artist fallback, album and JPEG cover | [0B-18](metadata.txt): ffprobe and VLC metadata, two embedded MJPEG pictures and automated playback. VLC's ArtworkURL was empty; visible cover display was not proved. | yt-dlp HTTP fetched media/YouTube art; PowerShell fetched Archive PNG; FFmpeg read local inputs. |
| Partial resume and parseable progress | [0B-19](resume-progress.txt): real `.part` prefix retained, resume at byte 195136, final MP4 inspection and parseable `ZP1` lines with normal/error output intact. | yt-dlp HTTP fetched direct MP4; no FFmpeg media download. |
| Invalid, unavailable, restricted, startup and timeout errors | [0B-20](errors.txt): exit 1 and distinct `ERROR:` stderr for invalid URL, HTTP 404 and HTTP 401; bounded startup and simulated launch/timeout probes. | Extractor metadata/error requests only; no media or FFmpeg. |

The [matrix transport review](../../../ytdlp-commands.md#gate-0b-transport-review-for-the-command-matrix)
finds no passing required test that makes FFmpeg fetch HTTPS, including the
selected HLS streams. This is a statement about the tested formats. The
stopped 0B-16 `--download-sections` diagnostic did make FFmpeg fetch HTTPS and
failed; it is excluded from the passing matrix. Future HLS/DASH selections
need the same transport check before a support claim.

## Corrections and limits for owner review

- Appendix B's `--audio-quality` proposal did not re-encode an already-MP3
  128 kbps Archive source at a requested 320K. The original 0B-14/15 result
  remains in [single](mp3-singles.txt) and [playlist](mp3-playlist.txt) evidence.
  The owner-approved non-MP3 fixtures prove the preset rates for Vorbis/WAV
  inputs. Product handling of already-MP3 sources is an open Phase 1/2 choice;
  the matrix makes no unconditional preset claim for those sources.
- MP4 merge alone preserved Opus. The tested `Merger+ffmpeg_o:-c:a aac` override
  produced AAC for the selected non-AAC source. The Archive PNG had to be
  fetched explicitly and converted locally to a JPEG cover.
- The first Blender MP4 probe timed out on a long selected stream. The
  owner-approved short NatureClip fixture provided the passing Max/Min rerun.
  The failed command and HTTPS diagnostic remain in [mp4.txt](mp4.txt).
- VLC 3.0.24/libVLC automated checks opened and advanced the MP3/MP4 files,
  and video decode was enabled for MP4. These are player results, not a human
  listening/viewing claim. The owner should review the produced files manually
  before accepting the checkpoint if a human playback check is required.
- The per-release source bundle and Microsoft runtime entitlement checks in
  [license-audit.txt](license-audit.txt) remain later release work. Android
  QuickJS was inspected as an ELF, not executed on a device in Gate 0B.

Verification entrypoint: `powershell -NoProfile -File scripts/gate-0b/verify-gate.ps1`.
Gate 0C stays closed until the owner explicitly accepts this checkpoint in
`docs/STATE.md`.
