# Gate 0A toolchain and OS matrix

Selected 2026-10-17 for the empty Tauri 2 foundation. The JavaScript/Rust scaffold and Android project are present. The Android debug APK build passed in 0A-09, hosted CI passed in 0A-10 and 0A-12, and a clean Windows checkout passed in 0A-11. Gate 0A awaits the owner's checkpoint review and explicit acceptance.

**Android NDK build pin: r30 (`30.0.16248370`).** The r27c version in the NDK review is a dated local-installation observation. The setup and verification commands below use r30.

## Exact versions

| Component | Pin | Evidence / use |
|---|---|---|
| Tauri runtime crate | `tauri = 2.12.4` | Latest stable v2 release at selection; [Tauri release](https://github.com/tauri-apps/tauri/releases/tag/tauri-v2.12.4). Do not use the v3 alpha. |
| Tauri build crate | `tauri-build = 2.7.3` | [Tauri build release](https://github.com/tauri-apps/tauri/releases/tag/tauri-build-v2.7.3). |
| Tauri npm CLI | `@tauri-apps/cli = 2.12.0` | [Tauri CLI release](https://github.com/tauri-apps/tauri/releases/tag/tauri-cli-v2.12.0). Pin exactly in `package.json`/lockfile in 0A-03. |
| Rust and Cargo | `1.99.1` | [Rust 1.99.1 release notes](https://doc.rust-lang.org/releases.html#version-1991-2026-10-15); install with rustup and select the MSVC host on Windows per [Tauri prerequisites](https://tauri.app/start/prerequisites/). |
| Node.js | `24.22.0` LTS | [Node 24.22.0 release](https://nodejs.org/en/blog/release/v24.22.0); Tauri recommends Node LTS for a JavaScript frontend in its [prerequisites](https://tauri.app/start/prerequisites/). |
| Package manager | `npm 11.19.1` | Bundled with Node 24.22.0 per its [release notes](https://nodejs.org/en/blog/release/v24.22.0). Use `npm ci` after 0A-02 commits its lockfile. |
| JDK | Amazon Corretto `21.0.11.10.1` (Java `21.0.11`) | [Corretto release](https://github.com/corretto/corretto-21/releases/tag/21.0.11.10.1). The owner selected Corretto 21 for 0A-09, superseding the earlier Temurin 17 pin. [Gradle's compatibility matrix](https://docs.gradle.org/current/userguide/compatibility.html) supports running Gradle 9.6.1 on Java 21; [AGP 9.3](https://developer.android.com/build/releases/agp-9-3-0-release-notes) requires at least JDK 17. |
| Android NDK | r30, `30.0.16248370` | Google's [NDK download page](https://developer.android.com/ndk/downloads) identifies r30 as its current LTS and gives this `ndkVersion`. |
| Android SDK platform | Android 16, API `36` (`platforms;android-36`) | [Stable Android 16 SDK platform](https://developer.android.com/tools/releases/platforms). Set `compileSdk = 36`; set `targetSdk = 36` for the skeleton, subject to Android behavior checks in later gates. |
| Android SDK Build-Tools | `36.0.0` (`build-tools;36.0.0`) | [AGP 9.4 compatibility table](https://developer.android.com/build/releases/agp-9-4-0-release-notes) lists Build-Tools 36.0.0. |
| Android SDK Platform-Tools | `37.0.1` (`platform-tools`) | Google's [Platform-Tools release notes](https://developer.android.com/tools/releases/platform-tools). Verify the installed revision because `platform-tools` resolves to the current package. |
| Android SDK Command-Line Tools | `22.0` (`cmdline-tools;22.0`, standalone archive build `15859902`) | Google's [current standalone download](https://developer.android.com/studio#command-line-tools-only) names archive build `15859902`; install the versioned SDK package to avoid a moving `latest` path. |
| Tauri updater plugin | `2.13.0` | Already required by `PROJECT.md:385`; [updater release](https://github.com/tauri-apps/plugins-workspace/releases/tag/updater-v2.13.0). No updater code belongs in Gate 0A. |

### NDK version review (2026-10-17)

The local SDK initially had r27c (`27.2.12479018`), a dated observation of this Windows machine. Within the r27 series, r27d (`27.3.13750724`) is the better choice: Android's [r27 changelog](https://github.com/android/ndk/wiki/Changelog-r27#r27d) records a newer Clang build and fixes for `lldb.sh` on paths with spaces and for Python lookup on macOS. Android's [unsupported downloads list](https://github.com/android/ndk/wiki/Unsupported-Downloads#r27d) confirms the exact r27d version and classifies it as obsolete. The [NDK release page](https://github.com/android/ndk/wiki#ndk-r30-2026-lts) lists r30 (`30.0.16248370`) as the supported LTS. Keep r30 as the Gate 0A pin, consistent with the current stable toolchain rule in `PROJECT.md:389`.

## Android project pins (0A-08)

`npm run tauri -- android init --ci --skip-targets-install` with Tauri CLI 2.12.0 generated `src-tauri/gen/android`. The generated wrapper pins **Gradle 9.6.1**, and both generated build scripts pin **Android Gradle Plugin 9.3.1**; the root build script pins **Kotlin Gradle Plugin 2.2.10**. These generated versions are retained. [Tauri 2.12's Android template notes](https://github.com/tauri-apps/tauri-docs/blob/v2/src/content/docs/blog/tauri-2.12.mdx) describe the move to Gradle 9 and Kotlin 2; [Android's AGP compatibility guidance](https://developer.android.com/build/releases/about-agp) documents the Gradle/JDK relationship.

The generated app module explicitly sets `compileSdk = 36`, `targetSdk = 36`, `minSdk = 24`, `buildToolsVersion = "36.0.0"`, and `ndkVersion = "30.0.16248370"`, matching the selected SDK, Build-Tools, NDK and OS pins above. The template's API 37 defaults were changed to API 36 because API 36 is the Gate 0A platform pin. Java and Kotlin compile targets remain 17 while Gradle runs on pinned Corretto 21 through `JAVA_HOME`; [Android's JDK guidance](https://developer.android.com/build/jdks) distinguishes the Gradle runtime from source and target compatibility. No Kotlin engine plugin is present.

After installing the pinned Corretto JDK/SDK and running the Rust target setup above, use these commands from the repository root on Windows:

```powershell
$env:ANDROID_HOME = Join-Path $env:LOCALAPPDATA 'Android\Sdk'
$env:JAVA_HOME = '<installed Corretto 21.0.11.10.1 JDK directory>'
$env:NDK_HOME = Join-Path $env:ANDROID_HOME 'ndk\30.0.16248370'
npm ci
npm run android:debug
```

`android:debug` requests one `aarch64` debug APK through the Tauri CLI. The APK build and resulting path are **0A-09** evidence; 0A-08 only initializes and checks the generated project. Command-Line Tools 22.0 and Platform-Tools 37.0.1 were installed on 2026-10-18.

## Setup commands

Use the linked vendor downloads for the exact Node and Corretto releases; install Microsoft C++ Build Tools with the **Desktop development with C++** workload and WebView2 for Windows development, as described by [Tauri](https://tauri.app/start/prerequisites/). On macOS, run `xcode-select --install`. On Ubuntu, install the [Tauri Linux prerequisites](https://tauri.app/start/prerequisites/#linux) for the chosen runner image.

From the repository root, after installing Rust via [rustup](https://rustup.rs/) and the vendor Node/JDK packages:

```powershell
rustup toolchain install 1.99.1 --profile minimal
rustup target add aarch64-linux-android --toolchain 1.99.1
node --version
npm --version
rustc +1.99.1 --version
java -version
```

For Android on Windows, download Google's Command-Line Tools archive linked above and place its inner `cmdline-tools` contents under `%LOCALAPPDATA%\Android\Sdk\cmdline-tools\22.0` so `22.0\bin\sdkmanager.bat` exists. Set `ANDROID_HOME` to `%LOCALAPPDATA%\Android\Sdk` and `JAVA_HOME` to the installed Corretto 21 directory. Then run in PowerShell (use the equivalent SDK path on macOS/Linux):

```powershell
$env:ANDROID_HOME = Join-Path $env:LOCALAPPDATA 'Android\Sdk'
& "$env:ANDROID_HOME\cmdline-tools\22.0\bin\sdkmanager.bat" --install 'platforms;android-36' 'build-tools;36.0.0' 'platform-tools' 'cmdline-tools;22.0' 'ndk;30.0.16248370'
& "$env:ANDROID_HOME\cmdline-tools\22.0\bin\sdkmanager.bat" --licenses
$env:NDK_HOME = Join-Path $env:ANDROID_HOME 'ndk\30.0.16248370'
& "$env:ANDROID_HOME\cmdline-tools\22.0\bin\sdkmanager.bat" --list_installed
```

Verify `source.properties` reports Platform-Tools `37.0.1`, Command-Line Tools `22.0`, NDK `30.0.16248370`, and Build-Tools `36.0.0`. The exact Android install and build results belong in 0A-08/0A-09, after the scaffold exists.

## Minimum OS and validation matrix

| Target | Selected minimum / test baseline | Evidence and later proof |
|---|---|---|
| Windows x64 | Windows 10 version 1803 or later | [Tauri prerequisites](https://tauri.app/start/prerequisites/#windows) identify WebView2 availability from 1803. Test clean Windows 10/11 installs before release. Set Tauri `bundle.windows.webviewInstallMode.type` to `offlineInstaller` for both NSIS and MSI so one installer never needs a WebView2 download; [Tauri installer options](https://tauri.app/distribute/windows-installer/#webview2-installation-options). |
| macOS x64/arm64 | macOS 10.15 or later; arm64 testing starts on macOS 11 hardware | [Tauri prerequisites](https://tauri.app/start/prerequisites/#macos) support Catalina 10.15+. Set `bundle.macOS.minimumSystemVersion` to `10.15`; validate both architectures on hosted/macOS test machines in later gates. |
| Android arm64-v8a | Android 7.0 / API 24 or later | [Tauri Android minimum](https://tauri.app/distribute/google-play/) and [config default](https://tauri.app/reference/config/#minsdkversion) are API 24. Set `bundle.android.minSdkVersion = 24`; build the skeleton in 0A-09 and test an API 24 device/emulator and a current Android version in the Android spike. |
| Linux x64 | Ubuntu 24.04 LTS is the Gate 0A CI build baseline; minimum user distribution is set in Stage 4A | `PROJECT.md:208` explicitly defers the Linux support matrix to Stage 4A. [Tauri Linux prerequisites](https://tauri.app/start/prerequisites/#linux) vary by distribution. Gate 0A CI can prove this build baseline, not a portable minimum. |

These OS minima are the proposed `PROJECT.md:208,715` baseline checked against framework documentation. Device/install proof is still required by those lines and the Gate 0A/0C checkpoints; a version pin alone does not prove runtime support. The Windows `offlineInstaller` setting also follows `PROJECT.md:200`'s one-artifact, no-extra-download requirement.

## Local installation evidence on 2026-10-17

Before scaffold work, this Windows checkout reported Node `24.14.0`, npm `11.21.0`, Rust/Cargo `1.99.0`, and Oracle JDK `26.0.2`; its SDK had Command-Line Tools `19.0`, Platform-Tools `37.0.0`, Build-Tools `36.0.0`, and API 36. These are observations, not accepted pins.

The owner subsequently installed the pinned Android NDK r30 (`30.0.16248370`) in `%LOCALAPPDATA%\Android\Sdk\ndk\30.0.16248370`. Its `source.properties` reports `Pkg.Revision = 30.0.16248370`, and its Windows `clang.exe --version` runs and reports Clang `21.0.0`. The SDK still contains the earlier r27c installation. An Android skeleton build remains part of 0A-09.

## 0A-09 local attempt on 2026-10-18

- Installed Rust target `aarch64-linux-android` for toolchain `1.99.1`. Installed SDK Command-Line Tools `22.0` and Platform-Tools `37.0.1`; the existing SDK platform API 36, Build-Tools `36.0.0`, and NDK `30.0.16248370` were confirmed by `source.properties`.
- The first exact `npm run android:debug` attempt failed because Tauri does not allow the scaffold's `0.0.0` Android app version. `src-tauri/tauri.conf.json` was changed to `0.0.1` for the next attempt.
- The next exact command used available Corretto JDK `21.0.11`, local Node `24.14.0`/npm `11.21.0`, Rust `1.99.1`, Tauri CLI `2.12.0`, and the SDK versions above. The frontend built, and the Android Rust library compiled in 8m 47s. Tauri then failed while creating the `libzownload_lib.so` symlink under `src-tauri/gen/android/app/src/main/jniLibs/arm64-v8a`: Windows reports that symbolic-link creation is not allowed. The machine's `AllowDevelopmentWithoutDevLicense` registry value is `0x0`; Gradle packaging did not run in that attempt.
- A continuation ran the exact `npm run android:debug` command outside the sandbox with `JAVA_HOME` set to Amazon Corretto `21.0.11.10.1`, Node `24.14.0`/npm `11.21.0`, Rust `1.99.1`, Tauri CLI `2.12.0`, Gradle `9.6.1`, AGP `9.3.1`, SDK API `36`, Build-Tools `36.0.0`, Platform-Tools `37.0.1`, Command-Line Tools `22.0`, and NDK `30.0.16248370`. Tauri created the native-library symlink, Gradle packaged the debug APK, and the command exited `0`. The earlier Temurin 17 requirement was superseded by the owner's Corretto 21 choice. The build did not require Windows Developer Mode when run with symbolic-link privilege.
- APK: `src-tauri/gen/android/app/build/outputs/apk/universal/debug/app-universal-debug.apk` (136,162,644 bytes; SHA-256 `11B696468F8B586E5C3EBE48BBB38887210EE619B826879DF5475B8494D7D25A`). Although Gradle names the variant `universalDebug`, the APK contains the single requested native ABI, `lib/arm64-v8a/libzownload_lib.so`. The Android version name is `0.0.1`.

## Gate 0A CI setup (0A-10)

`.github/workflows/ci.yml` runs on pushes and pull requests with read-only repository permission. Its Windows 2025 job uses Node `24.22.0` with bundled npm `11.19.1`, installs Rust `1.99.1`, runs `npm ci`, and invokes `powershell -NoProfile -File scripts/verify-foundation.ps1`. That script runs `npm run build`, `npm run check:contracts`, `cargo test --manifest-path src-tauri/Cargo.toml`, and `powershell -NoProfile -File scripts/check-design.ps1`, stopping at the first failure.

The Ubuntu 24.04 Android job uses the same Node/npm and Rust pins, adds Rust target `aarch64-linux-android`, and installs SDK platform API 36, Build-Tools `36.0.0`, Platform-Tools `37.0.1`, Command-Line Tools `22.0` (archive build `15859902`), and NDK `30.0.16248370`. It checks each installed SDK revision before running `npm ci` and `npm run android:debug`. Google's unversioned `platform-tools` package is checked against the recorded `37.0.1` pin so a changed upstream resolution fails instead of silently changing the build. The generated Gradle wrapper is marked executable on the Linux runner; its committed file currently lacks the executable bit.

The Android job downloads the exact [Corretto 21.0.11.10.1 Linux x64 archive](https://github.com/corretto/corretto-21/releases/tag/21.0.11.10.1) and checks the vendor's SHA-256 `5b4dc8817df13f88f9bfc434e5d018adb535889ff2fe0ccf758bcebcc216f394` before extracting it to the runner's temporary directory and setting `JAVA_HOME`. Workflow setup uses [setup-node](https://github.com/actions/setup-node), [setup-android](https://github.com/android-actions/setup-android), and Tauri's [Linux prerequisites](https://tauri.app/start/prerequisites/). No installer, release, publish, or artifact-upload step is configured. Hosted-run evidence is assigned to 0A-12.

## 0A-11 clean-checkout Windows proof (2026-10-18)

`scripts/verify-clean.ps1` clones the current named branch into a unique system temporary directory with `git clone --no-local --single-branch --branch`, confirms that the clone is clean and its HEAD matches the source commit, runs `npm ci`, then invokes the existing foundation verifier from inside the clone. It checks the exact Node, npm, Rust, and Cargo pins before installation and removes only its validated temporary clone path afterward. Run from the repository root with the pinned tools on `PATH`:

```powershell
powershell -NoProfile -File scripts/verify-clean.ps1
```

The command passed on Windows NT `10.0.26200.0` from branch `task-0a-11` at source and clone commit `a6c52810274c729a6b8fef1f9633e7d4abd14770`. Node `v24.22.0` and bundled npm `11.19.1` came from the [official Windows x64 archive](https://nodejs.org/dist/v24.22.0/node-v24.22.0-win-x64.zip), checked against its [release checksum file](https://nodejs.org/dist/v24.22.0/SHASUMS256.txt): SHA-256 `f9683a19877e12a9b167305c8db71040d812876359de21f0d2e97c3f321f80c3`. Rust and Cargo both reported `1.99.1`.

The fresh clone's `npm ci` installed 47 packages and reported zero vulnerabilities. `npm run build` passed TypeScript checking and Vite (16 modules transformed); `npm run check:contracts` matched the shared JSON fixture; `cargo test --manifest-path src-tauri/Cargo.toml` passed three contract unit tests and one parity integration test after a 7m 06s clean Rust test build; and `scripts/check-design.ps1` confirmed all nine tracked PNG dimensions. The first sandboxed attempt was blocked by npm registry/cache access; the completed run had the required network and filesystem access and exited `0`. The temporary clone was removed.

## 0A-12 hosted CI and checkpoint evidence (2026-10-18)

The exact `gh run list --limit 5` command showed [Foundation CI run 39177425523](https://github.com/zahidzta/zownload_application/actions/runs/39177425523) on `main` at merge commit `f51aeb63538da39e6161d26953b33fbff402e7d8` as `completed/success` (started 2026-10-18 23:39:19 UTC; duration 4m 16s). `gh run view` confirmed both jobs completed successfully:

| Hosted job | Runner | Successful checks |
|---|---|---|
| `foundation` | `windows-2025` | Node `24.22.0` and npm `11.19.1` pin checks, Rust `1.99.1` setup, `npm ci`, then `scripts/verify-foundation.ps1`: frontend build/type-check, TypeScript JSON contract fixtures, Rust unit and parity tests, and the nine indexed design PNGs. |
| `android` | `ubuntu-24.04` | Same Node/npm and Rust pins, Corretto `21.0.11.10.1`, SDK API `36`, Build-Tools `36.0.0`, Platform-Tools `37.0.1`, Command-Line Tools `22.0`, NDK `30.0.16248370`, `npm ci`, then `npm run android:debug` for `aarch64`. |

The exact selected tool versions, source links and setup commands are in the tables and sections above. The generated Android project additionally pins Gradle `9.6.1`, Android Gradle Plugin `9.3.1`, and Kotlin Gradle Plugin `2.2.10`; `src-tauri/Cargo.lock` and `package-lock.json` record the dependency trees.

At 0A-12, the local APK at `src-tauri/gen/android/app/build/outputs/apk/universal/debug/app-universal-debug.apk` was 136,162,644 bytes, SHA-256 `11B696468F8B586E5C3EBE48BBB38887210EE619B826879DF5475B8494D7D25A`. Hosted CI also completed its Android build, but the workflow does not upload the APK as an artifact; the checked file and hash are from the local 0A-09/0A-10 build. The 0A-11 section above records the independent clean-checkout Windows proof. Gate 0A owner acceptance is pending; Android device behavior and release installers are later-stage checks.

## 0C-05 Android runtime package setup

On the pinned Ubuntu 24.04 host with NDK r30 installed at the CI path, prepare
the ignored local Android engine package before `npm run android:debug`:

```bash
export NDK_HOME=/usr/local/lib/android/sdk/ndk/30.0.16248370
bash scripts/gate-0b/build-quickjs.sh android-arm64 --verify
pwsh -NoProfile -File scripts/gate-0c/package-quickjs.ps1 -QuickJsPath work/engine/build/quickjs/android-arm64/qjs
```

The packaging script checks the Gate 0B QuickJS hash, downloads and checks the
official yt-dlp 2026.08.19 zipapp, checks its yt-dlp and EJS version files,
then writes the pinned native and raw-resource inputs under ignored
`work/android/0c-05/`. Gradle keeps the original pinned youtubedl-android
0.18.1 Maven modules and includes those two inputs in the APK. The Android CI
job runs these commands before its debug build and does not upload the APK or
native output. On Windows, use an Ubuntu 24.04 build environment for the
QuickJS ELF; pass its local path to the same PowerShell packaging command.

## 1B-03 interactive test harness (2026-10-22)

From the repository root, install the approved, exact dev dependency versions:

```powershell
npm install --save-dev --save-exact vitest@5.0.5 @testing-library/react@16.3.3 @testing-library/user-event@14.6.8 jsdom@29.0.1
```

The command added 72 packages and reported zero vulnerabilities. It ran locally
with Node `24.14.0` and npm `11.21.0`, so npm warned that they differ from the
repository's Node `24.22.0` and npm `11.19.1` pins. jsdom `29.0.1` accepts both
the local Node version and the pinned CI version. The exact versions are recorded
in `package.json` and `package-lock.json`; clean checkouts use `npm ci`.

`npm run test:ui` runs only `tests/interactive/**/*.test.ts` and `.test.tsx` in
jsdom with Testing Library cleanup after each test. Keep the existing `node
--test --test-concurrency=1` suite separate; its Vite SSR tests remain under
`tests/ui/*.test.mjs`.

## 1C-09 desktop folder picker (2026-10-24)

The approved native folder picker uses Tauri's dialog plugin. Context7 was
consulted first but returned a monthly-quota error, so setup and the
`open({ directory: true, multiple: false })` API were checked against the
[official Tauri dialog documentation](https://v2.tauri.app/plugin/dialog/).
The JavaScript and Rust plugin versions are both pinned to `2.7.3`. Setup:

```powershell
npm install --save --save-exact @tauri-apps/plugin-dialog@2.7.3
# After adding tauri-plugin-dialog = { version = "=2.7.3" } to Cargo.toml:
cargo check --manifest-path src-tauri/Cargo.toml
```

`npm install` added one package and reported zero vulnerabilities. It warned
that the local Node `24.14.0` and npm `11.21.0` differ from the repository's
exact `24.22.0`/`11.19.1` pins. Cargo locked the exact Rust plugin and its
transitive dependencies. The app grants only `dialog:allow-open` in its main
window capability.

## 2B-02 Windows engine resource staging (2026-10-25)

Run from the repository root after Gate 0B's locked artifacts have been acquired
or built at the paths in [engine-sources](engine-sources.md) and the
[0B checkpoint](gates/evidence/0b/checkpoint.md):

```powershell
powershell -NoProfile -File scripts/gate-2b/stage-windows-engine.ps1
powershell -NoProfile -File scripts/gate-2b/test-stage-windows-engine.ps1
```

The first command verifies input SHA-256 values, copies into ignored
`src-tauri/resources/windows-engine/`, verifies the output again, and only then
replaces the staged resource directory. Tauri's Windows configuration maps the
three files to `binaries/` in the resource directory. Run staging before
`npm run tauri -- dev` or `npm run tauri -- build`; builds do not use a system
yt-dlp, FFmpeg, or QuickJS. Other platforms do not include these resources.

| Staged Windows x64 file | SHA-256 | Locked origin |
|---|---|---|
| `yt-dlp.exe` | `66674953fe251b89f4d08c5f0e35e0728679bd67ab3d7d05c0562af101dd3e7a` | Official yt-dlp 2026.08.19 release |
| `ffmpeg.exe` | `fa050630ddf5b7c3303d8dab5e5a42e7023547fb78ec9b90b5be0a4f788a7e66` | Gate 0B FFmpeg 8.1.3/LAME 3.100/zlib 1.3.2 build |
| `qjs.exe` | `bec67f8f87fa22958d3ab8be5508088116b8bff90032323d82c94545e1698b83` | Gate 0B QuickJS 2026-06-04 build |

Context7 was consulted before this Tauri configuration change but returned a
quota error. The resource mapping and platform configuration were checked
against the [official resource](https://v2.tauri.app/develop/resources/) and
[configuration](https://v2.tauri.app/reference/config/) documentation.

The 2B-02 no-bundle Windows build also succeeded with
`npm run tauri -- build --no-bundle`. Its release resource directory contained
`binaries/yt-dlp.exe`, `binaries/ffmpeg.exe`, and `binaries/qjs.exe`, each with
the exact staged hash above.

Foundation CI runs Rust tests from a clean checkout without packaging native
resources. Its test step overlays `TAURI_CONFIG={"bundle":{"resources":null}}`
only for that verification process; native development/build commands retain
the Windows resource map and require verified staging. A clean local
`cargo check` with resources temporarily absent failed on the missing FFmpeg
path, then passed with this test-only overlay. This follows Tauri's documented
[`TAURI_CONFIG` merge behavior](https://docs.rs/tauri-build/latest/tauri_build/#environment-variables).

## 2B-03 app-data bootstrap (2026-10-25)

Rust uses the already locked `sha2 0.10.9` for streaming checksum verification
and `time 0.3.55` for the manifest's RFC 3339 install timestamp. Cargo's lock
file already contained both crates transitively; adding them as direct
dependencies changed only the app dependency list. The Tauri setup code
resolves `binaries/` through Tauri's resource directory and uses the existing
app-local data directory. The bootstrap checks hashes before running bounded
health probes on staged app-data copies. A healthy prior directory is retained
if preparation or activation fails.

The exact Gate 2B V1 command is in [gate-2b](gates/gate-2b.md). To run the
additional real-binary health test after staging:

```powershell
$env:ZOWNLOAD_TEST_REAL_ENGINE = '1'
cargo test --manifest-path src-tauri/Cargo.toml real_pinned_resources_pass_health_checks_only_after_app_data_copy
Remove-Item Env:ZOWNLOAD_TEST_REAL_ENGINE
```

The focused real-binary test passed with all three processes launched from a
temporary app-data directory. Context7 returned a quota error when consulted;
the implementation used the [official Tauri resource documentation](https://v2.tauri.app/develop/resources/),
[RustCrypto SHA-2 documentation](https://docs.rs/sha2/0.10.9/sha2/), and
[time RFC 3339 documentation](https://docs.rs/time/0.3.55/time/format_description/well_known/struct.Rfc3339.html).

## 2B-08 native review verification setup (2026-10-26)

The native review used the locked Windows resources staged by 2B-02. Before
the live runs, these commands passed from the repository root:

```powershell
powershell -NoProfile -File scripts/gate-0b/verify-fixtures.ps1
npm run tauri -- build --debug --no-bundle
```

The first exact V3 attempt in the generated working checkout passed the UI
suite but hit Vite SSR module-loading timeouts in the Node suite. Reinstalling
with `npm ci` and trying pinned Node `24.22.0` did not clear that local
checkout's timeout. A clean detached worktree at the same source commit passed
the isolated header test in five seconds. Its first full V3 attempt hit a
Vitest fork startup timeout; the exact V3 rerun passed. No test or product
source was changed to get that pass.

The pinned [Node 24.22.0 Windows archive](https://nodejs.org/dist/v24.22.0/node-v24.22.0-win-x64.zip)
was downloaded into ignored `work/engine/2b-08/`, checked against the SHA-256
`f9683a19877e12a9b167305c8db71040d812876359de21f0d2e97c3f321f80c3`,
then extracted. The clean verification setup was:

```powershell
$repo = (Resolve-Path .).Path
$archive = Join-Path $repo 'work\engine\2b-08\node-v24.22.0-win-x64.zip'
Invoke-WebRequest -Uri 'https://nodejs.org/dist/v24.22.0/node-v24.22.0-win-x64.zip' -OutFile $archive
if ((Get-FileHash $archive -Algorithm SHA256).Hash.ToLowerInvariant() -ne 'f9683a19877e12a9b167305c8db71040d812876359de21f0d2e97c3f321f80c3') { throw 'Node archive hash mismatch' }
Expand-Archive -LiteralPath $archive -DestinationPath (Join-Path $repo 'work\engine\2b-08\node')
$check = Join-Path $repo 'work\engine\2b-08\clean'
$nodeDir = Join-Path $repo 'work\engine\2b-08\node\node-v24.22.0-win-x64'
git worktree add --detach $check HEAD
$env:PATH = "$nodeDir;$env:PATH"
Push-Location $check
npm ci
New-Item -ItemType Directory -Path src-tauri/resources/windows-engine -Force | Out-Null
foreach ($name in @('yt-dlp.exe', 'ffmpeg.exe', 'qjs.exe')) {
    Copy-Item -LiteralPath (Join-Path $repo "src-tauri\resources\windows-engine\$name") -Destination (Join-Path $check "src-tauri\resources\windows-engine\$name")
}
$env:CARGO_TARGET_DIR = Join-Path $repo 'src-tauri\target'
# Run the exact V3 command from docs/gates/gate-2b.md here.
Pop-Location
```

The copied resource hashes matched the 2B-02 table above. The clean checkout
was detached at `1ebddb8`; `task-2b-08` had only documentation and screenshot
changes relative to that commit. See the [native evidence](gates/evidence/2b/native-analysis.md)
for the exact V3 result and the separate active-window-close observation.
