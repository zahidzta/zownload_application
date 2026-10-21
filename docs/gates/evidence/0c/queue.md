# 0C-07 — Durable one-item Rust queue

Verified on 2026-10-21 on `task-0c-07`.

## Implementation

- Rust stores one `QueueItem` JSON snapshot in a single-row SQLite table under Tauri's app-local data directory. The Rust queue ID is a UUID; Kotlin still has no queue or database.
- Enqueue writes `queued` and then `downloading` before invoking Kotlin. The blocking mobile-plugin call runs off Tauri's command thread, leaving `get_queue` available during engine work. Rust emits the contract's `queue:item-updated` and `queue:item-removed` events.
- Startup changes interrupted `analyzing`, `queued`, `downloading`, `postProcessing`, and `packaging` snapshots to `paused` while retaining their ID, request, and percent. It never invokes the engine or resumes work. A paused item occupies the one spike slot.
- The disposable React screen subscribes to both queue events, then calls `get_queue`. It reloads from Rust after events and ignores stale responses. It shows a restored paused item after WebView recreation.
- Rust validates monotonic percentages in `0..100` and saves each checkpoint atomically. The current Kotlin adapter returns only a final result, so live device downloads currently save 0% at start and 100% on success. An intermediate 25% checkpoint and its JSON shape are verified by the focused Rust test. A later callback task must connect real engine percentages; this task makes no live-progress claim.
- On success or failure Rust emits a terminal snapshot and clears the transient queue row. Persistent history and error notifications are outside this one-item spike.

## Verification

```powershell
cargo test --manifest-path src-tauri/Cargo.toml android_spike_queue
npm run android:debug
```

The exact focused Rust command passed **2/2 tests**. One test reopens the SQLite file after each active status and verifies restoration as `paused`, preserved ID and 37.5% checkpoint, and rejection of a second item. The other verifies the one-item limit, UUID, camelCase contract fields, status/progress JSON, monotonic progress, and removal.

The arm64 Android debug APK build passed with the pinned Corretto 21 JDK and NDK r30. Its Tauri build also ran `npm run build` successfully. This was a compile/package check only; device interruption, foreground service, real progress callbacks, and WebView recreation remain for 0C-08..12. The existing Android native corresponding-source/build-input/notice **OPEN RELEASE BLOCKER** and no-distribution rule remain unchanged.
