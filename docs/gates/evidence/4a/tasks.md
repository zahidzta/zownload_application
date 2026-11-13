<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
<!-- SPDX-FileCopyrightText: 2026 zahidzta -->

# Gate 4A task evidence

Gate 4A was accepted by the owner on 2026-11-12; see the [checkpoint](checkpoint.md).

- Completed 4A-01: Approved the Linux runtime and release plan; commit `1c9c221`; [plan and V0 evidence](../../gate-4a.md#verification).
- Completed 4A-02: Added Linux runtime paths, pinned engines, verified app-data copies, and process cleanup; commit `0fabf35`; [V1 CI](https://github.com/zahidzta/zownload_application/actions/runs/41545291079).
- Completed 4A-02-R1: Embedded hashes for staged Windows FFmpeg/QuickJS after the v0.0.2 mismatch; commit `42187e4`; [regression evidence](4a-02-windows-regression.md).
- Completed 4A-03: Added Linux AppImage updates and the `.deb` direct-link updater; commit `3f6af9c`; [gate plan](../../gate-4a.md).
- Completed 4A-04: Built signed Linux AppImage/`.deb`, verified combined release metadata, and recorded provenance; commits `571fd8f`–`3ca4bbd`; [V2 evidence](4a-04.md).
- Completed 4A-05: Completed native Linux install/update review; initial Debian portion commit `887bfca`, checkpoint commits `39bda59` and `9d2273a`; [V3 evidence](4a-05.md) and [checkpoint](checkpoint.md).
