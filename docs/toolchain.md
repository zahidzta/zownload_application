# Gate 0A toolchain and OS matrix

Selected 2026-10-17 for the empty Tauri 2 foundation. These are **pins for the forthcoming scaffold and CI**, not claims that this checkout has installed or built them. Commit `package-lock.json`, `Cargo.lock`, a Rust toolchain file, and the generated Gradle wrapper in their assigned Gate 0A tasks. CI and clean-checkout work must verify the pins before feature work.

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
| JDK | Eclipse Temurin `17.0.20.1+1` | [Temurin release](https://github.com/adoptium/temurin17-binaries/releases/tag/jdk-17.0.20.1%2B1). JDK 17 matches Android Gradle Plugin's documented default/minimum in the [AGP 9.4 compatibility table](https://developer.android.com/build/releases/agp-9-4-0-release-notes). The locally installed JDK 26 is not the pin. |
| Android NDK | r30, `30.0.16248370` | Google's [NDK download page](https://developer.android.com/ndk/downloads) identifies r30 as its current LTS and gives this `ndkVersion`. |
| Android SDK platform | Android 16, API `36` (`platforms;android-36`) | [Stable Android 16 SDK platform](https://developer.android.com/tools/releases/platforms). Set `compileSdk = 36`; set `targetSdk = 36` for the skeleton, subject to Android behavior checks in later gates. |
| Android SDK Build-Tools | `36.0.0` (`build-tools;36.0.0`) | [AGP 9.4 compatibility table](https://developer.android.com/build/releases/agp-9-4-0-release-notes) lists Build-Tools 36.0.0. |
| Android SDK Platform-Tools | `37.0.1` (`platform-tools`) | Google's [Platform-Tools release notes](https://developer.android.com/tools/releases/platform-tools). Verify the installed revision because `platform-tools` resolves to the current package. |
| Android SDK Command-Line Tools | `22.0` (`cmdline-tools;22.0`, standalone archive build `15859902`) | Google's [current standalone download](https://developer.android.com/studio#command-line-tools-only) names archive build `15859902`; install the versioned SDK package to avoid a moving `latest` path. |
| Tauri updater plugin | `2.13.0` | Already required by `PROJECT.md:385`; [updater release](https://github.com/tauri-apps/plugins-workspace/releases/tag/updater-v2.13.0). No updater code belongs in Gate 0A. |

### NDK version review (2026-10-17)

The local SDK initially had r27c (`27.2.12479018`), a dated observation of this Windows machine. Within the r27 series, r27d (`27.3.13750724`) is the better choice: Android's [r27 changelog](https://github.com/android/ndk/wiki/Changelog-r27#r27d) records a newer Clang build and fixes for `lldb.sh` on paths with spaces and for Python lookup on macOS. Android's [unsupported downloads list](https://github.com/android/ndk/wiki/Unsupported-Downloads#r27d) confirms the exact r27d version and classifies it as obsolete. The [NDK release page](https://github.com/android/ndk/wiki#ndk-r30-2026-lts) lists r30 (`30.0.16248370`) as the supported LTS. Keep r30 as the Gate 0A pin, consistent with the current stable toolchain rule in `PROJECT.md:389`.

The Android Gradle Plugin and Gradle wrapper are selected and committed with the generated Android project in **0A-08**. That task must check the generated versions against JDK 17, SDK 36 and NDK r30 before accepting them; the [AGP compatibility table](https://developer.android.com/build/releases/agp-9-4-0-release-notes) is a compatibility reference, not an instruction to replace Tauri's generated template blindly.

## Setup commands

Use the linked vendor downloads for the exact Node and Temurin releases; install Microsoft C++ Build Tools with the **Desktop development with C++** workload and WebView2 for Windows development, as described by [Tauri](https://tauri.app/start/prerequisites/). On macOS, run `xcode-select --install`. On Ubuntu, install the [Tauri Linux prerequisites](https://tauri.app/start/prerequisites/#linux) for the chosen runner image.

From the repository root, after installing Rust via [rustup](https://rustup.rs/) and the vendor Node/JDK packages:

```powershell
rustup toolchain install 1.99.1 --profile minimal
rustup target add aarch64-linux-android --toolchain 1.99.1
node --version
npm --version
rustc +1.99.1 --version
java -version
```

For Android on Windows, download Google's Command-Line Tools archive linked above and place its inner `cmdline-tools` contents under `%LOCALAPPDATA%\Android\Sdk\cmdline-tools\22.0` so `22.0\bin\sdkmanager.bat` exists. Set `ANDROID_HOME` to `%LOCALAPPDATA%\Android\Sdk` and `JAVA_HOME` to the installed Temurin 17 directory. Then run in PowerShell (use the equivalent SDK path on macOS/Linux):

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
