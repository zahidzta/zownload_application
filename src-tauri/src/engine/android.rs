// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

//! Rust adapter for the Kotlin single-entry engine. Queue state remains in the
//! shared SQLite database; this module only calls the native engine bridge.

use crate::{
    android_contract::{
        entry_request, parse_analysis, BridgeReply, CancelResult, DownloadResult, EngineAnalysis,
        EngineProgress, EngineUpdateResult,
    },
    contract::{
        AnalyzeResult, AppError, DownloadRequest, EngineUpdateInfo, ErrorCode, ItemStatus,
        Progress, QueueItem,
    },
    persistence::{notifications::TerminalOutcome, Database},
};
use serde::{de::DeserializeOwned, Serialize};
use std::{
    path::PathBuf,
    sync::{
        atomic::{AtomicBool, Ordering},
        Arc, Mutex,
    },
    thread,
    time::{Duration, Instant},
};
use tauri::{
    ipc::Channel,
    plugin::{mobile::PluginInvokeError, Builder, PluginHandle, TauriPlugin},
    AppHandle, Emitter, Manager, Runtime,
};

pub(crate) trait Engine<R: Runtime>: Send + Sync {
    fn analyze(&self, url: &str) -> Result<EngineAnalysis, AppError>;
    fn download_entry(
        &self,
        request: &DownloadRequest,
        operation_id: &str,
        on_progress: Arc<dyn Fn(EngineProgress) + Send + Sync>,
    ) -> Result<DownloadResult, AppError>;
    fn cancel(&self, operation_id: &str) -> Result<bool, AppError>;
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
struct CancelArgs<'a> {
    operation_id: &'a str,
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
}

impl<R: Runtime> Engine<R> for AndroidEngine<R> {
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

    fn cancel(&self, operation_id: &str) -> Result<bool, AppError> {
        let result: CancelResult = self.call("cancel", CancelArgs { operation_id })?;
        Ok(result.cancelled)
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
    let queue = AndroidQueueCoordinator::new(database, engine, app_data, app.clone());
    app.manage(Arc::clone(&queue));
    queue
        .kick()
        .map_err(|error| std::io::Error::other(error.detail.unwrap_or_default()))?;
    Ok(())
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum Intent {
    Run,
    Pause,
    Remove,
}

struct Active {
    id: String,
    operation_id: String,
    intent: Intent,
    cancel: Arc<AtomicBool>,
}

#[derive(Default)]
struct Control {
    active: Option<Active>,
}

pub(crate) struct AndroidQueueCoordinator<R: Runtime> {
    database: Arc<Mutex<Database>>,
    engine: Arc<AndroidEngine<R>>,
    app_data: PathBuf,
    app: AppHandle<R>,
    control: Mutex<Control>,
}

fn failure(detail: impl Into<String>) -> AppError {
    AppError::new(ErrorCode::Unknown, Some(detail.into()))
}

fn io_failure(error: std::io::Error) -> AppError {
    let code = match error.kind() {
        std::io::ErrorKind::PermissionDenied => ErrorCode::PermissionDenied,
        std::io::ErrorKind::StorageFull => ErrorCode::DiskFull,
        _ => ErrorCode::Unknown,
    };
    AppError::new(code, Some(error.to_string()))
}

impl<R: Runtime> AndroidQueueCoordinator<R> {
    pub fn new(
        database: Arc<Mutex<Database>>,
        engine: Arc<AndroidEngine<R>>,
        app_data: PathBuf,
        app: AppHandle<R>,
    ) -> Arc<Self> {
        Arc::new(Self {
            database,
            engine,
            app_data,
            app,
            control: Mutex::new(Control::default()),
        })
    }

    fn db(&self) -> Result<std::sync::MutexGuard<'_, Database>, AppError> {
        self.database
            .lock()
            .map_err(|_| failure("database lock poisoned"))
    }

    fn get_item(&self, id: &str) -> Result<QueueItem, AppError> {
        self.db()?
            .get_queue()
            .map_err(|error| failure(error.to_string()))?
            .into_iter()
            .find(|item| item.id == id)
            .ok_or_else(|| failure("queue item not found"))
    }

    fn save(&self, item: &QueueItem) -> Result<(), AppError> {
        self.db()?
            .update_queue_item(item)
            .map(|_| ())
            .map_err(|error| failure(error.to_string()))
    }

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

    fn emit_null(&self, event: &str) {
        if let Err(error) = self.app.emit(event, ()) {
            eprintln!("could not emit Android {event}: {error}");
        }
    }

    pub fn enqueue(self: &Arc<Self>, request: DownloadRequest) -> Result<String, AppError> {
        let id = uuid::Uuid::new_v4().to_string();
        let progress = if request.is_playlist {
            Progress::Playlist {
                done: 0,
                failed: 0,
                total: 0,
                current_title: None,
                current_percent: 0.0,
            }
        } else {
            Progress::Single { percent: 0.0 }
        };
        let item = QueueItem {
            id: id.clone(),
            request,
            title: None,
            thumbnail: None,
            status: ItemStatus::Queued,
            progress,
            error: None,
        };
        self.db()?
            .insert_queue_item(&item)
            .map_err(|error| failure(error.to_string()))?;
        self.emit_item(&item);
        self.kick()?;
        Ok(id)
    }

    pub fn kick(self: &Arc<Self>) -> Result<(), AppError> {
        let mut control = self
            .control
            .lock()
            .map_err(|_| failure("queue control lock poisoned"))?;
        if control.active.is_some() {
            return Ok(());
        }
        let Some(mut item) = self
            .db()?
            .get_queue()
            .map_err(|error| failure(error.to_string()))?
            .into_iter()
            .find(|item| item.status == ItemStatus::Queued)
        else {
            return Ok(());
        };
        item.status = if item.request.is_playlist {
            ItemStatus::Analyzing
        } else {
            ItemStatus::Downloading
        };
        self.save(&item)?;
        self.emit_item(&item);
        let active = Arc::new(AtomicBool::new(false));
        control.active = Some(Active {
            id: item.id.clone(),
            operation_id: item.id.clone(),
            intent: Intent::Run,
            cancel: Arc::clone(&active),
        });
        drop(control);
        let coordinator = Arc::clone(self);
        thread::spawn(move || coordinator.run(item, active));
        Ok(())
    }

    fn set_operation(&self, id: &str, operation_id: &str) {
        if let Ok(mut control) = self.control.lock() {
            if let Some(active) = control.active.as_mut().filter(|active| active.id == id) {
                active.operation_id = operation_id.to_owned();
            }
        }
    }

    fn update_progress(&self, id: &str, percent: f32, title: Option<String>, playlist: bool) {
        if !percent.is_finite() {
            return;
        }
        let mut item = match self.get_item(id) {
            Ok(item) => item,
            Err(_) => return,
        };
        if item.status != ItemStatus::Downloading {
            return;
        }
        if playlist {
            if let Progress::Playlist {
                current_percent,
                current_title,
                ..
            } = &mut item.progress
            {
                if percent < *current_percent {
                    return;
                }
                *current_percent = percent.clamp(0.0, 100.0);
                if title.is_some() {
                    *current_title = title;
                }
            }
        } else if let Progress::Single { percent: previous } = &mut item.progress {
            if percent < *previous {
                return;
            }
            *previous = percent.clamp(0.0, 100.0);
        }
        if self.save(&item).is_ok() {
            self.emit_item(&item);
        }
    }

    fn copy_result(
        &self,
        id: &str,
        index: usize,
        request: &DownloadRequest,
        result: &DownloadResult,
    ) -> Result<(), AppError> {
        if !result.path.is_file() {
            return Err(AppError::new(
                ErrorCode::EngineMissing,
                Some("Android engine reported a missing output file".into()),
            ));
        }
        let directory = self.app_data.join("android-engine-outputs").join(id);
        std::fs::create_dir_all(&directory).map_err(io_failure)?;
        let name = crate::android_contract::safe_output_name(
            &result.title,
            &format!("{id}-{index}"),
            request.format,
        );
        let destination = directory.join(name);
        if !result.path.is_file()
            || std::fs::metadata(&result.path).map_err(io_failure)?.len() != result.bytes
        {
            return Err(AppError::new(
                ErrorCode::EngineMissing,
                Some("Android engine output size does not match its result".into()),
            ));
        }
        let mut input = std::fs::File::open(&result.path).map_err(io_failure)?;
        let mut output = std::fs::OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&destination)
            .map_err(io_failure)?;
        let copied = match std::io::copy(&mut input, &mut output) {
            Ok(copied) => copied,
            Err(error) => {
                drop(output);
                let _ = std::fs::remove_file(&destination);
                return Err(io_failure(error));
            }
        };
        if let Err(error) = output.sync_all() {
            drop(output);
            let _ = std::fs::remove_file(&destination);
            return Err(io_failure(error));
        }
        if copied != result.bytes {
            let _ = std::fs::remove_file(&destination);
            return Err(AppError::new(
                ErrorCode::EngineMissing,
                Some("Android output copy was incomplete".into()),
            ));
        }
        // The engine's temporary directory is private to this operation.
        std::fs::remove_file(&result.path).map_err(io_failure)?;
        Ok(())
    }

    fn download_one(
        self: &Arc<Self>,
        id: &str,
        index: usize,
        total: usize,
        request: &DownloadRequest,
        playlist: bool,
    ) -> Result<DownloadResult, AppError> {
        let operation_id = if playlist {
            format!("{id}_{index}")
        } else {
            id.to_owned()
        };
        self.set_operation(id, &operation_id);
        let coordinator = Arc::clone(self);
        let id = id.to_owned();
        let last_report = Arc::new(Mutex::new(Instant::now() - Duration::from_secs(1)));
        let progress_clock = Arc::clone(&last_report);
        let callback = Arc::new(move |signal: EngineProgress| {
            let now = Instant::now();
            if let Ok(mut last) = progress_clock.lock() {
                if now.duration_since(*last) < Duration::from_millis(200) && signal.percent < 100.0
                {
                    return;
                }
                *last = now;
            }
            let percent = if playlist && total > 0 {
                ((index as f32 * 100.0) + signal.percent.clamp(0.0, 100.0)) / total as f32
            } else {
                signal.percent
            };
            coordinator.update_progress(
                &id,
                percent,
                (!signal.title.is_empty()).then_some(signal.title),
                playlist,
            );
        });
        self.engine.download_entry(request, &operation_id, callback)
    }

    fn run(self: Arc<Self>, mut item: QueueItem, cancel: Arc<AtomicBool>) {
        let result = (|| -> Result<(u32, u32), AppError> {
            if !item.request.is_playlist {
                let file = self.download_one(&item.id, 0, 1, &item.request, false)?;
                self.copy_result(&item.id, 0, &item.request, &file)?;
                item.title = Some(file.title);
                if let Some(thumbnail) = file.thumbnail {
                    item.thumbnail = Some(thumbnail);
                }
                return Ok((1, 0));
            }

            let analysis = self.engine.analyze(&item.request.url)?;
            let AnalyzeResult::Playlist {
                title, item_count, ..
            } = analysis.result
            else {
                return Err(AppError::new(
                    ErrorCode::UnsupportedSite,
                    Some("the selected URL is not a playlist".into()),
                ));
            };
            let total = analysis.entries.len();
            if total == 0 || total > 100_000 {
                return Err(AppError::new(
                    ErrorCode::EngineMissing,
                    Some("Android engine returned an invalid playlist size".into()),
                ));
            }
            item.title = Some(title);
            item.progress = Progress::Playlist {
                done: 0,
                failed: 0,
                total: item_count.max(total as u32),
                current_title: None,
                current_percent: 0.0,
            };
            item.status = ItemStatus::Downloading;
            self.save(&item)?;
            self.emit_item(&item);

            let mut done = 0u32;
            let mut failed = 0u32;
            for (index, entry) in analysis.entries.into_iter().enumerate() {
                if cancel.load(Ordering::SeqCst) {
                    break;
                }
                let request =
                    entry_request(entry.url, item.request.format, item.request.quality.clone());
                match self.download_one(&item.id, index, total, &request, true) {
                    Ok(file) => match self.copy_result(&item.id, index, &request, &file) {
                        Ok(()) => done += 1,
                        Err(error) => {
                            eprintln!(
                                "Android playlist output failed: {}",
                                error.detail.unwrap_or_default()
                            );
                            failed += 1;
                        }
                    },
                    Err(error)
                        if matches!(
                            error.code,
                            ErrorCode::DiskFull | ErrorCode::PermissionDenied
                        ) =>
                    {
                        return Err(error)
                    }
                    Err(_) if cancel.load(Ordering::SeqCst) => break,
                    Err(error) => {
                        failed += 1;
                        eprintln!(
                            "Android playlist entry failed: {}",
                            error.detail.unwrap_or_default()
                        );
                    }
                }
                item.progress = Progress::Playlist {
                    done,
                    failed,
                    total: total as u32,
                    current_title: Some(entry.title),
                    current_percent: 100.0,
                };
                if cancel.load(Ordering::SeqCst) {
                    break;
                }
                item.progress = Progress::Playlist {
                    done,
                    failed,
                    total: total as u32,
                    current_title: None,
                    current_percent: 0.0,
                };
                item.status = ItemStatus::Downloading;
                self.save(&item)?;
                self.emit_item(&item);
            }
            if done == 0 && failed > 0 {
                return Err(AppError::new(
                    ErrorCode::Unknown,
                    Some("all Android playlist entries failed".into()),
                ));
            }
            Ok((done, failed))
        })();

        let active = self.control.lock().ok().and_then(|control| {
            control
                .active
                .as_ref()
                .filter(|active| active.id == item.id)
                .map(|active| (active.intent, active.operation_id.clone()))
        });
        let Some((intent, operation_id)) = active else {
            return;
        };
        if intent == Intent::Remove {
            let _ = self.engine.cancel(&operation_id);
            let owned = self.app_data.join("android-engine-outputs").join(&item.id);
            if owned.exists() {
                let _ = std::fs::remove_dir_all(owned);
            }
            if self
                .db()
                .is_ok_and(|mut db| db.remove_queue_item(&item.id).unwrap_or(false))
            {
                self.emit_removed(&item.id);
            }
        } else if intent == Intent::Pause || cancel.load(Ordering::SeqCst) {
            item.status = ItemStatus::Paused;
            let _ = self.save(&item);
            self.emit_item(&item);
        } else {
            match result {
                Ok((done, _failed)) if done > 0 => {
                    item.status = ItemStatus::Done;
                    item.error = None;
                    match item.progress {
                        Progress::Single { .. } => {
                            item.progress = Progress::Single { percent: 100.0 }
                        }
                        Progress::Playlist {
                            done,
                            failed,
                            total,
                            ..
                        } => {
                            item.progress = Progress::Playlist {
                                done,
                                failed,
                                total,
                                current_title: None,
                                current_percent: 100.0,
                            };
                        }
                    }
                    if self.save(&item).is_ok() {
                        self.emit_item(&item);
                        if self.db().is_ok_and(|mut db| {
                            db.settle_queue_item(
                                &item.id,
                                TerminalOutcome::Completed {
                                    successful_files: done,
                                },
                            )
                            .is_ok()
                        }) {
                            self.emit_null("history:changed");
                            self.emit_removed(&item.id);
                        }
                    }
                }
                Ok(_) => self.fail_item(&mut item, failure("Android engine produced no files")),
                Err(error) => self.fail_item(&mut item, error),
            }
        }
        if let Ok(mut control) = self.control.lock() {
            control.active = None;
        }
        let _ = self.kick();
    }

    fn fail_item(&self, item: &mut QueueItem, error: AppError) {
        item.status = ItemStatus::Failed;
        item.error = Some(error.clone());
        if self.save(item).is_ok() {
            self.emit_item(item);
            if self.db().is_ok_and(|mut db| {
                db.settle_queue_item(&item.id, TerminalOutcome::Failed(error))
                    .is_ok()
            }) {
                self.emit_null("error-notifications:changed");
                self.emit_removed(&item.id);
            }
        }
    }

    pub fn pause(&self, id: &str) -> Result<(), AppError> {
        let operation = {
            let mut control = self
                .control
                .lock()
                .map_err(|_| failure("queue control lock poisoned"))?;
            match control.active.as_mut().filter(|active| active.id == id) {
                Some(active) => {
                    active.intent = Intent::Pause;
                    active.cancel.store(true, Ordering::SeqCst);
                    Some(active.operation_id.clone())
                }
                None => None,
            }
        };
        if let Some(operation_id) = operation {
            self.engine.cancel(&operation_id)?;
            return Ok(());
        }
        let mut item = self.get_item(id)?;
        if item.status != ItemStatus::Queued {
            return Err(failure("only queued or downloading items can be paused"));
        }
        item.status = ItemStatus::Paused;
        self.save(&item)?;
        self.emit_item(&item);
        Ok(())
    }

    pub fn resume(self: &Arc<Self>, id: &str) -> Result<(), AppError> {
        let mut item = self.get_item(id)?;
        if item.status != ItemStatus::Paused {
            return Err(failure("only paused items can be resumed"));
        }
        item.status = ItemStatus::Queued;
        item.error = None;
        self.save(&item)?;
        self.emit_item(&item);
        self.kick()
    }

    pub fn remove(self: &Arc<Self>, id: &str) -> Result<(), AppError> {
        let operation = {
            let mut control = self
                .control
                .lock()
                .map_err(|_| failure("queue control lock poisoned"))?;
            match control.active.as_mut().filter(|active| active.id == id) {
                Some(active) => {
                    active.intent = Intent::Remove;
                    active.cancel.store(true, Ordering::SeqCst);
                    Some(active.operation_id.clone())
                }
                None => None,
            }
        };
        if let Some(operation_id) = operation {
            self.engine.cancel(&operation_id)?;
            return Ok(());
        }
        if !self
            .db()?
            .remove_queue_item(id)
            .map_err(|error| failure(error.to_string()))?
        {
            return Err(failure("queue item not found"));
        }
        self.emit_removed(id);
        self.kick()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn entry_request_keeps_playlist_quality_without_changing_public_request_types() {
        let request = entry_request(
            "https://example.test/entry".into(),
            Format::Mp3,
            crate::contract::Quality::Min,
        );
        assert!(!request.is_playlist);
        assert_eq!(request.quality, crate::contract::Quality::Min);
    }
}
