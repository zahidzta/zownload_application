// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta
// Keep the shared contract in the Rust build before commands are implemented.
pub mod contract;
pub mod android_spike;

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(android_spike::init())
        .run(tauri::generate_context!())
        .expect("error while running Zownload");
}
