<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
<!-- SPDX-FileCopyrightText: 2026 zahidzta -->

# Gate 3C task evidence

Gate 3C was accepted by the owner on 2026-11-02; see the [checkpoint](checkpoint.md).

- Completed 3C-01: Approved the Windows-only AC-23/AC-36 plan; commit `76c8ba9`; [plan](../../gate-3c.md).
- Completed 3C-02/03-fix: Preserved verified installer lifetime and waited for ZIP worker cleanup; commit `50df838`; [post-fix V2 evidence](3c-03.md#post-merge-downloadbootstrapper-v2-rerun-after-console-window-fix--passed).
- Completed 3C-03-log-fix: Isolated installer request logs per scenario; commit `a108e86`; [post-fix V2 evidence](3c-03.md#post-merge-downloadbootstrapper-v2-rerun-after-console-window-fix--passed).
- Completed 3C-03-exit-fix: Corrected verifier exit status after expected tamper rejection; commit `65e9d50`; [historical V2 evidence](3c-03.md#earlier-automatic-v2-result--offlineinstaller).
- Completed 3C-02-v1-url-fix: Resolved GitHub API asset IDs to draft package names; commit `a155a14`; [production rerun evidence](3c-02.md#v1-asset-url-verifier-correction--2026-11-02).
- Completed 3C-02-V1: Verified signed Windows x64 NSIS/MSI packages and bundle-aware metadata in run `41393046389`; commit `d18b552`; [production evidence](3c-02.md#v1-production-draft-run--passed).
- Completed 3C-02-size-change: Selected `downloadBootstrapper`; PR build `41484361422` measured unsigned NSIS 33.90 MB and MSI 39.32 MB; commit `4251b8e`; [size evidence](3c-02.md#pull-request-build-size-measurement--2026-11-02).
- Completed 3C-02-V1-rerun-pre-fix: Verified production-signed NSIS/MSI assets, metadata, signatures, and tamper rejection in run `41496741229`; commit `dfaa56d`; [V1 evidence](3c-02.md#signed-production-v1-rerun-with-downloadbootstrapper--passed).
- Completed 3C-03-V2-rerun-pre-fix: Passed clean install, same-format update, relaunch/version, and uninstall for NSIS/MSI in run `41500715879`; commit `dfaa56d`; [historical V2 evidence](3c-03.md#previous-downloadbootstrapper-v2-result-before-console-fix--passed).
- Completed 3C-02-V1-console-rerun: Verified signed NSIS/MSI assets, metadata, signatures, and tamper rejection in run `41515896085`; evidence commit `77ec64a`; [V1 record](3c-02.md#signed-production-v1-rerun-after-console-window-fix--passed).
- Completed 3C-03-V2-console-rerun: Passed NSIS/MSI install, same-format update, relaunch/version, and uninstall in run `41519891153`; evidence commit `77ec64a`; [V2 record](3c-03.md#post-merge-downloadbootstrapper-v2-rerun-after-console-window-fix--passed).
- Completed 3C-04-docs: Added Windows install instructions, desktop provenance, criterion mapping, and initial V3 checks; commits `be8e9fc` and `77ec64a`; [checkpoint](checkpoint.md) and [provenance](release-provenance.md).
- Completed 3C-04-console-fix: Suppressed Windows engine console windows during analysis/download; commit `bde48f6`; [local follow-up evidence](3c-03.md#owner-reported-console-window--fix-verified-locally).
