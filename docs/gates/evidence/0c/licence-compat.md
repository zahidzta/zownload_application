# 0C-01B licence compatibility audit

Checked 2026-10-20. Scope: every direct npm runtime/development package in `package.json` and every direct Cargo runtime/build/test crate in `src-tauri/Cargo.toml`, at the exact versions in `package-lock.json` and `src-tauri/Cargo.lock`. This is a manifest-level compatibility check; resolved Android packages, engine binaries, and all transitive dependencies need the later Gate 0C package/source inventory before release. No library was integrated for this task.

The repository's new SPDX identifier is `GPL-3.0-or-later`. The root [LICENSE](../../../../LICENSE) is byte-identical to the official [GNU GPLv3 plain text](https://www.gnu.org/licenses/gpl-3.0.txt): 35,149 bytes, SHA-256 `3972dc9744f6499f0f9b2dbf76696f2ae7ad8af9b23dde66d6af86c9dfb36986`. The identifier's “or later” choice is stated in the manifests and README; the GNU licence text itself was not changed.

## Direct npm packages

Licence values below come from the locked entries in [`package-lock.json`](../../../../package-lock.json), which record npm registry package metadata. Each listed value is compatible with GPL-3.0-or-later under the owner's stated MIT/Apache/BSD/ISC/MPL acceptance rule.

| Package | Locked version | Declared licence | Result |
|---|---:|---|---|
| `@tauri-apps/api` | 2.12.0 | Apache-2.0 OR MIT | Compatible |
| `react` | 19.3.1 | MIT | Compatible |
| `react-dom` | 19.3.1 | MIT | Compatible |
| `zustand` | 5.0.15 | MIT | Compatible |
| `@tailwindcss/vite` | 4.3.3 | MIT | Compatible |
| `@tauri-apps/cli` | 2.12.0 | Apache-2.0 OR MIT | Compatible |
| `@types/node` | 24.19.2 | MIT | Compatible |
| `@types/react` | 19.3.0 | MIT | Compatible |
| `@types/react-dom` | 19.3.0 | MIT | Compatible |
| `@vitejs/plugin-react` | 6.1.2 | MIT | Compatible |
| `tailwindcss` | 4.3.3 | MIT | Compatible |
| `typescript` | 7.0.2 | Apache-2.0 | Compatible |
| `vite` | 8.3.4 | MIT | Compatible |

## Direct Cargo crates

Licence values were checked against each version's primary crates.io metadata, with versions confirmed in [`Cargo.lock`](../../../../src-tauri/Cargo.lock). `serde_json` is a test-only direct dependency; `tauri-build` is build-only.

| Crate | Locked version | Declared licence | Primary metadata | Result |
|---|---:|---|---|---|
| `tauri-build` | 2.7.3 | Apache-2.0 OR MIT | [crates.io](https://crates.io/api/v1/crates/tauri-build/2.7.3) | Compatible |
| `serde` | 1.0.229 | MIT OR Apache-2.0 | [crates.io](https://crates.io/api/v1/crates/serde/1.0.229) | Compatible |
| `tauri` | 2.12.4 | Apache-2.0 OR MIT | [crates.io](https://crates.io/api/v1/crates/tauri/2.12.4) | Compatible |
| `serde_json` | 1.0.154 | MIT OR Apache-2.0 | [crates.io](https://crates.io/api/v1/crates/serde_json/1.0.154) | Compatible |

**Result:** 17/17 direct dependencies have a compatible declared licence. None is GPL-2.0-only, proprietary, or unknown in this direct inventory. This does not certify combined release artifacts; legal review remains open before the first public release.

## Owner review and remaining mentions

The full line-numbered `rg` inventory is [`licence-mentions.txt`](licence-mentions.txt). It includes historical Gate 0A/0B evidence, true third-party MIT/LGPL licences, old planning alternatives, and current requirements. The scan intentionally excludes its own output file and the verbatim GNU `LICENSE` text.

`PROJECT.md` lines **388, 627, 684, and 708** still state a repo MIT or LGPL-only release commitment; **751–752** state historical Gate 0A/B deliverables in those terms. Lines **370, 473–474** describe third-party or desktop build licences, which remain facts about those components. Gate 0C also flags **372, 753, and 820** for owner review of the Option A engine/update plan. `PROJECT.md` was not edited. The existing `docs/PROJECT-INDEX.md:11`, `docs/gates/evidence/0b/checkpoint.md:16`, and earlier state/decision records also retain historical wording, as shown in the inventory.

**Per-file source headers:** should new and existing source files receive an SPDX header, and if so which copyright name/year convention should be used? No headers were added in this task.
