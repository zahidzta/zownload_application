// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

//! One Windows media worker at a time. The control lock orders user actions,
//! phase changes and terminal settlement; SQLite commits precede every event.

use super::{process::Supervisor, single, updater, EnginePaths};
use crate::{
    contract::{AppError, DownloadRequest, ErrorCode, ItemStatus, Progress, QueueItem},
    persistence::{notifications::TerminalOutcome, paths::DownloadPaths, Database},
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

#[derive(Clone, Debug)]
pub enum QueueEvent {
    Updated(QueueItem),
    Removed(String),
    HistoryChanged,
    NotificationsChanged,
}

type Emit = Arc<dyn Fn(QueueEvent) + Send + Sync>;

#[derive(Clone, Copy, PartialEq, Eq)]
enum Intent {
    Run,
    Pause,
    Remove,
}

struct Active {
    id: String,
    cancel: Arc<AtomicBool>,
    phase: ItemStatus,
    intent: Intent,
}

#[derive(Default)]
struct Control {
    active: Option<Active>,
    closing: bool,
}

pub struct QueueCoordinator {
    database: Arc<Mutex<Database>>,
    engine: Option<EnginePaths>,
    supervisor: Arc<Supervisor>,
    app_data: PathBuf,
    resources: Option<PathBuf>,
    downloads: PathBuf,
    emit: Emit,
    control: Mutex<Control>,
}

fn failure(detail: impl Into<String>) -> AppError {
    AppError::new(ErrorCode::Unknown, Some(detail.into()))
}

impl QueueCoordinator {
    pub fn new(
        database: Arc<Mutex<Database>>,
        engine: Option<EnginePaths>,
        supervisor: Arc<Supervisor>,
        app_data: PathBuf,
        resources: Option<PathBuf>,
        downloads: PathBuf,
        emit: Emit,
    ) -> Arc<Self> {
        Arc::new(Self {
            database,
            engine,
            supervisor,
            app_data,
            resources,
            downloads,
            emit,
            control: Mutex::new(Control::default()),
        })
    }

    fn db(&self) -> Result<std::sync::MutexGuard<'_, Database>, AppError> {
        self.database
            .lock()
            .map_err(|_| failure("database lock poisoned"))
    }

    fn item(&self, id: &str) -> Result<QueueItem, AppError> {
        self.db()?
            .get_queue()
            .map_err(|error| failure(error.to_string()))?
            .into_iter()
            .find(|item| item.id == id)
            .ok_or_else(|| failure("queue item not found"))
    }

    fn save(&self, item: &QueueItem) -> Result<(), AppError> {
        let changed = self
            .db()?
            .update_queue_item(item)
            .map_err(|error| failure(error.to_string()))?;
        if !changed {
            return Err(failure("queue item was removed"));
        }
        (self.emit)(QueueEvent::Updated(item.clone()));
        Ok(())
    }

    pub fn enqueue(self: &Arc<Self>, request: DownloadRequest) -> Result<String, AppError> {
        let control = self
            .control
            .lock()
            .map_err(|_| failure("queue control lock poisoned"))?;
        if control.closing {
            return Err(failure("application is closing"));
        }
        if !request.is_playlist && self.engine.is_none() {
            return Err(AppError::new(
                ErrorCode::EngineMissing,
                Some("Windows engine unavailable".into()),
            ));
        }
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
        let mut db = self.db()?;
        let paths = if item.request.is_playlist {
            None
        } else {
            let settings = db
                .get_settings()
                .map_err(|error| failure(error.to_string()))?;
            Some(
                DownloadPaths::new(
                    &id,
                    &self.app_data,
                    settings.download_dir.as_deref().map(std::path::Path::new),
                    &self.downloads,
                )
                .map_err(|error| failure(error.to_string()))?,
            )
        };
        db.insert_queue_item_with_paths(&item, paths.as_ref())
            .map_err(|error| failure(error.to_string()))?;
        drop(db);
        (self.emit)(QueueEvent::Updated(item));
        drop(control);
        if let Err(error) = self.kick() {
            eprintln!("could not start accepted queue item: {error:?}");
        }
        Ok(id)
    }

    pub fn kick(self: &Arc<Self>) -> Result<(), AppError> {
        let mut control = self
            .control
            .lock()
            .map_err(|_| failure("queue control lock poisoned"))?;
        if control.closing || control.active.is_some() || self.engine.is_none() {
            return Ok(());
        }
        if self.app_data.join("engine/engine.json").exists() {
            if let Err(error) = updater::activate_pending(&self.app_data) {
                eprintln!("pending yt-dlp activation deferred: {error}");
            }
        }
        // Paused work needs an explicit Continue. Playlist rows do not block singles.
        let next = self
            .db()?
            .get_queue()
            .map_err(|error| failure(error.to_string()))?
            .into_iter()
            .find(|item| !item.request.is_playlist && item.status == ItemStatus::Queued);
        let Some(mut item) = next else { return Ok(()) };
        item.status = ItemStatus::Analyzing;
        self.save(&item)?;
        let cancel = Arc::new(AtomicBool::new(false));
        control.active = Some(Active {
            id: item.id.clone(),
            cancel: Arc::clone(&cancel),
            phase: ItemStatus::Analyzing,
            intent: Intent::Run,
        });
        let coordinator = Arc::clone(self);
        thread::spawn(move || coordinator.run(item, cancel));
        Ok(())
    }

    fn observe(
        &self,
        id: &str,
        observation: single::Observation,
        clock: &Mutex<(Instant, Instant)>,
    ) {
        let Ok(mut control) = self.control.lock() else {
            return;
        };
        if control.closing {
            return;
        }
        let Some(active) = control.active.as_mut().filter(|active| active.id == id) else {
            return;
        };
        if active.intent != Intent::Run {
            return;
        }
        let Ok(mut item) = self.item(id) else { return };
        match observation {
            single::Observation::Title(title) => {
                item.title = Some(title);
                let _ = self.save(&item);
            }
            single::Observation::Downloaded { percent, .. } => {
                if active.phase == ItemStatus::PostProcessing {
                    return;
                }
                let now = Instant::now();
                let Ok(mut times) = clock.lock() else { return };
                let phase_changed = active.phase != ItemStatus::Downloading;
                active.phase = ItemStatus::Downloading;
                item.status = ItemStatus::Downloading;
                item.progress = Progress::Single {
                    percent: percent as f32,
                };
                // UI events are capped at five per second; SQLite checkpoints are slower.
                if phase_changed || now.duration_since(times.1) >= Duration::from_secs(1) {
                    let _ = self.save(&item);
                    times.1 = now;
                    times.0 = now;
                } else if now.duration_since(times.0) >= Duration::from_millis(200) {
                    (self.emit)(QueueEvent::Updated(item));
                    times.0 = now;
                }
            }
            single::Observation::PostProcessing => {
                if active.phase != ItemStatus::PostProcessing {
                    active.phase = ItemStatus::PostProcessing;
                    item.status = ItemStatus::PostProcessing;
                    let _ = self.save(&item);
                }
            }
        }
    }

    fn run(self: Arc<Self>, mut item: QueueItem, cancel: Arc<AtomicBool>) {
        let id = item.id.clone();
        let paths = self
            .db()
            .ok()
            .and_then(|db| db.get_download_paths(&id).ok().flatten());
        let result = if let (Some(engine), Some(mut disk)) = (self.engine.as_ref(), paths) {
            let clock = Arc::new(Mutex::new((
                Instant::now() - Duration::from_secs(1),
                Instant::now() - Duration::from_secs(1),
            )));
            let observe_self = Arc::clone(&self);
            let observed_id = id.clone();
            let observe: Arc<dyn Fn(single::Observation) + Send + Sync> =
                Arc::new(move |signal| observe_self.observe(&observed_id, signal, &clock));
            let mut persist = |record: &DownloadPaths| {
                self.db()?
                    .put_download_paths(record)
                    .map_err(|error| failure(error.to_string()))
            };
            let result = match updater::begin_invocation(&self.app_data) {
                Ok((read_lease, _probation_guard, probation)) => {
                    let mut broken = false;
                    let first = single::run_single_classified(
                        engine,
                        &self.supervisor,
                        &mut disk,
                        &self.app_data,
                        &id,
                        &item.request,
                        &cancel,
                        Arc::clone(&observe),
                        &mut persist,
                        &mut broken,
                    );
                    if broken && !cancel.load(Ordering::SeqCst) && probation.is_some() {
                        drop(read_lease);
                        let fallback = match updater::slot().write() {
                            Ok(write_lease) => self.resources.as_ref().map(|resources| {
                                updater::restore_baseline_locked(
                                    &self.app_data,
                                    resources,
                                    probation.as_deref().unwrap(),
                                    &write_lease,
                                )
                            }),
                            Err(_) => Some(Err("engine slot poisoned".into())),
                        };
                        match fallback {
                            Some(Ok(_)) => {
                                let mut second_broken = false;
                                match updater::slot().read() {
                                    Ok(_retry_lease) => single::run_single_classified(
                                        engine,
                                        &self.supervisor,
                                        &mut disk,
                                        &self.app_data,
                                        &id,
                                        &item.request,
                                        &cancel,
                                        observe,
                                        &mut persist,
                                        &mut second_broken,
                                    ),
                                    Err(_) => Err(failure("engine slot poisoned")),
                                }
                            }
                            Some(Err(reason)) => {
                                Err(AppError::new(ErrorCode::EngineMissing, Some(reason)))
                            }
                            None => first,
                        }
                    } else {
                        if !broken && !cancel.load(Ordering::SeqCst) {
                            if let Some(version) = probation.as_deref() {
                                let _ = updater::mark_good(&self.app_data, version);
                            }
                        }
                        first
                    }
                }
                Err(reason) => Err(failure(reason)),
            };
            (result, Some(disk))
        } else {
            (
                Err(failure("download paths or Windows engine unavailable")),
                None,
            )
        };
        let Ok(mut control) = self.control.lock() else {
            return;
        };
        let intent = control
            .active
            .as_ref()
            .filter(|active| active.id == id)
            .map(|active| active.intent);
        if intent.is_none() {
            return;
        }
        let (outcome, disk) = result;
        if let Ok(current) = self.item(&id) {
            item = current;
        }
        if intent == Some(Intent::Remove) {
            let cleanup = (|| {
                if let Ok(completed) = &outcome {
                    match std::fs::remove_file(&completed.path) {
                        Ok(()) => (),
                        Err(error) if error.kind() == std::io::ErrorKind::NotFound => (),
                        Err(error) => return Err(error),
                    }
                }
                if let Some(disk) = &disk {
                    disk.clean_owned(&self.app_data)?;
                }
                Ok(())
            })();
            match cleanup {
                Ok(()) => match self.db().and_then(|mut db| {
                    db.remove_queue_item(&id)
                        .map_err(|error| failure(error.to_string()))
                }) {
                    Ok(true) => (self.emit)(QueueEvent::Removed(id.clone())),
                    other => {
                        item.status = ItemStatus::Paused;
                        item.error =
                            Some(failure(format!("could not remove queue row: {other:?}")));
                        let _ = self.save(&item);
                    }
                },
                Err(error) => {
                    item.status = ItemStatus::Paused;
                    item.error = Some(AppError::new(
                        ErrorCode::PermissionDenied,
                        Some(error.to_string()),
                    ));
                    let _ = self.save(&item);
                }
            }
        } else if (control.closing || intent == Some(Intent::Pause)) && outcome.is_err() {
            item.status = ItemStatus::Paused;
            if !control.closing {
                let _ = self.save(&item);
            }
        } else {
            match outcome {
                Ok(completed) => {
                    item.title = Some(completed.title);
                    item.status = ItemStatus::Done;
                    item.progress = Progress::Single { percent: 100.0 };
                    if self.save(&item).is_ok() {
                        let settled = self.db().is_ok_and(|mut db| {
                            db.settle_queue_item(
                                &id,
                                TerminalOutcome::Completed {
                                    successful_files: 1,
                                },
                            )
                            .is_ok()
                        });
                        if settled {
                            (self.emit)(QueueEvent::HistoryChanged);
                            (self.emit)(QueueEvent::Removed(id.clone()));
                        }
                    }
                    if let Some(disk) = &disk {
                        let _ = disk.clean_owned(&self.app_data);
                    }
                }
                Err(error) => {
                    item.status = ItemStatus::Failed;
                    item.error = Some(error.clone());
                    if self.save(&item).is_ok() {
                        let settled = self.db().is_ok_and(|mut db| {
                            db.settle_queue_item(&id, TerminalOutcome::Failed(error))
                                .is_ok()
                        });
                        if settled {
                            (self.emit)(QueueEvent::NotificationsChanged);
                            (self.emit)(QueueEvent::Removed(id.clone()));
                        }
                    }
                    if let Some(disk) = &disk {
                        let _ = disk.clean_owned(&self.app_data);
                    }
                }
            }
        }
        control.active = None;
        drop(control);
        let _ = self.kick();
    }

    pub fn pause(&self, id: &str) -> Result<(), AppError> {
        let mut control = self
            .control
            .lock()
            .map_err(|_| failure("queue control lock poisoned"))?;
        let Some(active) = control.active.as_mut().filter(|active| active.id == id) else {
            return Err(failure("item is not running"));
        };
        if active.phase != ItemStatus::Downloading || active.intent != Intent::Run {
            return Err(failure("pause is available only while downloading"));
        }
        active.intent = Intent::Pause;
        active.cancel.store(true, Ordering::SeqCst);
        Ok(())
    }

    pub fn resume(self: &Arc<Self>, id: &str) -> Result<(), AppError> {
        let _control = self
            .control
            .lock()
            .map_err(|_| failure("queue control lock poisoned"))?;
        let mut item = self.item(id)?;
        if item.status != ItemStatus::Paused || item.request.is_playlist {
            return Err(failure("only a paused single can continue in Stage 2C"));
        }
        if self.engine.is_none() {
            return Err(AppError::new(
                ErrorCode::EngineMissing,
                Some("Windows engine unavailable".into()),
            ));
        }
        item.status = ItemStatus::Queued;
        item.error = None;
        self.save(&item)?;
        drop(_control);
        if let Err(error) = self.kick() {
            eprintln!("could not start resumed queue item: {error:?}");
        }
        Ok(())
    }

    pub fn remove(self: &Arc<Self>, id: &str) -> Result<(), AppError> {
        let mut control = self
            .control
            .lock()
            .map_err(|_| failure("queue control lock poisoned"))?;
        if let Some(active) = control.active.as_mut().filter(|active| active.id == id) {
            active.intent = Intent::Remove;
            active.cancel.store(true, Ordering::SeqCst);
            return Ok(());
        }
        let _item = self.item(id)?;
        let disk = self
            .db()?
            .get_download_paths(id)
            .map_err(|error| failure(error.to_string()))?;
        if let Some(disk) = disk {
            disk.clean_owned(&self.app_data)
                .map_err(|error| failure(error.to_string()))?;
        }
        self.db()?
            .remove_queue_item(id)
            .map_err(|error| failure(error.to_string()))?;
        (self.emit)(QueueEvent::Removed(id.into()));
        drop(control);
        if let Err(error) = self.kick() {
            eprintln!("could not start next queue item: {error:?}");
        }
        Ok(())
    }

    pub fn close(&self) {
        let Ok(mut control) = self.control.lock() else {
            return;
        };
        control.closing = true;
        if let Some(active) = &control.active {
            if let Ok(mut item) = self.item(&active.id) {
                item.status = ItemStatus::Paused;
                let _ = self.save(&item);
            }
            active.cancel.store(true, Ordering::SeqCst);
        }
        self.supervisor.shutdown();
    }
}
