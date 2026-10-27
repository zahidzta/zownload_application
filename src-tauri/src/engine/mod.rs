// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::{
    fs::{self, File},
    io::{Read, Write},
    path::{Path, PathBuf},
    sync::atomic::AtomicBool,
    time::Duration,
};
use time::{format_description::well_known::Rfc3339, OffsetDateTime};

pub mod analysis;
pub mod process;
pub mod queue;
pub mod single;

const YT_DLP_VERSION: &str = "2026.08.19";
const YT_DLP_HASH: &str = "66674953fe251b89f4d08c5f0e35e0728679bd67ab3d7d05c0562af101dd3e7a";
const FFMPEG_HASH: &str = "fa050630ddf5b7c3303d8dab5e5a42e7023547fb78ec9b90b5be0a4f788a7e66";
const QUICKJS_HASH: &str = "bec67f8f87fa22958d3ab8be5508088116b8bff90032323d82c94545e1698b83";
const PROBE_TIMEOUT: Duration = Duration::from_secs(10);

struct Hashes<'a> {
    yt_dlp: &'a str,
    ffmpeg: &'a str,
    quickjs: &'a str,
}

const BASELINE_HASHES: Hashes<'static> = Hashes {
    yt_dlp: YT_DLP_HASH,
    ffmpeg: FFMPEG_HASH,
    quickjs: QUICKJS_HASH,
};

#[derive(Debug)]
pub enum EngineStatus {
    Ready(EnginePaths),
    Unavailable(String),
}

#[derive(Clone, Debug)]
pub struct EnginePaths {
    pub yt_dlp: PathBuf,
    pub ffmpeg: PathBuf,
    pub quickjs: PathBuf,
}

impl EnginePaths {
    fn in_dir(dir: &Path) -> Self {
        Self {
            yt_dlp: dir.join("yt-dlp.exe"),
            ffmpeg: dir.join("ffmpeg.exe"),
            quickjs: dir.join("qjs.exe"),
        }
    }

    fn entries<'a>(&'a self, hashes: &'a Hashes<'_>) -> [(&'a Path, &'a str); 3] {
        [
            (&self.yt_dlp, hashes.yt_dlp),
            (&self.ffmpeg, hashes.ffmpeg),
            (&self.quickjs, hashes.quickjs),
        ]
    }
}

#[derive(Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct EngineManifest {
    yt_dlp: YtDlpManifest,
    baseline_app_version: String,
    failed_versions: Vec<String>,
    last_update_check: Option<String>,
}

#[derive(Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct YtDlpManifest {
    version: String,
    source: String,
    state: String,
    installed_at: String,
}

fn hash_file(path: &Path) -> Result<String, String> {
    let mut file = File::open(path).map_err(|error| format!("{}: {error}", path.display()))?;
    let mut hash = Sha256::new();
    let mut chunk = [0u8; 64 * 1024];
    loop {
        let count = file.read(&mut chunk).map_err(|error| error.to_string())?;
        if count == 0 {
            break;
        }
        hash.update(&chunk[..count]);
    }
    Ok(format!("{:x}", hash.finalize()))
}

fn verify_files(paths: &EnginePaths, hashes: &Hashes<'_>) -> Result<(), String> {
    for (path, expected) in paths.entries(hashes) {
        if hash_file(path)? != expected {
            return Err(format!("baseline checksum mismatch: {}", path.display()));
        }
    }
    Ok(())
}

fn probe(path: &Path, args: &[&str], expected: &str) -> Result<(), String> {
    let supervisor = process::Supervisor::install().map_err(|error| error.to_string())?;
    let args = args
        .iter()
        .map(std::ffi::OsString::from)
        .collect::<Vec<_>>();
    let output = supervisor
        .run(path, &args, PROBE_TIMEOUT, 4096, &AtomicBool::new(false))
        .map_err(|error| format!("health probe failed for {}: {error}", path.display()))?;
    let value = String::from_utf8_lossy(&output.stdout);
    if !output.status.success() || !value.contains(expected) {
        return Err(format!(
            "health probe failed for {}: {}; {value}",
            path.display(),
            output.status
        ));
    }
    Ok(())
}

fn health_check(paths: &EnginePaths) -> Result<(), String> {
    probe(&paths.yt_dlp, &["--version"], YT_DLP_VERSION)?;
    probe(&paths.ffmpeg, &["-version"], "ffmpeg version 8.1.3")?;
    probe(
        &paths.quickjs,
        &["-e", "print('quickjs-ready')"],
        "quickjs-ready",
    )
}

fn valid_manifest(path: &Path, app_version: &str) -> bool {
    let Ok(bytes) = fs::read(path) else {
        return false;
    };
    let Ok(manifest) = serde_json::from_slice::<EngineManifest>(&bytes) else {
        return false;
    };
    manifest.baseline_app_version == app_version
        && manifest.yt_dlp.version == YT_DLP_VERSION
        && manifest.yt_dlp.source == "bundled"
        && manifest.yt_dlp.state == "good"
}

fn make_manifest(app_version: &str) -> Result<EngineManifest, String> {
    let installed_at = OffsetDateTime::now_utc()
        .format(&Rfc3339)
        .map_err(|error| error.to_string())?;
    Ok(EngineManifest {
        yt_dlp: YtDlpManifest {
            version: YT_DLP_VERSION.to_owned(),
            source: "bundled".to_owned(),
            state: "good".to_owned(),
            installed_at,
        },
        baseline_app_version: app_version.to_owned(),
        failed_versions: Vec::new(),
        last_update_check: None,
    })
}

fn prepare_with(
    resources: &Path,
    data: &Path,
    app_version: &str,
    hashes: &Hashes<'_>,
    check: impl Fn(&EnginePaths) -> Result<(), String>,
    promote: impl Fn(&Path, &Path) -> std::io::Result<()>,
) -> Result<EnginePaths, String> {
    fs::create_dir_all(data).map_err(|error| error.to_string())?;
    let active = data.join("engine");
    let active_paths = EnginePaths::in_dir(&active);
    if valid_manifest(&active.join("engine.json"), app_version)
        && verify_files(&active_paths, hashes).is_ok()
        && check(&active_paths).is_ok()
    {
        return Ok(active_paths);
    }

    // Only the pinned installation resources may become an active engine.
    let source_paths = EnginePaths::in_dir(resources);
    verify_files(&source_paths, hashes)?;
    let id = uuid::Uuid::new_v4();
    let stage = data.join(format!(".engine-stage-{id}"));
    let backup = data.join(format!(".engine-backup-{id}"));
    fs::create_dir(&stage).map_err(|error| error.to_string())?;
    let result = (|| {
        let staged_paths = EnginePaths::in_dir(&stage);
        for ((source, _), (destination, _)) in source_paths
            .entries(hashes)
            .iter()
            .zip(staged_paths.entries(hashes))
        {
            fs::copy(source, destination).map_err(|error| error.to_string())?;
        }
        verify_files(&staged_paths, hashes)?;
        check(&staged_paths)?;
        let manifest = make_manifest(app_version)?;
        let mut file =
            File::create(stage.join("engine.json")).map_err(|error| error.to_string())?;
        serde_json::to_writer_pretty(&mut file, &manifest).map_err(|error| error.to_string())?;
        file.write_all(b"\n").map_err(|error| error.to_string())?;
        file.sync_all().map_err(|error| error.to_string())?;
        // Windows cannot rename the staged directory while this handle is open.
        drop(file);

        if active.exists() {
            fs::rename(&active, &backup).map_err(|error| error.to_string())?;
        }
        if let Err(error) = promote(&stage, &active) {
            if backup.exists() {
                fs::rename(&backup, &active).map_err(|rollback| {
                    format!("activation failed: {error}; rollback failed: {rollback}")
                })?;
            }
            return Err(format!("activation failed: {error}"));
        }
        Ok(active_paths)
    })();
    if stage.exists() {
        let _ = fs::remove_dir_all(&stage);
    }
    if backup.exists() && active.exists() {
        let _ = fs::remove_dir_all(&backup);
    }
    result
}

pub fn bootstrap(resources: &Path, data: &Path, app_version: &str) -> EngineStatus {
    match prepare_with(
        resources,
        data,
        app_version,
        &BASELINE_HASHES,
        health_check,
        |from, to| fs::rename(from, to),
    ) {
        Ok(paths) => EngineStatus::Ready(paths),
        Err(reason) => EngineStatus::Unavailable(reason),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    struct Fixture {
        root: PathBuf,
        resources: PathBuf,
        data: PathBuf,
        hashes: [String; 3],
    }

    impl Fixture {
        fn new() -> Self {
            let root =
                std::env::temp_dir().join(format!("zownload-engine-test-{}", uuid::Uuid::new_v4()));
            let resources = root.join("resources");
            let data = root.join("data");
            fs::create_dir_all(&resources).unwrap();
            let files = EnginePaths::in_dir(&resources);
            fs::write(&files.yt_dlp, b"yt-dlp stub").unwrap();
            fs::write(&files.ffmpeg, b"ffmpeg stub").unwrap();
            fs::write(&files.quickjs, b"quickjs stub").unwrap();
            let hashes = [
                hash_file(&files.yt_dlp).unwrap(),
                hash_file(&files.ffmpeg).unwrap(),
                hash_file(&files.quickjs).unwrap(),
            ];
            Self {
                root,
                resources,
                data,
                hashes,
            }
        }

        fn hashes(&self) -> Hashes<'_> {
            Hashes {
                yt_dlp: &self.hashes[0],
                ffmpeg: &self.hashes[1],
                quickjs: &self.hashes[2],
            }
        }

        fn prepare(&self, version: &str) -> Result<EnginePaths, String> {
            prepare_with(
                &self.resources,
                &self.data,
                version,
                &self.hashes(),
                |paths| {
                    assert!(paths.yt_dlp.starts_with(&self.data));
                    assert!(paths.ffmpeg.starts_with(&self.data));
                    assert!(paths.quickjs.starts_with(&self.data));
                    Ok(())
                },
                |from, to| fs::rename(from, to),
            )
        }
    }

    impl Drop for Fixture {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.root);
        }
    }

    #[test]
    fn first_launch_writes_verified_copies_and_manifest_under_app_data() {
        let fixture = Fixture::new();
        let paths = fixture.prepare("0.0.1").unwrap();
        verify_files(&paths, &fixture.hashes()).unwrap();
        let manifest = fs::read_to_string(fixture.data.join("engine/engine.json")).unwrap();
        let value: serde_json::Value = serde_json::from_str(&manifest).unwrap();
        assert_eq!(value["ytDlp"]["version"], YT_DLP_VERSION);
        assert_eq!(value["ytDlp"]["source"], "bundled");
        assert_eq!(value["ytDlp"]["state"], "good");
        assert!(value["ytDlp"]["installedAt"]
            .as_str()
            .unwrap()
            .ends_with('Z'));
        assert_eq!(value["baselineAppVersion"], "0.0.1");
        assert_eq!(value["failedVersions"], serde_json::json!([]));
        assert!(value["lastUpdateCheck"].is_null());
    }

    #[test]
    fn healthy_reopen_uses_app_data_without_install_resources() {
        let fixture = Fixture::new();
        fixture.prepare("0.0.1").unwrap();
        let before = fs::read(fixture.data.join("engine/engine.json")).unwrap();
        fs::remove_dir_all(&fixture.resources).unwrap();
        fixture.prepare("0.0.1").unwrap();
        assert_eq!(
            fs::read(fixture.data.join("engine/engine.json")).unwrap(),
            before
        );
    }

    #[test]
    fn corrupt_active_copy_is_replaced_from_verified_resources() {
        let fixture = Fixture::new();
        fixture.prepare("0.0.1").unwrap();
        fs::write(fixture.data.join("engine/yt-dlp.exe"), b"corrupt").unwrap();
        let paths = fixture.prepare("0.0.1").unwrap();
        verify_files(&paths, &fixture.hashes()).unwrap();
    }

    #[test]
    fn missing_or_corrupt_resources_are_rejected_before_activation() {
        let fixture = Fixture::new();
        let yt = fixture.resources.join("yt-dlp.exe");
        fs::remove_file(&yt).unwrap();
        assert!(fixture.prepare("0.0.1").is_err());
        assert!(!fixture.data.join("engine").exists());
        fs::write(&yt, b"wrong").unwrap();
        assert!(fixture
            .prepare("0.0.1")
            .unwrap_err()
            .contains("checksum mismatch"));
        assert!(!fixture.data.join("engine").exists());
    }

    #[test]
    fn failed_probe_preserves_prior_healthy_set() {
        let fixture = Fixture::new();
        fixture.prepare("0.0.1").unwrap();
        let before = fs::read(fixture.data.join("engine/engine.json")).unwrap();
        let result = prepare_with(
            &fixture.resources,
            &fixture.data,
            "0.0.2",
            &fixture.hashes(),
            |_| Err("probe rejected candidate".into()),
            |from, to| fs::rename(from, to),
        );
        assert!(result.unwrap_err().contains("probe rejected"));
        assert_eq!(
            fs::read(fixture.data.join("engine/engine.json")).unwrap(),
            before
        );
        verify_files(
            &EnginePaths::in_dir(&fixture.data.join("engine")),
            &fixture.hashes(),
        )
        .unwrap();
        assert_eq!(fs::read_dir(&fixture.data).unwrap().count(), 1);
    }

    #[test]
    fn failed_activation_rolls_back_prior_set() {
        let fixture = Fixture::new();
        fixture.prepare("0.0.1").unwrap();
        let before = fs::read(fixture.data.join("engine/engine.json")).unwrap();
        let result = prepare_with(
            &fixture.resources,
            &fixture.data,
            "0.0.2",
            &fixture.hashes(),
            |_| Ok(()),
            |_, _| Err(std::io::Error::other("simulated rename failure")),
        );
        assert!(result.unwrap_err().contains("activation failed"));
        assert_eq!(
            fs::read(fixture.data.join("engine/engine.json")).unwrap(),
            before
        );
        assert_eq!(fs::read_dir(&fixture.data).unwrap().count(), 1);
    }

    #[test]
    fn real_pinned_resources_pass_health_checks_only_after_app_data_copy() {
        if std::env::var_os("ZOWNLOAD_TEST_REAL_ENGINE").is_none() {
            return;
        }
        let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
        let resources = root.join("resources/windows-engine");
        let data =
            std::env::temp_dir().join(format!("zownload-real-engine-{}", uuid::Uuid::new_v4()));
        let result = bootstrap(&resources, &data, "0.0.1");
        match result {
            EngineStatus::Ready(paths) => {
                assert!(paths.yt_dlp.starts_with(&data));
                assert!(paths.ffmpeg.starts_with(&data));
                assert!(paths.quickjs.starts_with(&data));
                verify_files(&paths, &BASELINE_HASHES).unwrap();
            }
            EngineStatus::Unavailable(reason) => {
                panic!("real baseline health check failed: {reason}")
            }
        }
        fs::remove_dir_all(data).unwrap();
    }
}
