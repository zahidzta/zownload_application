<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
<!-- SPDX-FileCopyrightText: 2026 zahidzta -->

# Gate 1C checkpoint — 2026-10-24

**Status:** The owner explicitly accepted the **full Gate 1C checkpoint** on 2026-10-24 and directed the Stage 2A plan. Tasks 1C-02 through 1C-10 were integrated, and the owner approved their pending Queue, History, notification, Settings, and responsive visual results before requesting 1C-11. This checkpoint records the accepted Gate 1C evidence under [Appendix A](../../../../PROJECT.md).

## Acceptance evidence

| Criterion | Deterministic evidence and result |
|---|---|
| AC-06 — empty Queue and History | The [shell test](../../../../tests/ui/shell.test.mjs) checks both exact English empty strings, and the [queue-card test](../../../../tests/interactive/queueCard.test.tsx) checks the mounted Queue after removal. The [empty-state browser capture](visual-review.md) shows both cards in the built app. |
| AC-07 — paused status and continuation | The [queue-card tests](../../../../tests/interactive/queueCard.test.tsx) check Paused, keyboard Stop/Continue, progress display, disabled Stop during processing, and missed-event recovery. The [simulator lifecycle test](../../../../tests/interactive/simulator.test.tsx) pauses only during downloading and resumes from recorded progress; its restart test restores an interrupted item as paused until explicit Continue. These prove mock UI/state behavior, not continuation of a real `.part` file. |
| AC-08 — playlist counts and failures | The [queue-card playlist test](../../../../tests/interactive/queueCard.test.tsx) checks completed/total and failure counts, including processing and packaging states. The [simulator tests](../../../../tests/interactive/simulator.test.tsx) drive playlist progress, partial success, all-failed outcomes, and terminal transitions with a manual clock. |
| AC-09 — direct Redownload | The [History tests](../../../../tests/interactive/historyCard.test.tsx) show that Redownload sends the stored request directly to Queue without opening the preview, while delete/clear persist and duplicate titles retain distinct ids. The [simulator tests](../../../../tests/interactive/simulator.test.tsx) cover newest-first replacement of an identical request and the closest-lower MP4 height fallback. |
| AC-18 — terminal queue removal | The accepted Download-to-cleared-Input portion was established in the [1B checkpoint](../1b/checkpoint.md). The [simulator terminal tests](../../../../tests/interactive/simulator.test.tsx) verify that success and partial success write History, all-failed writes a notification, and terminal items then leave Queue. The [notification UI test](../../../../tests/interactive/notificationCard.test.tsx) observes a failure after queue removal. |
| AC-19 — persistent failure notification | The [notification tests](../../../../tests/interactive/notificationCard.test.tsx) verify translated announcement, survival through UI recreation and mock transport restart, and visibility until a successful dismissal. The [activity tests](../../../../tests/interactive/activity.test.tsx) verify restart refetch and stale-snapshot reconciliation. The [simulator tests](../../../../tests/interactive/simulator.test.tsx) verify persisted notifications and dismissal across transport recreation. |

## UI recreation, Settings, and accepted decisions

- The [activity tests](../../../../tests/interactive/activity.test.tsx) subscribe before reading snapshots, reject stale queue/history/notification responses, share subscriptions across mounts, release them on unmount, and reload state into a new UI store. A failed queue snapshot leaves an accepted enqueue intact and offers Retry. The simulator's replaceable backing store preserves history, notifications, settings, and interrupted queue progress across new mock transports; restored active items become paused and do not auto-resume.
- The [Settings tests](../../../../tests/interactive/settings.test.tsx) cover immediate en/es switching, persisted ZIP choice and desktop folder path, picker cancellation, Android folder hiding, and separation of engine-update and app-update information. The [1C visual review](visual-review.md) records the native Windows folder dialog selection/cancel/reload/reset scenario. The chosen path is mock-stored and receives no download output.
- The owner approved omitting speed/ETA, which are absent from `Progress`; using **Cancel** for removal beside **Stop/Continue**; and using the native desktop folder picker with mock-stored settings. The [Gate 1C decision record](../../gate-1c.md) preserves the details. The owner also requested a centered Settings card and icon-only Back arrow; the [refreshed captures and measurements](visual-review.md) record the correction. Developer-information text remains a placeholder pending owner content.

## Reference, responsive, and accessibility review

The owner approved the pending 1C-06 through 1C-10 visual results on 2026-10-24. The [1C visual review](visual-review.md) compares active single and playlist cards to the two indexed desktop progress components and retains desktop/mobile captures for paused, History, notification, empty, and Settings states. Browser measurements in English and Spanish at 360, 369 at 2×, 738, 800, 1024, and 1920 CSS pixels found no horizontal overflow in 26 activity/Settings observations; visible actions were at least 44 CSS pixels high. Ten additional Settings measurements found zero horizontal center offset and a 44 × 44 CSS-pixel Back target. Secondary Queue/History text was corrected to meet the calculated 4.5:1 normal-text contrast threshold. Focus and notification announcement have focused interaction tests. Physical-device touch and screen-reader judgement remain open.

## Checkpoint verification

Gate 1C **V2** was run from `task-1c-11` on 2026-10-24 with the exact command below and exited **0**:

```powershell
powershell -NoProfile -Command 'npm run build; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; npm run test:ui; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; node --test --test-concurrency=1; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; powershell -NoProfile -File scripts/verify-foundation.ps1; exit $LASTEXITCODE'
```

- The frontend build passed; **12 interactive test files, 55/55 tests** passed.
- The sequential Node suite passed **18/18 tests** with no failures. Repeated Vite optimizer scans extended it to about **863 seconds**; they did not fail a test.
- The foundation verifier repeated the frontend build, checked TypeScript/shared JSON contract fixtures, passed **6 Rust unit tests and 1 Rust contract-parity test**, and verified all **9 tracked design PNGs** at their indexed dimensions.
- This checkpoint task changes documentation only. No production source, dependency, contract, or design image is committed. A pre-existing uncommitted `src-tauri/Cargo.toml` edit was present during verification and is excluded from this task's commits.

## Exit and carried limits

Gate 1C proves the offline mock UI and replaceable mock-store recovery. It does not verify Rust command handlers, SQLite persistence, real media output, process pause/kill, `.part` continuation, engine progress, or a real updater. Stage 2A must implement Rust-owned SQLite migrations and repositories for settings, history, queue, and error notifications; contract commands/events; restart recovery and ordering/uniqueness/serialization tests; and UI operation against that persistence boundary. Later stages own actual download lifecycle and media output. The Android distribution blocker, legal review, and other release conditions remain open in [STATE](../../../STATE.md). The owner accepted this checkpoint before Stage 2A planning began.
