<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
<!-- SPDX-FileCopyrightText: 2026 zahidzta -->

# Gate 5A-03 — CPython and yt-dlp Android runtime evidence

Completed 2026-11-23. The approved CPython `3.14.10` source build and locked
yt-dlp/EJS packages passed the runtime verifier for Android `arm64-v8a`.

## Pinned inputs and verification

The CPython source archive SHA-256 is
`de414a57119abef52784d8993e341d53aed635fc2b05c2607d9f98a2c5b72032`.
The six native dependencies, upstream source hashes, recipe tags and commits,
and NDK pin adjustments are in the [approved Gate 5A source lock](../../../engine-sources.md#gate-5a-android-python-runtime-lock--owner-approved-2026-11-22).
The build patches CPython's `Android/android-env.sh` from NDK `27.3.13750724`
to `30.0.16248370`, and applies each locked `cpython-android-source-deps`
recipe's NDK `android-env.sh` adjustment before building. The captured recipe
source and patch snapshot is
`work/android/gate-5a/5a-03-cpython/recipe-source-snapshots.tar.gz` (62,289
bytes, SHA-256
`1f2bee6a29cd324c7d389e8274d5954eca844ab626c84d8e00a600cb0ed9137b`).
Checksum-verified source archives and package sources are retained under the
same work directory.

The exact verifier command was:

```powershell
pwsh -NoProfile -File scripts/gate-5a/verify.ps1 -Case python-runtime
```

It passed with `CPython 3.14.10`, yt-dlp `2026.08.19`, EJS `0.8.0`, and ABI
`arm64-v8a`. The build host was Ubuntu 24.04 x86_64 under WSL2, PowerShell
7.7.0, Corretto `21.0.11.10.1`, Python `3.12.3`, Node.js `24.22.0` / npm
`11.19.1`, GCC `13.3.0`, and GNU Make `4.3`. Android Command-Line Tools were
`22.0`; the target used NDK `30.0.16248370`, Clang `21.0.0`, and API 24. The
app build used Android SDK API 36 and build-tools `36.0.0`.

## Runtime output and package hashes

The source-built runtime archive is 28,147,727 bytes, SHA-256
`54a37d70d4ab1f379bde40312154cdd6f15f8b916a5de359a579771c4b4d2efe`.
It targets `aarch64-linux-android` / `arm64-v8a`, API 24. The verifier recorded
122 ELF files and their hashes and `DT_NEEDED` entries in the local
`runtime-manifest.json` (38,562 bytes, SHA-256
`773b1d93b70bc3fc3d0732da4b007cf12049093d99c6ef1d8a9f812a9dd8b7aa`). The
unique direct dependencies are `libc.so`, `libcrypto_python.so`, `libdl.so`,
`liblog.so`, `libm.so`, `libpython3.14.so`, `libsqlite3_python.so`,
`libssl_python.so`, and `libz.so`.

| Source-built native dependency | Version / recipe | Output archive SHA-256 |
|---|---|---|
| bzip2 | 1.0.8 / `bzip2-1.0.8-3` | `691dbc06f28c342029445ff0841b33eb3b52804f919c501e746715f1a3f811c3` |
| libffi | 3.4.4 / `libffi-3.4.4-3` | `f3ea402af71e843f8115b1421168c130b1db8cc8940b1c4d27c54f8a243ecdd9` |
| OpenSSL | 3.5.9 / `openssl-3.5.9-0` | `a7fd9f6c0a5bb2e9a4a4ae1e3a22c10e0867959a6fe68c86b7f92ae931f72a99` |
| SQLite | 3.53.4 / `sqlite-3.53.4-0` | `a0b66817d8da7c668cdc239209ff6f5164dc7f7085aeaa16670c31ad40451d42` |
| xz | 5.4.6 / `xz-5.4.6-1` | `9918e5395349bc791a97146e2eb2e66b9a020ceabe64e0f72321e96fbeec492d` |
| zstd | 1.5.7 / `zstd-1.5.7-2` | `ac2fd8b92eb0e6047db4739897711f4cdabd8238c5bbc98d35e1b3ab2886c2c7` |

| Locked Python source package | Version | Source archive SHA-256 |
|---|---:|---|
| Brotli | 1.2.0 | `e310f77e41941c13340a95976fe66a8a95b01e783d430eeaf7a2f87e0a57dd0a` |
| certifi | 2026.7.22 | `741e2c3b351ddf169a738da9f2c048608ff7f2c5cc02f1ebc6b118bb090d5d55` |
| charset-normalizer | 3.5.0 | `49bd5feb59b0bf3cbf6ebcf4352e371c95b9da9bacd4449f8b64d0ad2c10a26e` |
| idna | 3.18 | `ffb385a7e039654cef1ab9ef32c6fafe283c0c0467bba1d9029738ce4a14a848` |
| Mutagen | 1.48.1 | `8f95637ab9f6f305cec6bd1294e197debe207998e3e068596563c74f86b0a173` |
| pycryptodomex | 3.23.0 | `71909758f010c82bc99b0abf4ea12012c98962fbf0583c2164f8b84533c2e4da` |
| requests | 2.34.2 | `f288924cae4e29463698d6d60bc6a4da69c89185ad1e0bcc4104f584e960b9ed` |
| urllib3 | 2.7.0 | `231e0ec3b63ceb14667c67be60f2f2c40a518cb38b03af60abc813da26505f4c` |
| websockets | 17.0.1 | `5baa9bc0dfbae8c507e51c8cf1b6d4628086f7a87bbd3a9952bd5f035451f1cc` |
| yt-dlp-ejs | 0.8.0 | `d5fa1639f63b5c4af8d932495f60689d5370f1a095782c944f7f62a303eb104e` |
| yt-dlp | 2026.08.19 | `072aad4f2a7604e92155f61a275a4752dc64046c8f6d90df3710525d94cd37c1` |

## APK packaging inspection

`npm run android:debug` passed with the staged runtime. The resulting APK is
145,920,095 bytes, SHA-256
`09d5d2ce5d61d5f42f5db5e99925bed606c753dc7d72a1a71ce63aad581d3668`. The
pre-runtime baseline APK was 104,333,480 bytes, SHA-256
`1f3a7394be295f448e4935fe86546fecb219f38892f635b32ca0b456db158e98`. The
APK has 15 native-library entries, all under `lib/arm64-v8a/`, and 2,129
`assets/python-runtime/` entries (24,080,233 bytes uncompressed; 7,658,340
bytes compressed).

The APK still contains the inherited `libpython.so` and `libpython.zip.so`
payloads from `youtubedl-android` `0.18.1`. This is expected at 5A-03: task
5A-06 removes those opaque AAR payloads and performs the final transitive
provenance audit. This APK remains local and must not be shared.

## Notices and source materials

The [third-party notice inventory](../../../THIRD-PARTY-NOTICES.md#android-cpython-runtime)
records the runtime and host-only build dependency licenses. Packaged source
distributions retain their upstream metadata and license files where supplied.
The source lock records the archive checksums, recipe commits, patch inputs,
and Python package licenses; the local build log and complete runtime manifest
are under `work/android/gate-5a/5a-03-cpython/`.
