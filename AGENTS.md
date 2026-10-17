Before anything else, read docs/STATE.md and the current gate file.

# Zownload agent instructions

- The owner uses OpenAI Codex, knows React/TypeScript, and has little Rust/Tauri experience. Explain Rust changes plainly; keep Rust simple, commented, and based on established crates.
- Authority: `shared/contract.ts` and `src-tauri/src/contract.rs` govern field names and types; `PROJECT.md` governs behavior and intent; confirmed images indexed by `docs/design/README.md` govern visuals. Report conflicts to the owner.
- Use `docs/PROJECT-INDEX.md` to locate relevant specification lines. Never load all of `PROJECT.md` automatically.
- Before writing code that uses a library or framework, consult its current documentation through context7.

## Session protocol

1. One task per session. Read this file, `docs/STATE.md`, the current gate file, and only the `PROJECT.md` ranges listed for that task.
2. Use subagents or parallel work only for independent tasks and only when the tool supports them. Otherwise work sequentially, one task per session. Delegated results are at most 10 lines: changes, files touched, test status, blockers.
3. Limit command output to failures or the last 50 lines. Read large files only for the relevant task ranges.
4. If `PROJECT.md` is ambiguous or contradicts another authority, ask the owner; do not silently decide.
5. When verification passes, commit the task, update `docs/STATE.md`, commit that update, then stop and tell the owner to start a fresh session.
6. Respect Appendix A's delivery rule: do not start the next stage until the owner accepts the checkpoint.

## Build, test, and delivery

- No app build/test scripts exist yet. Once Gate 0A creates them, use the current gate task's exact commands and record setup commands in `docs/toolchain.md`.
- Work on one `task-<id>` branch per task. After verification, commit and open a PR with `gh pr create`. Never merge, force-push, or create releases; the owner does that.
- For CI failures use `gh run list --limit 5` and `gh run view <id> --log-failed | tail -50`. Never print full logs.
