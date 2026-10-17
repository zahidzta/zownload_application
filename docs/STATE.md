# Zownload state

- Current gate: Gate 0A planning only; `docs/gates/gate-0a.md` is the current task brief. No app work is authorized in this setup session.
- Completed: project index, root agent guidance, state memory, Gate 0A task breakdown, and reusable gate template committed in `task-setup` (`79dbae4`); no app code or scaffold added.
- Verification: structural checks passed (15 essentials lines; 12 tasks with all required fields; `AGENTS.md` 23/80 lines; `STATE.md` below 40 lines; no `opencode.json`; staged diff clean).
- Next: owner reviews this setup and resolves the gate-status discrepancy; then begin `0A-01` in a fresh session if Gate 0A is still needed.
- Key decisions: Codex is the owner tool; no `opencode.json` and no automatic full `PROJECT.md` loading. Contract files govern types, `PROJECT.md` behavior, design images visuals.
- Key decisions: one task per session; each completed task records evidence here and gets its own `task-<id>` branch and PR when GitHub is available.
- Key decisions: `docs/` is no longer ignored. Existing design images are still untracked and belong to inventory task 0A-06.
- Open question: `PROJECT.md:15` says Gate 0A was accepted and Gate 0B is active, but this checkout has no scaffold, lockfiles, CI, or toolchain record. Should Gate 0A be redone here, or should this repository be restored to that accepted checkpoint?
- Open question: no Git remote is configured and `gh` is unavailable in this checkout, so a PR cannot yet be opened.
- Open question for `0A-01`: confirm minimum OS matrix against the pinned toolchain (`PROJECT.md:208,715`).
- Checkpoint: do not begin Gate 0B until Gate 0A evidence is complete and the owner explicitly accepts it.
