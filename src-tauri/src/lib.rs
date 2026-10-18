// Keep the shared contract in the Rust build before commands are implemented.
pub mod contract;

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .run(tauri::generate_context!())
        .expect("error while running Zownload");
}
