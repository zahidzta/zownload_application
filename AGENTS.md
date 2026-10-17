## Documentation
- When using a library or framework, consult context7 to obtain the current documentation before writing any code.

## Git/GitHub
- Git/GitHub: one branch per task (task-<id>), commit when verification passes, open a PR with `gh pr create`. NEVER merge, force-push, or create releases; the owner does that.
- For CI failures use `gh run list --limit 5` and `gh run view <id> --log-failed | tail -50`. Never print full logs.