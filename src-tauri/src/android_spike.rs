// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

use tauri::{
    plugin::{Builder, TauriPlugin},
    Runtime,
};

#[cfg(target_os = "android")]
use serde::{Deserialize, Serialize};
#[cfg(target_os = "android")]
use std::sync::atomic::{AtomicBool, Ordering};
#[cfg(target_os = "android")]
use tauri::{
    plugin::{mobile::PluginInvokeError, PluginHandle},
    AppHandle, Manager, State,
};

#[cfg(target_os = "android")]
pub struct ProbeBusy(AtomicBool);

// The handle is owned by Rust; Kotlin only answers adapter calls.
#[cfg(target_os = "android")]
struct AndroidSpike<R: Runtime>(PluginHandle<R>);

#[cfg(target_os = "android")]
#[derive(Serialize)]
struct SmokeRequest {
    value: String,
}

#[cfg(target_os = "android")]
#[derive(Deserialize)]
pub struct SmokeResponse {
    pub value: String,
}

#[cfg(target_os = "android")]
#[derive(Serialize)]
struct DownloadMp3Request {
    url: String,
}

#[cfg(target_os = "android")]
#[derive(Deserialize)]
struct DownloadMp3Response {
    id: String,
    uri: String,
}

// This one-item bridge proves AC-30. Task 0C-07 replaces the in-memory guard
// with the durable Rust queue; Kotlin does not keep job state or a queue.
#[cfg(target_os = "android")]
#[tauri::command]
pub fn enqueue_download<R: Runtime>(
    app: AppHandle<R>,
    request: crate::contract::DownloadRequest,
    busy: State<'_, ProbeBusy>,
) -> Result<String, String> {
    use crate::contract::{Format, Quality};
    if request.format != Format::Mp3
        || request.is_playlist
        || !matches!(request.quality, Quality::Audio { bitrate: 128 })
        || request.url.trim().is_empty()
    {
        return Err("0C-06 accepts one YouTube MP3 at 128 kbps".into());
    }
    if busy.0.swap(true, Ordering::AcqRel) {
        return Err("A spike download is already running".into());
    }
    let plugin = app.state::<AndroidSpike<R>>();
    let result: Result<DownloadMp3Response, PluginInvokeError> = plugin
        .0
        .run_mobile_plugin("downloadMp3", DownloadMp3Request { url: request.url });
    busy.0.store(false, Ordering::Release);
    let response = result.map_err(|error| error.to_string())?;
    if response.id.is_empty() || !response.uri.starts_with("content://") {
        return Err("Android plugin returned an invalid published MP3".into());
    }
    Ok(response.id)
}

#[cfg(target_os = "android")]
#[tauri::command]
pub fn get_queue() -> Vec<crate::contract::QueueItem> {
    // The 0C-06 call resolves only after publication. A durable queue and
    // observable progress are the explicit scope of 0C-07.
    Vec::new()
}

// Compile-only bridge probe for 0C-03. Later Android adapter work can call this
// through Rust without adding an undocumented UI command.
#[cfg(target_os = "android")]
pub fn smoke<R: Runtime>(
    app: &AppHandle<R>,
    value: String,
) -> Result<SmokeResponse, PluginInvokeError> {
    let plugin = app.state::<AndroidSpike<R>>();
    plugin.0.run_mobile_plugin("smoke", SmokeRequest { value })
}

pub fn init<R: Runtime>() -> TauriPlugin<R> {
    Builder::new("android_spike")
        .setup(|_app, _api| {
            #[cfg(target_os = "android")]
            {
                let handle =
                    _api.register_android_plugin("com.zownload.app", "AndroidSpikePlugin")?;
                _app.manage(AndroidSpike(handle));
                _app.manage(ProbeBusy(AtomicBool::new(false)));
            }
            Ok(())
        })
        .build()
}
