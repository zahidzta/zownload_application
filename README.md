# Zownload

Zownload is an in-progress local media downloader built with Tauri, React, and Rust. The application is not ready for a public release.

**Android builds are experimental and are not distributed.**

## Windows installation

When a Windows release is available, download it from [GitHub Releases](https://github.com/zahidzta/zownload_application/releases). Most users should choose the NSIS `*-setup.exe`; managed environments may use the WiX `.msi`. These installers are unsigned, so if Windows SmartScreen warns, choose **More info** and then **Run anyway** if you trust the download.

The installer uses Microsoft's WebView2 bootstrapper. If the WebView2 Runtime is not already present, an Internet connection is required during installation so the bootstrapper can download it.

## Licence

Zownload source from this change onward is licensed under **GPL-3.0-or-later**. See [LICENSE](LICENSE) for the unmodified GPLv3 text and [third-party notices](docs/THIRD-PARTY-NOTICES.md) for dependencies and engine components, which retain their own licences.

Copies of the repository's earlier MIT-licensed history remain available under the MIT terms to people who received those versions. This change does not revoke those grants.
