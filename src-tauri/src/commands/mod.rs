// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

#[cfg(any(test, not(target_os = "windows")))]
use crate::contract::{ItemStatus, Progress};
#[cfg(target_os = "windows")]
use crate::engine::updater::ReleaseClient;
#[cfg(target_os = "windows")]
use crate::engine::{
    analysis,
    process::Supervisor,
    queue::{QueueCoordinator, QueueEvent},
    updater, EnginePaths, EngineStatus,
};
use crate::{
    contract::{
        AnalyzeResult, AppError, DownloadRequest, EngineUpdateInfo, EngineUpdateOutcome, ErrorCode,
        ErrorNotification, Format, HistoryEntry, Quality, QueueItem, Settings,
    },
    persistence::Database,
};
#[cfg(target_os = "windows")]
use std::sync::atomic::AtomicBool;
use std::sync::{Arc, Mutex};
#[cfg(target_os = "windows")]
use tauri::Manager;
use tauri::{AppHandle, Emitter, State};

type CommandResult<T> = Result<T, AppError>;

enum NativeEvent {
    QueueUpdated(QueueItem),
    QueueRemoved(String),
    HistoryChanged,
    NotificationsChanged,
}

impl NativeEvent {
    #[cfg(test)]
    fn name(&self) -> &'static str {
        match self {
            Self::QueueUpdated(_) => "queue:item-updated",
            Self::QueueRemoved(_) => "queue:item-removed",
            Self::HistoryChanged => "history:changed",
            Self::NotificationsChanged => "error-notifications:changed",
        }
    }

    #[cfg(test)]
    fn payload(&self) -> serde_json::Value {
        match self {
            Self::QueueUpdated(item) => serde_json::to_value(item).unwrap(),
            Self::QueueRemoved(id) => serde_json::to_value(id).unwrap(),
            Self::HistoryChanged | Self::NotificationsChanged => serde_json::Value::Null,
        }
    }
}

trait EventSink {
    fn emit(&self, event: NativeEvent);
}

impl EventSink for AppHandle {
    fn emit(&self, event: NativeEvent) {
        let result = match event {
            NativeEvent::QueueUpdated(item) => Emitter::emit(self, "queue:item-updated", item),
            NativeEvent::QueueRemoved(id) => Emitter::emit(self, "queue:item-removed", id),
            NativeEvent::HistoryChanged => Emitter::emit(self, "history:changed", ()),
            NativeEvent::NotificationsChanged => {
                Emitter::emit(self, "error-notifications:changed", ())
            }
        };
        // The durable write has already committed. An unavailable webview must not
        // turn a successful command into a reported write failure.
        if let Err(error) = result {
            eprintln!("could not emit native change event: {error}");
        }
    }
}

#[cfg(target_os = "windows")]
pub(crate) fn queue_sink(app: AppHandle) -> Arc<dyn Fn(QueueEvent) + Send + Sync> {
    Arc::new(move |event| {
        EventSink::emit(
            &app,
            match event {
                QueueEvent::Updated(item) => NativeEvent::QueueUpdated(item),
                QueueEvent::Removed(id) => NativeEvent::QueueRemoved(id),
                QueueEvent::HistoryChanged => NativeEvent::HistoryChanged,
                QueueEvent::NotificationsChanged => NativeEvent::NotificationsChanged,
            },
        );
    })
}

fn database_error(error: crate::persistence::Error) -> AppError {
    AppError::new(ErrorCode::Unknown, Some(error.to_string()))
}

fn lock_database(database: &Mutex<Database>) -> CommandResult<std::sync::MutexGuard<'_, Database>> {
    database
        .lock()
        .map_err(|_| AppError::new(ErrorCode::Unknown, Some("database lock poisoned".into())))
}

fn read<T>(
    database: &Mutex<Database>,
    action: impl FnOnce(&Database) -> CommandResult<T>,
) -> CommandResult<T> {
    let guard = lock_database(database)?;
    action(&guard)
}

fn mutate<T>(
    database: &Mutex<Database>,
    sink: &impl EventSink,
    action: impl FnOnce(&mut Database) -> CommandResult<(T, Option<NativeEvent>)>,
) -> CommandResult<T> {
    let mut guard = lock_database(database)?;
    let (value, event) = action(&mut guard)?;
    drop(guard);
    if let Some(event) = event {
        sink.emit(event);
    }
    Ok(value)
}

fn validate_request(request: &DownloadRequest) -> CommandResult<()> {
    let host = request
        .url
        .strip_prefix("https://")
        .or_else(|| request.url.strip_prefix("http://"))
        .and_then(|rest| rest.split('/').next());
    if host.is_none_or(|host| host.is_empty() || host.chars().any(char::is_whitespace)) {
        return Err(AppError::new(
            ErrorCode::InvalidUrl,
            Some("request URL needs an HTTP host".into()),
        ));
    }
    let quality_valid = match (&request.quality, request.format, request.is_playlist) {
        (Quality::Max | Quality::Min, _, true) => true,
        (
            Quality::Audio {
                bitrate: 128 | 192 | 256 | 320,
            },
            Format::Mp3,
            false,
        ) => true,
        (Quality::Video { height }, Format::Mp4, false) => *height > 0,
        _ => false,
    };
    if !quality_valid {
        return Err(AppError::new(
            ErrorCode::Unknown,
            Some("quality does not match request format or playlist".into()),
        ));
    }
    Ok(())
}

#[cfg(any(test, not(target_os = "windows")))]
fn enqueue(
    database: &mut Database,
    request: DownloadRequest,
) -> CommandResult<(String, Option<NativeEvent>)> {
    validate_request(&request)?;
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
    database.insert_queue_item(&item).map_err(database_error)?;
    Ok((id, Some(NativeEvent::QueueUpdated(item))))
}

#[cfg(any(test, not(target_os = "windows")))]
fn remove(database: &mut Database, id: String) -> CommandResult<((), Option<NativeEvent>)> {
    let item = database
        .get_queue()
        .map_err(database_error)?
        .into_iter()
        .find(|item| item.id == id)
        .ok_or_else(|| AppError::new(ErrorCode::Unknown, Some("queue item not found".into())))?;
    if item.status != ItemStatus::Queued {
        return Err(AppError::new(
            ErrorCode::Unknown,
            Some("only queued items can be removed before the engine is available".into()),
        ));
    }
    if !database.remove_queue_item(&id).map_err(database_error)? {
        return Err(AppError::new(
            ErrorCode::Unknown,
            Some("queue item was already removed".into()),
        ));
    }
    Ok(((), Some(NativeEvent::QueueRemoved(id))))
}

fn deferred(detail: &'static str) -> AppError {
    AppError::new(ErrorCode::EngineMissing, Some(detail.into()))
}

#[cfg(target_os = "windows")]
fn ready_engine(status: &EngineStatus) -> CommandResult<EnginePaths> {
    match status {
        EngineStatus::Ready(paths) => Ok(paths.clone()),
        EngineStatus::Unavailable(reason) => Err(AppError::new(
            ErrorCode::EngineMissing,
            Some(reason.clone()),
        )),
    }
}

#[tauri::command]
pub async fn analyze_url(app: AppHandle, url: String) -> CommandResult<AnalyzeResult> {
    #[cfg(target_os = "windows")]
    {
        let status = app
            .try_state::<EngineStatus>()
            .ok_or_else(|| deferred("Windows engine state is unavailable"))?;
        let paths = ready_engine(&status)?;
        let supervisor = app
            .try_state::<Arc<Supervisor>>()
            .ok_or_else(|| deferred("Windows process supervisor is unavailable"))?;
        let supervisor = Arc::clone(supervisor.inner());
        let data = paths
            .yt_dlp
            .parent()
            .and_then(std::path::Path::parent)
            .ok_or_else(|| deferred("Windows engine path is invalid"))?
            .to_path_buf();
        let resources = app
            .path()
            .resource_dir()
            .map_err(|error| AppError::new(ErrorCode::EngineMissing, Some(error.to_string())))?
            .join("binaries");
        // yt-dlp and JSON parsing are blocking work. Keep them off Tauri's UI thread.
        return tauri::async_runtime::spawn_blocking(move || {
            let cancel = AtomicBool::new(false);
            let (read_lease, _probation_guard, probation) = updater::begin_invocation(&data)
                .map_err(|reason| AppError::new(ErrorCode::EngineMissing, Some(reason)))?;
            let (first, broken) = analysis::analyze_classified(&paths, &supervisor, &url, &cancel);
            if let Some(version) = probation.as_deref() {
                if broken {
                    drop(read_lease);
                    let write_lease = updater::slot().write().map_err(|_| {
                        AppError::new(
                            ErrorCode::EngineMissing,
                            Some("engine slot poisoned".into()),
                        )
                    })?;
                    updater::restore_baseline_locked(&data, &resources, version, &write_lease)
                        .map_err(|reason| AppError::new(ErrorCode::EngineMissing, Some(reason)))?;
                    drop(write_lease);
                    let _retry_lease = updater::slot().read().map_err(|_| {
                        AppError::new(
                            ErrorCode::EngineMissing,
                            Some("engine slot poisoned".into()),
                        )
                    })?;
                    return analysis::analyze(&paths, &supervisor, &url, &cancel);
                }
                let _ = updater::mark_good(&data, version);
            }
            first
        })
        .await
        .map_err(|error| {
            AppError::new(
                ErrorCode::Unknown,
                Some(format!("analysis worker: {error}")),
            )
        })?;
    }
    #[cfg(not(target_os = "windows"))]
    {
        let _ = (app, url);
        Err(deferred(
            "desktop analysis is available on Windows in Stage 2B",
        ))
    }
}

#[tauri::command]
pub fn enqueue_download(
    database: State<'_, Arc<Mutex<Database>>>,
    app: AppHandle,
    request: DownloadRequest,
) -> CommandResult<String> {
    #[cfg(target_os = "windows")]
    {
        let _ = database;
        validate_request(&request)?;
        let queue = app
            .try_state::<Arc<QueueCoordinator>>()
            .ok_or_else(|| deferred("Windows queue coordinator unavailable"))?;
        return queue.enqueue(request);
    }
    #[cfg(not(target_os = "windows"))]
    mutate(database.inner(), &app, |db| enqueue(db, request))
}

#[tauri::command]
pub fn pause_download(app: AppHandle, id: String) -> CommandResult<()> {
    #[cfg(target_os = "windows")]
    return app
        .try_state::<Arc<QueueCoordinator>>()
        .ok_or_else(|| deferred("Windows queue coordinator unavailable"))?
        .pause(&id);
    #[cfg(not(target_os = "windows"))]
    {
        let _ = (app, id);
        Err(deferred("pause requires a running download engine"))
    }
}

#[tauri::command]
pub fn resume_download(app: AppHandle, id: String) -> CommandResult<()> {
    #[cfg(target_os = "windows")]
    return app
        .try_state::<Arc<QueueCoordinator>>()
        .ok_or_else(|| deferred("Windows queue coordinator unavailable"))?
        .resume(&id);
    #[cfg(not(target_os = "windows"))]
    {
        let _ = (app, id);
        Err(deferred("resume requires a running download engine"))
    }
}

#[tauri::command]
pub fn remove_download(
    database: State<'_, Arc<Mutex<Database>>>,
    app: AppHandle,
    id: String,
) -> CommandResult<()> {
    #[cfg(target_os = "windows")]
    let _ = database;
    #[cfg(target_os = "windows")]
    return app
        .try_state::<Arc<QueueCoordinator>>()
        .ok_or_else(|| deferred("Windows queue coordinator unavailable"))?
        .remove(&id);
    #[cfg(not(target_os = "windows"))]
    mutate(database.inner(), &app, |db| remove(db, id))
}

#[tauri::command]
pub fn get_queue(database: State<'_, Arc<Mutex<Database>>>) -> CommandResult<Vec<QueueItem>> {
    read(database.inner(), |db| {
        db.get_queue().map_err(database_error)
    })
}

#[tauri::command]
pub fn get_history(database: State<'_, Arc<Mutex<Database>>>) -> CommandResult<Vec<HistoryEntry>> {
    read(database.inner(), |db| {
        db.get_history().map_err(database_error)
    })
}

#[tauri::command]
pub fn delete_history_entry(
    database: State<'_, Arc<Mutex<Database>>>,
    app: AppHandle,
    id: i64,
) -> CommandResult<()> {
    mutate(database.inner(), &app, |db| {
        let changed = db.delete_history_entry(id).map_err(database_error)?;
        Ok(((), changed.then_some(NativeEvent::HistoryChanged)))
    })
}

#[tauri::command]
pub fn clear_history(
    database: State<'_, Arc<Mutex<Database>>>,
    app: AppHandle,
) -> CommandResult<()> {
    mutate(database.inner(), &app, |db| {
        let changed = db.clear_history().map_err(database_error)?;
        Ok(((), (changed > 0).then_some(NativeEvent::HistoryChanged)))
    })
}

#[tauri::command]
pub fn get_error_notifications(
    database: State<'_, Arc<Mutex<Database>>>,
) -> CommandResult<Vec<ErrorNotification>> {
    read(database.inner(), |db| {
        db.get_error_notifications().map_err(database_error)
    })
}

#[tauri::command]
pub fn dismiss_error_notification(
    database: State<'_, Arc<Mutex<Database>>>,
    app: AppHandle,
    id: String,
) -> CommandResult<()> {
    mutate(database.inner(), &app, |db| {
        let changed = db.dismiss_error_notification(&id).map_err(database_error)?;
        Ok(((), changed.then_some(NativeEvent::NotificationsChanged)))
    })
}

#[tauri::command]
pub fn get_settings(database: State<'_, Arc<Mutex<Database>>>) -> CommandResult<Settings> {
    read(database.inner(), |db| {
        db.get_settings().map_err(database_error)
    })
}

#[tauri::command]
pub fn set_settings(
    database: State<'_, Arc<Mutex<Database>>>,
    app: AppHandle,
    settings: Settings,
) -> CommandResult<()> {
    mutate(database.inner(), &app, |db| {
        db.set_settings(&settings).map_err(database_error)?;
        Ok(((), None))
    })
}

#[cfg(target_os = "windows")]
fn engine_update_error(reason: String) -> AppError {
    let lower = reason.to_ascii_lowercase();
    let code = if lower.contains("http")
        || lower.contains("request")
        || lower.contains("connection")
        || lower.contains("timed out")
    {
        ErrorCode::NoInternet
    } else {
        ErrorCode::Unknown
    };
    AppError::new(code, Some(reason))
}

#[tauri::command]
#[cfg(target_os = "windows")]
pub fn engine_check_update(
    app: AppHandle,
    engine: State<'_, EngineStatus>,
) -> CommandResult<EngineUpdateInfo> {
    ready_engine(engine.inner())?;
    let data = app
        .path()
        .app_local_data_dir()
        .map_err(|error| AppError::new(ErrorCode::Unknown, Some(error.to_string())))?;
    let client = ReleaseClient::official().map_err(engine_update_error)?;
    let candidate = client.latest().map_err(engine_update_error)?;
    client
        .update_info(&data, &candidate.version)
        .map_err(engine_update_error)
}

#[tauri::command]
#[cfg(target_os = "windows")]
pub fn engine_update(
    app: AppHandle,
    engine: State<'_, EngineStatus>,
    queue: State<'_, Arc<QueueCoordinator>>,
) -> CommandResult<EngineUpdateInfo> {
    ready_engine(engine.inner())?;
    let data = app
        .path()
        .app_local_data_dir()
        .map_err(|error| AppError::new(ErrorCode::Unknown, Some(error.to_string())))?;
    let client = ReleaseClient::official().map_err(engine_update_error)?;
    let candidate = client.latest().map_err(engine_update_error)?;
    let status = client
        .update_info(&data, &candidate.version)
        .map_err(engine_update_error)?;
    let previous = status.current.clone();
    if status.pending_version.as_deref() == Some(candidate.version.as_str())
        || !crate::engine::newer(&candidate.version, &status.current)
        || (status.failed_version.is_some() && status.manual_retry_available == Some(false))
    {
        return Ok(status);
    }
    let staged = client
        .update_manually(&data, &candidate)
        .map_err(engine_update_error)?;
    if !staged {
        return Ok(status);
    }
    queue.kick()?;
    let mut status = client
        .update_info(&data, &candidate.version)
        .map_err(engine_update_error)?;
    if status.pending_version.is_none() && status.current != previous {
        status.outcome = Some(EngineUpdateOutcome::Updated);
    }
    Ok(status)
}

#[cfg(not(target_os = "windows"))]
#[tauri::command]
pub fn engine_check_update() -> CommandResult<EngineUpdateInfo> {
    Err(deferred(
        "engine updates are currently supported on Windows only",
    ))
}

#[cfg(not(target_os = "windows"))]
#[tauri::command]
pub fn engine_update() -> CommandResult<EngineUpdateInfo> {
    Err(deferred(
        "engine updates are currently supported on Windows only",
    ))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{
        contract::{ErrorCode, Language},
        persistence::test_path,
    };
    use std::cell::RefCell;

    struct RecordingSink<'a> {
        database: &'a Mutex<Database>,
        events: RefCell<Vec<(String, serde_json::Value)>>,
    }

    impl EventSink for RecordingSink<'_> {
        fn emit(&self, event: NativeEvent) {
            // This read would deadlock if a command emitted while holding the write lock.
            let queue = self.database.lock().unwrap().get_queue().unwrap();
            match &event {
                NativeEvent::QueueUpdated(item) => {
                    assert!(queue.iter().any(|saved| saved.id == item.id))
                }
                NativeEvent::QueueRemoved(id) => {
                    assert!(!queue.iter().any(|saved| &saved.id == id))
                }
                _ => {}
            }
            self.events
                .borrow_mut()
                .push((event.name().into(), event.payload()));
        }
    }

    #[test]
    fn desktop_registers_every_shared_command_name() {
        let source = include_str!("../lib.rs").replace("\r\n", "\n");
        let desktop = source
            .split("#[cfg(not(target_os = \"android\"))]\n    let builder = builder.invoke_handler")
            .nth(1)
            .unwrap()
            .split("]);")
            .next()
            .unwrap();
        let names: Vec<_> = desktop
            .split("commands::")
            .skip(1)
            .map(|part| {
                part.split(|character: char| !character.is_ascii_alphanumeric() && character != '_')
                    .next()
                    .unwrap()
            })
            .collect();
        let expected = [
            "analyze_url",
            "enqueue_download",
            "pause_download",
            "resume_download",
            "remove_download",
            "get_queue",
            "get_history",
            "delete_history_entry",
            "clear_history",
            "get_error_notifications",
            "dismiss_error_notification",
            "get_settings",
            "set_settings",
            "engine_check_update",
            "engine_update",
        ];
        assert_eq!(names, expected);
    }

    #[cfg(target_os = "windows")]
    #[test]
    fn native_analysis_uses_ready_app_data_paths_and_reports_bootstrap_failure() {
        let paths = EnginePaths {
            yt_dlp: "C:/AppData/engine/yt-dlp.exe".into(),
            ffmpeg: "C:/AppData/engine/ffmpeg.exe".into(),
            quickjs: "C:/AppData/engine/qjs.exe".into(),
        };
        let ready = ready_engine(&EngineStatus::Ready(paths)).unwrap();
        assert!(ready.yt_dlp.ends_with("engine/yt-dlp.exe"));
        assert!(ready.quickjs.ends_with("engine/qjs.exe"));
        let error =
            ready_engine(&EngineStatus::Unavailable("failed health check".into())).unwrap_err();
        assert_eq!(error.code, ErrorCode::EngineMissing);
        assert_eq!(error.detail.as_deref(), Some("failed health check"));
        assert_eq!(
            serde_json::to_value(error).unwrap()["code"],
            "engine_missing"
        );
    }

    #[test]
    fn enqueue_and_remove_events_follow_commits_with_contract_payloads() {
        let path = test_path();
        let database = Mutex::new(Database::open_at(&path).unwrap());
        let sink = RecordingSink {
            database: &database,
            events: RefCell::new(Vec::new()),
        };
        let request: DownloadRequest = serde_json::from_value(serde_json::json!({
            "url":"https://example.com/media", "format":"mp3", "quality":{"type":"audio","bitrate":192}, "isPlaylist":false
        })).unwrap();
        let id = mutate(&database, &sink, |db| enqueue(db, request.clone())).unwrap();
        assert!(uuid::Uuid::parse_str(&id).is_ok());
        let event = sink.events.borrow()[0].clone();
        assert_eq!(event.0, "queue:item-updated");
        assert_eq!(event.1["id"], id);
        assert_eq!(event.1["status"], "queued");
        assert_eq!(event.1["request"]["quality"]["bitrate"], 192);
        assert_eq!(
            event.1["progress"],
            serde_json::json!({"kind":"single","percent":0.0})
        );
        assert_eq!(
            serde_json::to_value(
                database.lock().unwrap().get_queue().unwrap()[0]
                    .request
                    .clone()
            )
            .unwrap(),
            serde_json::to_value(&request).unwrap()
        );
        mutate(&database, &sink, |db| remove(db, id.clone())).unwrap();
        assert_eq!(
            sink.events.borrow()[1],
            ("queue:item-removed".into(), serde_json::json!(id))
        );
        assert!(database.lock().unwrap().get_queue().unwrap().is_empty());
        drop(sink);
        drop(database);
        std::fs::remove_file(path).unwrap();
    }

    #[test]
    fn rejected_mutations_emit_nothing_and_return_typed_errors() {
        let path = test_path();
        let database = Mutex::new(Database::open_at(&path).unwrap());
        let sink = RecordingSink {
            database: &database,
            events: RefCell::new(Vec::new()),
        };
        let request = DownloadRequest {
            url: "bad".into(),
            format: Format::Mp4,
            quality: Quality::Video { height: 720 },
            is_playlist: false,
        };
        let error = mutate(&database, &sink, |db| enqueue(db, request)).unwrap_err();
        assert_eq!(serde_json::to_value(error).unwrap()["code"], "invalid_url");
        let error = mutate(&database, &sink, |db| remove(db, "missing".into())).unwrap_err();
        assert_eq!(error.code, ErrorCode::Unknown);
        assert!(sink.events.borrow().is_empty());
        assert!(database.lock().unwrap().get_queue().unwrap().is_empty());
        let connection = rusqlite::Connection::open(&path).unwrap();
        connection.execute_batch("CREATE TRIGGER reject_queue_insert BEFORE INSERT ON queue_items BEGIN SELECT RAISE(FAIL, 'blocked'); END;").unwrap();
        drop(connection);
        let valid = DownloadRequest {
            url: "https://example.com/media".into(),
            format: Format::Mp4,
            quality: Quality::Video { height: 720 },
            is_playlist: false,
        };
        let error = mutate(&database, &sink, |db| enqueue(db, valid)).unwrap_err();
        assert_eq!(error.code, ErrorCode::Unknown);
        assert!(sink.events.borrow().is_empty());
        #[cfg(not(target_os = "windows"))]
        {
            assert_eq!(
                engine_check_update().unwrap_err().code,
                ErrorCode::EngineMissing
            );
            assert_eq!(engine_update().unwrap_err().code, ErrorCode::EngineMissing);
        }
        drop(sink);
        drop(database);
        std::fs::remove_file(path).unwrap();
    }

    #[test]
    fn stored_history_request_can_be_enqueued_directly_and_change_events_use_null() {
        let path = test_path();
        let database = Mutex::new(Database::open_at(&path).unwrap());
        let sink = RecordingSink {
            database: &database,
            events: RefCell::new(Vec::new()),
        };
        let request = DownloadRequest {
            url: "https://example.com/media".into(),
            format: Format::Mp4,
            quality: Quality::Video { height: 720 },
            is_playlist: false,
        };
        database
            .lock()
            .unwrap()
            .record_history(&request, Some("Saved title"))
            .unwrap();
        let saved = database.lock().unwrap().get_history().unwrap().remove(0);
        let id = mutate(&database, &sink, |db| enqueue(db, saved.request.clone())).unwrap();
        let queued = database.lock().unwrap().get_queue().unwrap();
        assert_eq!(queued[0].id, id);
        assert_eq!(
            serde_json::to_value(&queued[0].request).unwrap(),
            serde_json::to_value(&saved.request).unwrap()
        );
        mutate(&database, &sink, |db| {
            let deleted = db.delete_history_entry(saved.id).map_err(database_error)?;
            Ok(((), deleted.then_some(NativeEvent::HistoryChanged)))
        })
        .unwrap();
        assert_eq!(
            sink.events.borrow()[1],
            ("history:changed".into(), serde_json::Value::Null)
        );
        let settings = Settings {
            language: Language::Es,
            zip_playlists: true,
            download_dir: None,
        };
        database.lock().unwrap().set_settings(&settings).unwrap();
        assert_eq!(
            serde_json::to_value(database.lock().unwrap().get_settings().unwrap()).unwrap(),
            serde_json::json!({"language":"es","zipPlaylists":true,"downloadDir":null})
        );
        let notification_id = uuid::Uuid::new_v4().to_string();
        let connection = rusqlite::Connection::open(&path).unwrap();
        connection
            .execute(
                "INSERT INTO error_notifications (id, title, error) VALUES (?1, NULL, ?2)",
                rusqlite::params![notification_id, r#"{"code":"unknown","detail":null}"#],
            )
            .unwrap();
        drop(connection);
        mutate(&database, &sink, |db| {
            let changed = db
                .dismiss_error_notification(&notification_id)
                .map_err(database_error)?;
            Ok(((), changed.then_some(NativeEvent::NotificationsChanged)))
        })
        .unwrap();
        assert_eq!(
            sink.events.borrow()[2],
            (
                "error-notifications:changed".into(),
                serde_json::Value::Null
            )
        );
        drop(sink);
        drop(database);
        std::fs::remove_file(path).unwrap();
    }
}
