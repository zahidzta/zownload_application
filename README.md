# Zownload

Zownload is an in-progress local media downloader built with Tauri, React, and Rust. The application is not ready for a public release.

**Android builds are experimental and are not distributed.**

## Windows installation

When a Windows release is available, download it from [GitHub Releases](https://github.com/zahidzta/zownload_application/releases). Most users should choose the NSIS `*-setup.exe`; managed environments may use the WiX `.msi`. These installers are unsigned, so if Windows SmartScreen warns, choose **More info** and then **Run anyway** if you trust the download.

The installer uses Microsoft's WebView2 bootstrapper. If the WebView2 Runtime is not already present, an Internet connection is required during installation so the bootstrapper can download it.

## Linux x86_64 installation

When a Linux release is available, choose one of its two packages from [GitHub Releases](https://github.com/zahidzta/zownload_application/releases):

- **AppImage (portable):** Download `Zownload_<version>_amd64.AppImage`. In the file manager, open **Properties → Permissions**, allow the file to run as a program, then double-click it. If your distribution reports that `libfuse.so.2` is missing, install its FUSE 2 compatibility package (`libfuse2t64` on Ubuntu 24.04) through the distribution's package manager and open the AppImage again.
- **Debian package (Ubuntu/Debian):** Download `Zownload_<version>_amd64.deb`, double-click it, and install it through the graphical software installer. Approve the administrator prompt when asked.

For a later app release, the AppImage uses Zownload's in-app updater. A `.deb` installation instead shows a link to the matching new `.deb`; download it and install it through the graphical installer, approving its administrator prompt. The unpublished 0.0.1 draft has no earlier version, so an actual upgrade has not yet been verified.

## Licence

Zownload source from this change onward is licensed under **GPL-3.0-or-later**. See [LICENSE](LICENSE) for the unmodified GPLv3 text and [third-party notices](docs/THIRD-PARTY-NOTICES.md) for dependencies and engine components, which retain their own licences.

Copies of the repository's earlier MIT-licensed history remain available under the MIT terms to people who received those versions. This change does not revoke those grants.
