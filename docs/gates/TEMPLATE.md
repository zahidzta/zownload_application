# Gate <ID> — <name>

## Scope and checkpoint

- Source: `PROJECT.md:<lines>`; current status: `docs/STATE.md`.
- Strict deliverable: <one reviewable stage result>.
- Exit evidence: <tests, manual scenario, artifacts, owner acceptance>.
- Stop on a failed hard requirement; record evidence and ask the owner before changing the architecture.

## Tasks

Each task should fit one roughly 30-minute session. `docs/STATE.md` is updated after every completed task. Do not load other `PROJECT.md` ranges without a task reason.

### <ID>-01 — <task title>

- Goal: <single outcome>.
- Files to touch: `<exact paths or directories>`.
- Read: `PROJECT.md:<start>-<end>`.
- Dependencies: <task IDs or none>; independent of <task IDs, if any>.
- Acceptance: <observable result and evidence>.
- Exact verification command: `<runnable command>`.

## Delivery

Commit verified work, record verification and decisions in `docs/STATE.md`, commit that update, and open a PR on `task-<id>` when GitHub is available. End the session. After all gate tasks pass, request the owner's checkpoint acceptance before the next stage.
