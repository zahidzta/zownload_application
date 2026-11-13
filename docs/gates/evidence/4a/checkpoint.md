<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
<!-- SPDX-FileCopyrightText: 2026 zahidzta -->

# Gate 4A — Linux runtime checkpoint

**Accepted by the owner:** 2026-11-12.

The owner confirmed that the remaining V3 native VM update scenarios passed
and authorized continuing to the next stage. Gate 4A is accepted. The owner
attestation and its evidence limits are recorded in [4A-05](4a-05.md).

| Acceptance area | Result | Evidence |
|---|---|---|
| Linux engine runtime and app-data copies | Pass. V1 verified Linux x86_64 paths, hashes, bootstrap, health checks, update verification/fallback, permissions, and process cleanup. | [V1 CI](https://github.com/zahidzta/zownload_application/actions/runs/41545291079) |
| Linux packages, update metadata, and provenance | Pass. V2 verified the signed AppImage and `.deb`, combined Windows/Linux asset allowlist, update metadata, engine inputs, hashes, and notices. | [V2 evidence](4a-04.md) |
| Native Linux install and download behavior | Pass. Recorded Ubuntu 24.04.5 AppImage and `.deb`, Debian 13.7 `.deb`, and Fedora Workstation 45 AppImage smoke results include single/playlist downloads and the applicable shutdown/queue checks. | [V3 evidence](4a-05.md#remaining-v3-and-acceptance) |
| Native app-update flows | Owner reports passing Ubuntu AppImage updates with and without FUSE 2, Ubuntu and Debian `.deb` updates, and Fedora Workstation 45 AppImage update from 0.0.1 to 0.0.2. The Ubuntu/Debian administrator prompts and matching package flows passed. | [Owner confirmation](4a-05.md#owner-confirmation-and-checkpoint-acceptance-2026-11-12) |
| Engine update and lifecycle criteria | V1 focused checks passed; the owner also reports a successful yt-dlp update from Settings and checked the before/after version and hash. Native AC-29 shutdown and paused restoration are recorded. | [V1 CI](https://github.com/zahidzta/zownload_application/actions/runs/41545291079), [V3 evidence](4a-05.md) |
| Linux desktop release compliance | Pass for the Linux portion. The engine build inputs, exact package resources, LGPL-compatible configuration, source links, and notices are recorded. | [V2 evidence](4a-04.md), [engine source lock](../../../engine-sources.md), [build recipes](../../../engine-builds.md), [third-party notices](../../../THIRD-PARTY-NOTICES.md) |

The owner did not include the exact VM build metadata, package hashes, engine
version/hash values, or screenshots with the final confirmation. The native
update outcomes above are therefore owner-attested; they were not independently
inspected in this session.

## Remaining work

- Global AC-23 and AC-36 coverage for macOS and Android remains open. The
  Android distribution blocker and the other release obligations remain in
  [STATE.md](../../../STATE.md#release-blocker--android-distribution).
- The Windows engine-hash fix is merged to `main`, but published v0.0.2 still
  contains the affected resources. A new Windows build and update/install
  review are still required to deliver that fix to users.
- No new public release was created as part of this checkpoint. Gate 4B's
  macOS plan is the next stage and requires its own owner-approved plan before
  implementation.
