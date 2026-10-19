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

## MP3 single preset probe — blocked (0B-14)

The proposed Appendix B command `-f "ba/b" -x --audio-format mp3
--audio-quality 320K` did not produce a 320 kbps file for the locked Archive
audio entry `effect-acid.mp3`. The best available source is already a 128 kbps
MP3. yt-dlp's ExtractAudio postprocessor reported that it was already in the
target format and skipped conversion; ffprobe measured 128,000 bps, with the
same output hash as a 128K request. The 256K and 192K presets and playback
remain untested. The proposed command is not verified for MP3 sources. See
[`mp3-singles.txt`](gates/evidence/0b/mp3-singles.txt) for the exact probe.
Task 0B-14A locked a short Commons original with Vorbis audio for the next
0B-14 run; no bitrate preset result is claimed from that fixture yet.
