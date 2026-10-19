# Gate 0B engine source lock

Locked on 2026-10-18 for task 0B-01 and attested in 0B-03. This is the
acquisition allowlist. A changed
version, URL, or digest requires a new source-lock task. All URLs identify a
versioned release or an immutable commit; no moving release channel is a pin.

```json source-lock
{
  "schema": 1,
  "ytDlp": {
    "version": "2026.08.19",
    "commit": "3a08beaf031ab68f966401ead017ac81fe8486cf",
    "license": "Unlicense (own code); GPL-3.0-or-later (official PyInstaller executables)",
    "ejsVersion": "0.8.0",
    "source": {
      "url": "https://github.com/yt-dlp/yt-dlp/releases/download/2026.08.19/yt-dlp.tar.gz",
      "sha256": "072aad4f2a7604e92155f61a275a4752dc64046c8f6d90df3710525d94cd37c1"
    },
    "checksumManifest": {
      "url": "https://github.com/yt-dlp/yt-dlp/releases/download/2026.08.19/SHA2-256SUMS",
      "sha256": "a63701f30755cb4d9317950d69703e9d751d490cb1b7059e1bb501a353fe7dcb",
      "signatureUrl": "https://github.com/yt-dlp/yt-dlp/releases/download/2026.08.19/SHA2-256SUMS.sig",
      "signatureSha256": "8d6f9a7c84c57222e3650c61699185878a3468308de702993ce4f20b5f9cf199"
    },
    "signingKey": {
      "url": "https://raw.githubusercontent.com/yt-dlp/yt-dlp/3a08beaf031ab68f966401ead017ac81fe8486cf/public.key",
      "sha256": "45d6b415928b5f3e228b461fa9e6d7eb56a824931c785ece00279a06c7a6d6e5",
      "fingerprint": "AC0CBBE6848D6A873464AF4E57CF65933B5A7581"
    },
    "binaries": {
      "windowsX64": {
        "url": "https://github.com/yt-dlp/yt-dlp/releases/download/2026.08.19/yt-dlp.exe",
        "sha256": "66674953fe251b89f4d08c5f0e35e0728679bd67ab3d7d05c0562af101dd3e7a"
      },
      "linuxX64": {
        "url": "https://github.com/yt-dlp/yt-dlp/releases/download/2026.08.19/yt-dlp_linux",
        "sha256": "58162f9bfdc27458ea47bfcb311cf47028f17d8154a8bf7d689861d46399230a"
      },
      "macosUniversal": {
        "url": "https://github.com/yt-dlp/yt-dlp/releases/download/2026.08.19/yt-dlp_macos",
        "sha256": "0f192b7ec147ab6288885d6351d9ab67367640029b4377576ef46dd79cf7b202"
      }
    }
  },
  "ejs": {
    "version": "0.8.0",
    "commit": "4fb477f4af56880cfd324c48bd4294a2d2294e50",
    "license": "Unlicense (own code); ISC and MIT in packaged solver scripts",
    "source": {
      "url": "https://files.pythonhosted.org/packages/d3/e6/cceb9530e8f4e5940f6f7822d90e9d94f1b85343329a16baaf47bbbb3de1/yt_dlp_ejs-0.8.0.tar.gz",
      "sha256": "d5fa1639f63b5c4af8d932495f60689d5370f1a095782c944f7f62a303eb104e"
    },
    "wheel": {
      "url": "https://files.pythonhosted.org/packages/e3/bd/520769863744b669440a924271a6159ddd82ad5ae26b4ac4d4b69e9f8d44/yt_dlp_ejs-0.8.0-py3-none-any.whl",
      "sha256": "79300e5fca7f937a1eeede11f0456862c1b41107ce1d726871e0207424f4bdb4"
    }
  },
  "quickjs": {
    "version": "2026-06-04",
    "license": "MIT",
    "source": {
      "url": "https://bellard.org/quickjs/quickjs-2026-06-04.tar.xz",
      "sha256": "b376e839b322978313d929fd20663b11ba58b75df5a46c126dd19ea2fa70ad2a"
    },
    "targets": ["windows-x64", "linux-x64", "macos-x64", "macos-arm64", "android-arm64"]
  },
  "ffmpeg": {
    "version": "8.1.3",
    "license": "LGPL-2.1-or-later only if configuration and linked libraries pass 0B-10/12",
    "source": {
      "url": "https://ffmpeg.org/releases/ffmpeg-8.1.3.tar.xz",
      "signatureUrl": "https://ffmpeg.org/releases/ffmpeg-8.1.3.tar.xz.asc",
      "signatureSha256": "5f2880c7fea01f8694d30cb9d06362f77241ee67ce5926b157a226b18f08a538",
      "sha256": "7138d28c96d9d3e3af4ee3d8cad72741f8ffb40da90c1112235dea3ecd3178a3"
    },
    "signingKey": {
      "url": "https://ffmpeg.org/ffmpeg-devel.asc",
      "sha256": "397b3becedcd5a98769967ff1ff8501ddc89f8368b8f766e4701377d7dbaabe5",
      "fingerprint": "FCF986EA15E6E293A5644F10B4322F04D67658D8"
    },
    "targets": ["windows-x64"]
  },
  "lame": {
    "version": "3.100",
    "license": "LGPL for encoder library; GPL-only mpglib decoder must be excluded",
    "source": {
      "url": "https://sourceforge.net/projects/lame/files/lame/3.100/lame-3.100.tar.gz/download",
      "sha256": "ddfe36cab873794038ae2c1210557ad34857a4b6bdc515785d1da9e175b1da1e"
    },
    "targets": ["windows-x64"]
  }
}
```

## Source and license evidence

| Component | Primary evidence | Acquisition and license meaning |
|---|---|---|
| yt-dlp | [immutable 2026.08.19 release](https://github.com/yt-dlp/yt-dlp/releases/tag/2026.08.19), [tagged README licensing section](https://github.com/yt-dlp/yt-dlp/blob/2026.08.19/README.md#licensing), [tagged dependency licenses](https://github.com/yt-dlp/yt-dlp/blob/2026.08.19/THIRD_PARTY_LICENSES.txt), [tagged own license](https://github.com/yt-dlp/yt-dlp/blob/2026.08.19/LICENSE) | Release page publishes the archive, binary, and checksum-file SHA-256 values above. Its README calls the official PyInstaller executables GPLv3+ combined works, despite yt-dlp's own Unlicense. Preserve the complete platform-specific notices and corresponding-source obligations. The source tarball and Unix zipimport variant also include ISC Meriyah and MIT Astring. |
| yt-dlp-ejs | [yt-dlp 2026.08.19 dependency pin](https://github.com/yt-dlp/yt-dlp/blob/2026.08.19/pyproject.toml), [ejs 0.8.0 release](https://github.com/yt-dlp/ejs/releases/tag/0.8.0), [PyPI artifact hashes and provenance](https://pypi.org/project/yt-dlp-ejs/0.8.0/), [tagged ejs license notes](https://github.com/yt-dlp/ejs/blob/0.8.0/README.md#licensing) | yt-dlp pins `yt-dlp-ejs==0.8.0` in both `default` and `pin` dependencies. Official standalone executables already bundle matching EJS; the separate source distribution and wheel preserve its provenance and allow later packaging inspection. The solver scripts include ISC Meriyah and MIT Astring. |
| QuickJS | [official 2026-06-04 download and MIT statement](https://bellard.org/quickjs/) | Only the upstream source tarball was acquired. No published SHA-256 was found on the official page; 0B-03 computed its hash and inspected the archive's MIT `LICENSE`. |
| FFmpeg | [official 8.1.3 release and signing procedure](https://ffmpeg.org/download.html), [license guidance](https://ffmpeg.org/legal.html), [codec documentation](https://ffmpeg.org/ffmpeg-codecs.html) | 0B-03 verified the source tarball and detached signature against FFmpeg's documented release key `FCF986EA15E6E293A5644F10B4322F04D67658D8`, then recorded SHA-256. 0B-10 must exclude `--enable-gpl` and `--enable-nonfree`; the native AAC encoder needs no external AAC library. |
| LAME | [project's 3.100 source and published SHA-256](https://sourceforge.net/projects/lame/files/lame/3.100/lame-3.100.tar.gz/download), [project license notice](https://lame.sourceforge.io/license.txt) | FFmpeg documents `--enable-libmp3lame` as the external MP3 encoder requirement. LAME's encoder library is LGPL, but its old mpglib decoder is GPL. 0B-10 must prove that the decoder is absent from the linked build; otherwise stop the LGPL build. |

## Artifact and build-dependency plan

| Target | yt-dlp/ejs | QuickJS | FFmpeg/MP3 encoder |
|---|---|---|---|
| Windows x64 Gate 0B probe | Official pinned `yt-dlp.exe` includes EJS; use the exact binary hash above. | Build `qjs.exe` from the locked C source in 0B-04/05. | Build `ffmpeg.exe` and `ffprobe.exe` from FFmpeg 8.1.3 with LAME 3.100 encoder in 0B-10/11. |
| Linux x64 | Official pinned `yt-dlp_linux` includes EJS; use the exact binary hash above. | Build `qjs` from the same source in 0B-06. | Later platform build from the same locked sources and LGPL configuration. |
| macOS x64 and arm64 | Official pinned universal `yt-dlp_macos` includes EJS; its hash is attested from the signed checksum file. | Build native `qjs` separately on each host in 0B-07/08. | Later platform builds from the same locked sources and LGPL configuration. |
| Android arm64 | No official Android yt-dlp standalone executable is claimed. Keep the pinned source and EJS wheel as inputs; Python runtime packaging is a Gate 0C decision and must be locked before device execution. | Build the native Android `qjs` from the same source with NDK r30 in 0B-09; device run is Gate 0C. | Android executable and dependency configuration belongs to Gate 0C; no Android FFmpeg binary is attested by Gate 0B. |

Source dependencies are the matched EJS 0.8.0 and LAME 3.100. yt-dlp's
versioned [`pyproject.toml`](https://github.com/yt-dlp/yt-dlp/blob/2026.08.19/pyproject.toml)
lists its pinned Python package set and PyInstaller 6.22.0 for official
bundles; 0B-12 must inspect the actual bundled inventory, not infer it from
that file. QuickJS needs a C compiler, Make and target C runtime. FFmpeg needs
a C toolchain, Make and libmp3lame headers/library; AAC encoding is native.
The exact compilers, flags and packaging commands are assigned to 0B-04,
0B-06/09 and 0B-10. They are not asserted by this source-only task.

## 0B-03 acquisition and verification

Run `powershell -NoProfile -File scripts/gate-0b/fetch-sources.ps1` to fetch
missing inputs into ignored `work/engine/downloads/`. The script checks each
byte stream against the locked SHA-256 before accepting it. Run
`powershell -NoProfile -File scripts/gate-0b/verify-downloads.ps1` before any
later build or CLI use; it works offline and fails on missing, altered or
unlisted files. Both scripts compare all 14 hashes with
`docs/gates/evidence/0b/source-hashes.txt`, check the yt-dlp artifacts against
the signed `SHA2-256SUMS`, and verify detached yt-dlp and FFmpeg signatures.
The yt-dlp key is fetched from the release commit; the FFmpeg key fingerprint
matches its official download page. Git for Windows supplies GnuPG 2.4.9 on
this machine. No engine executable was run in 0B-03.

The formerly unlisted macOS binary hash is from the verified yt-dlp manifest.
QuickJS has no upstream published SHA-256, so its value is the computed archive
hash; its archive `LICENSE` contains the MIT grant. FFmpeg's value was computed
after its detached signature verified against the published release-key
fingerprint. Later build tasks must invoke `verify-downloads.ps1` before
extracting or executing these inputs. A changed URL or hash requires a new
source-lock review.
