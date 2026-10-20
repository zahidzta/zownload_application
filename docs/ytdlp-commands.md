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
[`mp4.txt`](gates/evidence/0b/mp4.txt). The MP4 acceptance criteria remain
unverified; a shorter, rights-documented real playlist is the proposed next
fixture task, subject to owner review.
