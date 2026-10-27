<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
<!-- SPDX-FileCopyrightText: 2026 zahidzta -->

# 2C-02 — Windows single worker evidence

## Scope

The Rust worker accepts only single MP3/audio and MP4/video quality pairs. It probes one HTTP(S) URL with the verified app-data yt-dlp copy, chooses the requested height or the closest available lower height, and downloads with `--continue --part` into a queue-id-owned app-data directory. Its arguments always include `--ignore-config`, `--no-plugin-dirs`, `--no-remote-components`, `--no-playlist`, and `--` before the URL. The Windows supervisor streams bounded diagnostic tails and progress lines while retaining whole-tree cancellation, timeout, and close ownership. The caller supplies the private path record and a short persistence callback, so the worker does not hold the shared database mutex during media transfer. Queue scheduling, database progress checkpoints, UI events, and History/error settlement belong to 2C-03.

For MP3, the pinned local FFmpeg inspects an already-MP3 stream's actual bitrate when yt-dlp omits `abr`. It copies at or below the selected maximum and encodes above it; a non-MP3 source is encoded. The FFmpeg metadata pass sets the analyzed title and available artist/creator/uploader, preserves an existing source artist when the extractor omitted one, clears single-item album, and attaches an available JPEG thumbnail. MP4 uses the Gate 0B AAC merge option and thumbnail/metadata postprocessors. Output uses an exclusive file creation loop with ` (1)`, ` (2)` collision suffixes. SQLite schema 3 records the chosen output folder, private work directory, and an incomplete final-file reservation under the queue id. A restart can clear that reservation while keeping the `.part`; cleanup checks ownership before deleting files.

No wire contract, package dependency, or product requirement changed. Playlist requests are rejected by this worker and remain queued for 3A. The system Downloads path is supplied by the caller when `downloadDir` is null; 2C-03 will call Tauri's `download_dir()` when recording an enqueue. A chosen folder is captured in the private path record so a later Settings change does not redirect resume.

## Documentation checked

Context7 was consulted for `rusqlite` and yt-dlp before edits but returned **monthly quota exceeded** for both. The fallback references were the [rusqlite transaction/SQL documentation](https://docs.rs/rusqlite/latest/rusqlite/struct.Transaction.html), [yt-dlp CLI reference](https://github.com/yt-dlp/yt-dlp/blob/master/README.md), and [Tauri path resolver documentation](https://docs.rs/tauri/latest/tauri/path/struct.PathResolver.html). The latter documents `download_dir()` resolving Windows `FOLDERID_Downloads`. Gate 0B's [verified command matrix](../../../ytdlp-commands.md) supplied the pinned option profiles.

## Deterministic verification

- Exact V1 passed on 2026-10-26: `powershell -NoProfile -Command 'cargo fmt --manifest-path src-tauri/Cargo.toml --check; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; cargo test --manifest-path src-tauri/Cargo.toml; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; cargo check --manifest-path src-tauri/Cargo.toml; exit $LASTEXITCODE'`. The library/unit and integration suites passed, the two opt-in real-media and stub proofs remained ignored in this deterministic suite, and `cargo check` finished successfully.
- Focused Windows process-tree/stream-tail test passed separately: `cargo test --manifest-path src-tauri/Cargo.toml --test process_tree windows_supervisor_cleans_timeout_cancel_close_and_parent_exit -- --nocapture` (one test passed, including its child helper).
- Rust unit tests cover single-only arguments, quality guards, lower-height fallback, MP3 copy/reencode choice, malformed/oversized progress, phase observations, disk/permission classification, migration/reopen, folder capture, collision reservation, failed-copy cleanup, and owned-only `.part` cleanup. The existing Windows test covers child-tree timeout, cancellation, window close, and abrupt parent exit.

## Pinned Windows CLI proof

The final opt-in integration command ran from the repository root and passed both tests:

```powershell
$env:ZOWNLOAD_TEST_SINGLE_CLI = '1'
cargo test --manifest-path src-tauri/Cargo.toml --test single_cli -- --ignored --nocapture --test-threads=1
Remove-Item Env:ZOWNLOAD_TEST_SINGLE_CLI
```

The tests bootstrapped the checked installation resources into ignored `work/engine/2c-02/.../app-data/engine/` before execution. The real Archive downloads executed those app-data copies. The generated high-bitrate fixture used a tiny local yt-dlp stub to feed the worker while the pinned app-data FFmpeg performed the actual bitrate inspection and encode. Pinned hashes: yt-dlp `66674953fe251b89f4d08c5f0e35e0728679bd67ab3d7d05c0562af101dd3e7a`, FFmpeg `fa050630ddf5b7c3303d8dab5e5a42e7023547fb78ec9b90b5be0a4f788a7e66`, QuickJS `bec67f8f87fa22958d3ab8be5508088116b8bff90032323d82c94545e1698b83`; inspection used pinned ffprobe `bf44a50347aaba3e433c34c8c881d67eeaca41001577482ce3ba69b780824ec7` from Gate 0B.

The final real-download run is retained under ignored `work/engine/2c-02/proof-fc720a6d-cbb3-4431-8a3b-332326739606/`. `ffprobe -v error -show_entries 'format=duration,bit_rate:format_tags=title,artist,album:stream=codec_name,codec_type,width,height,bit_rate:stream_disposition=attached_pic' -of json -- <file>` showed:

| Request/output | Stream and metadata inspection | SHA-256 |
|---|---|---|
| Archive `effect-acid.mp3`, MP3 320 maximum | 128,000 bit/s MP3 copied at its source bitrate; title `effect-acid`; existing source artist `Andy Farnell` preserved; 174,015 bytes. This direct media URL exposes no thumbnail in yt-dlp. | `5b579a9e627c3a868014fa3094a94c787289e68823dc7a3d8b01fcc43d5f34ed` |
| Archive Justin Cone single, MP4 240 | H.264 360×240, AAC audio, attached 160×110 MJPEG cover; title and creator-derived artist; no album; 8,675,087 bytes. | `e4f09a42e8fbc3576880c34e6bd137e989c9c7c25cee96caebac4420ddc2b6b7` |

The final local fixture is retained under ignored `work/engine/2c-02/local-stub-0891b10b-0f79-4436-b8a1-0198731d05e4/`. Pinned app-data FFmpeg generated a two-second 256,000 bit/s MP3; the stub copied it into the private work folder and emitted bounded progress; the worker then inspected the actual stream and encoded it to 128,000 bit/s at the selected 128 maximum. Pinned ffprobe reported 256,000 → 128,000 bit/s and equal two-second durations. Source SHA-256: `ec83d54da021f72b1c6167bbd6e4baccc8aaf05208cbe397e75d76613c03d84d`; output SHA-256: `f9d3638101dca015825f68567e9052f85dd23a45f87aa0f36b4888d0f89669d2`.

An earlier passing NatureClip run under ignored `work/engine/2c-02/proof-6b32440c-a5ca-45e5-a9d6-3e202786282c/` also produced a non-MP3-to-192,000-bit/s MP3 with a 1280×720 JPEG cover and a 720p H.264/AAC MP4 with the same cover. Their SHA-256 values are `fbe1b6ff85b539274ced2fa3ae04cc1eb24f0e21e9ed4835b553bcd138943f5e` and `a098791beb17058078fb2c8b281a8fefd43f37007c3a3dfd569c36d806c7e76d`, respectively. A later YouTube rerun timed out and requested bot sign-in, so the final live test uses Archive. Localhost HTTP attempts intermittently failed with Windows `ConnectionAbortedError(10053)` before sending a request, so the final bitrate probe uses a deterministic stub. A direct Archive item-page MP3 request selected a large MOV transfer and was stopped; its process tree exited without an orphan. The first Archive MP3 run exposed an FFmpeg codec-label variant (`mp3 (mp3float)`); the parser was corrected before the final run. Native playback, visible Queue progress, real pause/restart, and History/error settlement remain for 2C-03/04.
