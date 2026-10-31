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
pub mod updater;
pub mod zip_output;

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

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct EngineManifest {
    yt_dlp: YtDlpManifest,
    baseline_app_version: String,
    #[serde(default)]
    failed_versions: Vec<String>,
    #[serde(default)]
    manual_retry_versions: Vec<String>,
    #[serde(default)]
    last_update_check: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pending_version: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    reverted_version: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pending_sha256: Option<String>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct YtDlpManifest {
    version: String,
    source: String,
    state: String,
    installed_at: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    sha256: Option<String>,
}

pub(crate) fn hash_file(path: &Path) -> Result<String, String> {
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

fn probe_version(path: &Path, expected: &str) -> Result<(), String> {
    let supervisor = process::Supervisor::install().map_err(|error| error.to_string())?;
    let output = supervisor
        .run(
            path,
            &["--version".into()],
            PROBE_TIMEOUT,
            4096,
            &AtomicBool::new(false),
        )
        .map_err(|error| format!("yt-dlp version probe failed: {error}"))?;
    if !output.status.success() || String::from_utf8_lossy(&output.stdout).trim() != expected {
        return Err(format!("yt-dlp version probe did not report {expected}"));
    }
    Ok(())
}

fn health_check(paths: &EnginePaths, version: &str) -> Result<(), String> {
    probe_version(&paths.yt_dlp, version)?;
    probe(&paths.ffmpeg, &["-version"], "ffmpeg version 8.1.3")?;
    probe(
        &paths.quickjs,
        &["-e", "print('quickjs-ready')"],
        "quickjs-ready",
    )
}

pub(crate) fn read_manifest(data: &Path) -> Result<EngineManifest, String> {
    let path = data.join("engine/engine.json");
    let bytes = fs::read(&path).map_err(|error| format!("{}: {error}", path.display()))?;
    serde_json::from_slice(&bytes).map_err(|error| error.to_string())
}

pub(crate) fn write_manifest(data: &Path, manifest: &EngineManifest) -> Result<(), String> {
    let path = data.join("engine/engine.json");
    let temp = data.join("engine/engine.json.tmp");
    let mut file = File::create(&temp).map_err(|error| error.to_string())?;
    serde_json::to_writer_pretty(&mut file, manifest).map_err(|error| error.to_string())?;
    file.write_all(b"\n").map_err(|error| error.to_string())?;
    file.sync_all().map_err(|error| error.to_string())?;
    drop(file);
    fs::rename(&temp, &path).map_err(|error| error.to_string())
}

fn version_parts(value: &str) -> Option<Vec<u32>> {
    let parts = value
        .split('.')
        .map(str::parse::<u32>)
        .collect::<Result<Vec<_>, _>>()
        .ok()?;
    (parts.len() == 3).then_some(parts)
}

pub(crate) fn newer(left: &str, right: &str) -> bool {
    match (version_parts(left), version_parts(right)) {
        (Some(left), Some(right)) => left > right,
        _ => false,
    }
}

fn active_is_healthy(
    paths: &EnginePaths,
    manifest: &EngineManifest,
    hashes: &Hashes<'_>,
    check: &impl Fn(&EnginePaths, &str) -> Result<(), String>,
) -> bool {
    yt_is_verified(paths, manifest, hashes)
        && hash_file(&paths.ffmpeg).is_ok_and(|hash| hash == hashes.ffmpeg)
        && hash_file(&paths.quickjs).is_ok_and(|hash| hash == hashes.quickjs)
        && check(paths, &manifest.yt_dlp.version).is_ok()
}

fn yt_is_verified(paths: &EnginePaths, manifest: &EngineManifest, hashes: &Hashes<'_>) -> bool {
    if !matches!(manifest.yt_dlp.source.as_str(), "bundled" | "updated")
        || !matches!(manifest.yt_dlp.state.as_str(), "good" | "probation")
    {
        return false;
    }
    let expected = if manifest.yt_dlp.source == "bundled" {
        if manifest.yt_dlp.version != YT_DLP_VERSION {
            return false;
        }
        hashes.yt_dlp
    } else {
        match manifest.yt_dlp.sha256.as_deref() {
            Some(hash) if hash.len() == 64 => hash,
            _ => return false,
        }
    };
    hash_file(&paths.yt_dlp).is_ok_and(|hash| hash == expected)
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
            sha256: None,
        },
        baseline_app_version: app_version.to_owned(),
        failed_versions: Vec::new(),
        manual_retry_versions: Vec::new(),
        last_update_check: None,
        pending_version: None,
        reverted_version: None,
        pending_sha256: None,
    })
}

fn clean_orphaned_stages(data: &Path) {
    let root = fs::canonicalize(data).ok();
    if let Ok(entries) = fs::read_dir(data) {
        for entry in entries.flatten() {
            let name = entry.file_name();
            let name = name.to_string_lossy();
            if (name.starts_with(".engine-stage-") || name.starts_with(".engine-backup-"))
                && entry
                    .file_type()
                    .is_ok_and(|kind| kind.is_dir() && !kind.is_symlink())
                && root.as_ref().is_some_and(|root| {
                    fs::canonicalize(entry.path()).is_ok_and(|target| target.starts_with(root))
                })
            {
                let _ = fs::remove_dir_all(entry.path());
            }
        }
    }
}

fn prepare_with(
    resources: &Path,
    data: &Path,
    app_version: &str,
    hashes: &Hashes<'_>,
    check: impl Fn(&EnginePaths, &str) -> Result<(), String>,
    promote: impl Fn(&Path, &Path) -> std::io::Result<()>,
) -> Result<EnginePaths, String> {
    fs::create_dir_all(data).map_err(|error| error.to_string())?;
    let active = data.join("engine");
    // A crash between the two directory renames leaves only the previous set.
    if !active.exists() {
        let mut backups = fs::read_dir(data)
            .map_err(|error| error.to_string())?
            .filter_map(Result::ok)
            .map(|entry| entry.path())
            .filter(|path| {
                path.file_name()
                    .is_some_and(|name| name.to_string_lossy().starts_with(".engine-backup-"))
            })
            .collect::<Vec<_>>();
        backups.sort_by_key(|path| fs::metadata(path).and_then(|meta| meta.modified()).ok());
        if let Some(previous) = backups.pop() {
            fs::rename(previous, &active).map_err(|error| error.to_string())?;
        }
    }
    let active_paths = EnginePaths::in_dir(&active);
    let previous = read_manifest(data).ok();
    let healthy = previous
        .as_ref()
        .is_some_and(|manifest| active_is_healthy(&active_paths, manifest, hashes, &check));
    if healthy
        && previous
            .as_ref()
            .is_some_and(|manifest| manifest.baseline_app_version == app_version)
    {
        clean_orphaned_stages(data);
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
        let mut manifest = previous.clone().unwrap_or(make_manifest(app_version)?);
        let retain_updated = previous
            .as_ref()
            .is_some_and(|old| yt_is_verified(&active_paths, old, hashes))
            && manifest.yt_dlp.source == "updated"
            && !newer(YT_DLP_VERSION, &manifest.yt_dlp.version);
        if retain_updated {
            fs::copy(&active_paths.yt_dlp, &staged_paths.yt_dlp)
                .map_err(|error| error.to_string())?;
        } else {
            if manifest.yt_dlp.source == "updated" && !healthy {
                manifest
                    .failed_versions
                    .push(manifest.yt_dlp.version.clone());
                manifest.reverted_version = Some(manifest.yt_dlp.version.clone());
            }
            manifest.yt_dlp = make_manifest(app_version)?.yt_dlp;
        }
        manifest.baseline_app_version = app_version.to_owned();
        if manifest.pending_version.is_some() {
            let pending = active.join("staging/candidate.exe");
            if pending.is_file()
                && manifest
                    .pending_sha256
                    .as_deref()
                    .is_some_and(|hash| hash_file(&pending).is_ok_and(|actual| actual == hash))
            {
                fs::create_dir(stage.join("staging")).map_err(|error| error.to_string())?;
                fs::copy(pending, stage.join("staging/candidate.exe"))
                    .map_err(|error| error.to_string())?;
            } else {
                manifest.pending_version = None;
                manifest.pending_sha256 = None;
            }
        }
        if !retain_updated {
            verify_files(&staged_paths, hashes)?;
        } else {
            let expected = manifest
                .yt_dlp
                .sha256
                .as_deref()
                .ok_or("updated hash missing")?;
            if hash_file(&staged_paths.yt_dlp)? != expected {
                return Err("updated copy changed during staging".into());
            }
            for (path, hash) in [
                (&staged_paths.ffmpeg, hashes.ffmpeg),
                (&staged_paths.quickjs, hashes.quickjs),
            ] {
                if hash_file(path)? != hash {
                    return Err("baseline tool checksum mismatch".into());
                }
            }
        }
        check(&staged_paths, &manifest.yt_dlp.version)?;
        let mut file =
            File::create(stage.join("engine.json")).map_err(|error| error.to_string())?;
        serde_json::to_writer_pretty(&mut file, &manifest).map_err(|error| error.to_string())?;
        file.write_all(b"\n").map_err(|error| error.to_string())?;
        file.sync_all().map_err(|error| error.to_string())?;
        // Windows cannot rename the staged directory while this handle is open.
        drop(file);

        if active.exists() {
            updater::rename_after_probe(&active, &backup).map_err(|error| error.to_string())?;
        }
        if let Err(error) = promote(&stage, &active) {
            if backup.exists() {
                updater::rename_after_probe(&backup, &active).map_err(|rollback| {
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
        updater::rename_after_probe,
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
                |paths, _| {
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
            |_, _| Err("probe rejected candidate".into()),
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
            |_, _| Ok(()),
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
    fn healthy_updated_copy_and_manifest_survive_restart_and_app_refresh() {
        let fixture = Fixture::new();
        let paths = fixture.prepare("0.0.1").unwrap();
        fs::write(&paths.yt_dlp, b"updated yt-dlp stub").unwrap();
        let mut manifest = read_manifest(&fixture.data).unwrap();
        manifest.yt_dlp.version = "2026.10.21".into();
        manifest.yt_dlp.source = "updated".into();
        manifest.yt_dlp.state = "probation".into();
        manifest.yt_dlp.sha256 = Some(hash_file(&paths.yt_dlp).unwrap());
        manifest.failed_versions = vec!["2026.09.10".into()];
        manifest.last_update_check = Some("2026-10-28T10:00:00Z".into());
        write_manifest(&fixture.data, &manifest).unwrap();
        fixture.prepare("0.0.1").unwrap();
        assert_eq!(fs::read(&paths.yt_dlp).unwrap(), b"updated yt-dlp stub");
        fixture.prepare("0.0.2").unwrap();
        let restored = read_manifest(&fixture.data).unwrap();
        assert_eq!(restored.yt_dlp.version, "2026.10.21");
        assert_eq!(restored.yt_dlp.state, "probation");
        assert_eq!(restored.failed_versions, manifest.failed_versions);
        assert_eq!(restored.last_update_check, manifest.last_update_check);
        assert_eq!(restored.baseline_app_version, "0.0.2");
        assert_eq!(fs::read(&paths.yt_dlp).unwrap(), b"updated yt-dlp stub");
    }

    #[test]
    fn app_refresh_replaces_changed_tools_without_downgrading_updated_ytdlp() {
        let mut fixture = Fixture::new();
        let paths = fixture.prepare("0.0.1").unwrap();
        fs::write(&paths.yt_dlp, b"updated yt-dlp stub").unwrap();
        let mut manifest = read_manifest(&fixture.data).unwrap();
        manifest.yt_dlp.version = "2026.10.21".into();
        manifest.yt_dlp.source = "updated".into();
        manifest.yt_dlp.sha256 = Some(hash_file(&paths.yt_dlp).unwrap());
        write_manifest(&fixture.data, &manifest).unwrap();
        let resources = EnginePaths::in_dir(&fixture.resources);
        fs::write(&resources.ffmpeg, b"new ffmpeg").unwrap();
        fs::write(&resources.quickjs, b"new quickjs").unwrap();
        fixture.hashes[1] = hash_file(&resources.ffmpeg).unwrap();
        fixture.hashes[2] = hash_file(&resources.quickjs).unwrap();
        fixture.prepare("0.0.2").unwrap();
        assert_eq!(fs::read(&paths.yt_dlp).unwrap(), b"updated yt-dlp stub");
        assert_eq!(fs::read(&paths.ffmpeg).unwrap(), b"new ffmpeg");
        assert_eq!(fs::read(&paths.quickjs).unwrap(), b"new quickjs");
    }

    #[test]
    fn bundled_date_version_wins_only_when_newer_than_active_update() {
        for (active_version, expected_source) in [
            ("2026.07.04", "bundled"),
            (YT_DLP_VERSION, "updated"),
            ("2026.10.21", "updated"),
        ] {
            let fixture = Fixture::new();
            let paths = fixture.prepare("0.0.1").unwrap();
            fs::write(&paths.yt_dlp, b"updated yt-dlp stub").unwrap();
            let mut manifest = read_manifest(&fixture.data).unwrap();
            manifest.yt_dlp.version = active_version.into();
            manifest.yt_dlp.source = "updated".into();
            manifest.yt_dlp.sha256 = Some(hash_file(&paths.yt_dlp).unwrap());
            write_manifest(&fixture.data, &manifest).unwrap();
            fixture.prepare("0.0.2").unwrap();
            assert_eq!(
                read_manifest(&fixture.data).unwrap().yt_dlp.source,
                expected_source,
                "active version {active_version}"
            );
        }
    }

    #[test]
    fn verified_pending_candidate_survives_app_version_refresh() {
        let fixture = Fixture::new();
        fixture.prepare("0.0.1").unwrap();
        let staging = fixture.data.join("engine/staging");
        fs::create_dir_all(&staging).unwrap();
        let candidate = staging.join("candidate.exe");
        fs::write(&candidate, b"pending update").unwrap();
        let mut manifest = read_manifest(&fixture.data).unwrap();
        manifest.pending_version = Some("2026.10.21".into());
        manifest.pending_sha256 = Some(hash_file(&candidate).unwrap());
        write_manifest(&fixture.data, &manifest).unwrap();
        fixture.prepare("0.0.2").unwrap();
        assert_eq!(fs::read(&candidate).unwrap(), b"pending update");
        assert_eq!(
            read_manifest(&fixture.data)
                .unwrap()
                .pending_version
                .as_deref(),
            Some("2026.10.21")
        );
    }

    #[test]
    fn legacy_manifest_and_interrupted_directory_swap_recover() {
        let fixture = Fixture::new();
        fixture.prepare("0.0.1").unwrap();
        let manifest_path = fixture.data.join("engine/engine.json");
        let mut value: serde_json::Value =
            serde_json::from_slice(&fs::read(&manifest_path).unwrap()).unwrap();
        value.as_object_mut().unwrap().remove("pendingVersion");
        value.as_object_mut().unwrap().remove("revertedVersion");
        value.as_object_mut().unwrap().remove("pendingSha256");
        fs::write(&manifest_path, serde_json::to_vec(&value).unwrap()).unwrap();
        let backup = fixture.data.join(".engine-backup-interrupted");
        fs::rename(fixture.data.join("engine"), &backup).unwrap();
        let orphan = fixture.data.join(".engine-stage-orphan");
        fs::create_dir(&orphan).unwrap();
        fixture.prepare("0.0.1").unwrap();
        assert!(fixture.data.join("engine/engine.json").exists());
        assert!(!backup.exists());
        assert!(!orphan.exists());
    }

    #[test]
    fn corrupt_updated_copy_reverts_without_losing_failed_versions_or_clock() {
        let fixture = Fixture::new();
        let paths = fixture.prepare("0.0.1").unwrap();
        let mut manifest = read_manifest(&fixture.data).unwrap();
        manifest.yt_dlp.version = "2026.10.21".into();
        manifest.yt_dlp.source = "updated".into();
        manifest.yt_dlp.sha256 = Some("a".repeat(64));
        manifest.failed_versions.push("2026.09.10".into());
        manifest.last_update_check = Some("2026-10-28T10:00:00Z".into());
        write_manifest(&fixture.data, &manifest).unwrap();
        fs::write(&paths.yt_dlp, b"bad updated copy").unwrap();
        fixture.prepare("0.0.1").unwrap();
        let restored = read_manifest(&fixture.data).unwrap();
        assert_eq!(restored.yt_dlp.source, "bundled");
        assert!(restored.failed_versions.contains(&"2026.10.21".into()));
        assert!(restored.failed_versions.contains(&"2026.09.10".into()));
        assert_eq!(restored.last_update_check, manifest.last_update_check);
        verify_files(&paths, &fixture.hashes()).unwrap();
    }

    #[test]
    fn date_versions_are_compared_numerically() {
        assert!(newer("2026.10.01", "2026.09.30"));
        assert!(!newer("2026.08.19", "2026.08.19"));
        assert!(!newer("2026.07.04", "2026.08.19"));
        assert!(!newer("malformed", "2026.08.19"));
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
