// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

//! Tauri Android plugin adapter for the Rust-owned Android queue and MediaStore
//! ZIP storage engine.

use crate::{
    android_contract::{
        parse_analysis, BridgeReply, CancelResult, DownloadResult, EngineAnalysis, EngineProgress,
        EngineUpdateResult, ForegroundProgressArgs, ForegroundServiceArgs, LifecycleSignal,
        PendingZipFd, PendingZipHandle, PublishedZipResult,
    },
    android_queue::{AndroidEngineBackend, AndroidEventSink, AndroidQueueCore},
    android_zip::PendingArchiveStore,
    contract::{
        AppError, DownloadRequest, EngineUpdateInfo, ErrorCode, Format, QueueItem, Settings,
    },
    persistence::Database,
};
use serde::{de::DeserializeOwned, Serialize};
use std::{
    fs::File,
    os::fd::FromRawFd,
    sync::{Arc, Mutex},
};
use tauri::{
    ipc::Channel,
    plugin::{mobile::PluginInvokeError, Builder, PluginHandle, TauriPlugin},
    AppHandle, Emitter, Manager, Runtime,
};

pub(crate) trait Engine<R: Runtime>: Send + Sync {
    fn analyze(&self, url: &str) -> Result<EngineAnalysis, AppError>;
    fn check_update(&self) -> Result<EngineUpdateInfo, AppError>;
    fn update(&self) -> Result<EngineUpdateInfo, AppError>;
}

pub(crate) struct AndroidEngine<R: Runtime> {
    plugin: PluginHandle<R>,
}

#[derive(Serialize)]
struct AnalyzeArgs<'a> {
    url: &'a str,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct DownloadArgs<'a> {
    operation_id: &'a str,
    request: &'a DownloadRequest,
    on_progress: Channel<EngineProgress>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct OperationArgs<'a> {
    operation_id: &'a str,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct QueueCacheArgs<'a> {
    queue_id: &'a str,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct PublishOutputArgs<'a> {
    path: &'a str,
    display_name: String,
    format: &'static str,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct CreatePendingZipArgs<'a> {
    display_name: &'a str,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct UriArgs<'a> {
    uri: &'a str,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct PublishPendingZipArgs<'a> {
    uri: &'a str,
    expected_bytes: u64,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct RegisterLifecycleArgs {
    on_signal: Channel<LifecycleSignal>,
}

impl<R: Runtime> AndroidEngine<R> {
    fn call<T: DeserializeOwned, A: Serialize>(
        &self,
        command: &str,
        args: A,
    ) -> Result<T, AppError> {
        let reply: BridgeReply<T> =
            self.plugin
                .run_mobile_plugin(command, args)
                .map_err(|error: PluginInvokeError| {
                    AppError::new(
                        ErrorCode::EngineMissing,
                        Some(format!("Android engine bridge {command}: {error}")),
                    )
                })?;
        reply.into_result()
    }

    fn register_lifecycle_channel(
        &self,
        channel: Channel<LifecycleSignal>,
    ) -> Result<(), AppError> {
        let _: serde_json::Value = self.call(
            "registerLifecycleChannel",
            RegisterLifecycleArgs { on_signal: channel },
        )?;
        Ok(())
    }
}

impl<R: Runtime> Engine<R> for AndroidEngine<R> {
    fn analyze(&self, url: &str) -> Result<EngineAnalysis, AppError> {
        AndroidEngineBackend::analyze(self, url)
    }

    fn check_update(&self) -> Result<EngineUpdateInfo, AppError> {
        AndroidEngineBackend::check_update(self)
    }

    fn update(&self) -> Result<EngineUpdateInfo, AppError> {
        AndroidEngineBackend::update(self)
    }
}

impl<R: Runtime> PendingArchiveStore for AndroidEngine<R> {
    fn create_pending(&self, display_name: &str) -> Result<PendingZipHandle, AppError> {
        self.call("createPendingZip", CreatePendingZipArgs { display_name })
    }

    fn open_rw(&self, handle: &PendingZipHandle) -> Result<File, AppError> {
        let result: PendingZipFd = self.call("openPendingZipFd", UriArgs { uri: &handle.uri })?;
        if result.fd < 0 {
            return Err(AppError::new(
                ErrorCode::EngineMissing,
                Some("MediaStore returned an invalid file descriptor".into()),
            ));
        }
        // SAFETY: Kotlin detached this ParcelFileDescriptor for exclusive Rust ownership.
        Ok(unsafe { File::from_raw_fd(result.fd) })
    }

    fn publish(
        &self,
        handle: &PendingZipHandle,
        expected_bytes: u64,
    ) -> Result<PublishedZipResult, AppError> {
        self.call(
            "publishPendingZip",
            PublishPendingZipArgs {
                uri: &handle.uri,
                expected_bytes,
            },
        )
    }

    fn delete_pending(&self, handle: &PendingZipHandle) -> Result<(), AppError> {
        let _: serde_json::Value = self.call("deletePendingZip", UriArgs { uri: &handle.uri })?;
        Ok(())
    }
}

impl<R: Runtime> AndroidEngineBackend for AndroidEngine<R> {
    fn analyze(&self, url: &str) -> Result<EngineAnalysis, AppError> {
        let value: serde_json::Value = self.call("analyze", AnalyzeArgs { url })?;
        parse_analysis(value)
    }

    fn download_entry(
        &self,
        request: &DownloadRequest,
        operation_id: &str,
        on_progress: Arc<dyn Fn(EngineProgress) + Send + Sync>,
    ) -> Result<DownloadResult, AppError> {
        let on_progress = Channel::new(move |body| {
            if let Ok(progress) = body.deserialize() {
                on_progress(progress);
            }
            Ok(())
        });
        self.call(
            "downloadOne",
            DownloadArgs {
                operation_id,
                request,
                on_progress,
            },
        )
    }

    fn publish_output(
        &self,
        result: &DownloadResult,
        request: &DownloadRequest,
    ) -> Result<(), AppError> {
        let path = result.path.to_str().ok_or_else(|| {
            AppError::new(
                ErrorCode::EngineMissing,
                Some("Android engine output path is not valid UTF-8".into()),
            )
        })?;
        let format = match request.format {
            Format::Mp3 => "mp3",
            Format::Mp4 => "mp4",
        };
        let args = PublishOutputArgs {
            path,
            display_name: crate::android_contract::safe_output_name(&result.title, request.format),
            format,
        };
        let _: serde_json::Value = self.call("publishOutput", args)?;
        Ok(())
    }

    fn cleanup_operation(&self, operation_id: &str) -> Result<(), AppError> {
        let _: serde_json::Value = self.call("cleanupOperation", OperationArgs { operation_id })?;
        Ok(())
    }

    fn cleanup_queue_cache(&self, queue_id: &str) -> Result<(), AppError> {
        let _: serde_json::Value = self.call("cleanupQueueCache", QueueCacheArgs { queue_id })?;
        Ok(())
    }

    fn cancel(&self, operation_id: &str) -> Result<bool, AppError> {
        let result: CancelResult = self.call("cancel", OperationArgs { operation_id })?;
        Ok(result.cancelled)
    }

    fn start_foreground_service(
        &self,
        title: &str,
        detail: &str,
        percent: i32,
        indeterminate: bool,
        timeout_detail: &str,
    ) -> Result<(), AppError> {
        let _: serde_json::Value = self.call(
            "startForegroundService",
            ForegroundServiceArgs {
                title,
                detail,
                percent,
                indeterminate,
                timeout_detail,
            },
        )?;
        Ok(())
    }

    fn update_foreground_progress(
        &self,
        title: &str,
        detail: &str,
        percent: i32,
        indeterminate: bool,
    ) -> Result<(), AppError> {
        let _: serde_json::Value = self.call(
            "updateForegroundProgress",
            ForegroundProgressArgs {
                title,
                detail,
                percent,
                indeterminate,
            },
        )?;
        Ok(())
    }

    fn stop_foreground_service(&self) -> Result<(), AppError> {
        let _: serde_json::Value = self.call("stopForegroundService", ())?;
        Ok(())
    }

    fn check_update(&self) -> Result<EngineUpdateInfo, AppError> {
        self.call::<EngineUpdateResult, _>("checkUpdate", ())
            .map(Into::into)
    }

    fn update(&self) -> Result<EngineUpdateInfo, AppError> {
        self.call::<EngineUpdateResult, _>("update", ())
            .map(Into::into)
    }
}

struct TauriAndroidEventSink<R: Runtime> {
    app: AppHandle<R>,
}

impl<R: Runtime> AndroidEventSink for TauriAndroidEventSink<R> {
    fn emit_item(&self, item: &QueueItem) {
        if let Err(error) = self.app.emit("queue:item-updated", item) {
            eprintln!("could not emit Android queue update: {error}");
        }
    }

    fn emit_removed(&self, id: &str) {
        if let Err(error) = self.app.emit("queue:item-removed", id) {
            eprintln!("could not emit Android queue removal: {error}");
        }
    }

    fn emit_history_changed(&self) {
        if let Err(error) = self.app.emit("history:changed", ()) {
            eprintln!("could not emit Android history:changed: {error}");
        }
    }

    fn emit_notifications_changed(&self) {
        if let Err(error) = self.app.emit("error-notifications:changed", ()) {
            eprintln!("could not emit Android error-notifications:changed: {error}");
        }
    }
}

pub(crate) struct AndroidQueueCoordinator<R: Runtime> {
    core: Arc<AndroidQueueCore<AndroidEngine<R>, TauriAndroidEventSink<R>>>,
}

impl<R: Runtime> AndroidQueueCoordinator<R> {
    pub fn enqueue(&self, request: DownloadRequest) -> Result<String, AppError> {
        self.core.enqueue(request)
    }

    pub fn pause(&self, id: &str) -> Result<(), AppError> {
        self.core.pause(id)
    }

    pub fn resume(&self, id: &str) -> Result<(), AppError> {
        self.core.resume(id)
    }

    pub fn remove(&self, id: &str) -> Result<(), AppError> {
        self.core.remove(id)
    }

    pub fn kick(&self) -> Result<(), AppError> {
        self.core.kick()
    }
}

pub fn init<R: Runtime>() -> TauriPlugin<R> {
    Builder::new("android_engine")
        .setup(|app, api| {
            let plugin = api.register_android_plugin("com.zownload.app", "AndroidEnginePlugin")?;
            app.manage(Arc::new(AndroidEngine { plugin }));
            Ok(())
        })
        .build()
}

pub fn init_queue<R: Runtime>(
    app: &AppHandle<R>,
    database: Arc<Mutex<Database>>,
) -> Result<(), Box<dyn std::error::Error>> {
    let engine = Arc::clone(app.state::<Arc<AndroidEngine<R>>>().inner());
    let app_data = app.path().app_local_data_dir()?;
    let sink = Arc::new(TauriAndroidEventSink { app: app.clone() });
    let core = AndroidQueueCore::new(database, Arc::clone(&engine), sink, app_data);
    let signal_core = Arc::clone(&core);
    let lifecycle_channel = Channel::new(move |body| {
        if let Ok(signal) = body.deserialize::<LifecycleSignal>() {
            match signal.kind.as_str() {
                "task_removed" => signal_core.on_task_removed(),
                "foreground_timeout" => signal_core.on_foreground_timeout(),
                other => eprintln!("ignoring unknown Android lifecycle signal: {other}"),
            }
        }
        Ok(())
    });
    engine
        .register_lifecycle_channel(lifecycle_channel)
        .map_err(|error| std::io::Error::other(error.detail.unwrap_or_default()))?;

    let queue = Arc::new(AndroidQueueCoordinator { core });
    app.manage(Arc::clone(&queue));
    queue
        .kick()
        .map_err(|error| std::io::Error::other(error.detail.unwrap_or_default()))?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use crate::android_contract::entry_request;
    use crate::contract::{Format, Quality};

    #[test]
    fn entry_request_keeps_playlist_quality_without_changing_public_request_types() {
        let request = entry_request(
            "https://example.test/entry".into(),
            Format::Mp3,
            Quality::Min,
        );
        assert!(!request.is_playlist);
        assert_eq!(request.quality, Quality::Min);
    }
}
