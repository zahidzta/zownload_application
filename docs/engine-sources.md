# Gate 0B engine source lock

Locked on 2026-10-18 for task 0B-01 and attested in 0B-03; zlib was added in
the owner-approved 0B-10A source-lock repair on 2026-10-19. This is the
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
      "fallbackUrls": [
        "https://mirror.math.princeton.edu/pub/macports/distfiles/ffmpeg/ffmpeg-8.1.3.tar.xz"
      ],
      "signatureUrl": "https://ffmpeg.org/releases/ffmpeg-8.1.3.tar.xz.asc",
      "signatureFallbackUrls": [
        "https://mirrors.mit.edu/gentoo-distfiles/distfiles/85/ffmpeg-8.1.3.tar.xz.asc"
      ],
      "signatureSha256": "5f2880c7fea01f8694d30cb9d06362f77241ee67ce5926b157a226b18f08a538",
      "sha256": "7138d28c96d9d3e3af4ee3d8cad72741f8ffb40da90c1112235dea3ecd3178a3"
    },
    "signingKey": {
      "url": "https://ffmpeg.org/ffmpeg-devel.asc",
      "fallbackUrls": [
        "https://raw.githubusercontent.com/FFmpeg/web/2d2f5f72996cdbc9420a5f0dc9c22a97d54871ae/htdocs/ffmpeg-devel.asc"
      ],
      "sha256": "397b3becedcd5a98769967ff1ff8501ddc89f8368b8f766e4701377d7dbaabe5",
      "fingerprint": "FCF986EA15E6E293A5644F10B4322F04D67658D8"
    },
    "targets": ["windows-x64", "linux-x64", "macos-x64", "macos-arm64"]
  },
  "zlib": {
    "version": "1.3.2",
    "license": "Zlib (root library only; exclude contrib programs)",
    "source": {
      "url": "https://zlib.net/fossils/zlib-1.3.2.tar.gz",
      "sha256": "bb329a0a2cd0274d05519d61c667c062e06990d72e125ee2dfa8de64f0119d16",
      "fallbackUrls": ["https://github.com/madler/zlib/releases/download/v1.3.2/zlib-1.3.2.tar.gz"]
    },
    "targets": ["windows-x64", "linux-x64", "macos-x64", "macos-arm64"]
  },
  "lame": {
    "version": "3.100",
    "license": "LGPL for encoder library; GPL-only mpglib decoder must be excluded",
    "source": {
      "url": "https://sourceforge.net/projects/lame/files/lame/3.100/lame-3.100.tar.gz/download",
      "sha256": "ddfe36cab873794038ae2c1210557ad34857a4b6bdc515785d1da9e175b1da1e"
    },
    "targets": ["windows-x64", "linux-x64", "macos-x64", "macos-arm64"]
  }
}
```

The Windows source workflow falls back to the pinned MacPorts and Gentoo
distfile mirrors for the FFmpeg archive and detached signature when the
canonical host is unavailable. It can also read the signing key from the
FFmpeg project's immutable GitHub web-mirror commit. The existing locked
SHA-256 values and detached FFmpeg signature remain mandatory before a build.

## Source and license evidence

| Component | Primary evidence | Acquisition and license meaning |
|---|---|---|
| yt-dlp | [immutable 2026.08.19 release](https://github.com/yt-dlp/yt-dlp/releases/tag/2026.08.19), [tagged README licensing section](https://github.com/yt-dlp/yt-dlp/blob/2026.08.19/README.md#licensing), [tagged dependency licenses](https://github.com/yt-dlp/yt-dlp/blob/2026.08.19/THIRD_PARTY_LICENSES.txt), [tagged own license](https://github.com/yt-dlp/yt-dlp/blob/2026.08.19/LICENSE) | Release page publishes the archive, binary, and checksum-file SHA-256 values above. Its README calls the official PyInstaller executables GPLv3+ combined works, despite yt-dlp's own Unlicense. Preserve the complete platform-specific notices and corresponding-source obligations. The source tarball and Unix zipimport variant also include ISC Meriyah and MIT Astring. |
| yt-dlp-ejs | [yt-dlp 2026.08.19 dependency pin](https://github.com/yt-dlp/yt-dlp/blob/2026.08.19/pyproject.toml), [ejs 0.8.0 release](https://github.com/yt-dlp/ejs/releases/tag/0.8.0), [PyPI artifact hashes and provenance](https://pypi.org/project/yt-dlp-ejs/0.8.0/), [tagged ejs license notes](https://github.com/yt-dlp/ejs/blob/0.8.0/README.md#licensing) | yt-dlp pins `yt-dlp-ejs==0.8.0` in both `default` and `pin` dependencies. Official standalone executables already bundle matching EJS; the separate source distribution and wheel preserve its provenance and allow later packaging inspection. The solver scripts include ISC Meriyah and MIT Astring. |
| QuickJS | [official 2026-06-04 download and MIT statement](https://bellard.org/quickjs/) | Only the upstream source tarball was acquired. No published SHA-256 was found on the official page; 0B-03 computed its hash and inspected the archive's MIT `LICENSE`. |
| FFmpeg | [official 8.1.3 release and signing procedure](https://ffmpeg.org/download.html), [license guidance](https://ffmpeg.org/legal.html), [codec documentation](https://ffmpeg.org/ffmpeg-codecs.html) | 0B-03 verified the source tarball and detached signature against FFmpeg's documented release key `FCF986EA15E6E293A5644F10B4322F04D67658D8`, then recorded SHA-256. 0B-10 must exclude `--enable-gpl` and `--enable-nonfree`; the native AAC encoder needs no external AAC library. |
| zlib | [official 1.3.2 release and published SHA-256](https://zlib.net/), [versioned archive directory](https://zlib.net/fossils/), [upstream license](https://zlib.net/zlib_license.html) | 0B-10A acquired the versioned fossil archive and matched its SHA-256 to the value published by zlib. The archive's `zlib.h` declares `ZLIB_VERSION "1.3.2"`, and its root `LICENSE` contains the Zlib license. Only the root compression library is planned; `contrib/` programs are excluded. |
| LAME | [project's 3.100 source and published SHA-256](https://sourceforge.net/projects/lame/files/lame/3.100/lame-3.100.tar.gz/download), [project license notice](https://lame.sourceforge.io/license.txt) | FFmpeg documents `--enable-libmp3lame` as the external MP3 encoder requirement. LAME's encoder library is LGPL, but its old mpglib decoder is GPL. 0B-10 must prove that the decoder is absent from the linked build; otherwise stop the LGPL build. |

## Gate 5A Android Python runtime lock — owner approved 2026-11-22

The owner selected an upstream CPython source build embedded behind the Kotlin
`AndroidEnginePackage` boundary. Runtime integration remains assigned to
5A-03 and later tasks. Versions of the Python package set follow the `pin`
group in yt-dlp's tagged
[`pyproject.toml`](https://github.com/yt-dlp/yt-dlp/blob/2026.08.19/pyproject.toml).
PyPI source hashes below come from each version's release metadata. Hashes for
the native libraries are computed from their exact upstream source archives,
except OpenSSL, whose hash is published by its release page.

| Package | Version | Source archive | SHA-256 | License |
|---|---:|---|---|---|
| CPython | `3.14.10` | [Python.org source XZ](https://www.python.org/ftp/python/3.14.10/Python-3.14.10.tar.xz) | `de414a57119abef52784d8993e341d53aed635fc2b05c2607d9f98a2c5b72032` | PSF-2.0 |
| Brotli | `1.2.0` | [PyPI sdist](https://files.pythonhosted.org/packages/f7/16/c92ca344d646e71a43b8bb353f0a6490d7f6e06210f8554c8f874e454285/brotli-1.2.0.tar.gz) | `e310f77e41941c13340a95976fe66a8a95b01e783d430eeaf7a2f87e0a57dd0a` | MIT |
| certifi | `2026.7.22` | [PyPI sdist](https://files.pythonhosted.org/packages/a3/c2/24167ea9858356b47a87a50d39908bfdb72ceeefe0041586e704e5376b3a/certifi-2026.7.22.tar.gz) | `741e2c3b351ddf169a738da9f2c048608ff7f2c5cc02f1ebc6b118bb090d5d55` | MPL-2.0 |
| charset-normalizer | `3.5.0` | [PyPI sdist](https://files.pythonhosted.org/packages/cb/31/4971872b3ed8715346231fb6eb4da8fcba65a4143c189db151ee28a2812b/charset_normalizer-3.5.0.tar.gz) | `49bd5feb59b0bf3cbf6ebcf4352e371c95b9da9bacd4449f8b64d0ad2c10a26e` | MIT |
| idna | `3.18` | [PyPI sdist](https://files.pythonhosted.org/packages/cd/63/9496c57188a2ee585e0f1db071d75089a11e98aa86eb99d9d7618fc1edce/idna-3.18.tar.gz) | `ffb385a7e039654cef1ab9ef32c6fafe283c0c0467bba1d9029738ce4a14a848` | BSD-3-Clause |
| mutagen | `1.48.1` | [PyPI sdist](https://files.pythonhosted.org/packages/df/70/1675da133ea92227da41bf5b24e1c66be597ff736a1533ade41da986852f/mutagen-1.48.1.tar.gz) | `8f95637ab9f6f305cec6bd1294e197debe207998e3e068596563c74f86b0a173` | GPL-2.0-or-later |
| pycryptodomex | `3.23.0` | [PyPI sdist](https://files.pythonhosted.org/packages/c9/85/e24bf90972a30b0fcd16c73009add1d7d7cd9140c2498a68252028899e41/pycryptodomex-3.23.0.tar.gz) | `71909758f010c82bc99b0abf4ea12012c98962fbf0583c2164f8b84533c2e4da` | BSD-2-Clause and public domain |
| requests | `2.34.2` | [PyPI sdist](https://files.pythonhosted.org/packages/ac/c3/e2a2b89f2d3e2179abd6d00ebd70bff6273f37fb3e0cc209f48b39d00cbf/requests-2.34.2.tar.gz) | `f288924cae4e29463698d6d60bc6a4da69c89185ad1e0bcc4104f584e960b9ed` | Apache-2.0 |
| urllib3 | `2.7.0` | [PyPI sdist](https://files.pythonhosted.org/packages/53/0c/06f8b233b8fd13b9e5ee11424ef85419ba0d8ba0b3138bf360be2ff56953/urllib3-2.7.0.tar.gz) | `231e0ec3b63ceb14667c67be60f2f2c40a518cb38b03af60abc813da26505f4c` | MIT |
| websockets | `17.0.1` | [PyPI sdist](https://files.pythonhosted.org/packages/f7/96/e01084f83a64bcb3a27994bd0cb0db68ff29d9c6707fae37ec19b18ba990/websockets-17.0.1.tar.gz) | `5baa9bc0dfbae8c507e51c8cf1b6d4628086f7a87bbd3a9952bd5f035451f1cc` | BSD-3-Clause |

| Native library | Version / recipe | Source archive | SHA-256 | License | Pinned Android source recipe and patch files |
|---|---|---|---|---|---|
| bzip2 | `1.0.8` / build `3` | [Sourceware archive](https://sourceware.org/pub/bzip2/bzip2-1.0.8.tar.gz) | `ab5a03176ee106d3f0fa90e381da478ddae405918153cca248e682cd0c4a2269` | bzip2 license | `bzip2-1.0.8-3` @ `dcea166d40d573e963a35435e48b047afe243c2d`; `symlink.patch` |
| libffi | `3.4.4` / build `3` | [Upstream release](https://github.com/libffi/libffi/releases/download/v3.4.4/libffi-3.4.4.tar.gz) | `d66c56ad259a82cf2a9dfc408b32bf5da52371500b84745f7fb8b645712df676` | MIT | `libffi-3.4.4-3` @ `65d87e392d69198f3dd1ed2feb3b5fcea1b029a6`; `long_double.patch`, `open_temp_exec_file.patch` |
| OpenSSL | `3.5.9` / build `0` | [Upstream release](https://github.com/openssl/openssl/releases/download/openssl-3.5.9/openssl-3.5.9.tar.gz) | `603f5602e2eef00d77fbd429d34dcd5822bb301757a1bc9cdb24c670f1eb859a` | Apache-2.0 | `openssl-3.5.9-0` @ `5521f2c16ee87dd7f9d081421351f675fac2ee45`; `at_secure.patch`, `configuration.patch`, `soname-3.patch` |
| SQLite | `3.53.4` / build `0` | [SQLite autoconf source](https://www.sqlite.org/2026/sqlite-autoconf-3530400.tar.gz) | `0e9483900e92cd5de8fd48d16bf9200145a61f7fd5be542a5ac81d8a9516eb9c` | Public domain | `sqlite-3.53.4-0` @ `5521f2c16ee87dd7f9d081421351f675fac2ee45`; `soname.patch` |
| xz / liblzma | `5.4.6` / build `1` | [Upstream release](https://github.com/tukaani-project/xz/releases/download/v5.4.6/xz-5.4.6.tar.gz) | `aeba3e03bf8140ddedf62a0a367158340520f6b384f75ca6045ccc6c0d43fd5c` | LGPL-2.1-or-later for liblzma | `xz-5.4.6-1` @ `65d87e392d69198f3dd1ed2feb3b5fcea1b029a6`; no patch |
| zstd | `1.5.7` / build `2` | [Upstream release](https://github.com/facebook/zstd/releases/download/v1.5.7/zstd-1.5.7.tar.gz) | `eb33e51f49a15e023950cd7825ca74a4a2b43db8354825ac24fc1b7ee09e6fa3` | BSD-3-Clause (library) | `zstd-1.5.7-2` @ `f4c94a0fbc359d17993547b66f0627d436f8897b`; no patch |

The Android source recipes are from the MIT-licensed
[`cpython-android-source-deps`](https://github.com/beeware/cpython-android-source-deps)
repository, pinned to each exact tag commit in the table. Rebuild these inputs
from their source archives. Do not consume the repository's precompiled release
archives. CPython's `Android/android.py` will reuse source-built dependency
archives placed in its local `cross-build/downloads/` cache under their expected
filenames, so its download helper will not fetch the precompiled artifacts.

The CPython `3.14.10` Android helper pins NDK `27.3.13750724`; the dependency
repository's environment script pins NDK `27.2.12479018`. Before building,
apply the two recorded one-line environment patches to NDK `30.0.16248370`.
The default Android API level `24` and `aarch64-linux-android` target remain.
The exact patch targets and all lock values are mirrored in this machine-readable
record:

```json android-python-runtime-lock
{
  "schema": 1,
  "status": "owner-approved",
  "approvedOn": "2026-11-22",
  "approach": "cpython-source-embedded-jni",
  "python": {
    "version": "3.14.10",
    "license": "PSF-2.0",
    "sourceUrl": "https://www.python.org/ftp/python/3.14.10/Python-3.14.10.tar.xz",
    "sha256": "de414a57119abef52784d8993e341d53aed635fc2b05c2607d9f98a2c5b72032",
    "androidHost": "aarch64-linux-android",
    "apiLevel": 24,
    "ndkPatch": { "file": "Android/android-env.sh", "from": "27.3.13750724", "to": "30.0.16248370" }
  },
  "sourceDependenciesRepository": {
    "url": "https://github.com/beeware/cpython-android-source-deps",
    "license": "MIT",
    "ndkPatch": { "file": "android-env.sh", "from": "27.2.12479018", "to": "30.0.16248370" }
  },
  "nativeDependencies": [
    { "name": "bzip2", "version": "1.0.8", "build": "3", "sourceUrl": "https://sourceware.org/pub/bzip2/bzip2-1.0.8.tar.gz", "sha256": "ab5a03176ee106d3f0fa90e381da478ddae405918153cca248e682cd0c4a2269", "license": "bzip2", "recipeTag": "bzip2-1.0.8-3", "recipeCommit": "dcea166d40d573e963a35435e48b047afe243c2d", "patches": ["symlink.patch"] },
    { "name": "libffi", "version": "3.4.4", "build": "3", "sourceUrl": "https://github.com/libffi/libffi/releases/download/v3.4.4/libffi-3.4.4.tar.gz", "sha256": "d66c56ad259a82cf2a9dfc408b32bf5da52371500b84745f7fb8b645712df676", "license": "MIT", "recipeTag": "libffi-3.4.4-3", "recipeCommit": "65d87e392d69198f3dd1ed2feb3b5fcea1b029a6", "patches": ["long_double.patch", "open_temp_exec_file.patch"] },
    { "name": "openssl", "version": "3.5.9", "build": "0", "sourceUrl": "https://github.com/openssl/openssl/releases/download/openssl-3.5.9/openssl-3.5.9.tar.gz", "sha256": "603f5602e2eef00d77fbd429d34dcd5822bb301757a1bc9cdb24c670f1eb859a", "license": "Apache-2.0", "recipeTag": "openssl-3.5.9-0", "recipeCommit": "5521f2c16ee87dd7f9d081421351f675fac2ee45", "patches": ["at_secure.patch", "configuration.patch", "soname-3.patch"] },
    { "name": "sqlite", "version": "3.53.4", "build": "0", "sourceUrl": "https://www.sqlite.org/2026/sqlite-autoconf-3530400.tar.gz", "sha256": "0e9483900e92cd5de8fd48d16bf9200145a61f7fd5be542a5ac81d8a9516eb9c", "license": "Public-Domain", "recipeTag": "sqlite-3.53.4-0", "recipeCommit": "5521f2c16ee87dd7f9d081421351f675fac2ee45", "patches": ["soname.patch"] },
    { "name": "xz", "version": "5.4.6", "build": "1", "sourceUrl": "https://github.com/tukaani-project/xz/releases/download/v5.4.6/xz-5.4.6.tar.gz", "sha256": "aeba3e03bf8140ddedf62a0a367158340520f6b384f75ca6045ccc6c0d43fd5c", "license": "LGPL-2.1-or-later-libLZMA", "recipeTag": "xz-5.4.6-1", "recipeCommit": "65d87e392d69198f3dd1ed2feb3b5fcea1b029a6", "patches": [] },
    { "name": "zstd", "version": "1.5.7", "build": "2", "sourceUrl": "https://github.com/facebook/zstd/releases/download/v1.5.7/zstd-1.5.7.tar.gz", "sha256": "eb33e51f49a15e023950cd7825ca74a4a2b43db8354825ac24fc1b7ee09e6fa3", "license": "BSD-3-Clause-library", "recipeTag": "zstd-1.5.7-2", "recipeCommit": "f4c94a0fbc359d17993547b66f0627d436f8897b", "patches": [] }
  ],
  "pythonPackages": [
    { "name": "Brotli", "version": "1.2.0", "sourceUrl": "https://files.pythonhosted.org/packages/f7/16/c92ca344d646e71a43b8bb353f0a6490d7f6e06210f8554c8f874e454285/brotli-1.2.0.tar.gz", "sha256": "e310f77e41941c13340a95976fe66a8a95b01e783d430eeaf7a2f87e0a57dd0a", "license": "MIT" },
    { "name": "certifi", "version": "2026.7.22", "sourceUrl": "https://files.pythonhosted.org/packages/a3/c2/24167ea9858356b47a87a50d39908bfdb72ceeefe0041586e704e5376b3a/certifi-2026.7.22.tar.gz", "sha256": "741e2c3b351ddf169a738da9f2c048608ff7f2c5cc02f1ebc6b118bb090d5d55", "license": "MPL-2.0" },
    { "name": "charset-normalizer", "version": "3.5.0", "sourceUrl": "https://files.pythonhosted.org/packages/cb/31/4971872b3ed8715346231fb6eb4da8fcba65a4143c189db151ee28a2812b/charset_normalizer-3.5.0.tar.gz", "sha256": "49bd5feb59b0bf3cbf6ebcf4352e371c95b9da9bacd4449f8b64d0ad2c10a26e", "license": "MIT" },
    { "name": "idna", "version": "3.18", "sourceUrl": "https://files.pythonhosted.org/packages/cd/63/9496c57188a2ee585e0f1db071d75089a11e98aa86eb99d9d7618fc1edce/idna-3.18.tar.gz", "sha256": "ffb385a7e039654cef1ab9ef32c6fafe283c0c0467bba1d9029738ce4a14a848", "license": "BSD-3-Clause" },
    { "name": "mutagen", "version": "1.48.1", "sourceUrl": "https://files.pythonhosted.org/packages/df/70/1675da133ea92227da41bf5b24e1c66be597ff736a1533ade41da986852f/mutagen-1.48.1.tar.gz", "sha256": "8f95637ab9f6f305cec6bd1294e197debe207998e3e068596563c74f86b0a173", "license": "GPL-2.0-or-later" },
    { "name": "pycryptodomex", "version": "3.23.0", "sourceUrl": "https://files.pythonhosted.org/packages/c9/85/e24bf90972a30b0fcd16c73009add1d7d7cd9140c2498a68252028899e41/pycryptodomex-3.23.0.tar.gz", "sha256": "71909758f010c82bc99b0abf4ea12012c98962fbf0583c2164f8b84533c2e4da", "license": "BSD-and-Public-Domain" },
    { "name": "requests", "version": "2.34.2", "sourceUrl": "https://files.pythonhosted.org/packages/ac/c3/e2a2b89f2d3e2179abd6d00ebd70bff6273f37fb3e0cc209f48b39d00cbf/requests-2.34.2.tar.gz", "sha256": "f288924cae4e29463698d6d60bc6a4da69c89185ad1e0bcc4104f584e960b9ed", "license": "Apache-2.0" },
    { "name": "urllib3", "version": "2.7.0", "sourceUrl": "https://files.pythonhosted.org/packages/53/0c/06f8b233b8fd13b9e5ee11424ef85419ba0d8ba0b3138bf360be2ff56953/urllib3-2.7.0.tar.gz", "sha256": "231e0ec3b63ceb14667c67be60f2f2c40a518cb38b03af60abc813da26505f4c", "license": "MIT" },
    { "name": "websockets", "version": "17.0.1", "sourceUrl": "https://files.pythonhosted.org/packages/f7/96/e01084f83a64bcb3a27994bd0cb0db68ff29d9c6707fae37ec19b18ba990/websockets-17.0.1.tar.gz", "sha256": "5baa9bc0dfbae8c507e51c8cf1b6d4628086f7a87bbd3a9952bd5f035451f1cc", "license": "BSD-3-Clause" }
  ],
  "pythonBuildTools": [
    { "name": "setuptools", "version": "84.1.0", "license": "MIT", "sourceUrl": "https://files.pythonhosted.org/packages/73/eb/7e5f628ee2eb168fecbf8026de7856b2543d6d609cc85f086b9a91ac93d6/setuptools-84.1.0.tar.gz", "sha256": "23657205b63d4d31395ab917815247f694aafad28cd21316bf5fd45a51048ea0", "wheelUrl": "https://files.pythonhosted.org/packages/18/02/b4bbb90f8f29e334898ff45c6d9b1fffaa6f378017052b3023a06262b5f7/setuptools-84.1.0-py3-none-any.whl", "wheelSha256": "5231689c6ac8156cd155cfb98c3fd6fb252c3e7e9bd3d78b64d3c55f132624c9" }
  ],
  "ytDlp": { "version": "2026.08.19", "sourceLockKey": "ytDlp", "sourceUrl": "https://github.com/yt-dlp/yt-dlp/releases/download/2026.08.19/yt-dlp.tar.gz", "sha256": "072aad4f2a7604e92155f61a275a4752dc64046c8f6d90df3710525d94cd37c1" },
  "ejs": { "version": "0.8.0", "sourceLockKey": "ejs", "sourceUrl": "https://files.pythonhosted.org/packages/d3/e6/cceb9530e8f4e5940f6f7822d90e9d94f1b85343329a16baaf47bbbb3de1/yt_dlp_ejs-0.8.0.tar.gz", "sha256": "d5fa1639f63b5c4af8d932495f60689d5370f1a095782c944f7f62a303eb104e" },
  "quickjs": { "version": "2026-06-04", "sourceLockKey": "quickjs", "sourceUrl": "https://bellard.org/quickjs/quickjs-2026-06-04.tar.xz", "sha256": "b376e839b322978313d929fd20663b11ba58b75df5a46c126dd19ea2fa70ad2a" },
  "buildTools": {
    "host": "ubuntu-24.04-x86_64",
    "jdk": "21.0.11.10.1",
    "androidApi": "36",
    "buildTools": "36.0.0",
    "platformTools": "37.0.3",
    "commandLineTools": "22.0",
    "ndk": "30.0.16248370",
    "abi": "arm64-v8a"
  }
}
```

The Android build also includes `yt-dlp-ejs` `0.8.0` and QuickJS `2026-06-04`
from the existing source lock. The package builder must build only this pinned
default set and must not use `pip` to resolve unpinned dependencies.

## Artifact and build-dependency plan

| Target | yt-dlp/ejs | QuickJS | FFmpeg/MP3 encoder |
|---|---|---|---|
| Windows x64 Gate 0B probe | Official pinned `yt-dlp.exe` includes EJS; use the exact binary hash above. | Build `qjs.exe` from the locked C source in 0B-04/05. | Build `ffmpeg.exe` and `ffprobe.exe` from FFmpeg 8.1.3 with LAME 3.100 encoder and zlib 1.3.2 in 0B-10/11. |
| Linux x64 | Official pinned `yt-dlp_linux` includes EJS; use the exact binary hash above. | Build `qjs` from the same source in 0B-06 and verify the Gate 4A package copy. | Gate 4A builds `ffmpeg` and `ffprobe` from the same locked FFmpeg, LAME encoder, and zlib sources using [`build-linux-engine.sh`](../scripts/gate-4a/build-linux-engine.sh). |
| macOS x64 and arm64 | Official pinned universal `yt-dlp_macos` includes EJS; its hash is attested from the signed checksum file. | Build native `qjs` separately on each host in 0B-07/08. | Gate 4B builds `ffmpeg` and `ffprobe` from the same locked FFmpeg, LAME encoder, and zlib sources using [`build-macos-engine.sh`](../scripts/gate-4b/build-macos-engine.sh) and the LGPL-compatible configuration. |
| Android arm64 | No official Android yt-dlp standalone executable is claimed. Gate 5A-02 must approve and lock a Python runtime and its source inputs before build integration. | Build the native Android `qjs` from the same source with NDK r30 in 0B-09; device run is Gate 5A. | Android executable and dependency configuration belongs to Gate 5A; no Android FFmpeg binary is attested by Gate 0B. |

The Gate 4B-02 evidence records the architecture-specific macOS engine hashes
and LGPL-compatible FFmpeg configuration. Gate 4B-03's package hashes and
runner tool versions are recorded in
[`4b-03.md`](gates/evidence/4b/4b-03.md); its updater bundles contain the same
verified app-data engine resources.

Source dependencies are the matched EJS 0.8.0, LAME 3.100 and zlib 1.3.2. yt-dlp's
versioned [`pyproject.toml`](https://github.com/yt-dlp/yt-dlp/blob/2026.08.19/pyproject.toml)
lists its pinned Python package set and PyInstaller 6.22.0 for official
bundles; 0B-12 must inspect the actual bundled inventory, not infer it from
that file. QuickJS needs a C compiler, Make and target C runtime. FFmpeg needs
a C toolchain, Make, libmp3lame headers/library and zlib headers/library for PNG
artwork decoding; AAC encoding is native. For Windows, 0B-10 must use the pinned
w64devkit GCC/Make toolchain to build only zlib's static `libz.a` with its
`win32/Makefile.gcc`, then provide that archive and the root `zlib.h`/`zconf.h`
to FFmpeg's configure probe. The exact commands, flags and static-link check
belong to 0B-10/11; no zlib object or FFmpeg binary was built in 0B-10A.

## 0B-03 acquisition and verification

Run `powershell -NoProfile -File scripts/gate-0b/fetch-sources.ps1` to fetch
missing inputs into ignored `work/engine/downloads/`. The script checks each
byte stream against the locked SHA-256 before accepting it. Run
`powershell -NoProfile -File scripts/gate-0b/verify-downloads.ps1` before any
later build or CLI use; it works offline and fails on missing, altered or
unlisted files. Both scripts compare all 15 hashes with
`docs/gates/evidence/0b/source-hashes.txt`, check the yt-dlp artifacts against
the signed `SHA2-256SUMS`, and verify detached yt-dlp and FFmpeg signatures.
The yt-dlp key is fetched from the release commit; the FFmpeg key fingerprint
matches its official download page. Git for Windows supplies GnuPG 2.4.9 on
this machine. No engine executable was run in 0B-03.

0B-10A added the upstream zlib 1.3.2 fossil archive. Its SHA-256 matches the
hash published on the official release page; the offline verifier additionally
checks the archive's declared version and root license. This source is not
covered by the yt-dlp or FFmpeg signatures. No build or engine command was run
in 0B-10A.

The formerly unlisted macOS binary hash is from the verified yt-dlp manifest.
QuickJS has no upstream published SHA-256, so its value is the computed archive
hash; its archive `LICENSE` contains the MIT grant. FFmpeg's value was computed
after its detached signature verified against the published release-key
fingerprint. Later build tasks must invoke `verify-downloads.ps1` before
extracting or executing these inputs. A changed URL or hash requires a new
source-lock review.

## 0B-12 redistribution source plan

The signed official yt-dlp executables have three distinct SHA-256 values in
the lock above. Their embedded `THIRD_PARTY_LICENSES.txt` files have 45
entries with identical normalized text; Windows uses CRLF, Linux/macOS LF.
The 0B-12 verifier opens each PyInstaller archive, hashes the embedded notice,
and proves both EJS solver scripts match the locked EJS 0.8.0 wheel. The full
inventory and embedded digests are in
[`license-audit.txt`](gates/evidence/0b/license-audit.txt).

The owner chose the existing signed artifact/source lock plus a per-release
corresponding-source plan for this audit. A source bundle accompanying an
actual release must identify the exact versions in each executable, obtain
and checksum all bundled dependency sources, preserve their full license
texts, and map each binary member to source and build configuration. The
current yt-dlp source tarball covers its own code but excludes the bundled
Python/native dependencies and `bundle/` build recipes. The immutable
[`3a08beaf` release commit](https://github.com/yt-dlp/yt-dlp/tree/3a08beaf031ab68f966401ead017ac81fe8486cf/bundle)
identifies the upstream PyInstaller recipe and platform requirements; the
release packager must snapshot and checksum those materials too. Upstream's
offer to provide third-party source does not replace the project's release
source bundle. Proprietary Microsoft runtime files inside `yt-dlp.exe` have
separate redistribution terms rather than public corresponding source;
their entitlement and per-file hashes are release packaging checks.

QuickJS's one locked source archive covers the five built targets; the exact
build commands and five binary hashes are linked from
[`THIRD-PARTY-NOTICES.md`](THIRD-PARTY-NOTICES.md). Windows FFmpeg's
corresponding sources are the locked FFmpeg, LAME and zlib archives. Its
static-link relinking materials and full configuration must accompany each
release. The Gate 0B Windows hashes do not attest future platform builds.

## Gate 0C Android library candidate (0C-01; integration stopped)

The [Android library audit](gates/evidence/0c/library-audit.md) inspected
`io.github.junkfood02.youtubedl-android:{library,ffmpeg}:0.18.1`, upstream tag
`0.18.1` at commit `d725d5c9a18c3a99a13ee0308bf78275dc310760`.
Maven Central publishes SHA-256
`579b5fb480892b1abc2b218c2089699d52759cc8d7ba256bf876453f0365faef`
for the library AAR and
`0a87ffa6cf912b0fe76c1a99b9107f543ee2f247935fae2c71f0822eb7bc5f49`
for its FFmpeg AAR. These are **candidate** hashes, not additions to the Gate
0B source lock or app dependencies. The tag bundles yt-dlp 2025.11.12 with
ejs 0.3.1 and a different QuickJS binary. Its Maven metadata says GPL-3.0;
the tagged arm64 FFmpeg 7.1.1 executable has `--enable-gpl` and x264/x265.
The built-in updater has no digest check or bad-update rollback. This fails
the project's current LGPL-compatible Android FFmpeg plan, so Android engine
integration stops for owner architecture/licensing decision 0C-01A. The audit
records exact source links, tagged binary hashes, and open package/device
checks. Gate 0B's pinned yt-dlp/ejs/QuickJS sources remain unchanged.
