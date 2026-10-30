// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

#![cfg(target_os = "windows")]

use std::{
    fs,
    path::Path,
    process::Command,
    sync::{atomic::AtomicBool, Arc},
};
use zownload_lib::{
    contract::{AppError, DownloadRequest, Format, Quality},
    engine::{self, analysis::PlaylistEntry, process::Supervisor, single::run_playlist_entry},
    persistence::paths::DownloadPaths,
};

#[test]
fn four_profiles_run_entries_in_order_and_preserve_colliding_outputs() {
    let root = std::env::temp_dir().join(format!("zownload-playlist-cli-{}", uuid::Uuid::new_v4()));
    fs::create_dir_all(&root).unwrap();
    let app_data = root.join("app-data");
    let audio = root.join("audio.wav");
    let video = root.join("video.mp4");
    fs::write(&audio, b"local audio fixture").unwrap();
    fs::write(&video, b"local video fixture").unwrap();
    let stub = root.join("yt-dlp.exe");
    let source = Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/support/playlist_stub.rs");
    assert!(Command::new("rustc")
        .arg(source)
        .arg("-o")
        .arg(&stub)
        .status()
        .unwrap()
        .success());
    let ffmpeg = root.join("ffmpeg.exe");
    assert!(Command::new("rustc")
        .arg(Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/support/playlist_stub.rs"))
        .arg("-o")
        .arg(&ffmpeg)
        .status()
        .unwrap()
        .success());
    let paths = engine::EnginePaths {
        yt_dlp: stub,
        ffmpeg,
        quickjs: root.join("qjs.exe"),
    };
    let trace = root.join("trace.txt");
    std::env::set_var("ZOWNLOAD_PLAYLIST_STUB_AUDIO", &audio);
    std::env::set_var("ZOWNLOAD_PLAYLIST_STUB_VIDEO", &video);
    std::env::set_var("ZOWNLOAD_PLAYLIST_STUB_TRACE", &trace);
    let id = uuid::Uuid::new_v4().to_string();
    let mut disk = DownloadPaths::new(
        &id,
        &app_data,
        Some(&root.join("out")),
        &root.join("Downloads"),
    )
    .unwrap();
    let supervisor = Supervisor::install().unwrap();
    let mut outputs = Vec::new();
    for (index, format, quality) in [
        (0, Format::Mp4, Quality::Max),
        (1, Format::Mp4, Quality::Min),
        (2, Format::Mp3, Quality::Max),
        (3, Format::Mp3, Quality::Min),
    ] {
        let entry = PlaylistEntry {
            url: format!("https://example.com/entry/{index}"),
            title: "Track".into(),
        };
        let request = DownloadRequest {
            url: "https://example.com/playlist".into(),
            format,
            quality,
            is_playlist: true,
        };
        let output = run_playlist_entry(
            &paths,
            &supervisor,
            &mut disk,
            &app_data,
            &id,
            &request,
            &entry,
            index,
            "Album",
            &AtomicBool::new(false),
            Arc::new(|_| {}),
            &mut |_paths| Ok::<(), AppError>(()),
        )
        .unwrap_or_else(|error| panic!("entry {index}: {error:?}"));
        assert!(output.path.metadata().unwrap().len() > 5);
        outputs.push(output.path);
    }
    std::env::remove_var("ZOWNLOAD_PLAYLIST_STUB_AUDIO");
    std::env::remove_var("ZOWNLOAD_PLAYLIST_STUB_VIDEO");
    std::env::remove_var("ZOWNLOAD_PLAYLIST_STUB_TRACE");
    let trace = fs::read_to_string(&trace).unwrap();
    let entries: Vec<_> = trace
        .lines()
        .filter(|line| line.starts_with("ENTRY|"))
        .collect();
    assert_eq!(
        entries,
        [
            "ENTRY|0|bv*+ba/b",
            "ENTRY|1|wv*+ba/w",
            "ENTRY|2|ba/b",
            "ENTRY|3|ba/b",
        ]
    );
    let ffmpeg: Vec<_> = trace
        .lines()
        .filter(|line| line.starts_with("FFMPEG|"))
        .collect();
    assert_eq!(ffmpeg.len(), 4);
    assert!(ffmpeg
        .iter()
        .all(|line| line.contains("title=Track") && line.contains("album=Album")));
    assert!(ffmpeg[2].contains("-b:a|320k"));
    assert!(ffmpeg[3].contains("-b:a|128k"));
    assert_eq!(outputs[0].file_name().unwrap(), "Track.mp4");
    assert_eq!(outputs[1].file_name().unwrap(), "Track (1).mp4");
    assert_eq!(outputs[2].file_name().unwrap(), "Track.mp3");
    assert_eq!(outputs[3].file_name().unwrap(), "Track (1).mp3");
    assert!(!root.join("out/Album.zip").exists());
    assert!(fs::read_dir(root.join("out")).unwrap().all(|file| file
        .unwrap()
        .path()
        .extension()
        .unwrap()
        != "zip"));
    fs::remove_dir_all(root).unwrap();
}
