// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta
// Keep the shared contract in the Rust build before commands are implemented.
pub mod android_spike;
#[cfg(not(target_os = "android"))]
mod commands;
pub mod contract;
#[cfg(target_os = "windows")]
pub mod engine;
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
                #[cfg(target_os = "windows")]
                {
                    let resources = app.path().resource_dir()?.join("binaries");
                    let data = app.path().app_local_data_dir()?;
                    let status = engine::bootstrap(
                        &resources,
                        &data,
                        &app.package_info().version.to_string(),
                    );
                    if let engine::EngineStatus::Unavailable(reason) = &status {
                        eprintln!("Windows engine unavailable: {reason}");
                    }
                    app.manage(status);
                }
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
    #[cfg(not(target_os = "android"))]
    let builder = builder.invoke_handler(tauri::generate_handler![
        commands::analyze_url,
        commands::enqueue_download,
        commands::pause_download,
        commands::resume_download,
        commands::remove_download,
        commands::get_queue,
        commands::get_history,
        commands::delete_history_entry,
        commands::clear_history,
        commands::get_error_notifications,
        commands::dismiss_error_notification,
        commands::get_settings,
        commands::set_settings,
        commands::engine_check_update,
        commands::engine_update
    ]);
    builder
        .run(tauri::generate_context!())
        .expect("error while running Zownload");
}
