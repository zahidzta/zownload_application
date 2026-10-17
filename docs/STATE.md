# Zownload state

- Current gate: Gate 0A execution in this checkout; the owner approved rebuilding it from scratch on 2026-10-17 (`docs/gates/gate-0a.md`).
- Completed setup: project index, root agent guidance, state memory, Gate 0A task breakdown, and reusable gate template (`79dbae4`).
- Completed 0A-07: MIT `LICENSE` and `docs/THIRD-PARTY-NOTICES.md` template committed on `task-0a-07` (`ae318fc`). No engine artifacts or app scaffold were added by this task.
- Verification 0A-07: both exact `rg -q` commands passed; all three notice sections contain source, version, checksum, license and build-configuration fields; staged whitespace check passed. MIT text was checked against OSI.
- Completed 0A-06: restored the confirmed design index and nine original PNGs from `cf8b189` without changing their contents; added `scripts/check-design.ps1` on `task-0a-06` (`43bd172`). No UI was built.
- Verification 0A-06: `powershell -NoProfile -File scripts/check-design.ps1` passed for all nine tracked images and their listed dimensions; `git diff --cached --exit-code cf8b189 -- docs/design` confirmed the assets and index match the source commit; staged whitespace check passed.
- Next: begin a different Gate 0A task in a fresh session, observing its dependencies. Gate 0A is not yet complete.
- Key decisions: Codex is the owner tool; no `opencode.json` and no automatic full `PROJECT.md` loading. Contract files govern types, `PROJECT.md` behavior, design images visuals.
- Key decisions: one task per session; each completed task records evidence here and gets its own `task-<id>` branch and PR when GitHub is available.
- Key decisions: `docs/` is no longer ignored. The nine confirmed design images and their index are now tracked by Git.
- Repository note: this checkout has no app scaffold, lockfiles, CI, or toolchain record yet; `PROJECT.md:15` describes a different accepted checkpoint. The owner approved rebuilding Gate 0A here.
- Delivery: PR #1 for `task-0a-07` was merged into `main` (`9dae6b6`), including the Gate 0A brief clarification commit (`e0ddd23`).
- Open question for `0A-01`: confirm minimum OS matrix against the pinned toolchain (`PROJECT.md:208,715`).
- Checkpoint: do not begin Gate 0B until Gate 0A evidence is complete and the owner explicitly accepts it.
