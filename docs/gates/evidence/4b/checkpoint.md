<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
<!-- SPDX-FileCopyrightText: 2026 zahidzta -->

# Gate 4B — macOS runtime checkpoint

**Accepted by the owner:** 2026-11-22.

The owner accepted Gate 4B after reporting that the native install/update review passed and authorized proceeding to the next task. V3 is owner-attested; the available detail limits are recorded in [4B-04 evidence](4b-04.md). Gate 4B is accepted. See the [task evidence](tasks.md).

| Acceptance area | Result | Evidence |
|---|---|---|
| macOS engine runtime and app-data copies | Pass. CI verified x86_64 and arm64 paths, hashes, bootstrap, health checks, update fallback, permissions, cancellation, and process shutdown. | [4B-02 evidence](4b-02.md) |
| Architecture-specific packages, updater metadata, and provenance | Pass. V2 verified the two DMGs and signed updater bundles, platform mappings, asset allowlist, hashes, engine inputs, and notices. | [4B-03 evidence](4b-03.md) |
| Native install, Gatekeeper, downloads, playlist, and shutdown | Pass, owner-attested for both architecture baselines. Exact host metadata, screenshots, and raw logs were not supplied with the confirmation. | [4B-04 evidence](4b-04.md) |
| Native app update | Pass, owner-attested. The installed/candidate version pair was not included in the confirmation. | [4B-04 evidence](4b-04.md) |
| AC-20, AC-22, AC-23, and macOS portion of AC-36 | Pass for macOS. | [4B-03 evidence](4b-03.md), [4B-04 evidence](4b-04.md) |

No public release was created for this checkpoint. Android's source/build/notice blocker and other global release obligations remain open in [STATE.md](../../../STATE.md#release-blocker--android-distribution). The next task is Gate 5A planning; resolve that Android blocker before production-engine implementation.
