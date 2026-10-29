<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
<!-- SPDX-FileCopyrightText: 2026 zahidzta -->

# Gate 2D-02 through 2D-04 — Windows engine update evidence

## Scope

The Windows engine manifest now retains a checksum-verified updated yt-dlp
across restart, including probation, failed versions, the last check clock,
and a pending activation. An app-version change refreshes the bundled FFmpeg
and QuickJS copies; the bundled yt-dlp replaces the active copy only when its
date version is newer or the updated copy is corrupt. A failed directory
promotion restores its previous directory, and startup recovers a backup left
by an interrupted two-rename promotion. All active paths remain in app data.

The release client asks the official stable yt-dlp GitHub release API for one
`yt-dlp.exe` and one `SHA2-256SUMS` asset with the matching tag. It bounds
redirects to GitHub release hosts, connection and request times, metadata and
asset sizes, and stages downloads in app data. The exact checksum entry must
match the downloaded bytes before the ten-second version probe can run. The
pending version and hash are durable; a queue-idle activation uses a shared
engine slot, so an active analysis or download holds off the directory swap.
During probation, invocations use a separate gate so the first outcome and
its possible fallback/retry stay together. Healthy-version analysis can still
run while a download is active. The Windows directory promotion retries
transient access/sharing errors for at most five seconds after a probe exits.
The first process-level failure during probation re-copies the verified
bundled baseline into app data and retries that invocation once. Reported
`ERROR:` and `WARNING:` site/network errors do not trigger fallback.

## Official stable release observed on 2026-10-28

- GitHub Releases API: `https://api.github.com/repos/yt-dlp/yt-dlp/releases/latest`
- Stable tag: `2026.10.26`; `draft = false`, `prerelease = false`.
- Published Windows asset: `yt-dlp.exe`, 23,575,744 bytes, SHA-256
  `f5389d3698ecde4ef06f4e6b1ce0294fe9ac1396228c8990b8d3416d6d177a7d`.
- The exact `yt-dlp.exe` line in the published `SHA2-256SUMS` has the same
  SHA-256. A downloaded copy hashed to that value and, when probed from a
  temporary directory under `LocalAppData/com.zownload.app`, printed
  `2026.10.26`. The temporary candidate was removed after the probe.
- The bundled baseline remains `2026.08.19`, SHA-256
  `66674953fe251b89f4d08c5f0e35e0728679bd67ab3d7d05c0562af101dd3e7a`.

## Deterministic local coverage

Rust tests use `http://127.0.0.1:<OS-assigned-port>/latest` with local
`/SHA2-256SUMS` and `/yt-dlp.exe` responses; no fixture executable is run
before checksum verification. Cases include malformed release metadata,
missing/duplicate checksum lines, checksum mismatch, non-executable
candidate, a timed-out metadata response, an interrupted asset body, strict
official URL/redirect host checks, wrong version, durable pending state, and an active slot
that holds activation until the process exits. Native activation copies the
pinned FFmpeg/QuickJS resources, executes a compiled local yt-dlp stub from
app data, records probation, and restores the pinned baseline from app data.
Manifest tests cover first launch, unchanged restart, updated restart,
legacy fields, corrupt copy, interrupted directory replacement, app-version
tool refresh, and numeric date-version order.

The focused queue integration uses a crashing updated stub and verifies that
the baseline is restored and the final notification comes from the single
baseline retry. A stub that emits a normal `ERROR:` site failure leaves the
updated copy in place and completes probation. Existing Windows process-tree
and queue tests cover cancellation, close, pause, and `.part` ownership.

## Verification and boundary

On 2026-10-29 the exact Gate 2D V1 command passed: Rust formatting check,
the full Rust test suite, and `cargo check`. `npm run check:contracts` passed.
The focused `process_tree` and `queue_lifecycle` integrations passed; the
full suite included the four-case `probation_queue` native integration. The
initial Windows rename failures were fixed with a bounded retry and the
final run passed. `engine_check_update`
and `engine_update` remain the scheduled 2D-05 native/UI wiring task; this
record covers the engine core used by those commands. Stage 2D-07 will repeat
the full native app flow with an official candidate and visible Settings
outcomes. App-update discovery and installer upgrade proof remain separate.
