# Gate 0B real test fixtures

Checked on **2026-10-19**. These are input fixtures and expected observations, not CLI results. Run `powershell -NoProfile -File scripts/gate-0b/verify-fixtures.ps1` immediately before each dependent CLI task. It checks public metadata and playlist membership without downloading media or invoking yt-dlp. A failed preflight marks the fixture unavailable; record that separately from a CLI failure. Replace a disappeared fixture only through a separate fixture task under the gate stop rule.

## Locked URLs and observations

| Name | URL and intended cases | Expected observation and permission basis |
|---|---|---|
| `youtube-short` | `https://www.youtube.com/watch?v=uW13KuRrg1g`; 0B-13 single analysis and QuickJS/ejs | YouTube oEmbed reports `10號風...` by `vgocyl`. Wikimedia Commons independently [reviewed this upload's CC BY 3.0 status](https://commons.wikimedia.org/wiki/File:10%E8%99%9F%E9%A2%A8....webm), names the original YouTube ID and reports a 15-second VP8/Vorbis copy. Use this YouTube URL for analysis; the Commons copy is a rights/codec reference, not a substitute for the JS-runtime probe. |
| `commons-vorbis-single` | [Wikimedia Commons file page](https://commons.wikimedia.org/wiki/File:10%E8%99%9F%E9%A2%A8....webm) and its [original WebM file](https://upload.wikimedia.org/wikipedia/commons/a/aa/10%E8%99%9F%E9%A2%A8....webm); 0B-14 MP3 single presets | This is a separate, directly downloadable fixture from the YouTube analysis URL above. Commons identifies `vgocyl` as author, records a reviewer-confirmed [CC BY 3.0 license](https://creativecommons.org/licenses/by/3.0/), and describes the original as 15-second VP8/Vorbis. A one-time download of the original (6,125,831 bytes) matched Commons SHA-1 `7f3bcad588ebb8fb74ad3e4d56272450b15071b2`; its SHA-256 is `3b8bc381e3173f032d30d37983b8662c12d32c5ab780e7dd6bf45b7cba74c36b`. Pinned ffprobe confirmed Vorbis audio and 14.748 seconds. Use the original file URL, not a changing Commons transcode, for the four presets. Attribution: vgocyl, *10號風...*, CC BY 3.0. The preflight checks Commons metadata and page text only; it does not fetch media. |
| `blender-playlist` | `https://www.youtube.com/playlist?list=PL6B3937A5D230E335`; 0B-13 pure playlist/benchmark and original 0B-16 stopped probe | YouTube's public playlist page reports **Official Blender Open Movies** and contains `u9lj-c29dxI` (Wing It!) and `UXqq0ZvbOnk` (Charge). The original 0B-16 Max transfer timed out on Charge; retain its finding in `mp4.txt`. [Blender Studio says Wing It! is CC BY 4.0](https://studio.blender.org/projects/wing-it/pages/licensing/) and [states its published films are generally CC BY](https://studio.blender.org/remixing/). Attribution: Blender Foundation / Blender Studio. No claim is made that every other playlist entry has been rights-checked. |
| `natureclip-video-playlist` | [NatureClip's CC BY playlist](https://www.youtube.com/playlist?list=PL7EDEF163A9B185EF); replacement for the 0B-16 MP4 Max/Min playlist probe | The real 28-entry playlist is titled *Creative Commons By Attribution - Free Videos to download*. Lock positions **4, 6, 7**: [Sunset](https://www.youtube.com/watch?v=Dkx4LYeFnVY) (12 s), [Clouds & Stars at Dusk](https://www.youtube.com/watch?v=-TcyfUI9yUQ) (4 s), and [Full Moon](https://www.youtube.com/watch?v=YC0kTqKbeFs) (16 s). Each video's yt-dlp metadata reports `Creative Commons Attribution license (reuse allowed)` and NatureClip as uploader. The creator's descriptions request credit, and [Creative Commons lists NatureClip as a CC BY video source](https://wiki.creativecommons.org/wiki/Nature_Clips). Attribution for each: **NatureClip, 2012**, linked to its individual video above, **CC BY**; downloaded test copies are not republished. The metadata-only preflight checks playlist membership, identity, license, at least two video heights, Max/Min selection and estimated transfer size. |
| `blender-mixed` | `https://www.youtube.com/watch?v=u9lj-c29dxI&list=PL6B3937A5D230E335`; 0B-13 mixed video-plus-playlist | The video ID is in the above playlist; with `--no-playlist`, expect one video result, not the whole playlist (D-28). The playlist can change, so membership is rechecked. |
| `archive-audio-playlist` | `https://archive.org/details/PureDataSoundEffects`; 0B-15 stopped finding and 0B-18 album/creator/cover | Internet Archive metadata names Andy Farnell and states CC BY 3.0; [item metadata](https://archive.org/metadata/PureDataSoundEffects) and [embed playlist](https://archive.org/embed/PureDataSoundEffects) expose 39 tracks. The bounded entries `effect-acid.mp3`, `effect-alarm-siren.mp3`, and `effect-alarmclock.mp3` are at positions 2–4. Source MD5 and pinned ffprobe confirm all three are 128 kbps MP3; the 0B-15 Max request failed because conversion was skipped. Keep this fixture for 0B-18 metadata/cover checks and as a source-behavior finding. Attribution: Andy Farnell and the [CC BY 3.0 license](https://creativecommons.org/licenses/by/3.0/). |
| `archive-pcm-playlist` | [VValkabout item](https://archive.org/details/vvalkabout); resumed 0B-15 MP3 playlist Max/Min | [Internet Archive metadata](https://archive.org/metadata/vvalkabout) declares [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/) for *Sound Effects for Proof of Concept Game called VValkabout*. It has no creator field; the uploader made the CC0 declaration. The bounded real playlist entries are positions **11, 12, 18**: original `glitch1.wav`, `glitch2.wav`, `hunter.wav`. Pinned yt-dlp `-f ba/b --skip-download` selected those WAV originals, and one-time source downloads matched Archive MD5/SHA-1/size. Pinned ffprobe found `pcm_s16le` at 1,411,200 bps, with durations 5.01, 3.57 and 8.00 seconds. The metadata-only preflight verifies the embed positions, catalog fingerprints and selected WAV URLs, records each inspected codec, and fails if any locked or selected source becomes MP3. It does not fetch media. |
| `archive-video` | `https://archive.org/details/Justin_Cone_-_Building_On_The_Past_-_640x480`; 0B-16 bounded-height single, 0B-17 non-AAC source, 0B-18 thumbnail, 0B-19 resume/progress | The [Creative Commons project page](https://creativecommons.org/about/videos/building-on-the-past/) names Justin Cone, grants CC BY and links this Archive item. [Archive metadata](https://archive.org/metadata/Justin_Cone_-_Building_On_The_Past_-_640x480) exposes a 120-second Ogg video derivative (~8 MB), a 240-line MP4 derivative and JPEG thumbnails. Ogg is the non-AAC candidate; 0B-17 must inspect its actual audio codec before claiming AAC conversion. Throttle the transfer for 0B-19 so interruption leaves a `.part` file. Attribution: Justin Cone, *Building on the Past*, CC BY, with a link to the Creative Commons project page. |
| `archive-short-video` | `https://archive.org/details/2026-02-16-public-short-video`; 0B-16 short MP4 single and 0B-18 thumbnail | [Archive metadata](https://archive.org/metadata/2026-02-16-public-short-video) identifies a 9.74-second 640×360 original MP4, generated JPEG thumbnails, and an uploader CC0 declaration. No creator field is present, so this fixture cannot prove artist fallback. |
| `missing-archive-item` | `https://archive.org/details/zownload-fixture-intentionally-missing-0b02`; 0B-20 unavailable | The Archive metadata endpoint returns `{}` rather than a named item. Recheck that it remains absent before expecting an unavailable-content error. No media is involved. |
| `restricted-archive-item` | `https://archive.org/details/lp_the-music-of-russia_various-artists-a-askaryan-alexander-melik`; 0B-20 access restricted | [Archive metadata](https://archive.org/metadata/lp_the-music-of-russia_various-artists-a-askaryan-alexander-melik) marks `disc1/01.01. Bells Of Rostov.mp3` as `private: true`. Probe only metadata/extraction failure; do not attempt to download or bypass access controls. |
| `invalid-input` | `not-a-url`; 0B-20 invalid URL | A deliberately malformed, local input. No permission or availability check is needed. |

YouTube access and format selection can vary by location, rate limits and site policy. A public page, CC content license, and successful preflight do not prove that yt-dlp extraction or media transfer will succeed. The later CLI tasks must record the exact result. Media made for these tests stays in ignored `work/engine/` and must not be committed or redistributed.

### 0B-14A Commons source inspection

On 2026-10-19, the Commons Imageinfo API returned the locked original URL,
`video/webm`, 6,125,831 bytes, SHA-1
`7f3bcad588ebb8fb74ad3e4d56272450b15071b2`, `CC BY 3.0`, and author
`vgocyl`. The [Commons file page](https://commons.wikimedia.org/wiki/File:10%E8%99%9F%E9%A2%A8....webm)
describes the original as VP8/Vorbis and records the license review. A one-time
download of the original to ignored `work/engine/fixtures/commons-vorbis.webm`
matched that SHA-1 and SHA-256
`3b8bc381e3173f032d30d37983b8662c12d32c5ab780e7dd6bf45b7cba74c36b`.
Pinned ffprobe 8.1.3 (SHA-256
`bf44a50347aaba3e433c34c8c881d67eeaca41001577482ce3ba69b780824ec7`)
exited 0 for:

```powershell
$ffprobe = (Resolve-Path work/engine/build/ffmpeg/windows-x64/recipe/ffmpeg-8.1.3/ffprobe.exe).Path
& $ffprobe -v error -show_entries 'stream=codec_type,codec_name,bit_rate:format=duration' -of json -- work/engine/fixtures/commons-vorbis.webm
```

It reported `vp8` video, `vorbis` audio, and `duration: 14.748000`.
The pinned yt-dlp analysis of the direct original URL exited 0 and identified
one WebM format. The exact fixture preflight command exited 0 and reports
metadata only; it does not request the media URL. The source inspection is
not an MP3 preset result.

### 0B-15A VValkabout source inspection

The owner approved a separate non-MP3 playlist fixture after the 0B-15 stop.
The [Archive item metadata](https://archive.org/metadata/vvalkabout) declares
CC0 1.0, labels the three selected files as original WAVE uploads, and gives
their sizes, MD5, SHA-1 and durations. Its [embed playlist](https://archive.org/embed/vvalkabout)
places them at positions 11, 12 and 18. The item supplies no creator field;
the CC0 declaration is the permission basis, without an invented attribution.

Pinned yt-dlp stable@2026.08.19 (SHA-256
`66674953fe251b89f4d08c5f0e35e0728679bd67ab3d7d05c0562af101dd3e7a`)
exited 0 for this metadata-only selection command:

```powershell
$yt = (Resolve-Path work/engine/downloads/yt-dlp.exe).Path
& $yt --ignore-config --playlist-items '11,12,18' -f 'ba/b' --skip-download --print '%(id)s | %(format_id)s | %(ext)s | %(url)s' -- 'https://archive.org/details/vvalkabout'
```

It selected `vvalkabout/glitch1.wav`, `vvalkabout/glitch2.wav`, and
`vvalkabout/hunter.wav` as format `3`, extension `wav`, with their direct
`https://archive.org/download/vvalkabout/<name>` original URLs. No MP3
derivative was selected. For one-time codec inspection outside the preflight,
the three original URLs were downloaded to ignored
`work/engine/fixtures/vvalkabout/`. Each local copy matched Archive size,
MD5 and SHA-1. Pinned ffprobe 8.1.3 (SHA-256
`bf44a50347aaba3e433c34c8c881d67eeaca41001577482ce3ba69b780824ec7`)
exited 0 on each:

```powershell
$ffprobe = (Resolve-Path work/engine/build/ffmpeg/windows-x64/recipe/ffmpeg-8.1.3/ffprobe.exe).Path
& $ffprobe -v error -show_entries 'stream=codec_name,codec_type,bit_rate,sample_rate,channels:format=duration,format_name' -of json -- work/engine/fixtures/vvalkabout/glitch1.wav
```

The other two inspections used `glitch2.wav` and `hunter.wav` at the same path.
All three streams were `pcm_s16le` at 1,411,200 bps:

| Position/file | Duration | Bytes | SHA-256 of inspected original |
|---|---:|---:|---|
| 11 `glitch1.wav` | 5.01 s | 883,884 | `60b2637e719f91cfdd16da25043840406d87fd4da5a1279b7157d38733506994` |
| 12 `glitch2.wav` | 3.57 s | 629,868 | `7e9a7137a2871abfbe7eead45174c67a1dba13a0124f481709e96be173f9c4ea` |
| 18 `hunter.wav` | 8.00 s | 1,411,244 | `f7cf865aa7490a90014b55e37139718d32a519a80ad23a4b1e61088fb78bd9f9` |

The read-only preflight checks current Archive metadata fingerprints and embed
positions against these inspected originals, prints each locked source codec,
and uses yt-dlp `--skip-download` to reject changed or MP3 format selection.
It does not request media bytes. Archive's catalog does not expose the exact
WAV audio codec; matching its source hashes binds the preflight's codec record
to the one-time ffprobe inspection. The three source files and all full
inspection output remain ignored under `work/engine/`.

For the original 0B-16 probe, the same preflight confirms at least two
distinct available video heights for each locked Blender video. It also checks
Archive video metadata for distinct 464×304 Ogg and 360×240 MP4 derivatives.
These availability checks do not claim MP4 quality selection or playback.

### 0B-16A NatureClip video playlist lock

On 2026-10-19, pinned yt-dlp stable@2026.08.19 with only pinned QuickJS
2026-06-04 selected the following formats through `--skip-download
--dump-single-json`. The three clips are real members of the linked NatureClip
playlist. Each reports a CC BY license and NatureClip as uploader. The
individual links and attribution appear in the fixture table above.

| Position / ID | Duration | Available video heights | Max video+audio, estimated bytes | Min video+audio, estimated bytes |
|---|---:|---|---|---|
| 4 `Dkx4LYeFnVY` | 12 s | 144, 240, 360, 480, 720, 1080 | `248+251` (1080p), 300,000 | `602+251` (144p), 162,353 |
| 6 `-TcyfUI9yUQ` | 4 s | 144, 360, 720 | `136+140` (720p), 282,245 | `269+140` (144p), 137,202 |
| 7 `YC0kTqKbeFs` | 16 s | 144, 360, 720, 1080 | `137+251` (1080p), 93,516 | `269+251` (144p), 186,885 |

The **per-entry limit is 524,288 estimated bytes (512 KiB)** for either
preset; the three-entry upper bound is 1.5 MiB per playlist invocation.
Known `filesize` is used first, then `filesize_approx`. For formats without
either value, the preflight estimates `tbr × duration × 1000 / 8 × 1.5`,
rounding up. The 1.5 multiplier allows for rate and HLS segment overhead; it
is still an estimate, not a download guarantee. Every selected component must
provide a size or bitrate and use `https` or yt-dlp's `m3u8_native` protocol.
The 20-second duration cap, resolution count, license and size cap fail closed
if the fixture changes. The current Max and Min totals are 675,761 and
486,440 estimated bytes. At the stopped Blender probe's ~23 KiB/s transfer
rate, even the 1.5 MiB cap is about 67 seconds of media transfer, leaving a
large margin for extraction and local merging within the unchanged 600-second
command timeout. HLS throughput can differ; only the 0B-16 rerun can prove
completion and playback. No media was downloaded for this lock.

## Capability map

| Gate probe | Fixtures |
|---|---|
| Single, pure playlist, mixed URL, YouTube JS runtime and playlist timing | `youtube-short`, `blender-playlist`, `blender-mixed` |
| MP3 320/256/192/128 single output | `commons-vorbis-single` original WebM with Vorbis audio |
| MP3 playlist Max/Min | `archive-pcm-playlist` (three bounded PCM/WAV originals); preserve `archive-audio-playlist` as the stopped already-MP3 finding and 0B-18 metadata fixture |
| MP4 Max/Min playlist and bounded-height single | `natureclip-video-playlist` (three checked entries); `archive-video` remains the bounded-height single; `blender-playlist` remains the stopped finding |
| Non-AAC to AAC in MP4 | `archive-video` Ogg candidate, after ffprobe confirms source codec |
| Title, creator/uploader fallback, playlist album, thumbnail-to-JPEG cover | `archive-audio-playlist`, `archive-video`, `archive-short-video` |
| Interrupted transfer, `.part` resume, parseable progress | `archive-video` with a low `--limit-rate` during the interruption phase |
| Unavailable, invalid, access restricted and executable startup failures | `missing-archive-item`, `invalid-input`, `restricted-archive-item`; executable failure uses the pinned local binary path rather than an external URL |

## Machine-readable preflight lock

The JSON below supplies the verifier's IDs and expected metadata. Changing its URLs, membership, or rights assertions is fixture maintenance, not a way to make a failed CLI probe pass.

```json fixture-lock
{
  "schema": 1,
  "checkedOn": "2026-10-19",
  "youtubeShort": {
    "url": "https://www.youtube.com/watch?v=uW13KuRrg1g",
    "id": "uW13KuRrg1g",
    "title": "10號風...",
    "author": "vgocyl"
  },
  "commonsVorbisSingle": {
    "pageUrl": "https://commons.wikimedia.org/wiki/File:10%E8%99%9F%E9%A2%A8....webm",
    "mediaUrl": "https://upload.wikimedia.org/wikipedia/commons/a/aa/10%E8%99%9F%E9%A2%A8....webm",
    "title": "File:10號風....webm",
    "author": "vgocyl",
    "license": "CC BY 3.0",
    "mime": "video/webm",
    "size": 6125831,
    "sha1": "7f3bcad588ebb8fb74ad3e4d56272450b15071b2",
    "sha256": "3b8bc381e3173f032d30d37983b8662c12d32c5ab780e7dd6bf45b7cba74c36b",
    "audioCodec": "vorbis"
  },
  "blenderPlaylist": {
    "url": "https://www.youtube.com/playlist?list=PL6B3937A5D230E335",
    "id": "PL6B3937A5D230E335",
    "title": "Official Blender Open Movies",
    "videoIds": ["u9lj-c29dxI", "UXqq0ZvbOnk"],
    "minDistinctVideoHeights": 2,
    "mixedUrl": "https://www.youtube.com/watch?v=u9lj-c29dxI&list=PL6B3937A5D230E335"
  },
  "natureclipVideoPlaylist": {
    "url": "https://www.youtube.com/playlist?list=PL7EDEF163A9B185EF",
    "id": "PL7EDEF163A9B185EF",
    "title": "Creative Commons By Attribution - Free Videos to download",
    "uploader": "NatureClip: Free Stock Footage",
    "license": "Creative Commons Attribution license (reuse allowed)",
    "minDistinctVideoHeights": 2,
    "maxDurationSeconds": 20,
    "maxEstimatedBytesPerEntry": 524288,
    "entries": [
      {"playlistIndex": 4, "id": "Dkx4LYeFnVY", "title": "FREE Time Lapse HD stock footage: Sunset in 1080p HD CC-By NatureClip"},
      {"playlistIndex": 6, "id": "-TcyfUI9yUQ", "title": "FREE Time-Lapse HD stock footage: Clouds & Stars at Dusk CC-BY NatureClip"},
      {"playlistIndex": 7, "id": "YC0kTqKbeFs", "title": "FREE Time-Lapse stock footage: Full Moon CC-BY NatureClip"}
    ]
  },
  "archiveAudio": {
    "url": "https://archive.org/details/PureDataSoundEffects",
    "id": "PureDataSoundEffects",
    "license": "creativecommons.org/licenses/by/3.0/",
    "creator": "Andy Farnell",
    "entries": ["effect-acid.mp3", "effect-alarm-siren.mp3", "effect-alarmclock.mp3"],
    "thumbnailExt": "png"
  },
  "archivePcmPlaylist": {
    "url": "https://archive.org/details/vvalkabout",
    "id": "vvalkabout",
    "title": "Sound Effects for Proof of Concept Game called VValkabout",
    "license": "creativecommons.org/publicdomain/zero/1.0/",
    "entries": [
      {"playlistIndex": 11, "name": "glitch1.wav", "sourceCodec": "pcm_s16le", "format": "WAVE", "size": 883884, "md5": "440fec3f8d602531b641be575f0115df", "sha1": "f426adbf55b337110264da8e990d731ca2dc7c41", "sha256": "60b2637e719f91cfdd16da25043840406d87fd4da5a1279b7157d38733506994", "duration": 5.01},
      {"playlistIndex": 12, "name": "glitch2.wav", "sourceCodec": "pcm_s16le", "format": "WAVE", "size": 629868, "md5": "e5aa334f15677a844855841e1480484e", "sha1": "0a8228c8cc5061793ddfde4474637a5467964ccc", "sha256": "7e9a7137a2871abfbe7eead45174c67a1dba13a0124f481709e96be173f9c4ea", "duration": 3.57},
      {"playlistIndex": 18, "name": "hunter.wav", "sourceCodec": "pcm_s16le", "format": "WAVE", "size": 1411244, "md5": "ad277b94d6bd4c02ed7c73711b3a4cbb", "sha1": "84fe8a9d7424b1531940318ac13caf3331696883", "sha256": "f7cf865aa7490a90014b55e37139718d32a519a80ad23a4b1e61088fb78bd9f9", "duration": 8.0}
    ]
  },
  "archiveVideo": {
    "url": "https://archive.org/details/Justin_Cone_-_Building_On_The_Past_-_640x480",
    "id": "Justin_Cone_-_Building_On_The_Past_-_640x480",
    "license": "creativecommons.org/licenses/by/3.0/",
    "creator": "Justin Cone",
    "files": ["Justin_Cone_-_Building_On_The_Past_-_640x480.ogv", "Justin_Cone_-_Building_On_The_Past_-_640x480_512kb.mp4"],
    "resolutions": [
      {"name": "Justin_Cone_-_Building_On_The_Past_-_640x480.ogv", "width": 464, "height": 304},
      {"name": "Justin_Cone_-_Building_On_The_Past_-_640x480_512kb.mp4", "width": 360, "height": 240}
    ]
  },
  "archiveShortVideo": {
    "url": "https://archive.org/details/2026-02-16-public-short-video",
    "id": "2026-02-16-public-short-video",
    "license": "creativecommons.org/publicdomain/zero/1.0/",
    "files": ["test.mp4", "2026-02-16-public-short-video.thumbs/test_000005.jpg"]
  },
  "missingArchiveId": "zownload-fixture-intentionally-missing-0b02",
  "restrictedArchive": {
    "url": "https://archive.org/details/lp_the-music-of-russia_various-artists-a-askaryan-alexander-melik",
    "id": "lp_the-music-of-russia_various-artists-a-askaryan-alexander-melik",
    "privateFile": "disc1/01.01. Bells Of Rostov.mp3"
  },
  "invalidInput": "not-a-url"
}
```
