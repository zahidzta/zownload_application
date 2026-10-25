// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

#![cfg(target_os = "windows")]

use std::{path::Path, process::Command, sync::atomic::AtomicBool};
use zownload_lib::engine::{analysis, process::Supervisor, EnginePaths};

#[test]
fn metadata_analysis_launches_with_checked_runtime_and_no_download() {
    let root = std::env::temp_dir().join(format!("zownload-analysis-{}", uuid::Uuid::new_v4()));
    std::fs::create_dir(&root).unwrap();
    let stub = root.join("yt-dlp.exe");
    let source = Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/support/analysis_stub.rs");
    assert!(Command::new("rustc")
        .arg(source)
        .arg("-o")
        .arg(&stub)
        .status()
        .unwrap()
        .success());
    let trace = root.join("args.txt");
    std::env::set_var("ZOWNLOAD_ANALYSIS_STUB_TRACE", &trace);
    let paths = EnginePaths {
        yt_dlp: stub,
        ffmpeg: root.join("ffmpeg.exe"),
        quickjs: root.join("qjs.exe"),
    };
    let url = "https://www.youtube.com/watch?v=uW13KuRrg1g";
    let result = analysis::analyze(
        &paths,
        &Supervisor::install().unwrap(),
        url,
        &AtomicBool::new(false),
    )
    .unwrap();
    std::env::remove_var("ZOWNLOAD_ANALYSIS_STUB_TRACE");
    let value = serde_json::to_value(result).unwrap();
    assert_eq!(value["kind"], "single");
    assert_eq!(value["url"], url);
    let args = std::fs::read_to_string(&trace).unwrap();
    let args = args.lines().collect::<Vec<_>>();
    assert_eq!(&args[args.len() - 2..], &["--", url]);
    assert!(args.contains(&"--skip-download"));
    assert!(args.contains(&"--no-cache-dir"));
    assert!(args.contains(&"--no-playlist"));
    assert!(args.contains(&format!("quickjs:{}", paths.quickjs.display()).as_str()));
    std::fs::remove_dir_all(root).unwrap();
}
