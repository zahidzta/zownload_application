// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

#![cfg(target_os = "windows")]

use std::{
    fs,
    path::Path,
    sync::{atomic::AtomicBool, Arc, Mutex},
};
use zownload_lib::{
    contract::{
        AppError, DownloadRequest, ErrorCode, Format, ItemStatus, Progress, Quality, QueueItem,
    },
    engine::{
        self,
        process::Supervisor,
        single::{run_single, Observation},
    },
    persistence::{paths::DownloadPaths, Database},
};

/// Opt-in pinned artifact proof. The Gate 2C evidence records the real output,
/// ffprobe inspection, and any site/network limit separately from V1 stubs.
#[test]
#[ignore]
fn real_pinned_single_mp3_and_mp4() {
    assert_eq!(
        std::env::var("ZOWNLOAD_TEST_SINGLE_CLI").as_deref(),
        Ok("1")
    );
    let root = Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../work/engine/2c-02")
        .join(format!("proof-{}", uuid::Uuid::new_v4()));
    fs::create_dir_all(&root).unwrap();
    let resources = Path::new(env!("CARGO_MANIFEST_DIR")).join("resources/windows-engine");
    let paths = match engine::bootstrap(&resources, &root.join("app-data"), "0.0.0") {
        engine::EngineStatus::Ready(paths) => paths,
        engine::EngineStatus::Unavailable(reason) => panic!("pinned engine: {reason}"),
    };
    let mut db = Database::open_at(&root.join("state.sqlite3")).unwrap();
    let supervisor = Supervisor::install().unwrap();
    let jobs = [
        DownloadRequest {
            url: "https://archive.org/download/PureDataSoundEffects/effect-acid.mp3".into(),
            format: Format::Mp3,
            quality: Quality::Audio { bitrate: 320 },
            is_playlist: false,
        },
        DownloadRequest {
            url: "https://archive.org/details/Justin_Cone_-_Building_On_The_Past_-_640x480".into(),
            format: Format::Mp4,
            quality: Quality::Video { height: 240 },
            is_playlist: false,
        },
    ];
    for request in jobs {
        let id = uuid::Uuid::new_v4().to_string();
        db.insert_queue_item(&QueueItem {
            id: id.clone(),
            request: request.clone(),
            title: None,
            thumbnail: None,
            status: ItemStatus::Queued,
            progress: Progress::Single { percent: 0.0 },
            error: None,
        })
        .unwrap();
        let mut disk = DownloadPaths::new(
            &id,
            &root.join("app-data"),
            Some(&root.join("out")),
            &root.join("Downloads"),
        )
        .unwrap();
        db.put_download_paths(&disk).unwrap();
        let mut persist = |paths: &DownloadPaths| {
            db.put_download_paths(paths)
                .map_err(|cause| AppError::new(ErrorCode::Unknown, Some(cause.to_string())))
        };
        let observations = Arc::new(Mutex::new(Vec::new()));
        let sink = Arc::clone(&observations);
        let result = run_single(
            &paths,
            &supervisor,
            &mut disk,
            &root.join("app-data"),
            &id,
            &request,
            &AtomicBool::new(false),
            Arc::new(move |event| sink.lock().unwrap().push(event)),
            &mut persist,
        )
        .unwrap();
        drop(persist);
        assert!(result.path.metadata().unwrap().len() > 1024);
        assert!(observations
            .lock()
            .unwrap()
            .iter()
            .any(|event| matches!(event, Observation::Downloaded { .. })));
        assert!(observations
            .lock()
            .unwrap()
            .iter()
            .any(|event| matches!(event, Observation::PostProcessing)));
        println!(
            "OUTPUT={} SELECTED_HEIGHT={:?}",
            result.path.display(),
            result.selected_height
        );
    }
}

#[test]
#[ignore]
fn real_pinned_high_mp3_reencodes_down_via_local_stub() {
    assert_eq!(
        std::env::var("ZOWNLOAD_TEST_SINGLE_CLI").as_deref(),
        Ok("1")
    );
    let root = Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../work/engine/2c-02")
        .join(format!("local-stub-{}", uuid::Uuid::new_v4()));
    fs::create_dir_all(&root).unwrap();
    let resources = Path::new(env!("CARGO_MANIFEST_DIR")).join("resources/windows-engine");
    let mut paths = match engine::bootstrap(&resources, &root.join("app-data"), "0.0.0") {
        engine::EngineStatus::Ready(paths) => paths,
        engine::EngineStatus::Unavailable(reason) => panic!("pinned engine: {reason}"),
    };
    let high = root.join("high.mp3");
    let status = std::process::Command::new(&paths.ffmpeg)
        .args([
            "-hide_banner",
            "-loglevel",
            "error",
            "-f",
            "lavfi",
            "-i",
            "sine=frequency=440:duration=2",
            "-c:a",
            "libmp3lame",
            "-b:a",
            "256k",
            "-y",
        ])
        .arg(&high)
        .status()
        .unwrap();
    assert!(status.success());
    let stub = root.join("app-data/engine/yt-dlp-stub.exe");
    let source = Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/support/single_stub.rs");
    assert!(std::process::Command::new("rustc")
        .arg(source)
        .arg("-o")
        .arg(&stub)
        .status()
        .unwrap()
        .success());
    paths.yt_dlp = stub;
    std::env::set_var("ZOWNLOAD_SINGLE_STUB_SOURCE", &high);
    let mut db = Database::open_at(&root.join("state.sqlite3")).unwrap();
    let id = uuid::Uuid::new_v4().to_string();
    let request = DownloadRequest {
        url: "https://example.com/high.mp3".into(),
        format: Format::Mp3,
        quality: Quality::Audio { bitrate: 128 },
        is_playlist: false,
    };
    db.insert_queue_item(&QueueItem {
        id: id.clone(),
        request: request.clone(),
        title: None,
        thumbnail: None,
        status: ItemStatus::Queued,
        progress: Progress::Single { percent: 0.0 },
        error: None,
    })
    .unwrap();
    let mut disk = DownloadPaths::new(
        &id,
        &root.join("app-data"),
        Some(&root.join("out")),
        &root.join("Downloads"),
    )
    .unwrap();
    db.put_download_paths(&disk).unwrap();
    let mut persist = |paths: &DownloadPaths| {
        db.put_download_paths(paths)
            .map_err(|cause| AppError::new(ErrorCode::Unknown, Some(cause.to_string())))
    };
    let result = run_single(
        &paths,
        &Supervisor::install().unwrap(),
        &mut disk,
        &root.join("app-data"),
        &id,
        &request,
        &AtomicBool::new(false),
        Arc::new(|_| {}),
        &mut persist,
    );
    std::env::remove_var("ZOWNLOAD_SINGLE_STUB_SOURCE");
    let result = result.unwrap();
    assert!(result.path.metadata().unwrap().len() > 1024);
    println!(
        "HIGH_MP3={} OUTPUT={}",
        high.display(),
        result.path.display()
    );
}
