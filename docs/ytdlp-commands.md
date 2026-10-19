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

## 0B-15 — MP3 playlist Max/Min (stopped)

The verifier first confirms the locked Archive playlist's 39 flat entries and
the three bounded IDs at positions 2–4, then runs one playlist CLI invocation
for Max and one for Min. The tested media command, repeated for B=320 and
B=128, is:

```powershell
$yt = (Resolve-Path work/engine/downloads/yt-dlp.exe).Path
$qjs = (Resolve-Path work/engine/build/quickjs/windows-x64/qjs.exe).Path
$ff = (Resolve-Path work/engine/build/ffmpeg/windows-x64/recipe/ffmpeg-8.1.3).Path
foreach ($B in @(320, 128)) {
    $out = Join-Path (Get-Location) "work/engine/cli/mp3-playlist/manual/$B"
    New-Item -ItemType Directory -Path $out -Force | Out-Null
    & $yt --ignore-config --verbose --no-js-runtimes --js-runtimes "quickjs:$qjs" --playlist-items '2:4' -f 'ba/b' -x --audio-format mp3 --audio-quality "${B}K" --ffmpeg-location $ff -o "$out/%(playlist_index)s.%(ext)s" -- 'https://archive.org/details/PureDataSoundEffects'
}
```

The reproducible verifier command is:

```powershell
powershell -NoProfile -File scripts/gate-0b/verify-cli.ps1 -Case mp3-playlist
```

On 2026-10-19 the media commands both exited 0 and processed all three locked
entries. yt-dlp skipped conversion for all six downloaded MP3s. Pinned ffprobe
reported 128000 bps on every file: Min met 128 kbps; Max missed 320 kbps for
all three. For each entry the Max and Min hashes were identical. VLC 3.0.24
opened and advanced all six files beyond two seconds. The verifier exited 1
on the Max mismatch, so 0B-15 is not accepted. Per-entry CLI invocations remain
untested. See [`mp3-playlist.txt`](gates/evidence/0b/mp3-playlist.txt) for the
exact input lock, hashes, durations, logs and playback result. Gate 0B stops
pending an owner decision about a separate non-MP3 playlist fixture task.
