# Gate 0B yt-dlp command matrix

These are the commands tested so far. Later Gate 0B CLI tasks extend this file.
All paths below are repository-relative Windows paths; the verifier resolves them
to absolute paths and checks the pinned executable hashes. Full CLI stdout and
stderr stay under ignored `work/engine/cli/`.

## 0B-13 — Analysis and playlist interpretation

Common options for all three commands:

```text
--ignore-config --verbose --no-js-runtimes --js-runtimes "quickjs:<absolute path to work/engine/build/quickjs/windows-x64/qjs.exe>" --skip-download
```

`--no-js-runtimes` must precede `--js-runtimes`. On the test host Deno was
installed, and yt-dlp enabled it by default even when QuickJS was added.
Clearing defaults makes QuickJS 2026-06-04 the only enabled runtime. The
official pinned `yt-dlp.exe` bundles matching `yt_dlp_ejs-0.8.0`; the verbose
log checks both identities. `--ignore-config` prevents local user settings from
changing the result. `--skip-download` keeps these probes at analysis only.

| Interpretation | Options after the common options | Verified JSON result |
|---|---|---|
| Single YouTube URL | `--dump-single-json --no-playlist -- https://www.youtube.com/watch?v=uW13KuRrg1g` | `_type: video`, `id: uW13KuRrg1g`, 14 formats |
| Pure YouTube playlist | `--dump-single-json --flat-playlist -- https://www.youtube.com/playlist?list=PL6B3937A5D230E335` | `_type: playlist`, `id: PL6B3937A5D230E335`, 17 flat entries including both locked Blender IDs |
| Mixed video and playlist URL | `--dump-single-json --no-playlist -- "https://www.youtube.com/watch?v=u9lj-c29dxI&list=PL6B3937A5D230E335"` | `_type: video`, `id: u9lj-c29dxI`, 48 formats; no playlist expansion |

Exact PowerShell invocations from the repository root (the verifier captures
stdout/stderr, times each process and validates the JSON):

```powershell
$yt = (Resolve-Path work/engine/downloads/yt-dlp.exe).Path
$qjs = (Resolve-Path work/engine/build/quickjs/windows-x64/qjs.exe).Path
$common = @('--ignore-config', '--verbose', '--no-js-runtimes', '--js-runtimes', "quickjs:$qjs", '--skip-download')
& $yt @common --dump-single-json --no-playlist -- 'https://www.youtube.com/watch?v=uW13KuRrg1g'
& $yt @common --dump-single-json --flat-playlist -- 'https://www.youtube.com/playlist?list=PL6B3937A5D230E335'
& $yt @common --dump-single-json --no-playlist -- 'https://www.youtube.com/watch?v=u9lj-c29dxI&list=PL6B3937A5D230E335'
```

The single and mixed commands use `--no-playlist` to implement D-28. The pure
playlist deliberately omits it. `--` keeps the URL from being parsed as an
option. The verifier has a 180-second timeout per CLI command, checks the
fixture lock immediately before running, and rejects unexpected JSON shapes.

The full playlist's flat analysis took **6.80 seconds** on the 2026-10-19
Windows run. This measures playlist page extraction and JSON serialization;
flat entries do not extract each video or measure JS challenge execution. The
two video requests registered QuickJS as the only available challenge runtime
and detected bundled EJS 0.8.0, but YouTube did not issue a challenge in this run. This
measurement alone cannot justify D-08's Deno fallback. See
[`analyze.txt`](gates/evidence/0b/analyze.txt) for versions, hashes and output.

Reproduce the probe:

```powershell
powershell -NoProfile -File scripts/gate-0b/verify-cli.ps1 -Case analyze
```

## 0B-14 — MP3 single presets

The locked Commons original has Vorbis audio. For each B in 320, 256, 192 and
128, this command downloaded its only WebM format and converted the audio to
MP3 with the pinned LGPL-compatible ffmpeg and LAME build:

```powershell
$yt = (Resolve-Path work/engine/downloads/yt-dlp.exe).Path
$qjs = (Resolve-Path work/engine/build/quickjs/windows-x64/qjs.exe).Path
$ff = (Resolve-Path work/engine/build/ffmpeg/windows-x64/recipe/ffmpeg-8.1.3).Path
$out = (Join-Path (Get-Location) 'work/engine/cli/mp3-singles/manual')
foreach ($B in @(320, 256, 192, 128)) {
    New-Item -ItemType Directory -Path (Join-Path $out "$B") -Force | Out-Null
    & $yt --ignore-config --verbose --no-js-runtimes --js-runtimes "quickjs:$qjs" --no-playlist -f 'ba/b' -x --audio-format mp3 --audio-quality "${B}K" --keep-video --ffmpeg-location $ff -o "$out/$B/source.%(ext)s" -- 'https://upload.wikimedia.org/wikipedia/commons/a/aa/10%E8%99%9F%E9%A2%A8....webm'
    & (Join-Path $ff 'ffprobe.exe') -v error -show_entries 'stream=codec_name,codec_type,bit_rate:format=duration,bit_rate' -of json -- "$out/$B/source.mp3"
}
```

The exact verifier creates a fresh ignored output directory, checks executable
hashes, runs the fixture preflight, then requires four successful conversions,
matching SHA-256 values for each retained WebM original, and ffprobe results.
Each output had one MP3 audio stream, no video,
and 14.749025 seconds duration. Stream bitrates were exactly 320000, 256000,
192000 and 128000 bps, within the verifier's 1% encoder tolerance. All output
hashes differ. VLC 3.0.24 opened and played each for more than two seconds via
its libVLC player API. See [`mp3-singles.txt`](gates/evidence/0b/mp3-singles.txt)
for hashes, playback method and ignored full-log path.

Reproduce the probe:

```powershell
powershell -NoProfile -File scripts/gate-0b/verify-cli.ps1 -Case mp3-singles
```

The same Appendix B command does **not** force re-encoding when the best source
is already MP3. On the locked Archive `effect-acid.mp3` entry, both 320K and
128K requests preserved its 128 kbps stream and produced identical hashes.
That finding is preserved in the same evidence file. The Commons result proves
the presets for a non-MP3 source only; the Phase 1/2 UI behavior for an
already-MP3 source remains an open owner decision.

## 0B-15 — MP3 playlist Max/Min

The first probe used the Archive `PureDataSoundEffects` playlist, whose three
selected originals were already 128 kbps MP3s. The exact earlier command and
failure are preserved below. The resumed probe uses the locked CC0
`vvalkabout` playlist and its non-MP3 WAV originals at positions 11, 12 and
18. It runs one playlist CLI invocation for Max and one for Min. The resumed
media command, repeated for B=320 and B=128, is:

```powershell
$yt = (Resolve-Path work/engine/downloads/yt-dlp.exe).Path
$qjs = (Resolve-Path work/engine/build/quickjs/windows-x64/qjs.exe).Path
$ff = (Resolve-Path work/engine/build/ffmpeg/windows-x64/recipe/ffmpeg-8.1.3).Path
foreach ($B in @(320, 128)) {
    $out = Join-Path (Get-Location) "work/engine/cli/mp3-playlist/manual/$B"
    New-Item -ItemType Directory -Path $out -Force | Out-Null
    & $yt --ignore-config --verbose --no-js-runtimes --js-runtimes "quickjs:$qjs" --playlist-items '11,12,18' -f 'ba/b' -x --audio-format mp3 --audio-quality "${B}K" --ffmpeg-location $ff -o "$out/%(playlist_index)s.%(ext)s" -- 'https://archive.org/details/vvalkabout'
}
```

Three separate Max CLI invocations also succeeded, one per locked direct
original URL. The verifier uses this command shape for each entry:

```powershell
& $yt --ignore-config --verbose --no-js-runtimes --js-runtimes "quickjs:$qjs" --no-playlist -f 'ba/b' -x --audio-format mp3 --audio-quality 320K --ffmpeg-location $ff -o "$out/11.%(ext)s" -- 'https://archive.org/download/vvalkabout/glitch1.wav'
```

The other two use `12`/`glitch2.wav` and `18`/`hunter.wav`. Pinned ffprobe
measured one audio-only MP3 stream in every output: 320000 bps for all three
Max outputs and three per-entry outputs, and 128000 bps for all three Min
outputs. The per-entry Max files matched their playlist Max counterparts by
SHA-256. VLC 3.0.24/libVLC advanced through all nine files beyond two seconds.
The exact commands, durations, hashes and player positions are in
[`mp3-playlist.txt`](gates/evidence/0b/mp3-playlist.txt). This proves separate
CLI invocations work for these direct Archive originals; it does not implement
or test the application queue.

The reproducible verifier command is:

```powershell
powershell -NoProfile -File scripts/gate-0b/verify-cli.ps1 -Case mp3-playlist
```

On 2026-10-19 the media commands both exited 0 and processed all three locked
entries. yt-dlp skipped conversion for all six downloaded MP3s. Pinned ffprobe
reported 128000 bps on every file: Min met 128 kbps; Max missed 320 kbps for
all three. For each entry the Max and Min hashes were identical. VLC 3.0.24
opened and advanced all six files beyond two seconds. The verifier exited 1
on the Max mismatch, so that original probe stopped. Per-entry CLI invocations
were not tested on those already-MP3 sources. See
[`mp3-playlist.txt`](gates/evidence/0b/mp3-playlist.txt) for the original
input lock, hashes, durations, logs and playback result. The owner approved
the separate non-MP3 fixture task 0B-15A, and the resumed 0B-15 probe above
passed on that fixture.

## 0B-16 — MP4 selection probe stopped

The locked Blender playlist at positions 2 and 3 offers distinct Max and Min
video heights. The metadata-only selection commands, repeated for S equal to
`bv*+ba/b` and `wv*+ba/w`, are:

```powershell
$yt = (Resolve-Path work/engine/downloads/yt-dlp.exe).Path
$qjs = (Resolve-Path work/engine/build/quickjs/windows-x64/qjs.exe).Path
$common = @('--ignore-config', '--verbose', '--no-js-runtimes', '--js-runtimes', "quickjs:$qjs")
& $yt @common --playlist-items '2,3' --skip-download -f $S --print '%(playlist_index)s|%(id)s|%(format_id)s|%(height)s|%(width)s|%(duration)s' -- 'https://www.youtube.com/playlist?list=PL6B3937A5D230E335'
```

For each playlist preset, the verifier then uses this full-download command:

```powershell
$ff = (Resolve-Path work/engine/build/ffmpeg/windows-x64/recipe/ffmpeg-8.1.3).Path
$out = (Join-Path (Get-Location) 'work/engine/cli/mp4/manual/max')
& $yt @common --playlist-items '2,3' -f 'bv*+ba/b' --merge-output-format mp4 --ffmpeg-location $ff -o "$out/%(id)s.%(ext)s" -- 'https://www.youtube.com/playlist?list=PL6B3937A5D230E335'
```

For Min, the selector is `wv*+ba/w` and the output directory is `min`. The
planned bounded-height single uses `--no-playlist -f
"bv*[height<=240]+ba/b[height<=240]" --merge-output-format mp4` with the
locked `archive-video` URL. The exact verifier entrypoint is:

```powershell
powershell -NoProfile -File scripts/gate-0b/verify-cli.ps1 -Case mp4
```

On 2026-10-19 the Max playlist command completed entry 2 as a valid MP4 with
VP9 1080p video and Opus audio. Entry 3's selected 1608p stream transferred
too slowly and hit the 600-second command bound at 46.3%; the verifier exited
1 before Min or the bounded single. A short-section diagnostic could not use
the pinned FFmpeg as a network downloader because that build lacks HTTPS
input. The exact observations and ignored log locations are in
[`mp4.txt`](gates/evidence/0b/mp4.txt). The original probe did not meet MP4
acceptance. The owner approved 0B-16A, which locked the short NatureClip
playlist at positions 4, 6 and 7 in [`fixtures.md`](gates/evidence/0b/fixtures.md).
The successful rerun below retains this stopped finding.

## 0B-16 rerun — NatureClip MP4 Max/Min and bounded-height single

The exact verifier command passed with pinned yt-dlp, QuickJS and FFmpeg:

```powershell
powershell -NoProfile -File scripts/gate-0b/verify-cli.ps1 -Case mp4
```

For `S` equal to `bv*+ba/b` (Max) and `wv*+ba/w` (Min), the verifier used
these exact option sequences. `$yt`, `$qjs` and `$ff` resolve to the pinned
paths above; `$out` is a fresh ignored directory for each preset.

```powershell
& $yt @common --playlist-items '4,6,7' --skip-download -f $S --print '%(playlist_index)s|%(id)s|%(format_id)s|%(height)s|%(width)s|%(duration)s' -- 'https://www.youtube.com/playlist?list=PL7EDEF163A9B185EF'
& $yt @common --playlist-items '4,6,7' -f $S --merge-output-format mp4 --ffmpeg-location $ff -o "$out/%(id)s.%(ext)s" -- 'https://www.youtube.com/playlist?list=PL7EDEF163A9B185EF'
```

The bounded single used the locked Archive video URL with `H=240`. Its
unbounded comparison selected 480p; the capped command selected 360×240.

```powershell
& $yt @common --no-playlist --skip-download -f 'bv*[height<=240]+ba/b[height<=240]' --print '%(id)s|%(format_id)s|%(height)s|%(width)s|%(duration)s' -- 'https://archive.org/details/Justin_Cone_-_Building_On_The_Past_-_640x480'
& $yt @common --no-playlist --skip-download -f 'bv*+ba/b' --print '%(height)s' -- 'https://archive.org/details/Justin_Cone_-_Building_On_The_Past_-_640x480'
& $yt @common --no-playlist -f 'bv*[height<=240]+ba/b[height<=240]' --merge-output-format mp4 --ffmpeg-location $ff -o "$out/%(id)s.%(ext)s" -- 'https://archive.org/details/Justin_Cone_-_Building_On_The_Past_-_640x480'
```

Max selected 1080p, 720p and 1080p video for the three playlist entries;
Min selected 144p for all three and retained each Max audio format. Pinned
ffprobe confirmed one video and one audio stream at each selected size in all
seven MP4 files. VLC 3.0.24 played each past two seconds with video decoding
enabled. The download trace shows yt-dlp `http` or `hlsnative` fetching media;
all twelve FFmpeg merge inputs were local `file:` paths. Exact dimensions,
codecs, hashes, timings and player positions are in
[`mp4.txt`](gates/evidence/0b/mp4.txt).

## 0B-17 — MP4 AAC compatibility

The earlier 0B-16 Max probe retained Opus audio in the MP4 for NatureClip
playlist entry 7. The locked 16-second entry has H.264 video and Opus audio,
so it tests the audio conversion without requiring a video transcode. The
Archive Ogg item in the fixture plan remains an untested candidate for this
case; the AAC result below uses the already locked NatureClip source. Apply
the AAC override only after selecting a non-AAC source. A source that already
has AAC can use the ordinary MP4 merge shown in 0B-16.

The exact reproducible verifier passed:

```powershell
powershell -NoProfile -File scripts/gate-0b/verify-cli.ps1 -Case aac
```

It first ran a metadata-only `--dump-single-json` with `-f 'bv*+ba/b'` and
confirmed separate `137` H.264 video and `251` Opus audio. It then ran this
media command with the pinned executables and a fresh ignored output path:

```powershell
$yt = (Resolve-Path work/engine/downloads/yt-dlp.exe).Path
$qjs = (Resolve-Path work/engine/build/quickjs/windows-x64/qjs.exe).Path
$ff = (Resolve-Path work/engine/build/ffmpeg/windows-x64/recipe/ffmpeg-8.1.3).Path
$out = Join-Path (Get-Location) 'work/engine/cli/aac/manual'
New-Item -ItemType Directory -Path $out -Force | Out-Null
& $yt --ignore-config --verbose --no-js-runtimes --js-runtimes "quickjs:$qjs" --no-playlist -f 'bv*+ba/b' --merge-output-format mp4 --postprocessor-args 'Merger+ffmpeg_o:-c:a aac' --keep-video --ffmpeg-location $ff -o "$out/%(id)s.%(ext)s" -- 'https://www.youtube.com/watch?v=YC0kTqKbeFs'
```

`--merge-output-format mp4` alone does not change Opus to AAC, as the 0B-16
probe showed. The `Merger+ffmpeg_o` override appends `-c:a aac` before the
output file: the recorded FFmpeg command used `-c copy` for the streams, then
`-c:a aac` for audio. Its two inputs were local `file:` paths. `--keep-video`
retained the downloaded components so pinned ffprobe could confirm Opus in
the source; it is an inspection option for this probe. Pinned ffprobe found
H.264 and AAC in the final MP4 at the selected 1920×1080 resolution. VLC
3.0.24/libVLC entered playing state and advanced past two seconds with video
decoding enabled. See [`aac.txt`](gates/evidence/0b/aac.txt) for source and
output stream details, hashes, logs and player results.

The [yt-dlp postprocessor-argument reference](https://github.com/yt-dlp/yt-dlp/blob/master/README.md#post-processing-options)
defines the `Merger+ffmpeg_o` placement; the [FFmpeg stream-codec reference](https://ffmpeg.org/ffmpeg.html#Stream-specifiers-1)
defines `-c:a` as an audio-only codec choice. The passing pinned CLI trace
above is the version-specific proof for this command.

## 0B-18 — Metadata and JPEG covers

The verifier runs the pinned executables with fresh ignored output paths and
checks source fields before downloading. The Archive playlist's position 2
reports `title=acid`, `creator=Andy Farnell`, no `artist`, and playlist title
`Pure Data sound effects by Andy Farnell`. Its per-track PNG is present in the
Archive catalog and embed playlist, but yt-dlp does **not** expose a
`thumbnail` field for this entry. The command therefore downloads the MP3 with
mapped metadata, then fetches that locked track's PNG and uses local FFmpeg to
convert it to an embedded JPEG cover. This is an explicit source-specific
fallback; `--embed-thumbnail` alone is not a passing Archive command.

```powershell
$yt = (Resolve-Path work/engine/downloads/yt-dlp.exe).Path
$qjs = (Resolve-Path work/engine/build/quickjs/windows-x64/qjs.exe).Path
$ff = (Resolve-Path work/engine/build/ffmpeg/windows-x64/recipe/ffmpeg-8.1.3).Path
$common = @('--ignore-config', '--verbose', '--no-js-runtimes', '--js-runtimes', "quickjs:$qjs")
$artistRule = '%(artist,creator,uploader|)s:%(meta_artist)s'
$albumRule = '%(playlist_title|)s:%(meta_album)s'
$base = Join-Path (Get-Location) 'work/engine/cli/metadata/manual'
$archiveOut = Join-Path $base 'archive'
$videoOut = Join-Path $base 'video'
New-Item -ItemType Directory -Path $archiveOut,$videoOut -Force | Out-Null
& $yt @common --playlist-items 2 --skip-download --dump-json -- 'https://archive.org/details/PureDataSoundEffects'
& $yt @common --playlist-items 2 -f 'ba/b' -x --audio-format mp3 --embed-metadata --parse-metadata $artistRule --parse-metadata $albumRule --ffmpeg-location $ff -o "$archiveOut/source.%(ext)s" -- 'https://archive.org/details/PureDataSoundEffects'
Invoke-WebRequest -Uri 'https://archive.org/download/PureDataSoundEffects/effect-acid.png' -OutFile "$archiveOut/cover.png" -UseBasicParsing -TimeoutSec 90
& (Join-Path $ff 'ffmpeg.exe') -hide_banner -loglevel info -y -i "$archiveOut/source.mp3" -i "$archiveOut/cover.png" -map '0:a:0' -map '1:v:0' -c:a copy -c:v mjpeg -q:v 2 -id3v2_version 3 -metadata:s:v title='Album cover' -metadata:s:v comment='Cover (front)' "$archiveOut/archive-cover.mp3"
```

The short NatureClip single reports `title=FREE Time-Lapse stock footage: Full
Moon CC-BY NatureClip`, no artist/creator, uploader `NatureClip: Free Stock
Footage`, no playlist title, and YouTube thumbnails. The selected video/audio
are the same H.264/Opus pair as 0B-17, so the AAC merge override is required.
yt-dlp tried thumbnail 44, found it unavailable, and embedded available
thumbnail 43 as JPEG. `--convert-thumbnails jpg` was accepted but did not
transcode that already-JPEG image; the Archive PNG path above proves conversion.

```powershell
& $yt @common --no-playlist --skip-download --dump-single-json -- 'https://www.youtube.com/watch?v=YC0kTqKbeFs'
& $yt @common --no-playlist -f 'bv*+ba/b' --merge-output-format mp4 --postprocessor-args 'Merger+ffmpeg_o:-c:a aac' --embed-metadata --embed-thumbnail --convert-thumbnails jpg --parse-metadata $artistRule --parse-metadata $albumRule --ffmpeg-location $ff -o "$videoOut/single.%(ext)s" -- 'https://www.youtube.com/watch?v=YC0kTqKbeFs'
```

The exact verifier is `powershell -NoProfile -File
scripts/gate-0b/verify-cli.ps1 -Case metadata`. Pinned ffprobe found the mapped
tags and one `mjpeg` attached-picture stream in each output; the MP3 cover is
800×200 and the MP4 cover is 1280×720. VLC 3.0.24/libVLC reported the title,
artist and album fields and played both files beyond two seconds. Its
`ArtworkURL` metadata field was empty for both, so the probe does not claim
that VLC displayed the image visually. Exact hashes, durations and player
output are in [`metadata.txt`](gates/evidence/0b/metadata.txt).

The [yt-dlp metadata and thumbnail options](https://github.com/yt-dlp/yt-dlp/blob/master/README.md#post-processing-options)
and [FFmpeg MP3 attached-picture documentation](https://ffmpeg.org/ffmpeg-all.html)
describe the CLI behavior; the pinned runs above establish the outcome for
these fixtures.

## Gate 0B transport review for the command matrix

The pinned FFmpeg build cannot open `https://` inputs. The stopped 0B-16
`--download-sections` diagnostic exposed this because it handed a remote media
URL to FFmpeg. This is an **OPEN** compatibility question for HLS/DASH paths
where yt-dlp can choose FFmpeg as the downloader. The build and 600-second
timeout remain unchanged.

At 0B-21, review **every required command** against this rule: record the
selected media protocol and downloader from verbose output, then confirm that
every FFmpeg input is a local file. A required row fails matrix review if
FFmpeg must fetch HTTPS, including a selected HLS or DASH stream. This check
also applies when adding the 0B-17 through 0B-20 commands. A TLS-enabled
FFmpeg rebuild needs an owner licensing decision first.

| Current matrix row | Media fetcher / FFmpeg role | Review state |
|---|---|---|
| 0B-13 analysis | Metadata extraction only; no media transfer or FFmpeg | No FFmpeg HTTPS dependency |
| 0B-14 MP3 singles | yt-dlp fetches HTTPS original; FFmpeg reads the retained local WebM for MP3 conversion | No FFmpeg HTTPS dependency in passing probe |
| 0B-15 MP3 playlist | yt-dlp fetches HTTPS WAV originals; FFmpeg reads local files for MP3 conversion | No FFmpeg HTTPS dependency in passing probe |
| 0B-16 MP4 playlist rerun | yt-dlp HTTP fetched all six Max streams; its HLS native downloader fetched three Min video streams, and HTTP fetched three Min audio streams. FFmpeg merged local files only, with twelve `file:` inputs. | No FFmpeg HTTPS dependency in passing probe |
| 0B-16 bounded-height single | yt-dlp HTTP fetched the selected MP4; no FFmpeg merge was needed. | No FFmpeg HTTPS dependency in passing probe |
| 0B-17 AAC | yt-dlp HTTP fetched H.264 and Opus components; FFmpeg read two local `file:` inputs, copied video and encoded AAC audio. | No FFmpeg HTTPS dependency in passing probe |
| 0B-18 metadata/cover | yt-dlp HTTP fetched Archive MP3 and NatureClip media/thumbnail; PowerShell fetched Archive PNG. FFmpeg read local MP3, PNG and MP4 components; MP4 image embedding used mutagen. | No FFmpeg HTTPS dependency in passing probe |
| 0B-19 through 0B-20 | Check each selected protocol and actual downloader when its required command runs. | Pending command-specific review |
