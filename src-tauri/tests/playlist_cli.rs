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
    let resources = Path::new(env!("CARGO_MANIFEST_DIR")).join("resources/windows-engine");
    let mut paths = match engine::bootstrap(&resources, &app_data, "0.0.0") {
        engine::EngineStatus::Ready(paths) => paths,
        engine::EngineStatus::Unavailable(reason) => panic!("pinned engine: {reason}"),
    };
    let audio = root.join("audio.wav");
    let video = root.join("video.mp4");
    let make = |args: &[&str]| {
        assert!(Command::new(&paths.ffmpeg)
            .args(args)
            .status()
            .unwrap()
            .success());
    };
    make(&[
        "-loglevel",
        "error",
        "-f",
        "lavfi",
        "-i",
        "sine=frequency=440:duration=1",
        "-y",
        audio.to_str().unwrap(),
    ]);
    make(&[
        "-loglevel",
        "error",
        "-f",
        "lavfi",
        "-i",
        "color=c=black:s=160x90:d=1",
        "-f",
        "lavfi",
        "-i",
        "sine=frequency=440:duration=1",
        "-c:v",
        "mpeg4",
        "-c:a",
        "aac",
        "-shortest",
        "-y",
        video.to_str().unwrap(),
    ]);
    let stub = app_data.join("engine/yt-dlp-stub.exe");
    let source = Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/support/playlist_stub.rs");
    assert!(Command::new("rustc")
        .arg(source)
        .arg("-o")
        .arg(&stub)
        .status()
        .unwrap()
        .success());
    paths.yt_dlp = stub;
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
        assert!(output.path.metadata().unwrap().len() > 1000);
        outputs.push(output.path);
    }
    std::env::remove_var("ZOWNLOAD_PLAYLIST_STUB_AUDIO");
    std::env::remove_var("ZOWNLOAD_PLAYLIST_STUB_VIDEO");
    std::env::remove_var("ZOWNLOAD_PLAYLIST_STUB_TRACE");
    assert_eq!(
        fs::read_to_string(&trace)
            .unwrap()
            .lines()
            .collect::<Vec<_>>(),
        ["0|bv*+ba/b", "1|wv*+ba/w", "2|ba/b", "3|ba/b"]
    );
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
    for (index, path) in outputs.iter().enumerate() {
        let probe = Command::new(&paths.ffmpeg)
            .args(["-hide_banner", "-i"])
            .arg(path)
            .output()
            .unwrap();
        let metadata = String::from_utf8_lossy(&probe.stderr);
        assert!(
            metadata.contains("Track"),
            "entry {index} has no title: {metadata}"
        );
        assert!(
            metadata.contains("Album"),
            "entry {index} has no album: {metadata}"
        );
        if index >= 2 {
            let bitrate = if index == 2 { "320 kb/s" } else { "128 kb/s" };
            assert!(
                metadata.contains(bitrate),
                "entry {index} bitrate: {metadata}"
            );
        }
    }
    fs::remove_dir_all(root).unwrap();
}
