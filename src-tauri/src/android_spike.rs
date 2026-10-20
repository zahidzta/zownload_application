// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

use tauri::{
    plugin::{Builder, TauriPlugin},
    Runtime,
};

#[cfg(target_os = "android")]
use serde::{Deserialize, Serialize};
#[cfg(target_os = "android")]
use tauri::{
    plugin::{mobile::PluginInvokeError, PluginHandle},
    AppHandle, Manager,
};

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
                let handle = _api.register_android_plugin("com.zownload.app", "AndroidSpikePlugin")?;
                _app.manage(AndroidSpike(handle));
            }
            Ok(())
        })
        .build()
}
