# Zownload

Zownload is an in-progress local media downloader built with Tauri, React, and Rust. The application is not ready for a public release.

**Android builds are experimental and are not distributed.**

## Windows installation

When a Windows release is available, download it from [GitHub Releases](https://github.com/zahidzta/zownload_application/releases). Most users should choose the NSIS `*-setup.exe`; managed environments may use the WiX `.msi`. These installers are unsigned, so if Windows SmartScreen warns, choose **More info** and then **Run anyway** if you trust the download.

The installer uses Microsoft's WebView2 bootstrapper. If the WebView2 Runtime is not already present, an Internet connection is required during installation so the bootstrapper can download it.

## Linux x86_64 installation

When a Linux release is available, download the artifact for your distribution from [GitHub Releases](https://github.com/zahidzta/zownload_application/releases).

### AppImage

Download the `.AppImage` file. In the file manager, open its **Properties** and enable **Allow executing file as a program** (wording varies by desktop), then double-click it to start Zownload.

If the desktop reports that FUSE v2 is missing, install the compatibility library from your distribution's software center: Ubuntu 24.04 uses [`libfuse2t64`](https://packages.ubuntu.com/noble/libfuse2t64), Ubuntu 22.04 uses [`libfuse2`](https://packages.ubuntu.com/jammy/libfuse2), and Fedora provides it as [`fuse-libs`](https://packages.fedoraproject.org/pkgs/fuse/fuse-libs/). The software center may ask for your administrator password.

### Debian package (`.deb`)

Use the `.deb` on Debian, Ubuntu, or a compatible derivative. Double-click the downloaded file to open it in the distribution's software installer, choose **Install**, and approve the administrator prompt. The installer supplies the required WebKitGTK runtime dependency from the distribution's configured repositories.

For an update, open **Settings** and check for app updates. When Zownload reports **New version available**, choose its update action to open the matching `.deb` release asset, download it, close Zownload, and open the downloaded package in the software installer. Choose **Install** or **Update** and approve the administrator prompt to replace the installed version.

## Licence

Zownload source from this change onward is licensed under **GPL-3.0-or-later**. See [LICENSE](LICENSE) for the unmodified GPLv3 text and [third-party notices](docs/THIRD-PARTY-NOTICES.md) for dependencies and engine components, which retain their own licences.

Copies of the repository's earlier MIT-licensed history remain available under the MIT terms to people who received those versions. This change does not revoke those grants.
