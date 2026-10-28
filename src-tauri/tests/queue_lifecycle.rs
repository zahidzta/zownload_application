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

fn request(name: &str) -> DownloadRequest {
    DownloadRequest {
        url: format!("https://example.com/{name}"),
        format: Format::Mp4,
        quality: Quality::Video { height: 240 },
        is_playlist: false,
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
fn sequential_pause_resume_settlement_and_close_are_durable() {
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
            zip_playlists: false,
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
    let playlist_id = coordinator.enqueue(playlist).unwrap();
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
    let active = coordinator.enqueue(request("close")).unwrap();
    until(|| {
        db.lock()
            .unwrap()
            .get_queue()
            .unwrap()
            .iter()
            .any(|item| item.id == active && item.status == ItemStatus::Downloading)
    });
    coordinator.close();
    assert_eq!(
        db.lock().unwrap().get_queue().unwrap()[0].status,
        ItemStatus::Paused
    );
    let close_part = root
        .join("app-data/downloads")
        .join(&active)
        .join("source.mp4.part");
    assert_eq!(close_part.metadata().unwrap().len(), 10);
    drop(coordinator);
    drop(db);
    let reopened = Database::open_at(&db_path).unwrap();
    assert_eq!(reopened.get_queue().unwrap()[0].status, ItemStatus::Paused);
    assert_eq!(reopened.get_error_notifications().unwrap().len(), 1);
}
