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
    contract::{
        DownloadRequest, Format, ItemStatus, Language, Progress, Quality, QueueItem, Settings,
    },
    engine::{
        analysis::{PlaylistEntry, PlaylistSnapshot},
        process::Supervisor,
        queue::{QueueCoordinator, QueueEvent},
        zip_output::ZipOutput,
        EnginePaths,
    },
    persistence::{paths::DownloadPaths, Database},
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

fn zip_staging_stats(root: &Path) -> (usize, u64, usize) {
    let mut files = 0;
    let mut bytes = 0;
    let mut media = 0;
    let mut pending = vec![root.join("app-data/downloads")];
    while let Some(path) = pending.pop() {
        let Ok(entries) = fs::read_dir(path) else {
            continue;
        };
        for entry in entries.flatten() {
            let path = entry.path();
            if path.is_dir() {
                pending.push(path);
            } else if let Ok(metadata) = entry.metadata() {
                files += 1;
                bytes += metadata.len();
                if path
                    .extension()
                    .is_some_and(|ext| ext == "mp3" || ext == "mp4")
                    || path
                        .file_name()
                        .is_some_and(|name| name.to_string_lossy().ends_with(".mp4.part"))
                {
                    media += 1;
                }
            }
        }
    }
    if let Ok(entries) = fs::read_dir(root.join("Output")) {
        for entry in entries.flatten() {
            let path = entry.path();
            if path
                .file_name()
                .is_some_and(|name| name.to_string_lossy().ends_with(".zip.part"))
            {
                if let Ok(metadata) = entry.metadata() {
                    files += 1;
                    bytes += metadata.len();
                }
            }
        }
    }
    (files, bytes, media)
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
    let first = coordinator.enqueue(request("one")).unwrap();
    until(|| {
        db.lock()
            .unwrap()
            .get_queue()
            .unwrap()
            .iter()
            .any(|item| item.id == first && item.status == ItemStatus::Downloading)
    });
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
        db.lock().unwrap().get_queue().unwrap()[1].status,
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
    assert_eq!(removals, vec![second.as_str(), first.as_str()]);
    drop(events);
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
    until(|| {
        let db = db.lock().unwrap();
        db.get_queue().unwrap().iter().all(|item| {
            item.id != success && item.id != mixed && item.id != failed && item.id != fatal
        })
    });
    let db_guard = db.lock().unwrap();
    let history = db_guard.get_history().unwrap();
    assert_eq!(history.len(), 2);
    assert_eq!(history[0].request.url, "https://example.com/mixed");
    assert_eq!(history[1].request.url, "https://example.com/all-success");
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
        Some("ERROR: No space left on device\n")
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
fn zip_playlists_publish_successes_and_cancel_fatal_jobs() {
    let _test_lock = TEST_LOCK.lock().unwrap();
    let root = std::env::temp_dir().join(format!("zownload-zip-queue-{}", uuid::Uuid::new_v4()));
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
    let db = Arc::new(Mutex::new(
        Database::open_at(&root.join("state.sqlite3")).unwrap(),
    ));
    db.lock()
        .unwrap()
        .set_settings(&Settings {
            language: Language::En,
            zip_playlists: true,
            download_dir: Some(root.join("Output").to_string_lossy().into_owned()),
        })
        .unwrap();
    let events = Arc::new(Mutex::new(Vec::<QueueEvent>::new()));
    let sink = Arc::clone(&events);
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
        Arc::new(move |event| sink.lock().unwrap().push(event)),
    );
    std::env::set_var("ZOWNLOAD_QUEUE_STUB_BYTES", (2 * 1024 * 1024).to_string());
    let success = coordinator
        .enqueue(playlist_request("all-success"))
        .unwrap();
    let mixed = coordinator.enqueue(playlist_request("mixed")).unwrap();
    let duplicates = coordinator.enqueue(playlist_request("duplicates")).unwrap();
    let failed = coordinator.enqueue(playlist_request("all-failed")).unwrap();
    let fatal = coordinator.enqueue(playlist_request("fatal")).unwrap();
    db.lock()
        .unwrap()
        .set_settings(&Settings {
            language: Language::En,
            zip_playlists: false,
            download_dir: Some(root.join("Other").to_string_lossy().into_owned()),
        })
        .unwrap();
    let deadline = Instant::now() + Duration::from_secs(20);
    let mut peak_files = 0;
    let mut peak_bytes = 0;
    let mut peak_media = 0;
    loop {
        let (files, bytes, media) = zip_staging_stats(&root);
        peak_files = peak_files.max(files);
        peak_bytes = peak_bytes.max(bytes);
        peak_media = peak_media.max(media);
        if db.lock().unwrap().get_queue().unwrap().is_empty() {
            break;
        }
        assert!(Instant::now() < deadline, "ZIP queue timed out");
        thread::sleep(Duration::from_millis(5));
    }
    println!(
        "ZIP_STAGE_PEAK files={peak_files} bytes={peak_bytes} media_files={peak_media} sample_ms=5"
    );
    std::env::remove_var("ZOWNLOAD_QUEUE_STUB_BYTES");
    let db = db.lock().unwrap();
    let history = db.get_history().unwrap();
    assert_eq!(history.len(), 3);
    assert_eq!(history[0].request.url, "https://example.com/duplicates");
    assert_eq!(history[1].request.url, "https://example.com/mixed");
    assert_eq!(history[2].request.url, "https://example.com/all-success");
    let notes = db.get_error_notifications().unwrap();
    assert_eq!(notes.len(), 3);
    assert_eq!(
        notes
            .iter()
            .find(|note| note.id == fatal)
            .unwrap()
            .error
            .code,
        zownload_lib::contract::ErrorCode::DiskFull
    );
    assert!(notes.iter().any(|note| note.id == failed));
    assert!(notes.iter().any(|note| note.id == mixed));
    drop(db);
    let mut archives = fs::read_dir(root.join("Output"))
        .unwrap()
        .map(|entry| entry.unwrap().path())
        .collect::<Vec<_>>();
    archives.sort();
    assert_eq!(archives.len(), 3);
    assert_eq!(archives[0].file_name().unwrap(), "Playlist (1).zip");
    assert_eq!(archives[1].file_name().unwrap(), "Playlist (2).zip");
    assert_eq!(archives[2].file_name().unwrap(), "Playlist.zip");
    let mut sizes = Vec::new();
    for path in &archives {
        let mut zip = zip::ZipArchive::new(fs::File::open(path).unwrap()).unwrap();
        sizes.push(zip.len());
        for index in 0..zip.len() {
            let entry = zip.by_index(index).unwrap();
            assert_eq!(entry.compression(), zip::CompressionMethod::Stored);
            assert_eq!(entry.size(), 2 * 1024 * 1024);
        }
    }
    assert_eq!(sizes, [2, 2, 2]);
    let mut duplicate_zip =
        zip::ZipArchive::new(fs::File::open(root.join("Output/Playlist (2).zip")).unwrap())
            .unwrap();
    assert_eq!(
        duplicate_zip.by_index(0).unwrap().name().unwrap(),
        "first.mp4"
    );
    assert_eq!(
        duplicate_zip.by_index(1).unwrap().name().unwrap(),
        "first (1).mp4"
    );
    assert!(events.lock().unwrap().iter().any(|event| matches!(event, QueueEvent::Updated(item) if item.id == success && item.status == ItemStatus::Packaging)));
    assert!(events.lock().unwrap().iter().any(|event| matches!(event, QueueEvent::Updated(item) if item.id == mixed && item.status == ItemStatus::Packaging)));
    assert!(events.lock().unwrap().iter().any(|event| matches!(event, QueueEvent::Updated(item) if item.id == duplicates && item.status == ItemStatus::Packaging)));
    assert!(!root.join("Other").exists());
    assert!(!root.join("app-data/downloads").join(fatal).exists());
}

#[test]
fn zip_restart_reconciles_a_committed_entry_before_downloading_the_next() {
    let _test_lock = TEST_LOCK.lock().unwrap();
    let root = std::env::temp_dir().join(format!("zownload-zip-restart-{}", uuid::Uuid::new_v4()));
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
    let mut db = Database::open_at(&db_path).unwrap();
    let id = uuid::Uuid::new_v4().to_string();
    let request = playlist_request("all-success");
    let disk = DownloadPaths::new(
        &id,
        &root.join("app-data"),
        Some(&root.join("Output")),
        &root.join("Downloads"),
    )
    .unwrap();
    let mut item = QueueItem {
        id: id.clone(),
        request: request.clone(),
        title: None,
        thumbnail: None,
        status: ItemStatus::Queued,
        progress: Progress::Playlist {
            done: 0,
            failed: 0,
            total: 0,
            current_title: None,
            current_percent: 0.0,
        },
        error: None,
    };
    db.insert_queue_item_with_options(&item, Some(&disk), Some(true))
        .unwrap();
    let snapshot = PlaylistSnapshot {
        entries: ["first", "second"]
            .into_iter()
            .map(|name| PlaylistEntry {
                url: format!("https://example.com/entry/{name}"),
                title: name.into(),
            })
            .collect(),
        next_index: 0,
    };
    db.save_playlist_snapshot(&id, "Playlist", &snapshot)
        .unwrap();
    let mut zip = ZipOutput::open(&disk.output_dir, &disk.work_dir, "Playlist").unwrap();
    let media = disk.work_dir.join("first.mp4");
    fs::write(&media, b"first committed media").unwrap();
    zip.append_entry(0, "first", &media).unwrap();
    let mut legacy_paths = disk.clone();
    legacy_paths.work_dir = disk.work_dir.join("entry-0");
    db.put_download_paths(&legacy_paths).unwrap();
    item = db.get_queue().unwrap().remove(0);
    item.status = ItemStatus::Packaging;
    db.update_queue_item(&item).unwrap();
    drop(db);
    let reopened = Database::open_at(&db_path).unwrap();
    assert_eq!(reopened.get_queue().unwrap()[0].status, ItemStatus::Paused);
    assert_eq!(
        reopened
            .get_playlist_state(&id)
            .unwrap()
            .unwrap()
            .snapshot
            .unwrap()
            .next_index,
        0
    );
    let db = Arc::new(Mutex::new(reopened));
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
        Arc::new(|_| {}),
    );
    coordinator.resume(&id).unwrap();
    until(|| db.lock().unwrap().get_queue().unwrap().is_empty());
    assert_eq!(db.lock().unwrap().get_history().unwrap().len(), 1);
    assert!(db
        .lock()
        .unwrap()
        .get_error_notifications()
        .unwrap()
        .is_empty());
    let mut archive =
        zip::ZipArchive::new(fs::File::open(root.join("Output/Playlist.zip")).unwrap()).unwrap();
    assert_eq!(archive.len(), 2);
    assert_eq!(archive.by_index(0).unwrap().name().unwrap(), "first.mp4");
    assert_eq!(archive.by_index(1).unwrap().name().unwrap(), "second.mp4");
    drop(archive);
    drop(coordinator);
    // Queue settlement precedes worker exit. Wait for its coordinator (and
    // SQLite reference) to be released before deleting the Windows test root.
    until(|| Arc::strong_count(&db) == 1);
    drop(db);
    fs::remove_dir_all(root).unwrap();
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
