// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

#![cfg(target_os = "windows")]

use std::{
    fs,
    path::Path,
    sync::{Arc, Mutex},
    thread,
    time::{Duration, Instant},
};
use zownload_lib::{
    contract::{DownloadRequest, Format, ItemStatus, Language, Quality, Settings},
    engine::{
        process::Supervisor,
        queue::{QueueCoordinator, QueueEvent},
        EnginePaths,
    },
    persistence::Database,
};

static TEST_LOCK: Mutex<()> = Mutex::new(());

fn request(name: &str) -> DownloadRequest {
    DownloadRequest {
        url: format!("https://example.com/{name}"),
        format: Format::Mp4,
        quality: Quality::Video { height: 240 },
        is_playlist: false,
    }
}

fn playlist_request(name: &str) -> DownloadRequest {
    DownloadRequest {
        url: format!("https://example.com/{name}"),
        format: Format::Mp4,
        quality: Quality::Max,
        is_playlist: true,
    }
}

fn until(mut condition: impl FnMut() -> bool) {
    let deadline = Instant::now() + Duration::from_secs(12);
    while !condition() {
        assert!(Instant::now() < deadline, "queue state timed out");
        thread::sleep(Duration::from_millis(20));
    }
}

#[test]
fn sequential_pause_resume_settlement_and_reopen_are_durable() {
    let _test_lock = TEST_LOCK.lock().unwrap();
    let root = std::env::temp_dir().join(format!("zownload-queue-{}", uuid::Uuid::new_v4()));
    fs::create_dir_all(&root).unwrap();
    let stub = root.join("yt-dlp.exe");
    assert!(std::process::Command::new("rustc")
        .arg(Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/support/queue_stub.rs"))
        .arg("-o")
        .arg(&stub)
        .status()
        .unwrap()
        .success());
    fs::copy(&stub, root.join("ffmpeg.exe")).unwrap();
    let db_path = root.join("state.sqlite3");
    let db = Arc::new(Mutex::new(Database::open_at(&db_path).unwrap()));
    db.lock()
        .unwrap()
        .set_settings(&Settings {
            language: Language::En,
            zip_playlists: true,
            download_dir: Some(root.join("Chosen").to_string_lossy().into_owned()),
        })
        .unwrap();
    let events = Arc::new(Mutex::new(Vec::<QueueEvent>::new()));
    let sink = Arc::clone(&events);
    let sink_db = Arc::clone(&db);
    let coordinator = QueueCoordinator::new(
        Arc::clone(&db),
        Some(EnginePaths {
            yt_dlp: stub,
            ffmpeg: root.join("ffmpeg.exe"),
            quickjs: root.join("qjs.exe"),
        }),
        Supervisor::install().unwrap(),
        root.join("app-data"),
        None,
        root.join("Downloads"),
        Arc::new(move |event| {
            let snapshot = sink_db.lock().unwrap();
            match &event {
                QueueEvent::Updated(item) => assert!(snapshot
                    .get_queue()
                    .unwrap()
                    .iter()
                    .any(|saved| saved.id == item.id)),
                QueueEvent::Removed(id) => assert!(!snapshot
                    .get_queue()
                    .unwrap()
                    .iter()
                    .any(|saved| &saved.id == id)),
                QueueEvent::HistoryChanged => assert!(!snapshot.get_history().unwrap().is_empty()),
                QueueEvent::NotificationsChanged => {
                    assert!(!snapshot.get_error_notifications().unwrap().is_empty())
                }
            }
            drop(snapshot);
            sink.lock().unwrap().push(event);
        }),
    );
    let mut playlist = request("playlist");
    playlist.is_playlist = true;
    playlist.quality = Quality::Max;
    let playlist_id = coordinator.enqueue(playlist.clone()).unwrap();
    let first = coordinator.enqueue(request("one")).unwrap();
    until(|| {
        db.lock()
            .unwrap()
            .get_queue()
            .unwrap()
            .iter()
            .any(|item| item.id == first && item.status == ItemStatus::Downloading)
    });
    let state = db
        .lock()
        .unwrap()
        .get_playlist_state(&playlist_id)
        .unwrap()
        .unwrap();
    assert!(state.zip_enabled);
    assert!(state.snapshot.is_none());
    db.lock()
        .unwrap()
        .set_settings(&Settings {
            language: Language::En,
            zip_playlists: false,
            download_dir: Some(root.join("Later").to_string_lossy().into_owned()),
        })
        .unwrap();
    let second = coordinator.enqueue(request("two")).unwrap();
    thread::sleep(Duration::from_millis(100));
    assert_eq!(
        db.lock().unwrap().get_queue().unwrap()[2].status,
        ItemStatus::Queued
    );
    coordinator.pause(&first).unwrap();
    until(|| {
        db.lock()
            .unwrap()
            .get_queue()
            .unwrap()
            .iter()
            .any(|item| item.id == first && item.status == ItemStatus::Paused)
    });
    let part = root
        .join("app-data/downloads")
        .join(&first)
        .join("source.mp4.part");
    assert_eq!(part.metadata().unwrap().len(), 10);
    until(|| {
        db.lock()
            .unwrap()
            .get_history()
            .unwrap()
            .iter()
            .any(|entry| entry.request.url.ends_with("/two"))
    });
    coordinator.resume(&first).unwrap();
    until(|| db.lock().unwrap().get_history().unwrap().len() == 2);
    assert!(!part.exists());
    assert_eq!(root.join("Chosen/one.mp4").metadata().unwrap().len(), 20);
    assert_eq!(root.join("Later/two.mp4").metadata().unwrap().len(), 20);
    assert_eq!(db.lock().unwrap().get_queue().unwrap()[0].id, playlist_id);
    coordinator.remove(&playlist_id).unwrap();
    let history = db.lock().unwrap().get_history().unwrap();
    assert_eq!(history.len(), 2);
    assert!(history[0].request.url.ends_with("/one"));
    let events = events.lock().unwrap();
    let removals: Vec<_> = events
        .iter()
        .filter_map(|event| match event {
            QueueEvent::Removed(id) => Some(id.as_str()),
            _ => None,
        })
        .collect();
    assert_eq!(
        removals,
        vec![second.as_str(), first.as_str(), playlist_id.as_str()]
    );
    drop(events);
    db.lock()
        .unwrap()
        .set_settings(&Settings {
            language: Language::En,
            zip_playlists: true,
            download_dir: Some(root.join("Later").to_string_lossy().into_owned()),
        })
        .unwrap();
    let redownload = coordinator.enqueue(playlist).unwrap();
    assert_ne!(redownload, playlist_id);
    until(|| {
        db.lock()
            .unwrap()
            .get_playlist_state(&redownload)
            .unwrap()
            .unwrap()
            .zip_enabled
    });
    assert_eq!(
        db.lock()
            .unwrap()
            .get_playlist_state(&redownload)
            .unwrap()
            .unwrap()
            .snapshot,
        None
    );
    db.lock()
        .unwrap()
        .set_settings(&Settings {
            language: Language::En,
            zip_playlists: false,
            download_dir: Some(root.join("Later").to_string_lossy().into_owned()),
        })
        .unwrap();
    coordinator.remove(&redownload).unwrap();
    let removed = coordinator.enqueue(request("remove")).unwrap();
    until(|| {
        db.lock()
            .unwrap()
            .get_queue()
            .unwrap()
            .iter()
            .any(|item| item.id == removed && item.status == ItemStatus::Downloading)
    });
    coordinator.remove(&removed).unwrap();
    until(|| db.lock().unwrap().get_queue().unwrap().is_empty());
    assert!(!root.join("app-data/downloads").join(&removed).exists());
    assert!(!root.join("Later/remove.mp4").exists());
    let failed = coordinator.enqueue(request("fail")).unwrap();
    until(|| {
        db.lock()
            .unwrap()
            .get_error_notifications()
            .unwrap()
            .iter()
            .any(|note| note.id == failed)
    });
    assert!(db.lock().unwrap().get_queue().unwrap().is_empty());
    let active = coordinator.enqueue(request("reopen")).unwrap();
    until(|| {
        db.lock()
            .unwrap()
            .get_queue()
            .unwrap()
            .iter()
            .any(|item| item.id == active && item.status == ItemStatus::Downloading)
    });
    coordinator.pause(&active).unwrap();
    until(|| db.lock().unwrap().get_queue().unwrap()[0].status == ItemStatus::Paused);
    let saved_part = root
        .join("app-data/downloads")
        .join(&active)
        .join("source.mp4.part");
    assert_eq!(saved_part.metadata().unwrap().len(), 10);
    drop(coordinator);
    drop(db);
    let reopened = Database::open_at(&db_path).unwrap();
    assert_eq!(reopened.get_queue().unwrap()[0].status, ItemStatus::Paused);
    assert_eq!(reopened.get_error_notifications().unwrap().len(), 1);
}

#[test]
fn playlists_continue_after_failure_and_settle_one_request_each() {
    let _test_lock = TEST_LOCK.lock().unwrap();
    let root = std::env::temp_dir().join(format!("zownload-playlist-{}", uuid::Uuid::new_v4()));
    fs::create_dir_all(&root).unwrap();
    let stub = root.join("yt-dlp.exe");
    assert!(std::process::Command::new("rustc")
        .arg(Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/support/queue_stub.rs"))
        .arg("-o")
        .arg(&stub)
        .status()
        .unwrap()
        .success());
    fs::copy(&stub, root.join("ffmpeg.exe")).unwrap();
    let db_path = root.join("state.sqlite3");
    let db = Arc::new(Mutex::new(Database::open_at(&db_path).unwrap()));
    db.lock()
        .unwrap()
        .set_settings(&Settings {
            language: Language::En,
            zip_playlists: false,
            download_dir: Some(root.join("Output").to_string_lossy().into_owned()),
        })
        .unwrap();
    let events = Arc::new(Mutex::new(Vec::<QueueEvent>::new()));
    let sink = Arc::clone(&events);
    let sink_db = Arc::clone(&db);
    let coordinator = QueueCoordinator::new(
        Arc::clone(&db),
        Some(EnginePaths {
            yt_dlp: stub,
            ffmpeg: root.join("ffmpeg.exe"),
            quickjs: root.join("qjs.exe"),
        }),
        Supervisor::install().unwrap(),
        root.join("app-data"),
        None,
        root.join("Downloads"),
        Arc::new(move |event| {
            let snapshot = sink_db.lock().unwrap();
            match &event {
                QueueEvent::Updated(item) => {
                    let stored = snapshot
                        .get_queue()
                        .unwrap()
                        .into_iter()
                        .find(|row| row.id == item.id)
                        .unwrap();
                    assert_eq!(stored.status, item.status);
                    assert_eq!(
                        serde_json::to_value(stored.progress).unwrap(),
                        serde_json::to_value(&item.progress).unwrap()
                    );
                }
                QueueEvent::Removed(id) => assert!(snapshot
                    .get_queue()
                    .unwrap()
                    .iter()
                    .all(|row| &row.id != id)),
                QueueEvent::HistoryChanged => assert!(!snapshot.get_history().unwrap().is_empty()),
                QueueEvent::NotificationsChanged => {
                    assert!(!snapshot.get_error_notifications().unwrap().is_empty())
                }
            }
            drop(snapshot);
            sink.lock().unwrap().push(event);
        }),
    );
    let success = coordinator
        .enqueue(playlist_request("all-success"))
        .unwrap();
    let mixed = coordinator.enqueue(playlist_request("mixed")).unwrap();
    let failed = coordinator.enqueue(playlist_request("all-failed")).unwrap();
    let fatal = coordinator.enqueue(playlist_request("fatal")).unwrap();
    db.lock()
        .unwrap()
        .set_settings(&Settings {
            language: Language::En,
            zip_playlists: true,
            download_dir: Some(root.join("Output").to_string_lossy().into_owned()),
        })
        .unwrap();
    let deferred = coordinator.enqueue(playlist_request("deferred")).unwrap();
    until(|| {
        let db = db.lock().unwrap();
        db.get_queue().unwrap().iter().all(|item| {
            item.id != success && item.id != mixed && item.id != failed && item.id != fatal
        })
    });
    let db_guard = db.lock().unwrap();
    let history = db_guard.get_history().unwrap();
    assert_eq!(history.len(), 3);
    assert_eq!(history[0].request.url, "https://example.com/fatal");
    assert_eq!(history[1].request.url, "https://example.com/mixed");
    assert_eq!(history[2].request.url, "https://example.com/all-success");
    let notifications = db_guard.get_error_notifications().unwrap();
    assert_eq!(notifications.len(), 3);
    assert_eq!(
        notifications
            .iter()
            .find(|note| note.id == mixed)
            .unwrap()
            .error
            .detail
            .as_deref(),
        Some("playlist_summary:2:1")
    );
    assert_eq!(
        notifications
            .iter()
            .find(|note| note.id == failed)
            .unwrap()
            .error
            .detail
            .as_deref(),
        Some("playlist_summary:0:2")
    );
    let fatal_note = notifications.iter().find(|note| note.id == fatal).unwrap();
    assert_eq!(
        fatal_note.error.code,
        zownload_lib::contract::ErrorCode::DiskFull
    );
    assert_eq!(
        fatal_note.error.detail.as_deref(),
        Some("playlist_summary:1:1")
    );
    assert_eq!(db_guard.get_queue().unwrap()[0].id, deferred);
    assert!(
        db_guard
            .get_playlist_state(&deferred)
            .unwrap()
            .unwrap()
            .zip_enabled
    );
    drop(db_guard);
    assert!(root.join("Output/first.mp4").exists());
    assert!(root.join("Output/first (1).mp4").exists());
    assert!(root.join("Output/first (2).mp4").exists());
    assert!(root.join("Output/second.mp4").exists());
    assert!(root.join("Output/second (1).mp4").exists());
    assert!(!root.join("Output/second (2).mp4").exists());
    let events = events.lock().unwrap();
    let mixed_progress: Vec<_> = events
        .iter()
        .filter_map(|event| match event {
            QueueEvent::Updated(item) if item.id == mixed => Some(item.progress.clone()),
            _ => None,
        })
        .collect();
    assert!(mixed_progress.iter().any(|progress| matches!(
        progress,
        zownload_lib::contract::Progress::Playlist {
            done: 1,
            failed: 1,
            total: 3,
            ..
        }
    )));
    assert!(mixed_progress.iter().any(|progress| matches!(
        progress,
        zownload_lib::contract::Progress::Playlist {
            done: 2,
            failed: 1,
            total: 3,
            ..
        }
    )));
    let removals: Vec<_> = events
        .iter()
        .filter_map(|event| match event {
            QueueEvent::Removed(id) => Some(id.as_str()),
            _ => None,
        })
        .collect();
    assert_eq!(
        removals,
        vec![
            success.as_str(),
            mixed.as_str(),
            failed.as_str(),
            fatal.as_str()
        ]
    );
}

#[test]
fn playlist_pause_restarts_at_current_entry_and_remove_cleans_partials() {
    let _test_lock = TEST_LOCK.lock().unwrap();
    let root =
        std::env::temp_dir().join(format!("zownload-playlist-resume-{}", uuid::Uuid::new_v4()));
    fs::create_dir_all(&root).unwrap();
    let stub = root.join("yt-dlp.exe");
    assert!(std::process::Command::new("rustc")
        .arg(Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/support/queue_stub.rs"))
        .arg("-o")
        .arg(&stub)
        .status()
        .unwrap()
        .success());
    fs::copy(&stub, root.join("ffmpeg.exe")).unwrap();
    let db_path = root.join("state.sqlite3");
    let db = Arc::new(Mutex::new(Database::open_at(&db_path).unwrap()));
    db.lock()
        .unwrap()
        .set_settings(&Settings {
            language: Language::En,
            zip_playlists: false,
            download_dir: Some(root.join("Output").to_string_lossy().into_owned()),
        })
        .unwrap();
    let make_coordinator = |db: Arc<Mutex<Database>>| {
        QueueCoordinator::new(
            db,
            Some(EnginePaths {
                yt_dlp: stub.clone(),
                ffmpeg: root.join("ffmpeg.exe"),
                quickjs: root.join("qjs.exe"),
            }),
            Supervisor::install().unwrap(),
            root.join("app-data"),
            None,
            root.join("Downloads"),
            Arc::new(|_| {}),
        )
    };
    let coordinator = make_coordinator(Arc::clone(&db));
    let id = coordinator
        .enqueue(playlist_request("all-success"))
        .unwrap();
    until(|| {
        db.lock().unwrap().get_queue().unwrap().iter().any(|item| {
            item.id == id
                && item.status == ItemStatus::Downloading
                && matches!(
                    item.progress,
                    zownload_lib::contract::Progress::Playlist { done: 1, .. }
                )
        })
    });
    coordinator.pause(&id).unwrap();
    until(|| {
        db.lock()
            .unwrap()
            .get_queue()
            .unwrap()
            .iter()
            .any(|item| item.id == id && item.status == ItemStatus::Paused)
    });
    let snapshot = db
        .lock()
        .unwrap()
        .get_playlist_state(&id)
        .unwrap()
        .unwrap()
        .snapshot
        .unwrap();
    assert_eq!(snapshot.next_index, 1);
    let part = root
        .join("app-data/downloads")
        .join(&id)
        .join("entry-1/source.mp4.part");
    assert_eq!(part.metadata().unwrap().len(), 10);
    drop(coordinator);
    drop(db);
    let reopened = Arc::new(Mutex::new(Database::open_at(&db_path).unwrap()));
    assert_eq!(
        reopened.lock().unwrap().get_queue().unwrap()[0].status,
        ItemStatus::Paused
    );
    let coordinator = make_coordinator(Arc::clone(&reopened));
    coordinator.resume(&id).unwrap();
    until(|| reopened.lock().unwrap().get_history().unwrap().len() == 1);
    until(|| !part.exists());
    assert_eq!(
        reopened.lock().unwrap().get_history().unwrap()[0]
            .request
            .url,
        "https://example.com/all-success"
    );
    assert_eq!(fs::read_dir(root.join("Output")).unwrap().count(), 2);
    let removed = coordinator
        .enqueue(playlist_request("all-success"))
        .unwrap();
    until(|| {
        reopened
            .lock()
            .unwrap()
            .get_queue()
            .unwrap()
            .iter()
            .any(|item| item.id == removed && item.status == ItemStatus::Downloading)
    });
    coordinator.remove(&removed).unwrap();
    until(|| {
        reopened
            .lock()
            .unwrap()
            .get_queue()
            .unwrap()
            .iter()
            .all(|item| item.id != removed)
    });
    assert!(!root.join("app-data/downloads").join(&removed).exists());
    assert_eq!(reopened.lock().unwrap().get_history().unwrap().len(), 1);
}
