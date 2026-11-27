// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

//! Android queue state machine, foreground-service lifecycle coordination, and
//! bounded MediaStore ZIP orchestration. Platform-independent traits keep all
//! transition, pause, timeout, and recovery rules testable on host builds.

use crate::{
    android_contract::{
        entry_request, safe_output_name, EngineAnalysis, EngineProgress, PendingZipHandle,
    },
    android_zip::{AndroidZipOutput, PendingArchiveStore},
    contract::{
        AnalyzeResult, AppError, DownloadRequest, EngineUpdateInfo, ErrorCode, Format, ItemStatus,
        Language, Progress, QueueItem,
    },
    persistence::{notifications::TerminalOutcome, Database},
    playlist::{PlaylistEntry as SnapshotEntry, PlaylistSnapshot, MAX_PLAYLIST_ENTRIES},
};
use std::{
    path::PathBuf,
    sync::{
        atomic::{AtomicBool, Ordering},
        Arc, Mutex,
    },
    thread,
    time::{Duration, Instant},
};

pub(crate) trait AndroidEngineBackend: PendingArchiveStore + Send + Sync {
    fn analyze(&self, url: &str) -> Result<EngineAnalysis, AppError>;
    fn download_entry(
        &self,
        request: &DownloadRequest,
        operation_id: &str,
        on_progress: Arc<dyn Fn(EngineProgress) + Send + Sync>,
    ) -> Result<crate::android_contract::DownloadResult, AppError>;
    fn publish_output(
        &self,
        result: &crate::android_contract::DownloadResult,
        request: &DownloadRequest,
    ) -> Result<(), AppError>;
    fn cleanup_operation(&self, operation_id: &str) -> Result<(), AppError>;
    fn cleanup_queue_cache(&self, queue_id: &str) -> Result<(), AppError>;
    fn cancel(&self, operation_id: &str) -> Result<bool, AppError>;
    fn start_foreground_service(
        &self,
        title: &str,
        detail: &str,
        percent: i32,
        indeterminate: bool,
        timeout_detail: &str,
    ) -> Result<(), AppError>;
    fn update_foreground_progress(
        &self,
        title: &str,
        detail: &str,
        percent: i32,
        indeterminate: bool,
    ) -> Result<(), AppError>;
    fn stop_foreground_service(&self) -> Result<(), AppError>;
    fn check_update(&self) -> Result<EngineUpdateInfo, AppError>;
    fn update(&self) -> Result<EngineUpdateInfo, AppError>;
}

pub(crate) trait AndroidEventSink: Send + Sync {
    fn emit_item(&self, item: &QueueItem);
    fn emit_removed(&self, id: &str);
    fn emit_history_changed(&self);
    fn emit_notifications_changed(&self);
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum Intent {
    Run,
    Pause,
    Remove,
    TaskRemovedPause,
    TimeoutPause,
}

impl Intent {
    fn is_pause_like(self) -> bool {
        matches!(
            self,
            Self::Pause | Self::TaskRemovedPause | Self::TimeoutPause
        )
    }
}

struct Active {
    id: String,
    operation_id: String,
    phase: ItemStatus,
    intent: Intent,
    cancel: Arc<AtomicBool>,
}

#[derive(Default)]
struct Control {
    active: Option<Active>,
    service_running: bool,
    halted_by_lifecycle: bool,
}

pub(crate) struct AndroidQueueCore<E: AndroidEngineBackend + 'static, S: AndroidEventSink + 'static>
{
    database: Arc<Mutex<Database>>,
    engine: Arc<E>,
    sink: Arc<S>,
    app_data: PathBuf,
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

fn service_text(language: Language, item: &QueueItem) -> (String, String, i32, bool, String) {
    let title = item
        .title
        .as_deref()
        .filter(|text| !text.trim().is_empty())
        .unwrap_or("Zownload")
        .to_owned();
    let timeout_detail = match language {
        Language::En => "Downloads paused. Open Zownload to continue.".to_owned(),
        Language::Es => "Descargas pausadas. Abre Zownload para continuar.".to_owned(),
    };
    let (detail, percent, indeterminate) = match (item.status, &item.progress, language) {
        (ItemStatus::Analyzing, _, Language::En) => ("Analyzing...".to_owned(), 0, true),
        (ItemStatus::Analyzing, _, Language::Es) => ("Analizando...".to_owned(), 0, true),
        (ItemStatus::PostProcessing, _, Language::En) => ("Processing...".to_owned(), 100, true),
        (ItemStatus::PostProcessing, _, Language::Es) => ("Procesando...".to_owned(), 100, true),
        (ItemStatus::Packaging, _, Language::En) => ("Packaging ZIP...".to_owned(), 100, true),
        (ItemStatus::Packaging, _, Language::Es) => ("Empaquetando ZIP...".to_owned(), 100, true),
        (_, Progress::Single { percent }, _) => {
            let clamped = percent.clamp(0.0, 100.0).round() as i32;
            (format!("{clamped}%"), clamped, false)
        }
        (
            _,
            Progress::Playlist {
                done,
                failed,
                total,
                current_title,
                current_percent,
            },
            _,
        ) => {
            let overall = if *total > 0 {
                let completed = f32::from((*done + *failed).min(*total) as u16) * 100.0;
                ((completed + current_percent.clamp(0.0, 100.0)) / (*total as f32))
                    .clamp(0.0, 100.0)
                    .round() as i32
            } else {
                0
            };
            let counter = format!("{done}/{total}");
            let detail = match current_title.as_deref().filter(|t| !t.trim().is_empty()) {
                Some(entry) => format!("{counter} · {entry}"),
                None => counter,
            };
            (detail, overall, *total == 0)
        }
    };
    (title, detail, percent, indeterminate, timeout_detail)
}

impl<E: AndroidEngineBackend + 'static, S: AndroidEventSink + 'static> AndroidQueueCore<E, S> {
    pub fn new(
        database: Arc<Mutex<Database>>,
        engine: Arc<E>,
        sink: Arc<S>,
        app_data: PathBuf,
    ) -> Arc<Self> {
        Arc::new(Self {
            database,
            engine,
            sink,
            app_data,
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
        let updated = self
            .db()?
            .update_queue_item(item)
            .map_err(|error| failure(error.to_string()))?;
        if !updated {
            return Err(failure("queue item was removed"));
        }
        self.sink.emit_item(item);
        Ok(())
    }

    fn language(&self) -> Language {
        self.db()
            .ok()
            .and_then(|db| db.get_settings().ok())
            .map_or(Language::En, |settings| settings.language)
    }

    fn zip_work_dir(&self, id: &str) -> PathBuf {
        self.app_data.join("android-zip").join(id)
    }

    fn update_foreground_notification(&self, item: &QueueItem) {
        let should_update = self
            .control
            .lock()
            .is_ok_and(|control| control.service_running && !control.halted_by_lifecycle);
        if !should_update {
            return;
        }
        let (title, detail, percent, indeterminate, _) = service_text(self.language(), item);
        let _ = self
            .engine
            .update_foreground_progress(&title, &detail, percent, indeterminate);
    }

    fn stop_service_if_running(&self) {
        let should_stop = {
            let Ok(mut control) = self.control.lock() else {
                return;
            };
            if !control.service_running {
                false
            } else {
                control.service_running = false;
                true
            }
        };
        if should_stop {
            let _ = self.engine.stop_foreground_service();
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
        {
            let mut db = self.db()?;
            let settings = db
                .get_settings()
                .map_err(|error| failure(error.to_string()))?;
            db.insert_queue_item_with_options(
                &item,
                None,
                item.request.is_playlist.then_some(settings.zip_playlists),
            )
            .map_err(|error| failure(error.to_string()))?;
        }
        self.sink.emit_item(&item);
        if let Ok(mut control) = self.control.lock() {
            control.halted_by_lifecycle = false;
        }
        self.kick()?;
        Ok(id)
    }

    pub fn kick(self: &Arc<Self>) -> Result<(), AppError> {
        {
            let control = self
                .control
                .lock()
                .map_err(|_| failure("queue control lock poisoned"))?;
            if control.active.is_some() || control.halted_by_lifecycle {
                return Ok(());
            }
        }
        let next = self
            .db()?
            .get_queue()
            .map_err(|error| failure(error.to_string()))?
            .into_iter()
            .find(|item| item.status == ItemStatus::Queued);
        let Some(mut item) = next else {
            self.stop_service_if_running();
            return Ok(());
        };

        let expanded = if item.request.is_playlist {
            self.db()?
                .get_playlist_state(&item.id)
                .map_err(|error| failure(error.to_string()))?
                .is_some_and(|state| state.snapshot.is_some())
        } else {
            false
        };

        item.status = if item.request.is_playlist && !expanded {
            ItemStatus::Analyzing
        } else {
            ItemStatus::Downloading
        };

        let language = self.language();
        let need_start = {
            let mut control = self
                .control
                .lock()
                .map_err(|_| failure("queue control lock poisoned"))?;
            if control.active.is_some() || control.halted_by_lifecycle {
                return Ok(());
            }
            let start = !control.service_running;
            control.service_running = true;
            start
        };

        let (svc_title, svc_detail, svc_percent, svc_indeterminate, timeout_detail) =
            service_text(language, &item);
        if need_start {
            if let Err(error) = self.engine.start_foreground_service(
                &svc_title,
                &svc_detail,
                svc_percent,
                svc_indeterminate,
                &timeout_detail,
            ) {
                if let Ok(mut control) = self.control.lock() {
                    control.service_running = false;
                }
                return Err(error);
            }
        } else {
            let _ = self.engine.update_foreground_progress(
                &svc_title,
                &svc_detail,
                svc_percent,
                svc_indeterminate,
            );
        }

        if let Err(error) = self.save(&item) {
            self.stop_service_if_running();
            return Err(error);
        }

        let cancel = Arc::new(AtomicBool::new(false));
        {
            let mut control = self
                .control
                .lock()
                .map_err(|_| failure("queue control lock poisoned"))?;
            if control.active.is_some() || control.halted_by_lifecycle {
                drop(control);
                let mut rollback = item;
                rollback.status = ItemStatus::Paused;
                let _ = self.save(&rollback);
                self.stop_service_if_running();
                return Ok(());
            }
            control.active = Some(Active {
                id: item.id.clone(),
                operation_id: item.id.clone(),
                phase: item.status,
                intent: Intent::Run,
                cancel: Arc::clone(&cancel),
            });
        }
        let coordinator = Arc::clone(self);
        thread::spawn(move || coordinator.run(item, cancel));
        Ok(())
    }

    fn set_operation(&self, id: &str, operation_id: &str) {
        if let Ok(mut control) = self.control.lock() {
            if let Some(active) = control.active.as_mut().filter(|active| active.id == id) {
                active.operation_id = operation_id.to_owned();
            }
        }
    }

    fn set_phase(&self, id: &str, phase: ItemStatus) {
        if let Ok(mut control) = self.control.lock() {
            if let Some(active) = control.active.as_mut().filter(|active| active.id == id) {
                active.phase = phase;
            }
        }
    }

    fn current_intent(&self, id: &str) -> Option<Intent> {
        self.control.lock().ok().and_then(|control| {
            control
                .active
                .as_ref()
                .filter(|active| active.id == id)
                .map(|active| active.intent)
        })
    }

    fn update_progress(
        &self,
        id: &str,
        percent: f32,
        status: &str,
        title: Option<String>,
        playlist: bool,
    ) {
        if self
            .current_intent(id)
            .is_some_and(|intent| intent != Intent::Run)
        {
            return;
        }
        let mut item = match self.get_item(id) {
            Ok(item) => item,
            Err(_) => return,
        };
        if status == "postProcessing" {
            if item.status == ItemStatus::Downloading {
                item.status = ItemStatus::PostProcessing;
                self.set_phase(id, ItemStatus::PostProcessing);
                if self.save(&item).is_ok() {
                    self.update_foreground_notification(&item);
                }
            }
            return;
        }
        if !percent.is_finite() || item.status != ItemStatus::Downloading {
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
            self.update_foreground_notification(&item);
        }
    }

    fn publish_result(
        &self,
        request: &DownloadRequest,
        result: &crate::android_contract::DownloadResult,
    ) -> Result<(), AppError> {
        if !result.path.is_file() {
            return Err(AppError::new(
                ErrorCode::EngineMissing,
                Some("Android engine reported a missing output file".into()),
            ));
        }
        let actual_bytes = match std::fs::metadata(&result.path) {
            Ok(metadata) => metadata.len(),
            Err(error) => {
                let _ = std::fs::remove_file(&result.path);
                return Err(io_failure(error));
            }
        };
        if result.bytes == 0 || actual_bytes != result.bytes {
            let _ = std::fs::remove_file(&result.path);
            return Err(AppError::new(
                ErrorCode::EngineMissing,
                Some("Android engine output is empty or its size does not match the result".into()),
            ));
        }
        let published = self.engine.publish_output(result, request);
        if let Err(error) = published {
            let _ = std::fs::remove_file(&result.path);
            return Err(error);
        }
        if let Err(error) = std::fs::remove_file(&result.path) {
            eprintln!("could not remove published Android engine source: {error}");
        }
        Ok(())
    }

    fn download_one(
        self: &Arc<Self>,
        id: &str,
        index: usize,
        total: usize,
        request: &DownloadRequest,
        playlist: bool,
    ) -> Result<crate::android_contract::DownloadResult, AppError> {
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
            if signal.status != "postProcessing" {
                if let Ok(mut last) = progress_clock.lock() {
                    if now.duration_since(*last) < Duration::from_millis(200)
                        && signal.percent < 100.0
                    {
                        return;
                    }
                    *last = now;
                }
            }
            let percent = if playlist && total > 0 {
                signal.percent.clamp(0.0, 100.0)
            } else {
                signal.percent
            };
            coordinator.update_progress(
                &id,
                percent,
                &signal.status,
                (!signal.title.is_empty()).then_some(signal.title),
                playlist,
            );
        });
        self.engine.download_entry(request, &operation_id, callback)
    }

    fn run(self: Arc<Self>, mut item: QueueItem, cancel: Arc<AtomicBool>) {
        let result = if !item.request.is_playlist {
            self.run_single(&mut item, &cancel)
        } else {
            self.run_playlist(&mut item, &cancel)
        };

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
            if item.request.is_playlist {
                let _ = AndroidZipOutput::remove_unrecoverable_pending(
                    self.engine.as_ref(),
                    &self.zip_work_dir(&item.id),
                );
                let _ = std::fs::remove_dir_all(self.zip_work_dir(&item.id));
            }
            let _ = self.engine.cleanup_queue_cache(&item.id);
            if self
                .db()
                .is_ok_and(|mut db| db.remove_queue_item(&item.id).unwrap_or(false))
            {
                self.sink.emit_removed(&item.id);
            }
        } else if intent.is_pause_like() || cancel.load(Ordering::SeqCst) {
            // Preserve .part files and pending MediaStore ZIP for Continue.
            if let Ok(current) = self.get_item(&item.id) {
                item = current;
            }
            item.status = ItemStatus::Paused;
            let _ = self.save(&item);
        } else {
            match result {
                Ok((done, failed)) if done > 0 => {
                    if let Ok(current) = self.get_item(&item.id) {
                        item = current;
                    }
                    item.status = ItemStatus::Done;
                    item.error = (failed > 0).then(|| {
                        AppError::new(
                            ErrorCode::Unknown,
                            Some(format!("playlist_summary:{done}:{failed}")),
                        )
                    });
                    match item.progress {
                        Progress::Single { .. } => {
                            item.progress = Progress::Single { percent: 100.0 };
                        }
                        Progress::Playlist {
                            done: _,
                            failed: _,
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
                    if self.save(&item).is_ok()
                        && self.db().is_ok_and(|mut db| {
                            db.settle_queue_item(
                                &item.id,
                                TerminalOutcome::Completed {
                                    successful_files: done,
                                },
                            )
                            .is_ok()
                        })
                    {
                        self.sink.emit_history_changed();
                        if failed > 0 {
                            self.sink.emit_notifications_changed();
                        }
                        self.sink.emit_removed(&item.id);
                    }
                    if item.request.is_playlist {
                        let _ = std::fs::remove_dir_all(self.zip_work_dir(&item.id));
                    }
                    let _ = self.engine.cleanup_queue_cache(&item.id);
                }
                Ok(_) => self.fail_item(&mut item, failure("Android engine produced no files")),
                Err(error) => self.fail_item(&mut item, error),
            }
        }

        let halted = {
            let Ok(mut control) = self.control.lock() else {
                return;
            };
            control.active = None;
            control.halted_by_lifecycle
        };
        if halted || intent == Intent::TimeoutPause {
            if intent == Intent::TaskRemovedPause {
                self.stop_service_if_running();
            }
            return;
        }
        let _ = self.kick();
    }

    fn run_single(
        self: &Arc<Self>,
        item: &mut QueueItem,
        cancel: &AtomicBool,
    ) -> Result<(u32, u32), AppError> {
        if cancel.load(Ordering::SeqCst) {
            return Err(failure("cancelled before download"));
        }
        let file = self.download_one(&item.id, 0, 1, &item.request, false)?;
        if cancel.load(Ordering::SeqCst) {
            return Err(failure("cancelled after download"));
        }
        self.publish_result(&item.request, &file)?;
        let _ = self.engine.cleanup_operation(&item.id);
        item.title = Some(file.title);
        if let Some(thumbnail) = file.thumbnail {
            item.thumbnail = Some(thumbnail);
        }
        Ok((1, 0))
    }

    fn run_playlist(
        self: &Arc<Self>,
        item: &mut QueueItem,
        cancel: &AtomicBool,
    ) -> Result<(u32, u32), AppError> {
        let mut state = self
            .db()?
            .get_playlist_state(&item.id)
            .map_err(|error| failure(error.to_string()))?
            .ok_or_else(|| failure("playlist state missing"))?;

        if state.snapshot.is_none() {
            let analysis = self.engine.analyze(&item.request.url)?;
            if cancel.load(Ordering::SeqCst) {
                return Err(failure("cancelled during playlist analysis"));
            }
            let AnalyzeResult::Playlist { title, .. } = analysis.result else {
                return Err(AppError::new(
                    ErrorCode::UnsupportedSite,
                    Some("the selected URL is not a playlist".into()),
                ));
            };
            let entries: Vec<SnapshotEntry> = analysis
                .entries
                .into_iter()
                .take(MAX_PLAYLIST_ENTRIES)
                .enumerate()
                .map(|(idx, entry)| SnapshotEntry {
                    url: entry.url,
                    title: if entry.title.trim().is_empty() {
                        format!("Track {}", idx + 1)
                    } else {
                        entry.title
                    },
                })
                .collect();
            if entries.is_empty() {
                return Err(AppError::new(
                    ErrorCode::EngineMissing,
                    Some("Android engine returned an empty playlist".into()),
                ));
            }
            let playlist_title = if title.trim().is_empty() {
                "Playlist".to_owned()
            } else {
                title
            };
            let snapshot = PlaylistSnapshot {
                entries,
                next_index: 0,
            };
            snapshot.validate()?;
            self.db()?
                .save_playlist_snapshot(&item.id, &playlist_title, &snapshot)
                .map_err(|error| failure(error.to_string()))?;
            *item = self.get_item(&item.id)?;
            state = self
                .db()?
                .get_playlist_state(&item.id)
                .map_err(|error| failure(error.to_string()))?
                .ok_or_else(|| failure("playlist state missing"))?;
        }

        let snapshot = state
            .snapshot
            .ok_or_else(|| failure("playlist snapshot missing"))?;
        let total = snapshot.entries.len();
        let zip_work_dir = self.zip_work_dir(&item.id);
        let mut archive = if state.zip_enabled {
            Some(AndroidZipOutput::open(
                self.engine.as_ref(),
                &zip_work_dir,
                item.title.as_deref().unwrap_or("playlist"),
            )?)
        } else {
            None
        };

        let mut next_index = snapshot.next_index;
        if let Some(zip) = &archive {
            while zip
                .committed_entries()
                .iter()
                .any(|entry| entry.index == next_index)
            {
                let mut current = self.get_item(&item.id)?;
                if let Progress::Playlist {
                    done,
                    current_title,
                    current_percent,
                    ..
                } = &mut current.progress
                {
                    *done += 1;
                    *current_title = snapshot
                        .entries
                        .get(next_index + 1)
                        .map(|entry| entry.title.clone());
                    *current_percent = 0.0;
                }
                current.status = ItemStatus::Queued;
                self.db()?
                    .advance_playlist(&current, next_index)
                    .map_err(|error| failure(error.to_string()))?;
                let _ = self
                    .engine
                    .cleanup_operation(&format!("{}_{}", item.id, next_index));
                self.sink.emit_item(&current);
                *item = current;
                next_index += 1;
            }
        }

        for index in next_index..total {
            if cancel.load(Ordering::SeqCst)
                || self
                    .current_intent(&item.id)
                    .is_some_and(|intent| intent != Intent::Run)
            {
                break;
            }

            let mut current = self.get_item(&item.id)?;
            current.status = ItemStatus::Downloading;
            if let Progress::Playlist {
                current_title,
                current_percent,
                ..
            } = &mut current.progress
            {
                *current_title = Some(snapshot.entries[index].title.clone());
                *current_percent = 0.0;
            }
            self.set_phase(&item.id, ItemStatus::Downloading);
            self.save(&current)?;
            self.update_foreground_notification(&current);

            let entry = &snapshot.entries[index];
            let request = entry_request(
                entry.url.clone(),
                item.request.format,
                item.request.quality.clone(),
            );
            let operation_id = format!("{}_{index}", item.id);
            let outcome = self.download_one(&item.id, index, total, &request, true);
            let entry_ok = match (archive.as_mut(), outcome) {
                (Some(zip), Ok(file)) => {
                    if cancel.load(Ordering::SeqCst)
                        || self
                            .current_intent(&item.id)
                            .is_some_and(|intent| intent != Intent::Run)
                    {
                        break;
                    }
                    self.set_phase(&item.id, ItemStatus::Packaging);
                    let mut packaging = self.get_item(&item.id)?;
                    packaging.status = ItemStatus::Packaging;
                    self.save(&packaging)?;
                    self.update_foreground_notification(&packaging);

                    let title = if file.title.trim().is_empty() {
                        entry.title.clone()
                    } else {
                        file.title.clone()
                    };
                    if let Err(error) = zip.append_entry(index, &title, &file.path) {
                        if matches!(
                            error.code,
                            ErrorCode::DiskFull | ErrorCode::PermissionDenied
                        ) {
                            let _ = zip.remove_incomplete();
                            let _ = std::fs::remove_dir_all(&zip_work_dir);
                            let _ = self.engine.cleanup_queue_cache(&item.id);
                        }
                        return Err(error);
                    }
                    self.engine.cleanup_operation(&operation_id)?;
                    true
                }
                (None, Ok(file)) => match self.publish_result(&request, &file) {
                    Ok(()) => {
                        let _ = self.engine.cleanup_operation(&operation_id);
                        true
                    }
                    Err(error)
                        if matches!(
                            error.code,
                            ErrorCode::DiskFull | ErrorCode::PermissionDenied
                        ) =>
                    {
                        let _ = self.engine.cleanup_queue_cache(&item.id);
                        return Err(error);
                    }
                    Err(error) => {
                        let _ = self.engine.cleanup_operation(&operation_id);
                        eprintln!(
                            "Android playlist output failed: {}",
                            error.detail.unwrap_or_default()
                        );
                        false
                    }
                },
                (_, Err(error))
                    if matches!(
                        error.code,
                        ErrorCode::DiskFull | ErrorCode::PermissionDenied
                    ) =>
                {
                    if let Some(zip) = &archive {
                        let _ = zip.remove_incomplete();
                        let _ = std::fs::remove_dir_all(&zip_work_dir);
                    }
                    let _ = self.engine.cleanup_queue_cache(&item.id);
                    return Err(error);
                }
                (_, Err(_))
                    if cancel.load(Ordering::SeqCst)
                        || self
                            .current_intent(&item.id)
                            .is_some_and(|intent| intent != Intent::Run) =>
                {
                    break;
                }
                (_, Err(error)) => {
                    let _ = self.engine.cleanup_operation(&operation_id);
                    eprintln!(
                        "Android playlist entry failed: {}",
                        error.detail.unwrap_or_default()
                    );
                    false
                }
            };

            let mut updated = self.get_item(&item.id)?;
            if let Progress::Playlist {
                done,
                failed,
                current_title,
                current_percent,
                ..
            } = &mut updated.progress
            {
                if entry_ok {
                    *done += 1;
                } else {
                    *failed += 1;
                }
                *current_title = snapshot
                    .entries
                    .get(index + 1)
                    .map(|next_entry| next_entry.title.clone());
                *current_percent = 0.0;
            }
            let intent = self.current_intent(&item.id).unwrap_or(Intent::Run);
            updated.status = if intent.is_pause_like() || cancel.load(Ordering::SeqCst) {
                ItemStatus::Paused
            } else {
                ItemStatus::Queued
            };
            self.set_phase(&item.id, updated.status);
            if !self
                .db()?
                .advance_playlist(&updated, index)
                .map_err(|error| failure(error.to_string()))?
            {
                return Err(failure("playlist row was removed"));
            }
            self.sink.emit_item(&updated);
            *item = updated;
            if intent != Intent::Run || cancel.load(Ordering::SeqCst) {
                break;
            }
        }

        if cancel.load(Ordering::SeqCst)
            || self
                .current_intent(&item.id)
                .is_some_and(|intent| intent != Intent::Run)
        {
            return Err(failure("playlist paused or removed"));
        }

        let (done, failed) = match item.progress {
            Progress::Playlist { done, failed, .. } => (done, failed),
            _ => (0, 0),
        };
        if let Some(zip) = archive.as_mut() {
            if let Err(error) = zip.finalize() {
                if matches!(
                    error.code,
                    ErrorCode::DiskFull | ErrorCode::PermissionDenied
                ) {
                    let _ = zip.remove_incomplete();
                    let _ = std::fs::remove_dir_all(&zip_work_dir);
                }
                return Err(error);
            }
        }
        if done == 0 && failed > 0 {
            return Err(AppError::new(
                ErrorCode::Unknown,
                Some("all Android playlist entries failed".into()),
            ));
        }
        Ok((done, failed))
    }

    fn fail_item(&self, item: &mut QueueItem, error: AppError) {
        if item.request.is_playlist {
            let zip_work_dir = self.zip_work_dir(&item.id);
            if zip_work_dir.exists() {
                let _ = AndroidZipOutput::remove_unrecoverable_pending(
                    self.engine.as_ref(),
                    &zip_work_dir,
                );
                let _ = std::fs::remove_dir_all(&zip_work_dir);
            }
        }
        let _ = self.engine.cleanup_queue_cache(&item.id);
        item.status = ItemStatus::Failed;
        item.error = Some(error.clone());
        if self.save(item).is_ok()
            && self.db().is_ok_and(|mut db| {
                db.settle_queue_item(&item.id, TerminalOutcome::Failed(error))
                    .is_ok()
            })
        {
            self.sink.emit_notifications_changed();
            self.sink.emit_removed(&item.id);
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
                    if active.phase != ItemStatus::Downloading || active.intent != Intent::Run {
                        return Err(failure("pause is available only while downloading"));
                    }
                    active.intent = Intent::Pause;
                    active.cancel.store(true, Ordering::SeqCst);
                    Some(active.operation_id.clone())
                }
                None => None,
            }
        };
        if let Some(operation_id) = operation {
            let _ = self.engine.cancel(&operation_id);
            return Ok(());
        }
        let mut item = self.get_item(id)?;
        if item.status != ItemStatus::Queued {
            return Err(failure("only queued or downloading items can be paused"));
        }
        item.status = ItemStatus::Paused;
        self.save(&item)?;
        Ok(())
    }

    pub fn resume(self: &Arc<Self>, id: &str) -> Result<(), AppError> {
        // Wait briefly if the same item is unwinding from pause/timeout/recents.
        for _ in 0..100 {
            let busy_with_same = {
                let control = self
                    .control
                    .lock()
                    .map_err(|_| failure("queue control lock poisoned"))?;
                control
                    .active
                    .as_ref()
                    .is_some_and(|active| active.id == id)
            };
            if !busy_with_same {
                break;
            }
            thread::sleep(Duration::from_millis(50));
        }
        let mut item = self.get_item(id)?;
        if item.status != ItemStatus::Paused {
            return Err(failure("only paused items can be resumed"));
        }
        item.status = ItemStatus::Queued;
        item.error = None;
        self.save(&item)?;
        if let Ok(mut control) = self.control.lock() {
            control.halted_by_lifecycle = false;
        }
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
            let _ = self.engine.cancel(&operation_id);
            return Ok(());
        }
        let item = self.get_item(id)?;
        if item.request.is_playlist {
            let zip_work_dir = self.zip_work_dir(id);
            if zip_work_dir.exists() {
                AndroidZipOutput::remove_unrecoverable_pending(
                    self.engine.as_ref(),
                    &zip_work_dir,
                )?;
                let _ = std::fs::remove_dir_all(&zip_work_dir);
            }
        }
        let _ = self.engine.cleanup_queue_cache(id);
        if !self
            .db()?
            .remove_queue_item(id)
            .map_err(|error| failure(error.to_string()))?
        {
            return Err(failure("queue item not found"));
        }
        self.sink.emit_removed(id);
        self.kick()
    }

    pub fn on_task_removed(&self) {
        self.handle_lifecycle_pause(Intent::TaskRemovedPause);
    }

    pub fn on_foreground_timeout(&self) {
        self.handle_lifecycle_pause(Intent::TimeoutPause);
    }

    fn handle_lifecycle_pause(&self, pause_intent: Intent) {
        let operation = {
            let Ok(mut control) = self.control.lock() else {
                return;
            };
            control.halted_by_lifecycle = true;
            if pause_intent == Intent::TimeoutPause {
                control.service_running = false;
            }
            control.active.as_mut().map(|active| {
                if active.intent != Intent::Remove {
                    active.intent = pause_intent;
                }
                active.cancel.store(true, Ordering::SeqCst);
                active.operation_id.clone()
            })
        };

        if let Ok(mut db) = self.db() {
            if let Ok(queue) = db.get_queue() {
                for mut item in queue {
                    if matches!(
                        item.status,
                        ItemStatus::Analyzing
                            | ItemStatus::Queued
                            | ItemStatus::Downloading
                            | ItemStatus::PostProcessing
                            | ItemStatus::Packaging
                    ) {
                        item.status = ItemStatus::Paused;
                        if db.update_queue_item(&item).unwrap_or(false) {
                            self.sink.emit_item(&item);
                        }
                    }
                }
            }
        }

        if let Some(op_id) = operation {
            let _ = self.engine.cancel(&op_id);
        }
        if pause_intent == Intent::TaskRemovedPause {
            self.stop_service_if_running();
        }
    }
}

pub(crate) fn safe_zip_file_name(title: &str) -> String {
    let base = safe_output_name(title, Format::Mp3);
    format!("{}.zip", base.strip_suffix(".mp3").unwrap_or(&base))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{
        android_contract::{DownloadResult, PlaylistEntry, PublishedZipResult},
        android_zip::zip_io_error,
        contract::{Quality, Settings},
    };
    use std::collections::HashMap;
    use std::fs::{self, File, OpenOptions};
    use zip::ZipArchive;

    #[derive(Clone, Debug, PartialEq, Eq)]
    enum ServiceCall {
        Start {
            title: String,
            timeout_detail: String,
        },
        Update {
            title: String,
            detail: String,
            percent: i32,
        },
        Stop,
    }

    struct MockBackend {
        root: PathBuf,
        service_calls: Mutex<Vec<ServiceCall>>,
        cancelled_ops: Mutex<Vec<String>>,
        cleaned_ops: Mutex<Vec<String>>,
        cleaned_queues: Mutex<Vec<String>>,
        published_singles: Mutex<Vec<String>>,
        published_zips: Mutex<Vec<PublishedZipResult>>,
        pending_zips: Mutex<HashMap<String, PathBuf>>,
        wait_on_download: Mutex<Option<Arc<AtomicBool>>>,
        fail_next_publish: Mutex<Option<ErrorCode>>,
        download_calls: Mutex<usize>,
    }

    impl MockBackend {
        fn new(root: PathBuf) -> Self {
            fs::create_dir_all(&root).unwrap();
            Self {
                root,
                service_calls: Mutex::new(Vec::new()),
                cancelled_ops: Mutex::new(Vec::new()),
                cleaned_ops: Mutex::new(Vec::new()),
                cleaned_queues: Mutex::new(Vec::new()),
                published_singles: Mutex::new(Vec::new()),
                published_zips: Mutex::new(Vec::new()),
                pending_zips: Mutex::new(HashMap::new()),
                wait_on_download: Mutex::new(None),
                fail_next_publish: Mutex::new(None),
                download_calls: Mutex::new(0),
            }
        }
    }

    impl PendingArchiveStore for MockBackend {
        fn create_pending(&self, display_name: &str) -> Result<PendingZipHandle, AppError> {
            let id = uuid::Uuid::new_v4().to_string();
            let uri = format!("content://media/external/downloads/{id}");
            let path = self
                .root
                .join("downloads")
                .join(format!("{id}-{display_name}"));
            fs::create_dir_all(path.parent().unwrap()).unwrap();
            File::create(&path).unwrap();
            self.pending_zips.lock().unwrap().insert(uri.clone(), path);
            Ok(PendingZipHandle {
                uri,
                display_name: display_name.to_owned(),
            })
        }

        fn open_rw(&self, handle: &PendingZipHandle) -> Result<File, AppError> {
            let path = self
                .pending_zips
                .lock()
                .unwrap()
                .get(&handle.uri)
                .cloned()
                .ok_or_else(|| failure("pending ZIP missing"))?;
            OpenOptions::new()
                .read(true)
                .write(true)
                .open(path)
                .map_err(zip_io_error)
        }

        fn publish(
            &self,
            handle: &PendingZipHandle,
            expected_bytes: u64,
        ) -> Result<PublishedZipResult, AppError> {
            let path = self
                .pending_zips
                .lock()
                .unwrap()
                .get(&handle.uri)
                .cloned()
                .ok_or_else(|| failure("pending ZIP missing"))?;
            let actual = fs::metadata(&path).map_err(zip_io_error)?.len();
            assert_eq!(actual, expected_bytes);
            let result = PublishedZipResult {
                uri: handle.uri.clone(),
                display_name: handle.display_name.clone(),
                bytes: actual,
            };
            self.published_zips.lock().unwrap().push(result.clone());
            Ok(result)
        }

        fn delete_pending(&self, handle: &PendingZipHandle) -> Result<(), AppError> {
            if let Some(path) = self.pending_zips.lock().unwrap().remove(&handle.uri) {
                let _ = fs::remove_file(path);
            }
            Ok(())
        }
    }

    impl AndroidEngineBackend for MockBackend {
        fn analyze(&self, url: &str) -> Result<EngineAnalysis, AppError> {
            Ok(EngineAnalysis {
                result: AnalyzeResult::Playlist {
                    url: url.to_owned(),
                    title: "Test Mix".into(),
                    author: "Tester".into(),
                    thumbnail: None,
                    site: "Fixture".into(),
                    item_count: 2,
                    item_titles: vec!["Song".into(), "Song".into()],
                },
                entries: vec![
                    PlaylistEntry {
                        url: "https://example.test/1".into(),
                        title: "Song".into(),
                    },
                    PlaylistEntry {
                        url: "https://example.test/2".into(),
                        title: "Song".into(),
                    },
                ],
            })
        }

        fn download_entry(
            &self,
            request: &DownloadRequest,
            operation_id: &str,
            on_progress: Arc<dyn Fn(EngineProgress) + Send + Sync>,
        ) -> Result<DownloadResult, AppError> {
            let call_num = {
                let mut count = self.download_calls.lock().unwrap();
                *count += 1;
                *count
            };
            self.cancelled_ops
                .lock()
                .unwrap()
                .retain(|id| id != operation_id);
            let work = self.root.join("cache").join(operation_id);
            fs::create_dir_all(&work).unwrap();
            let part = work.join("track.mp3.part");
            fs::write(&part, b"partial-data").unwrap();
            on_progress(EngineProgress {
                percent: 25.0,
                status: "downloading".into(),
                title: format!("Track {call_num}"),
                downloaded_bytes: 25,
                total_bytes: 100,
            });
            if let Some(gate) = self.wait_on_download.lock().unwrap().clone() {
                while !gate.load(Ordering::SeqCst)
                    && !self
                        .cancelled_ops
                        .lock()
                        .unwrap()
                        .contains(&operation_id.to_owned())
                {
                    thread::sleep(Duration::from_millis(10));
                }
            }
            if self
                .cancelled_ops
                .lock()
                .unwrap()
                .contains(&operation_id.to_owned())
            {
                return Err(AppError::new(ErrorCode::Unknown, Some("cancelled".into())));
            }
            let _ = fs::remove_file(&part);
            let ext = match request.format {
                Format::Mp3 => "mp3",
                Format::Mp4 => "mp4",
            };
            let out = work.join(format!("output.{ext}"));
            let payload = format!("media-bytes-{operation_id}").into_bytes();
            fs::write(&out, &payload).unwrap();
            Ok(DownloadResult {
                path: out,
                title: "Song".into(),
                thumbnail: None,
                bytes: payload.len() as u64,
            })
        }

        fn publish_output(
            &self,
            result: &DownloadResult,
            _request: &DownloadRequest,
        ) -> Result<(), AppError> {
            if let Some(code) = self.fail_next_publish.lock().unwrap().take() {
                return Err(AppError::new(code, Some("injected publish error".into())));
            }
            self.published_singles
                .lock()
                .unwrap()
                .push(result.title.clone());
            Ok(())
        }

        fn cleanup_operation(&self, operation_id: &str) -> Result<(), AppError> {
            self.cleaned_ops
                .lock()
                .unwrap()
                .push(operation_id.to_owned());
            let dir = self.root.join("cache").join(operation_id);
            if dir.exists() {
                fs::remove_dir_all(dir).unwrap();
            }
            Ok(())
        }

        fn cleanup_queue_cache(&self, queue_id: &str) -> Result<(), AppError> {
            self.cleaned_queues
                .lock()
                .unwrap()
                .push(queue_id.to_owned());
            let cache_root = self.root.join("cache");
            if cache_root.exists() {
                for entry in fs::read_dir(&cache_root).unwrap() {
                    let entry = entry.unwrap();
                    let name = entry.file_name().to_string_lossy().into_owned();
                    if name == queue_id || name.starts_with(&format!("{queue_id}_")) {
                        let _ = fs::remove_dir_all(entry.path());
                    }
                }
            }
            Ok(())
        }

        fn cancel(&self, operation_id: &str) -> Result<bool, AppError> {
            self.cancelled_ops
                .lock()
                .unwrap()
                .push(operation_id.to_owned());
            Ok(true)
        }

        fn start_foreground_service(
            &self,
            title: &str,
            _detail: &str,
            _percent: i32,
            _indeterminate: bool,
            timeout_detail: &str,
        ) -> Result<(), AppError> {
            self.service_calls.lock().unwrap().push(ServiceCall::Start {
                title: title.to_owned(),
                timeout_detail: timeout_detail.to_owned(),
            });
            Ok(())
        }

        fn update_foreground_progress(
            &self,
            title: &str,
            detail: &str,
            percent: i32,
            _indeterminate: bool,
        ) -> Result<(), AppError> {
            self.service_calls
                .lock()
                .unwrap()
                .push(ServiceCall::Update {
                    title: title.to_owned(),
                    detail: detail.to_owned(),
                    percent,
                });
            Ok(())
        }

        fn stop_foreground_service(&self) -> Result<(), AppError> {
            self.service_calls.lock().unwrap().push(ServiceCall::Stop);
            Ok(())
        }

        fn check_update(&self) -> Result<EngineUpdateInfo, AppError> {
            unreachable!()
        }

        fn update(&self) -> Result<EngineUpdateInfo, AppError> {
            unreachable!()
        }
    }

    #[derive(Default)]
    struct MockSink {
        events: Mutex<Vec<String>>,
    }

    impl AndroidEventSink for MockSink {
        fn emit_item(&self, item: &QueueItem) {
            self.events
                .lock()
                .unwrap()
                .push(format!("item:{}:{:?}", item.id, item.status));
        }
        fn emit_removed(&self, id: &str) {
            self.events.lock().unwrap().push(format!("removed:{id}"));
        }
        fn emit_history_changed(&self) {
            self.events.lock().unwrap().push("history".into());
        }
        fn emit_notifications_changed(&self) {
            self.events.lock().unwrap().push("notifications".into());
        }
    }

    fn wait_until(predicate: impl Fn() -> bool) {
        for _ in 0..400 {
            if predicate() {
                return;
            }
            thread::sleep(Duration::from_millis(10));
        }
        panic!("condition timed out");
    }

    fn setup() -> (
        PathBuf,
        Arc<Mutex<Database>>,
        Arc<MockBackend>,
        Arc<MockSink>,
        Arc<AndroidQueueCore<MockBackend, MockSink>>,
    ) {
        let root =
            std::env::temp_dir().join(format!("zownload-android-queue-{}", uuid::Uuid::new_v4()));
        fs::create_dir_all(&root).unwrap();
        let db = Arc::new(Mutex::new(
            Database::open_at(&root.join("test.sqlite3")).unwrap(),
        ));
        let backend = Arc::new(MockBackend::new(root.join("backend")));
        let sink = Arc::new(MockSink::default());
        let core = AndroidQueueCore::new(
            Arc::clone(&db),
            Arc::clone(&backend),
            Arc::clone(&sink),
            root.join("appdata"),
        );
        (root, db, backend, sink, core)
    }

    #[test]
    fn zip_playlist_publishes_stored_entries_cleans_work_and_stops_service() {
        let (root, db, backend, _sink, core) = setup();
        db.lock()
            .unwrap()
            .set_settings(&Settings {
                language: Language::En,
                zip_playlists: true,
                download_dir: None,
            })
            .unwrap();

        let id = core
            .enqueue(DownloadRequest {
                url: "https://example.test/list".into(),
                format: Format::Mp3,
                quality: Quality::Max,
                is_playlist: true,
            })
            .unwrap();

        wait_until(|| {
            db.lock().unwrap().get_queue().unwrap().is_empty()
                && core.control.lock().unwrap().active.is_none()
                && !core.control.lock().unwrap().service_running
        });
        let history = db.lock().unwrap().get_history().unwrap();
        assert_eq!(history.len(), 1);
        assert_eq!(history[0].title.as_deref(), Some("Test Mix"));

        let zips = backend.published_zips.lock().unwrap().clone();
        assert_eq!(zips.len(), 1);
        assert_eq!(zips[0].display_name, "Test Mix.zip");
        let zip_path = backend
            .pending_zips
            .lock()
            .unwrap()
            .get(&zips[0].uri)
            .unwrap()
            .clone();
        let mut archive = ZipArchive::new(File::open(zip_path).unwrap()).unwrap();
        assert_eq!(archive.len(), 2);
        assert_eq!(archive.by_index(0).unwrap().name().unwrap(), "Song.mp3");
        assert_eq!(archive.by_index(1).unwrap().name().unwrap(), "Song (1).mp3");
        drop(archive);

        assert_eq!(
            backend.cleaned_ops.lock().unwrap().as_slice(),
            &[format!("{id}_0"), format!("{id}_1")]
        );
        let calls = backend.service_calls.lock().unwrap().clone();
        assert!(matches!(calls.first(), Some(ServiceCall::Start { .. })));
        assert!(matches!(calls.last(), Some(ServiceCall::Stop)));
        let _ = fs::remove_dir_all(root);
    }

    #[test]
    fn recents_removal_pauses_queue_stops_service_and_preserves_part() {
        let (root, db, backend, _sink, core) = setup();
        let gate = Arc::new(AtomicBool::new(false));
        *backend.wait_on_download.lock().unwrap() = Some(Arc::clone(&gate));

        let id = core
            .enqueue(DownloadRequest {
                url: "https://example.test/single".into(),
                format: Format::Mp3,
                quality: Quality::Audio { bitrate: 128 },
                is_playlist: false,
            })
            .unwrap();

        wait_until(|| {
            backend
                .root
                .join("cache")
                .join(&id)
                .join("track.mp3.part")
                .is_file()
        });
        core.on_task_removed();
        wait_until(|| {
            db.lock()
                .unwrap()
                .get_queue()
                .unwrap()
                .first()
                .is_some_and(|item| item.status == ItemStatus::Paused)
                && core.control.lock().unwrap().active.is_none()
        });

        assert!(backend
            .root
            .join("cache")
            .join(&id)
            .join("track.mp3.part")
            .is_file());
        assert!(matches!(
            backend.service_calls.lock().unwrap().last(),
            Some(ServiceCall::Stop)
        ));

        *backend.wait_on_download.lock().unwrap() = None;
        core.resume(&id).unwrap();
        wait_until(|| {
            db.lock().unwrap().get_queue().unwrap().is_empty()
                && core.control.lock().unwrap().active.is_none()
                && !core.control.lock().unwrap().service_running
        });
        assert_eq!(backend.published_singles.lock().unwrap().len(), 1);
        let _ = fs::remove_dir_all(root);
    }

    #[test]
    fn foreground_timeout_pauses_without_stopping_detached_notification_and_resumes_on_continue() {
        let (root, db, backend, _sink, core) = setup();
        let gate = Arc::new(AtomicBool::new(false));
        *backend.wait_on_download.lock().unwrap() = Some(Arc::clone(&gate));

        let id = core
            .enqueue(DownloadRequest {
                url: "https://example.test/single".into(),
                format: Format::Mp3,
                quality: Quality::Audio { bitrate: 128 },
                is_playlist: false,
            })
            .unwrap();

        wait_until(|| {
            backend
                .root
                .join("cache")
                .join(&id)
                .join("track.mp3.part")
                .is_file()
        });
        core.on_foreground_timeout();
        wait_until(|| {
            db.lock()
                .unwrap()
                .get_queue()
                .unwrap()
                .first()
                .is_some_and(|item| item.status == ItemStatus::Paused)
                && core.control.lock().unwrap().active.is_none()
        });

        // Timeout must preserve the detached notification by NOT calling Stop.
        assert!(!backend
            .service_calls
            .lock()
            .unwrap()
            .iter()
            .any(|call| matches!(call, ServiceCall::Stop)));
        assert!(backend
            .root
            .join("cache")
            .join(&id)
            .join("track.mp3.part")
            .is_file());

        // Never auto-resumes; explicit Continue restarts service and completes.
        *backend.wait_on_download.lock().unwrap() = None;
        core.resume(&id).unwrap();
        wait_until(|| {
            db.lock().unwrap().get_queue().unwrap().is_empty()
                && core.control.lock().unwrap().active.is_none()
                && !core.control.lock().unwrap().service_running
        });
        let calls = backend.service_calls.lock().unwrap().clone();
        assert_eq!(
            calls
                .iter()
                .filter(|c| matches!(c, ServiceCall::Start { .. }))
                .count(),
            2
        );
        assert!(matches!(calls.last(), Some(ServiceCall::Stop)));
        let _ = fs::remove_dir_all(root);
    }
}
