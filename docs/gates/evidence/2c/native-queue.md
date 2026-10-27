<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
<!-- SPDX-FileCopyrightText: 2026 zahidzta -->

# 2C-03 Windows queue and UI lifecycle

On 2026-10-27 the exact [Gate 2C V2 command](../../gate-2c.md#verification-commands) passed in a clean detached checkout containing the task changes. The run included the frontend build, interactive UI tests, contract check, sequential Node tests, Rust formatting, all Rust tests (including `queue_lifecycle`), and `cargo check`. The separate focused `cargo test --manifest-path src-tauri/Cargo.toml --test process_tree windows_supervisor_cleans_timeout_cancel_close_and_parent_exit` passed.

The first V2 run in the working checkout passed its frontend phases but failed in `node --test`: Node also discovered the ignored old `work/engine/2b-09/clean` checkout and ran duplicate React tests from two dependency trees. No source change was made for that failure. The clean checkout used pinned Node `24.22.0`, `npm ci` (120 packages, zero reported vulnerabilities), verified staged Windows engine resources, and the existing Cargo target directory. Exact setup is in [toolchain](../../../toolchain.md#gate-2c-03-clean-verification).

The deterministic Windows CLI stub demonstrates that a queued playlist does not block eligible singles; only one single starts; Pause retains a 10-byte `.part`; Continue reads that byte offset and produces a 20-byte file; Settings changes affect later enqueues only; Remove cleans owned work; a failure persists a notification; close leaves the active row paused and the partial intact. The event sink reads SQLite on each structural, terminal, History, and notification event, so an event before its matching commit fails the test. A separate persistence test settles terminal rows on reopen after an interrupted settlement.

The mounted native transport test checks Input clearing, Stop/Continue routing, translated failure recovery after UI recreation, and browser simulator isolation. Media playback, real site behavior, screenshot review, and pinned-artifact pause/resume remain the [2C-04 native review](../../gate-2c.md).
