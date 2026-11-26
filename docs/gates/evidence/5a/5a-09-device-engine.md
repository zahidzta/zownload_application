<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
<!-- SPDX-FileCopyrightText: 2026 zahidzta -->

# Gate 5A-09 — Physical device proof

## Result

V4 passed on the physical OnePlus BE2011. Android now selects the native Tauri
transport, so React reads the same Rust queue, history, and settings state as
the device engine. Gate 5A checkpoint acceptance remains pending the owner's
explicit review; Gate 5B has not started.

## Device and build

- Device: OnePlus BE2011, serial `b1c28e0d`, Android API 29, ABI `arm64-v8a`.
- App APK SHA-256: `b4a9af302878d68e343ae3c5eecbccadf3c505c3bdfdefe670eb0c870df9cac1`.
- Instrumentation APK SHA-256: `c83a4506dcf8e89b1903861bfcce8c8bfb304b24a407fdfce5b97624cd762a45`.
- Physical proof: `powershell -NoProfile -File scripts/gate-5a/verify.ps1 -Case device-engine` — passed.
- Transport coverage: `npm.cmd run test:ui -- tests/interactive/nativeRuntime.test.tsx` — 3 tests passed.
- Full device logs and APKs remain local under `work/android/gate-5a/5a-09-device-engine/`.

## Fixtures and outputs

- MP3: Gate 0B/Gate 0C fixture `uW13KuRrg1g` (`10號風...`), 236,589 bytes,
  SHA-256 `579af752d3c4738e27a18833ac9e4de5269bef05317a38b7188169ba999137fc`.
- MP4: NatureClip video `Dkx4LYeFnVY`, playlist position 4, recorded CC BY in
  [Gate 0B fixture evidence](../0b/fixtures.md); 300,716 bytes,
  SHA-256 `ef6b20a536eab93d43445bda6f70a358b71ec748f9964cccc1cd8a80eac55fc5`.
  The test verified the ISO BMFF `ftyp` signature.
- Playlist: owner-provided
  `https://music.youtube.com/playlist?list=OLAK5uy_mg1CCHw9rqPEBSPT1Yb4TcvArZLsQDndU&si=rf35jGZWQgZ255mz&drli=1`.
  Metadata-only preflight resolved three entries (`devorarte`, `cuerpo frío`,
  `perdón`). Device outputs:
  - `devorarte`: 6,151,725 bytes, SHA-256 `b445e05c5c310082af332774c4cd7e88642d9ddd80ecaa2130a737a51e0451dc`.
  - `cuerpo frío`: 6,566,445 bytes, SHA-256 `565574d8131a11eff0ca62a7383196462cbea8d95633b73dbd1506392050eae2`.
  - `perdón`: 6,545,325 bytes, SHA-256 `70ad31793e46532acad38ac9a2b7961f6095f276d55f41b28efebf64afcb0be2`.
- Cancellation: Gate 0C Sintel fixture `eRsGyueVLvQ`; removed while downloading
  at 1.81% before recreation and 7.27% after restoration. It did not enter history.

The Music playlist was supplied for this local device test. Its media rights
were not independently verified; this evidence does not claim that playlist is
rights-cleared for redistribution or wider fixture use.

## Integration results

- Settings round trip: `zipPlaylists=false`, language `en`.
- Rust queue retained the active cancellation item across Activity/WebView
  recreation; the React Queue card showed its URL while the engine title was
  still unresolved.
- Rust history contains the completed MP3, MP4, and playlist; the cancelled
  item is absent. The queue is empty after cleanup.
- MP3/MP4/playlist outputs were written to app-private staging. Public Downloads
  via MediaStore, ZIP packaging, Android 15 lifecycle behavior, and release APK
  distribution remain outside this task. The Android distribution blocker in
  the Gate 5A plan remains open.
