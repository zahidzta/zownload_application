// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta
fn main() {
    tauri_build::build();
    #[cfg(windows)]
    {
        // Cargo test binaries lack the app bundle manifest needed by Windows dialogs.
        let manifest =
            std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("windows-tests.manifest");
        println!("cargo:rustc-link-arg-tests=/MANIFEST:EMBED");
        println!(
            "cargo:rustc-link-arg-tests=/MANIFESTINPUT:{}",
            manifest.display()
        );
    }
}
