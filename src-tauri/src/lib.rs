// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta
// Keep the shared contract in the Rust build before commands are implemented.
#[path = "engine/android_contract.rs"]
#[allow(dead_code)]
pub mod android_contract;
pub mod android_spike;
#[cfg(any(target_os = "windows", target_os = "linux"))]
pub mod app_update;
mod commands;
pub mod contract;
#[cfg(any(target_os = "windows", target_os = "linux", target_os = "macos"))]
pub mod engine;
#[cfg(target_os = "android")]
#[path = "engine/android.rs"]
pub mod engine;
pub mod persistence;
pub(crate) mod playlist;

use tauri::Manager;

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    let builder = tauri::Builder::default().plugin(tauri_plugin_dialog::init());
    #[cfg(target_os = "android")]
    let builder = builder.plugin(engine::init());
    let builder = builder
        .setup(|app| {
            // Production persistence is shared by desktop and Android. The old
            // 0C spike database remains separate until its bridge is retired.
            let path = app.path().app_local_data_dir()?.join("zownload.sqlite3");
            let database = std::sync::Arc::new(std::sync::Mutex::new(
                persistence::Database::open_at(&path)?,
            ));
            app.manage(std::sync::Arc::clone(&database));
            #[cfg(any(target_os = "windows", target_os = "linux", target_os = "macos"))]
            {
                // Install the platform supervisor before launching engine work.
                let supervisor = engine::process::Supervisor::install()?;
                app.manage(std::sync::Arc::clone(&supervisor));
                let resources = app.path().resource_dir()?.join("binaries");
                let data = app.path().app_local_data_dir()?;
                let status =
                    engine::bootstrap(&resources, &data, &app.package_info().version.to_string());
                if let engine::EngineStatus::Unavailable(reason) = &status {
                    eprintln!("desktop engine unavailable: {reason}");
                }
                let engine_ready = matches!(status, engine::EngineStatus::Ready(_));
                let ready = match &status {
                    engine::EngineStatus::Ready(paths) => Some(paths.clone()),
                    engine::EngineStatus::Unavailable(_) => None,
                };
                app.manage(status);
                let queue = engine::queue::QueueCoordinator::new(
                    database,
                    ready,
                    supervisor,
                    data.clone(),
                    Some(resources),
                    app.path().download_dir()?,
                    commands::queue_sink(app.handle().clone()),
                );
                app.manage(std::sync::Arc::clone(&queue));
                if let Err(error) = queue.kick() {
                    eprintln!("could not start saved queue: {error:?}");
                }
                if engine_ready {
                    let data = data.clone();
                    let queue = std::sync::Arc::clone(&queue);
                    std::thread::spawn(move || {
                        let checked =
                            engine::updater::ReleaseClient::official().and_then(|client| {
                                client.startup_check(&data, time::OffsetDateTime::now_utc())
                            });
                        match checked {
                            Ok(true) => {
                                if let Err(error) = queue.kick() {
                                    eprintln!(
                                        "could not activate startup yt-dlp update: {error:?}"
                                    );
                                }
                            }
                            Ok(false) => (),
                            Err(error) => {
                                eprintln!("startup yt-dlp update check failed: {error}")
                            }
                        }
                    });
                }
            }
            #[cfg(target_os = "android")]
            engine::init_queue(app.handle(), database)?;
            Ok(())
        })
        .on_window_event(|window, event| {
            #[cfg(any(target_os = "windows", target_os = "linux", target_os = "macos"))]
            if matches!(event, tauri::WindowEvent::CloseRequested { .. }) {
                if let Some(queue) =
                    window.try_state::<std::sync::Arc<engine::queue::QueueCoordinator>>()
                {
                    queue.close();
                }
                if let Some(supervisor) =
                    window.try_state::<std::sync::Arc<engine::process::Supervisor>>()
                {
                    supervisor.shutdown();
                }
            }
            #[cfg(not(any(target_os = "windows", target_os = "linux", target_os = "macos")))]
            let _ = (window, event);
        });
    #[cfg(any(target_os = "windows", target_os = "linux"))]
    let builder = builder.plugin(tauri_plugin_updater::Builder::new().build());
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
        commands::engine_update,
        commands::app_update_check,
        commands::app_update_install
    ]);
    builder
        .run(tauri::generate_context!())
        .expect("error while running Zownload");
}
