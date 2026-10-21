// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

#[cfg(target_os = "android")]
use crate::contract::ErrorCode;
#[cfg(any(test, target_os = "android"))]
use crate::contract::{AppError, DownloadRequest, ItemStatus, Progress, QueueItem};
#[cfg(any(test, target_os = "android"))]
use rusqlite::{Connection, OptionalExtension};
#[cfg(any(test, target_os = "android"))]
use std::path::Path;
use tauri::{
    plugin::{Builder, TauriPlugin},
    Runtime,
};
#[cfg(any(test, target_os = "android"))]
use uuid::Uuid;

#[cfg(target_os = "android")]
use serde::{Deserialize, Serialize};
#[cfg(target_os = "android")]
use std::io::{self, Write};
#[cfg(target_os = "android")]
use std::sync::Mutex;
#[cfg(target_os = "android")]
use tauri::{
    ipc::Channel,
    plugin::{mobile::PluginInvokeError, PluginHandle},
    AppHandle, Emitter, Manager, State,
};

// A single row makes the spike's one-item limit explicit. Each save is an
// atomic SQLite statement, so a process death leaves a complete snapshot.
#[cfg(any(test, target_os = "android"))]
struct QueueStore {
    connection: Connection,
}

#[cfg(any(test, target_os = "android"))]
impl QueueStore {
    fn open(path: &Path) -> Result<Self, String> {
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent).map_err(|error| error.to_string())?;
        }
        let connection = Connection::open(path).map_err(|error| error.to_string())?;
        connection
            .execute_batch(
                "CREATE TABLE IF NOT EXISTS android_spike_queue (
                    slot INTEGER PRIMARY KEY CHECK (slot = 1),
                    snapshot TEXT NOT NULL
                );",
            )
            .map_err(|error| error.to_string())?;
        let store = Self { connection };
        store.recover_interrupted()?;
        Ok(store)
    }

    fn current(&self) -> Result<Option<QueueItem>, String> {
        let snapshot: Option<String> = self
            .connection
            .query_row(
                "SELECT snapshot FROM android_spike_queue WHERE slot = 1",
                [],
                |row| row.get(0),
            )
            .optional()
            .map_err(|error| error.to_string())?;
        snapshot
            .map(|json| serde_json::from_str(&json).map_err(|error| error.to_string()))
            .transpose()
    }

    fn save(&self, item: &QueueItem) -> Result<(), String> {
        let snapshot = serde_json::to_string(item).map_err(|error| error.to_string())?;
        self.connection
            .execute(
                "INSERT INTO android_spike_queue (slot, snapshot) VALUES (1, ?1)
                 ON CONFLICT(slot) DO UPDATE SET snapshot = excluded.snapshot",
                [snapshot],
            )
            .map_err(|error| error.to_string())?;
        Ok(())
    }

    fn clear(&self, id: &str) -> Result<(), String> {
        if self.current()?.as_ref().is_some_and(|item| item.id == id) {
            self.connection
                .execute("DELETE FROM android_spike_queue WHERE slot = 1", [])
                .map_err(|error| error.to_string())?;
        }
        Ok(())
    }

    fn recover_interrupted(&self) -> Result<(), String> {
        if let Some(mut item) = self.current()? {
            // Android may kill the process at any point. No engine call is
            // restarted here; only an explicit future Continue may do that.
            match item.status {
                ItemStatus::Analyzing
                | ItemStatus::Queued
                | ItemStatus::Downloading
                | ItemStatus::PostProcessing
                | ItemStatus::Packaging => {
                    item.status = ItemStatus::Paused;
                    self.save(&item)?;
                }
                ItemStatus::Done | ItemStatus::Failed => self.clear(&item.id)?,
                ItemStatus::Paused => {}
            }
        }
        Ok(())
    }

    fn enqueue(&self, request: DownloadRequest) -> Result<QueueItem, String> {
        if self.current()?.is_some() {
            return Err("The one-item spike queue already has an item".into());
        }
        let item = QueueItem {
            id: Uuid::new_v4().to_string(),
            request,
            title: None,
            thumbnail: None,
            status: ItemStatus::Queued,
            progress: Progress::Single { percent: 0.0 },
            error: None,
        };
        self.save(&item)?;
        Ok(item)
    }

    // The Kotlin engine callback reaches this durable checkpoint through a
    // Rust channel; Kotlin does not keep queue state.
    fn checkpoint(
        &self,
        id: &str,
        status: ItemStatus,
        percent: Option<f32>,
        error: Option<AppError>,
    ) -> Result<QueueItem, String> {
        let mut item = self.current()?.ok_or("Queue item is missing")?;
        if item.id != id {
            return Err("Queue item ID does not match".into());
        }
        if let Some(percent) = percent {
            let Progress::Single { percent: previous } = item.progress else {
                return Err("Spike queue accepts single-item progress only".into());
            };
            if !percent.is_finite() || !(0.0..=100.0).contains(&percent) || percent < previous {
                return Err("Progress must stay between 0 and 100 and never decrease".into());
            }
            item.progress = Progress::Single { percent };
        }
        item.status = status;
        item.error = error;
        self.save(&item)?;
        Ok(item)
    }
}

#[cfg(target_os = "android")]
pub struct SpikeQueue(Mutex<QueueStore>);

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
    #[serde(rename = "itemId")]
    item_id: String,
    #[serde(rename = "onProgress")]
    on_progress: Channel<EngineProgress>,
}

#[cfg(target_os = "android")]
#[derive(Deserialize)]
struct EngineProgress {
    percent: f32,
}

#[cfg(target_os = "android")]
#[derive(Deserialize)]
struct DownloadMp3Response {
    id: Option<String>,
    uri: Option<String>,
    #[serde(default, rename = "timedOut")]
    timed_out: bool,
    #[serde(default, rename = "taskRemoved")]
    task_removed: bool,
}

#[cfg(target_os = "android")]
#[derive(Serialize)]
struct CancelWorkRequest<'a> {
    id: &'a str,
}

#[cfg(target_os = "android")]
#[derive(Deserialize)]
struct ZipHandle {
    id: String,
    uri: String,
}

#[cfg(target_os = "android")]
#[derive(Deserialize, Serialize)]
pub struct ZipProbeResponse {
    uri: String,
    name: String,
    bytes: u64,
}

// ZipWriter only sees this bounded Write sink. The Kotlin side owns the
// pending Android output stream, but Rust owns entry names, order and bytes.
#[cfg(target_os = "android")]
struct MediaStoreZipWriter<'a, R: Runtime> {
    plugin: &'a PluginHandle<R>,
    id: &'a str,
    bytes: std::sync::Arc<std::sync::atomic::AtomicU64>,
}

#[cfg(target_os = "android")]
impl<R: Runtime> Write for MediaStoreZipWriter<'_, R> {
    fn write(&mut self, bytes: &[u8]) -> io::Result<usize> {
        use base64::Engine as _;
        let chunk = &bytes[..bytes.len().min(16 * 1024)];
        if chunk.is_empty() {
            return Ok(0);
        }
        self.plugin
            .run_mobile_plugin::<serde_json::Value>(
                "writeZipChunk",
                serde_json::json!({
                    "id": self.id,
                    "data": base64::engine::general_purpose::STANDARD.encode(chunk)
                }),
            )
            .map_err(io::Error::other)?;
        self.bytes
            .fetch_add(chunk.len() as u64, std::sync::atomic::Ordering::Relaxed);
        Ok(chunk.len())
    }

    fn flush(&mut self) -> io::Result<()> {
        Ok(())
    }
}

#[cfg(target_os = "android")]
#[tauri::command]
pub async fn probe_mediastore_zip<R: Runtime>(
    app: AppHandle<R>,
    fail: bool,
) -> Result<ZipProbeResponse, String> {
    tauri::async_runtime::spawn_blocking(move || probe_mediastore_zip_blocking(app, fail))
        .await
        .map_err(|error| error.to_string())?
}

#[cfg(target_os = "android")]
fn probe_mediastore_zip_blocking<R: Runtime>(
    app: AppHandle<R>,
    fail: bool,
) -> Result<ZipProbeResponse, String> {
    let plugin = app.state::<AndroidSpike<R>>();
    let name = format!("Zownload-0C13-{}.zip", Uuid::new_v4());
    let handle: ZipHandle = plugin
        .0
        .run_mobile_plugin("openZip", serde_json::json!({ "name": name }))
        .map_err(|error| error.to_string())?;
    eprintln!("Zownload0C13 ZIP_PENDING uri={} name={name}", handle.uri);

    // Give the separate test app time to query while IS_PENDING=1. Only the
    // successful probe needs this host-observation window.
    std::thread::sleep(std::time::Duration::from_secs(if fail { 2 } else { 20 }));
    let result = (|| -> Result<ZipProbeResponse, String> {
        let byte_count = std::sync::Arc::new(std::sync::atomic::AtomicU64::new(0));
        let sink = MediaStoreZipWriter {
            plugin: &plugin.0,
            id: &handle.id,
            bytes: byte_count.clone(),
        };
        let mut archive = zip::ZipWriter::new_stream(sink);
        let options = zip::write::SimpleFileOptions::default()
            .compression_method(zip::CompressionMethod::Stored);
        archive
            .start_file("manifest.txt", options)
            .map_err(|error| error.to_string())?;
        archive
            .write_all(b"Zownload Gate 0C-13\nRust owns ZIP entries and order.\n")
            .map_err(|error| error.to_string())?;
        archive
            .start_file("payload.bin", options)
            .map_err(|error| error.to_string())?;
        let pattern: Vec<u8> = (0..=255).collect();
        for _ in 0..1024 {
            archive
                .write_all(&pattern)
                .map_err(|error| error.to_string())?;
        }
        if fail {
            return Err("Injected ZIP failure before archive close".into());
        }
        archive.finish().map_err(|error| error.to_string())?;
        let published: ZipProbeResponse = plugin
            .0
            .run_mobile_plugin("publishZip", serde_json::json!({ "id": handle.id }))
            .map_err(|error| error.to_string())?;
        if published.uri != handle.uri
            || published.name != name
            || published.bytes != byte_count.load(std::sync::atomic::Ordering::Relaxed)
        {
            return Err("Published ZIP metadata differs from Rust output".into());
        }
        eprintln!(
            "Zownload0C13 ZIP_PUBLISHED uri={} name={} bytes={}",
            published.uri, published.name, published.bytes
        );
        Ok(published)
    })();
    if let Err(error) = &result {
        let cleanup = plugin.0.run_mobile_plugin::<serde_json::Value>(
            "abortZip",
            serde_json::json!({ "id": handle.id }),
        );
        eprintln!("Zownload0C13 ZIP_ABORT error={error} cleanup={cleanup:?}");
    }
    result
}

#[cfg(target_os = "android")]
fn with_queue<T>(
    state: &State<'_, SpikeQueue>,
    work: impl FnOnce(&QueueStore) -> Result<T, String>,
) -> Result<T, String> {
    let store = state.0.lock().map_err(|_| "Queue lock is poisoned")?;
    work(&store)
}

#[cfg(target_os = "android")]
fn emit_item<R: Runtime>(app: &AppHandle<R>, item: &QueueItem) {
    if let Err(error) = app.emit("queue:item-updated", item) {
        eprintln!("Could not emit queue update: {error}");
    }
}

#[cfg(target_os = "android")]
fn emit_removed<R: Runtime>(app: &AppHandle<R>, id: &str) {
    if let Err(error) = app.emit("queue:item-removed", id) {
        eprintln!("Could not emit queue removal: {error}");
    }
}

#[cfg(target_os = "android")]
#[tauri::command]
pub async fn enqueue_download<R: Runtime>(
    app: AppHandle<R>,
    request: DownloadRequest,
) -> Result<String, String> {
    // Kotlin's mobile-plugin call waits for the worker result. Keep that wait
    // off Tauri's command thread so get_queue can answer while work continues.
    tauri::async_runtime::spawn_blocking(move || enqueue_download_blocking(app, request))
        .await
        .map_err(|error| error.to_string())?
}

#[cfg(target_os = "android")]
fn enqueue_download_blocking<R: Runtime>(
    app: AppHandle<R>,
    request: DownloadRequest,
) -> Result<String, String> {
    use crate::contract::{Format, Quality};
    if request.format != Format::Mp3
        || request.is_playlist
        || !matches!(request.quality, Quality::Audio { bitrate: 128 })
        || request.url.trim().is_empty()
    {
        return Err("0C-07 accepts one YouTube MP3 at 128 kbps".into());
    }
    let queue = app.state::<SpikeQueue>();
    let item = with_queue(&queue, |store| store.enqueue(request.clone()))?;
    emit_item(&app, &item);
    run_download_blocking(app, item)
}

#[cfg(target_os = "android")]
#[tauri::command]
pub async fn resume_download<R: Runtime>(app: AppHandle<R>, id: String) -> Result<(), String> {
    tauri::async_runtime::spawn_blocking(move || resume_download_blocking(app, id))
        .await
        .map_err(|error| error.to_string())?
}

#[cfg(target_os = "android")]
fn resume_download_blocking<R: Runtime>(app: AppHandle<R>, id: String) -> Result<(), String> {
    let queue = app.state::<SpikeQueue>();
    // Claim the paused item before starting Android work. A second Continue
    // cannot launch another engine against the same partial file.
    let item = with_queue(&queue, |store| {
        let current = store.current()?.ok_or("Queue item is missing")?;
        if current.id != id || current.status != ItemStatus::Paused {
            return Err("Only the matching paused item can continue".into());
        }
        store.checkpoint(&id, ItemStatus::Queued, None, None)
    })?;
    emit_item(&app, &item);
    run_download_blocking(app, item).map(|_| ())
}

#[cfg(target_os = "android")]
fn run_download_blocking<R: Runtime>(app: AppHandle<R>, item: QueueItem) -> Result<String, String> {
    let queue = app.state::<SpikeQueue>();
    let plugin = app.state::<AndroidSpike<R>>();
    // Android forbids starting this service from the background on recent
    // versions. This call is initiated by the user's foreground enqueue.
    let started: Result<serde_json::Value, PluginInvokeError> = plugin
        .0
        .run_mobile_plugin("startWorkService", serde_json::json!({}));
    let outcome = match started {
        Err(error) => Err(error.to_string()),
        Ok(_) => {
            eprintln!("Zownload0C08 RUST_SERVICE_STARTED item={}", item.id);
            let active = with_queue(&queue, |store| {
                store.checkpoint(&item.id, ItemStatus::Downloading, None, None)
            });
            let active = match active {
                Ok(active) => active,
                Err(error) => {
                    let _: Result<serde_json::Value, PluginInvokeError> = plugin
                        .0
                        .run_mobile_plugin("stopWorkService", serde_json::json!({}));
                    return Err(error);
                }
            };
            emit_item(&app, &active);

            // The Kotlin call can outlive a WebView. Never hold the database
            // lock while it runs; get_queue must answer a recreated UI.
            // Kotlin sends transient engine progress directly to this Rust
            // channel. Rust alone checkpoints it and publishes queue events.
            let progress_app = app.clone();
            let progress_id = item.id.clone();
            let on_progress = Channel::new(move |body| {
                let update: EngineProgress = match body.deserialize() {
                    Ok(update) => update,
                    Err(error) => {
                        eprintln!("Zownload0C09 RUST_PROGRESS_INVALID {error}");
                        return Ok(());
                    }
                };
                let state = progress_app.state::<SpikeQueue>();
                let changed = with_queue(&state, |store| {
                    let Some(current) = store.current()? else {
                        return Ok(None);
                    };
                    let Progress::Single { percent: previous } = current.progress else {
                        return Ok(None);
                    };
                    if current.id != progress_id
                        || current.status != ItemStatus::Downloading
                        || !update.percent.is_finite()
                        || update.percent <= previous
                        || update.percent > 100.0
                    {
                        return Ok(None);
                    }
                    store
                        .checkpoint(
                            &progress_id,
                            ItemStatus::Downloading,
                            Some(update.percent),
                            None,
                        )
                        .map(Some)
                });
                match changed {
                    Ok(Some(item)) => {
                        eprintln!(
                            "Zownload0C09 RUST_PROGRESS item={} percent={}",
                            item.id, update.percent
                        );
                        emit_item(&progress_app, &item);
                    }
                    Ok(None) => {}
                    Err(error) => eprintln!("Zownload0C09 RUST_PROGRESS_SAVE_FAILED {error}"),
                }
                Ok(())
            });
            let result: Result<DownloadMp3Response, PluginInvokeError> =
                plugin.0.run_mobile_plugin(
                    "downloadMp3",
                    DownloadMp3Request {
                        url: item.request.url.clone(),
                        item_id: item.id.clone(),
                        on_progress,
                    },
                );
            eprintln!(
                "Zownload0C08 RUST_DOWNLOAD_CALLBACK item={} result={}",
                item.id,
                if result.is_ok() { "ok" } else { "error" }
            );
            if let Ok(response) = &result {
                if response.task_removed {
                    // The service keeps this process alive after a recents
                    // swipe. Save first, then stop the native worker and service.
                    let paused = with_queue(&queue, |store| {
                        store.checkpoint(&item.id, ItemStatus::Paused, None, None)
                    });
                    if let Ok(ref paused) = paused {
                        emit_item(&app, paused);
                        eprintln!("Zownload0C10 RUST_PAUSED_ON_TASK_REMOVAL item={}", item.id);
                    }
                    // Even if SQLite fails, still terminate native work and
                    // stop the service before reporting the write failure.
                    let cancelled = response.id.as_deref().map_or_else(
                        || Err("Missing engine cancellation ID".to_string()),
                        |id| {
                            plugin
                                .0
                                .run_mobile_plugin::<serde_json::Value>(
                                    "cancelWork",
                                    CancelWorkRequest { id },
                                )
                                .map(|_| ())
                                .map_err(|error| {
                                    format!("Could not cancel Android engine: {error}")
                                })
                        },
                    );
                    let stopped: Result<serde_json::Value, PluginInvokeError> = plugin
                        .0
                        .run_mobile_plugin("stopWorkService", serde_json::json!({}));
                    eprintln!("Zownload0C10 RUST_SERVICE_STOP_REQUESTED item={}", item.id);
                    paused?;
                    cancelled?;
                    stopped.map_err(|error| format!("Could not stop Android service: {error}"))?;
                    return Err("Download paused after removal from recents".into());
                }
            }
            let stopped: Result<serde_json::Value, PluginInvokeError> = plugin
                .0
                .run_mobile_plugin("stopWorkService", serde_json::json!({}));
            eprintln!("Zownload0C08 RUST_SERVICE_STOP_REQUESTED item={}", item.id);
            match (result, stopped) {
                (Ok(response), stop_result) if response.timed_out => {
                    if let Err(error) = stop_result {
                        eprintln!("Zownload0C08 RUST_TIMEOUT_STOP_ERROR {error}");
                    }
                    eprintln!("Zownload0C08 RUST_TIMEOUT_CALLBACK item={}", item.id);
                    let paused = with_queue(&queue, |store| {
                        store.checkpoint(&item.id, ItemStatus::Paused, None, None)
                    })?;
                    emit_item(&app, &paused);
                    return Err("Foreground service timed out; open Zownload to continue".into());
                }
                (Ok(response), Ok(_))
                    if response.id.as_deref().is_some_and(|id| !id.is_empty())
                        && response
                            .uri
                            .as_deref()
                            .is_some_and(|uri| uri.starts_with("content://")) =>
                {
                    Ok(())
                }
                (Ok(_), Ok(_)) => Err("Android plugin returned an invalid published MP3".into()),
                (Err(error), _) => Err(error.to_string()),
                (_, Err(error)) => Err(format!("Could not stop Android service: {error}")),
            }
        }
    };

    match outcome {
        Ok(()) => {
            let done = with_queue(&queue, |store| {
                store.checkpoint(&item.id, ItemStatus::Done, Some(100.0), None)
            })?;
            emit_item(&app, &done);
            with_queue(&queue, |store| store.clear(&item.id))?;
            emit_removed(&app, &item.id);
            Ok(item.id)
        }
        Err(message) => {
            // Recents removal and foreground timeout have already saved a
            // paused checkpoint. Leave that row for an explicit Continue.
            if with_queue(&queue, |store| {
                Ok(store.current()?.is_some_and(|current| {
                    current.id == item.id && current.status == ItemStatus::Paused
                }))
            })? {
                return Err(message);
            }
            let failed = with_queue(&queue, |store| {
                store.checkpoint(
                    &item.id,
                    ItemStatus::Failed,
                    None,
                    Some(AppError::new(ErrorCode::Unknown, Some(message.clone()))),
                )
            })?;
            emit_item(&app, &failed);
            with_queue(&queue, |store| store.clear(&item.id))?;
            emit_removed(&app, &item.id);
            Err(message)
        }
    }
}

#[cfg(target_os = "android")]
#[tauri::command]
pub fn get_queue(queue: State<'_, SpikeQueue>) -> Result<Vec<QueueItem>, String> {
    with_queue(&queue, |store| Ok(store.current()?.into_iter().collect()))
}

// Compile-only bridge probe for 0C-03.
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
                let path = _app
                    .path()
                    .app_local_data_dir()?
                    .join("android-spike-queue.sqlite3");
                let store = QueueStore::open(&path).map_err(std::io::Error::other)?;
                _app.manage(SpikeQueue(Mutex::new(store)));
            }
            Ok(())
        })
        .build()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::contract::{Format, Quality};

    fn path() -> std::path::PathBuf {
        std::env::temp_dir().join(format!("android_spike_queue_{}.sqlite3", Uuid::new_v4()))
    }

    fn request() -> DownloadRequest {
        DownloadRequest {
            url: "https://www.youtube.com/watch?v=example".into(),
            format: Format::Mp3,
            quality: Quality::Audio { bitrate: 128 },
            is_playlist: false,
        }
    }

    #[test]
    fn android_spike_queue_restores_every_interrupted_state_as_paused() {
        for status in [
            ItemStatus::Analyzing,
            ItemStatus::Queued,
            ItemStatus::Downloading,
            ItemStatus::PostProcessing,
            ItemStatus::Packaging,
        ] {
            let database = path();
            let store = QueueStore::open(&database).unwrap();
            let item = store.enqueue(request()).unwrap();
            store
                .checkpoint(&item.id, status, Some(37.5), None)
                .unwrap();
            drop(store);

            let reopened = QueueStore::open(&database).unwrap();
            let restored = reopened.current().unwrap().unwrap();
            assert_eq!(restored.id, item.id);
            assert_eq!(restored.status, ItemStatus::Paused);
            assert_eq!(
                serde_json::to_value(&restored).unwrap()["progress"]["percent"],
                37.5
            );
            assert!(reopened.enqueue(request()).is_err());
            drop(reopened);
            std::fs::remove_file(database).unwrap();
        }
    }

    #[test]
    fn android_spike_queue_checkpoints_contract_json_and_one_item_limit() {
        let database = path();
        let store = QueueStore::open(&database).unwrap();
        let item = store.enqueue(request()).unwrap();
        assert!(store.enqueue(request()).is_err());
        assert!(Uuid::parse_str(&item.id).is_ok());
        let active = store
            .checkpoint(&item.id, ItemStatus::Downloading, Some(25.0), None)
            .unwrap();
        let json = serde_json::to_value(&active).unwrap();
        assert_eq!(json["request"]["isPlaylist"], false);
        assert_eq!(json["request"]["quality"]["type"], "audio");
        assert_eq!(json["status"], "downloading");
        assert_eq!(json["progress"]["kind"], "single");
        assert_eq!(json["progress"]["percent"], 25.0);
        assert!(store
            .checkpoint(&item.id, ItemStatus::Downloading, Some(24.0), None)
            .is_err());
        store.clear(&item.id).unwrap();
        assert!(store.current().unwrap().is_none());
        drop(store);
        std::fs::remove_file(database).unwrap();
    }
}
