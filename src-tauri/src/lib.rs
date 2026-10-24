// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta
// Keep the shared contract in the Rust build before commands are implemented.
pub mod android_spike;
pub mod contract;
pub mod persistence;

#[cfg(not(target_os = "android"))]
use tauri::Manager;

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    let builder = tauri::Builder::default()
        .plugin(android_spike::init())
        .plugin(tauri_plugin_dialog::init())
        .setup(|app| {
            #[cfg(not(target_os = "android"))]
            {
                // Production data is local to this app and separate from the Android spike DB.
                let path = app.path().app_local_data_dir()?.join("zownload.sqlite3");
                let database = persistence::Database::open_at(&path)?;
                app.manage(std::sync::Mutex::new(database));
            }
            Ok(())
        });
    #[cfg(target_os = "android")]
    let builder = builder.invoke_handler(tauri::generate_handler![
        android_spike::enqueue_download,
        android_spike::resume_download,
        android_spike::get_queue,
        android_spike::probe_mediastore_zip
    ]);
    builder
        .run(tauri::generate_context!())
        .expect("error while running Zownload");
}
