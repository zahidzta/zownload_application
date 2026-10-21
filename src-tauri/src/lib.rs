// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta
// Keep the shared contract in the Rust build before commands are implemented.
pub mod android_spike;
pub mod contract;

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    let builder = tauri::Builder::default().plugin(android_spike::init());
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
