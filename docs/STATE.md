# Zownload state

- Current gate: Gate 0A execution in this checkout; the owner approved rebuilding it from scratch on 2026-10-17 (`docs/gates/gate-0a.md`).
- Completed setup: project index, root agent guidance, state memory, Gate 0A task breakdown, and reusable gate template (`79dbae4`).
- Completed 0A-07: MIT `LICENSE` and `docs/THIRD-PARTY-NOTICES.md` template committed on `task-0a-07` (`ae318fc`). No engine artifacts or app scaffold were added by this task.
- Verification 0A-07: both exact `rg -q` commands passed; all three notice sections contain source, version, checksum, license and build-configuration fields; staged whitespace check passed. MIT text was checked against OSI.
- Completed 0A-01: exact Tauri/Rust/Node/npm/JDK/NDK/SDK pins, vendor source links, setup commands and the selected OS matrix are recorded in `docs/toolchain.md` on `task-0a-01` (`278e020`). No app scaffold or tools were installed by this task.
- Verification 0A-01: the exact `rg -n 'Tauri|Rust|Node|package manager|JDK|NDK|SDK|Windows|macOS|Android' docs/toolchain.md` command passed; every match and version was reviewed manually, and staged `git diff --cached --check` passed. Local Node/Rust/JDK/SDK versions differ from the pins; installation/build proof belongs to later Gate 0A tasks.
- Next task: **0A-02 — Empty React/Vite frontend** in a fresh session after 0A-01 is integrated. It must use the Node/npm pins in `docs/toolchain.md` and run its exact `npm run build` check. Gate 0A is not yet complete.
- Key decisions: Codex is the owner tool; no `opencode.json` and no automatic full `PROJECT.md` loading. Contract files govern types, `PROJECT.md` behavior, design images visuals.
- Key decisions: one task per session; each completed task records evidence here and gets its own `task-<id>` branch and PR when GitHub is available.
- Key decisions: `docs/` is no longer ignored. The 0A-06 design inventory work is committed on its separate `task-0a-06` branch (`90815ae`) and is not part of this task branch.
- Repository note: this checkout still has no app scaffold, lockfiles or CI; `PROJECT.md:15` describes a different accepted checkpoint. The owner approved rebuilding Gate 0A here.
- Delivery: PR #1 for `task-0a-07` was merged into `main` (`9dae6b6`), including the Gate 0A brief clarification commit (`e0ddd23`).
- OS matrix decision: Windows 10 1803+, macOS 10.15+, Android 7/API 24, and Ubuntu 24.04 as the Gate 0A Linux CI baseline. The Linux user minimum remains a Stage 4A decision per `PROJECT.md:208`; CI/device and clean-install validation are still required by `PROJECT.md:208,715`.
- Checkpoint: do not begin Gate 0B until Gate 0A evidence is complete and the owner explicitly accepts it.
