<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
<!-- SPDX-FileCopyrightText: 2026 zahidzta -->

# 2B-08 — Real Windows analysis and shutdown review

Observed on 2026-10-25 (America/Mexico_City) with the Windows x64 debug
Tauri app built from `task-2b-08` using
`npm run tauri -- build --debug --no-bundle`. The app executable was
`src-tauri/target/debug/zownload.exe` (version `0.0.1`). Its bundled resource
copies were under `src-tauri/target/debug/binaries/`; the copies actually
executed were under `<LOCALAPPDATA>/com.zownload.app/engine/`. The app-data
manifest recorded yt-dlp version `2026.08.19`, source `bundled`, state `good`,
and no failed versions. The exact [Gate 0B fixture preflight](../0b/fixtures.md)
passed immediately before these runs. All three URLs are public, locked Gate 0B
fixtures; no private user data or media files were recorded.

| File in bundled resources and app data | SHA-256 in each location |
|---|---|
| `yt-dlp.exe` | `66674953fe251b89f4d08c5f0e35e0728679bd67ab3d7d05c0562af101dd3e7a` |
| `ffmpeg.exe` | `fa050630ddf5b7c3303d8dab5e5a42e7023547fb78ec9b90b5be0a4f788a7e66` |
| `qjs.exe` | `bec67f8f87fa22958d3ab8be5508088116b8bff90032323d82c94545e1698b83` |

## Live native results

The WebView called Rust's production `analyze_url` command in the running app.
The recorded command times use `performance.now()` around the native invoke;
the UI times include the Input submit and preview transition. Values below
were read from returned contract JSON, then checked against the visible preview.

| Input and URL mode | Native result and timing | Visible result |
|---|---|---|
| [YouTube short](https://www.youtube.com/watch?v=uW13KuRrg1g), single | `single` in **5,268 ms**; title `10號風...`, author `vgocyl`, site `YouTube`, duration `15` seconds, thumbnail present, video heights `[720,360,144]`, audio requested maxima `[320,256,192,128]`. No `estimates` field. | Input submission reached the single card in **6,142 ms**; `0:15` and the three MP4 heights appeared. [Native screenshot](native-single.png). |
| [Blender playlist](https://www.youtube.com/playlist?list=PL6B3937A5D230E335), pure playlist | `playlist` in **4,313 ms**; title `Official Blender Open Movies`, author `Blender`, site `YouTube`, thumbnail present, `itemCount: 17`, and 17 item titles, including `WING IT!` and `CHARGE`. | Input submission reached the playlist card in **4,593 ms**; 17 items, Max/Min quality, and a scrollable title list appeared. [Cover](native-playlist-cover.png), [quality/list](native-playlist-details.png), [list scroll](native-playlist-list.png). |
| [Wing It! with list parameter](https://www.youtube.com/watch?v=u9lj-c29dxI&list=PL6B3937A5D230E335), mixed watch/list | `single` in **5,548 ms**; title `WING IT! - Blender Open Movie`, author `Blender Studio`, site `YouTube`, duration `238` seconds, thumbnail present, video heights `[1080,720,480,360,240,144]`, fixed audio maxima `[320,256,192,128]`. No `estimates` field. | Input submission reached the single card in **6,154 ms**; `3:58` and six MP4 heights appeared, with no playlist list. [Native screenshot](native-mixed.png). |

The three results preserve each input URL exactly and use the contract's
`single`/`playlist` field shapes. No size estimate was invented. Thumbnails
loaded asynchronously after the card appeared; captures above were retaken
after the WebView images reported nonzero natural width. The screenshot set is
of the running native WebView at 420 × 700 CSS pixels, captured through its
[WebView2 debug port](https://learn.microsoft.com/en-us/microsoft-edge/webview2/how-to/debug-visual-studio-code);
it omits the Windows frame. The owner has not yet reviewed the visible result.

## Close during active analysis

After the real runs, a temporary Rust stub replaced **only** the app-data
`yt-dlp.exe` while the app remained open. This deliberately bypassed the
earlier bootstrap health check to exercise the actual UI command and window
close path. The stub's SHA-256 was
`012307d755efc16c60e51304c90238932cf98ee49c25103226b4441b15e653f3`.
It accepted the normal analysis argument array, created a child and grandchild,
and waited indefinitely. The [active native UI](native-close-active.png) showed
the disabled **Analyzing** button. The observed Windows process ancestry was:

```text
zownload.exe  PID 29324
└─ yt-dlp.exe stub  PID 3964
   └─ yt-dlp.exe stub  PID 3832
      └─ yt-dlp.exe stub  PID 26224
```

`CloseMainWindow()` returned `True`. A process snapshot three seconds later
found **none** of those four PIDs alive. The pinned app-data yt-dlp copy was
restored afterward; all three app-data hashes again matched the table above.
The temporary PID markers were removed. This observation covers a normal
Windows window close during active analysis; the deterministic supervisor test
also covers timeout, cancellation, and abrupt parent exit.

## Verification and limits

- Exact Gate 2B **V3 passed on 2026-10-26** in a clean detached worktree of
  `1ebddb8`, the same implementation source as `task-2b-08`. It used the
  repository-pinned Node `24.22.0`/npm `11.19.1`, verified copies of all three
  Windows resources, and `CARGO_TARGET_DIR` pointing to the existing local
  target directory. Results: 57 interactive tests in 13 files, 18 sequential
  Node tests, Rust formatting, frontend build, contract fixtures, 42 Rust
  library tests, analysis CLI and contract-parity integrations, Windows
  process-tree integration, and all nine design images. The foundation script
  ended with `Foundation verification passed.` Setup is recorded in
  [toolchain](../../../toolchain.md#2b-08-native-review-verification-setup-2026-10-26).
- A separate focused `cargo test --manifest-path src-tauri/Cargo.toml --test
  process_tree windows_supervisor_cleans_timeout_cancel_close_and_parent_exit
  -- --exact` passed in the working checkout before V3.
- The first V3 attempt in the generated working checkout passed all 57 UI
  tests, then Vite SSR module loading timed out in two Node test files while
  its optimizer rescanned dependencies. The isolated header test reproduced
  the timeout there even after reinstalling dependencies with pinned Node.
  The same test passed in 5 seconds in the clean checkout. Its first full V3
  attempt hit a Vitest fork startup timeout after 38 tests; the exact clean
  rerun passed. No product-source or test-harness change was made for these
  local startup failures.
- No native download was enqueued and no media was fetched. The playlist list
  is a flat metadata preview, so this run does not establish per-entry
  extraction or future download success. YouTube results can change with
  site responses, location, and access restrictions.
- Owner review of the screenshots and visible native result is still required
  before 2B-09 compiles the checkpoint.
