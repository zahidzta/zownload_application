// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

#![cfg(target_os = "windows")]

use sha2::{Digest, Sha256};
use std::{
    fs,
    path::PathBuf,
    sync::{Arc, Mutex},
    thread,
    time::{Duration, Instant},
};
use zownload_lib::{
    contract::{DownloadRequest, ErrorCode, Format, Quality},
    engine::{bootstrap, process::Supervisor, queue::QueueCoordinator, EnginePaths, EngineStatus},
    persistence::Database,
};

fn fixture() -> (PathBuf, PathBuf, EnginePaths, Arc<Mutex<Database>>) {
    let root = std::env::temp_dir().join(format!("zownload-probation-{}", uuid::Uuid::new_v4()));
    fs::create_dir_all(&root).unwrap();
    let resources = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("resources/windows-engine");
    let data = root.join("app-data");
    let paths = match bootstrap(&resources, &data, "0.0.1") {
        EngineStatus::Ready(paths) => paths,
        EngineStatus::Unavailable(reason) => panic!("baseline unavailable: {reason}"),
    };
    let source = root.join("stub.rs");
    fs::write(
        &source,
        r#"// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta
fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    if args.iter().any(|arg| arg == "--version") { println!("2026.10.21"); return; }
    if args.last().is_some_and(|url| url.ends_with("/site")) {
        eprintln!("ERROR: simulated site error");
        std::process::exit(4);
    }
    if args.last().is_some_and(|url| url.ends_with("/malformed")) {
        println!("not JSON");
        return;
    }
    eprintln!("stub process crash");
    std::process::exit(7);
}
"#,
    )
    .unwrap();
    let executable = root.join("stub.exe");
    assert!(std::process::Command::new("rustc")
        .arg(&source)
        .arg("-o")
        .arg(&executable)
        .status()
        .unwrap()
        .success());
    fs::copy(&executable, &paths.yt_dlp).unwrap();
    let hash = format!("{:x}", Sha256::digest(fs::read(&paths.yt_dlp).unwrap()));
    let manifest_path = data.join("engine/engine.json");
    let mut manifest: serde_json::Value =
        serde_json::from_slice(&fs::read(&manifest_path).unwrap()).unwrap();
    manifest["ytDlp"]["version"] = "2026.10.21".into();
    manifest["ytDlp"]["source"] = "updated".into();
    manifest["ytDlp"]["state"] = "probation".into();
    manifest["ytDlp"]["sha256"] = hash.into();
    fs::write(&manifest_path, serde_json::to_vec(&manifest).unwrap()).unwrap();
    let db = Arc::new(Mutex::new(
        Database::open_at(&root.join("state.sqlite3")).unwrap(),
    ));
    (root, resources, paths, db)
}

fn execute(
    root: &PathBuf,
    resources: &PathBuf,
    paths: EnginePaths,
    db: Arc<Mutex<Database>>,
    name: &str,
) -> serde_json::Value {
    let data = root.join("app-data");
    let coordinator = QueueCoordinator::new(
        Arc::clone(&db),
        Some(paths),
        Supervisor::install().unwrap(),
        data.clone(),
        Some(resources.clone()),
        root.join("Downloads"),
        Arc::new(|_| {}),
    );
    coordinator
        .enqueue(DownloadRequest {
            url: format!("http://127.0.0.1:1/{name}"),
            format: Format::Mp4,
            quality: Quality::Video { height: 240 },
            is_playlist: false,
        })
        .unwrap();
    let deadline = Instant::now() + Duration::from_secs(40);
    loop {
        let db = db.lock().unwrap();
        if db.get_queue().unwrap().is_empty() && !db.get_error_notifications().unwrap().is_empty() {
            break;
        }
        drop(db);
        assert!(Instant::now() < deadline, "probation queue did not settle");
        thread::sleep(Duration::from_millis(25));
    }
    let manifest: serde_json::Value =
        serde_json::from_slice(&fs::read(data.join("engine/engine.json")).unwrap()).unwrap();
    thread::sleep(Duration::from_millis(100));
    manifest
}

fn clean(root: PathBuf) {
    for _ in 0..200 {
        if fs::remove_dir_all(&root).is_ok() {
            return;
        }
        thread::sleep(Duration::from_millis(50));
    }
    panic!("could not clean probation fixture {}", root.display());
}

fn crashing_probation_copy_restores_bundled_ytdlp_then_retries_once() {
    let (root, resources, paths, db) = fixture();
    let manifest = execute(&root, &resources, paths, Arc::clone(&db), "crash");
    assert_eq!(manifest["ytDlp"]["source"], "bundled");
    assert_eq!(manifest["revertedVersion"], "2026.10.21");
    assert!(manifest["failedVersions"]
        .as_array()
        .unwrap()
        .contains(&"2026.10.21".into()));
    let notifications = db.lock().unwrap().get_error_notifications().unwrap();
    assert_eq!(notifications.len(), 1);
    assert!(
        !format!("{:?}", notifications[0]).contains("stub process crash"),
        "the settled error must come from the one baseline retry"
    );
    drop(notifications);
    drop(db);
    clean(root);
}

fn reported_site_error_keeps_updated_copy_and_completes_probation() {
    let (root, resources, paths, db) = fixture();
    let manifest = execute(&root, &resources, paths, db, "site");
    assert_eq!(manifest["ytDlp"]["source"], "updated");
    assert_eq!(manifest["ytDlp"]["state"], "good");
    assert!(manifest.get("revertedVersion").is_none());
    clean(root);
}

fn malformed_analysis_json_triggers_one_baseline_retry() {
    let (root, resources, paths, db) = fixture();
    let manifest = execute(&root, &resources, paths, Arc::clone(&db), "malformed");
    assert_eq!(manifest["ytDlp"]["source"], "bundled");
    assert_eq!(manifest["revertedVersion"], "2026.10.21");
    drop(db);
    clean(root);
}

fn failed_baseline_health_reports_engine_missing_without_retry_loop() {
    let (root, _resources, paths, db) = fixture();
    let unavailable_resources = root.join("missing-resources");
    let manifest = execute(
        &root,
        &unavailable_resources,
        paths,
        Arc::clone(&db),
        "crash",
    );
    assert_eq!(manifest["ytDlp"]["source"], "updated");
    let notifications = db.lock().unwrap().get_error_notifications().unwrap();
    assert_eq!(notifications.len(), 1);
    assert_eq!(notifications[0].error.code, ErrorCode::EngineMissing);
    drop(notifications);
    drop(db);
    clean(root);
}

#[test]
fn probation_queue_scenarios() {
    crashing_probation_copy_restores_bundled_ytdlp_then_retries_once();
    reported_site_error_keeps_updated_copy_and_completes_probation();
    malformed_analysis_json_triggers_one_baseline_retry();
    failed_baseline_health_reports_engine_missing_without_retry_loop();
}
