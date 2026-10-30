// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

//! Verify the official release checksum before probing or activating yt-dlp.

use super::{
    hash_file, newer, read_manifest, write_manifest, EngineManifest, EnginePaths, BASELINE_HASHES,
    YT_DLP_VERSION,
};
use crate::contract::{EngineUpdateInfo, EngineUpdateOutcome};
use reqwest::{blocking::Client, redirect::Policy, Url};
use serde::Deserialize;
use std::{
    fs::{self, File},
    io::{self, Read, Write},
    path::Path,
    sync::{Mutex, MutexGuard, OnceLock, RwLock, RwLockReadGuard, RwLockWriteGuard},
    thread,
    time::{Duration, Instant},
};

const OFFICIAL_API: &str = "https://api.github.com/repos/yt-dlp/yt-dlp/releases/latest";
const MAX_RELEASE_JSON: u64 = 128 * 1024;
const MAX_CHECKSUMS: u64 = 32 * 1024;
const MAX_EXECUTABLE: u64 = 64 * 1024 * 1024;

static ENGINE_SLOT: OnceLock<RwLock<()>> = OnceLock::new();
static MANIFEST_SLOT: OnceLock<Mutex<()>> = OnceLock::new();
static PROBATION_SLOT: OnceLock<Mutex<()>> = OnceLock::new();

pub(crate) fn slot() -> &'static RwLock<()> {
    ENGINE_SLOT.get_or_init(|| RwLock::new(()))
}

fn manifest_slot() -> &'static Mutex<()> {
    MANIFEST_SLOT.get_or_init(|| Mutex::new(()))
}

fn probation_slot() -> &'static Mutex<()> {
    PROBATION_SLOT.get_or_init(|| Mutex::new(()))
}

pub(crate) fn begin_invocation(
    data: &Path,
) -> Result<
    (
        RwLockReadGuard<'static, ()>,
        Option<MutexGuard<'static, ()>>,
        Option<String>,
    ),
    String,
> {
    // Acquire the probation gate before the shared executable slot. Good
    // versions release it immediately, so analyses can run during downloads.
    let probation_guard = probation_slot()
        .lock()
        .map_err(|_| "probation slot poisoned")?;
    let read_guard = slot().read().map_err(|_| "engine slot poisoned")?;
    let version = probation_version(data);
    let probation_guard = if version.is_some() {
        Some(probation_guard)
    } else {
        None
    };
    Ok((read_guard, probation_guard, version))
}

#[derive(Deserialize)]
struct Release {
    tag_name: String,
    draft: bool,
    prerelease: bool,
    assets: Vec<Asset>,
}

#[derive(Deserialize)]
struct Asset {
    name: String,
    browser_download_url: String,
}

#[derive(Clone, Debug)]
pub(crate) struct Candidate {
    pub version: String,
    executable_url: String,
    checksums_url: String,
}

pub(crate) struct ReleaseClient {
    client: Client,
    endpoint: String,
    official: bool,
}

fn official_redirect(url: &Url) -> bool {
    url.scheme() == "https"
        && matches!(
            url.host_str(),
            Some(
                "github.com"
                    | "api.github.com"
                    | "release-assets.githubusercontent.com"
                    | "objects.githubusercontent.com"
            )
        )
}

impl ReleaseClient {
    pub(crate) fn official() -> Result<Self, String> {
        Self::new(OFFICIAL_API, true)
    }

    fn new(endpoint: &str, official: bool) -> Result<Self, String> {
        let policy = Policy::custom(move |attempt| {
            if attempt.previous().len() >= 5 || (official && !official_redirect(attempt.url())) {
                attempt.error("release redirect rejected")
            } else {
                attempt.follow()
            }
        });
        let client = Client::builder()
            .tls_backend_rustls()
            .redirect(policy)
            .connect_timeout(Duration::from_secs(10))
            .timeout(Duration::from_secs(90))
            .user_agent("Zownload/2D yt-dlp updater")
            .build()
            .map_err(|error| error.to_string())?;
        Ok(Self {
            client,
            endpoint: endpoint.into(),
            official,
        })
    }

    fn validate_url(&self, value: &str, version: &str, name: &str) -> Result<(), String> {
        let url = Url::parse(value).map_err(|error| error.to_string())?;
        if self.official {
            let expected = format!("/yt-dlp/yt-dlp/releases/download/{version}/{name}");
            if url.scheme() != "https"
                || url.host_str() != Some("github.com")
                || url.path() != expected
                || url.query().is_some()
                || url.fragment().is_some()
            {
                return Err(format!(
                    "release asset URL is outside official release: {name}"
                ));
            }
        } else {
            let base = Url::parse(&self.endpoint).map_err(|error| error.to_string())?;
            if url.origin() != base.origin() {
                return Err("fixture asset origin mismatch".into());
            }
        }
        Ok(())
    }

    fn open(&self, url: &str, maximum: u64) -> Result<reqwest::blocking::Response, String> {
        let response = self
            .client
            .get(url)
            .send()
            .map_err(|error| error.to_string())?;
        if !response.status().is_success() {
            return Err(format!("release HTTP {}", response.status()));
        }
        if response.content_length().is_some_and(|size| size > maximum) {
            return Err("release response too large".into());
        }
        Ok(response)
    }

    fn small(&self, url: &str, maximum: u64) -> Result<Vec<u8>, String> {
        let response = self.open(url, maximum)?;
        let mut bytes = Vec::new();
        response
            .take(maximum + 1)
            .read_to_end(&mut bytes)
            .map_err(|error| error.to_string())?;
        if bytes.len() as u64 > maximum {
            return Err("release response too large".into());
        }
        Ok(bytes)
    }

    pub(crate) fn latest(&self) -> Result<Candidate, String> {
        let body = self.small(&self.endpoint, MAX_RELEASE_JSON)?;
        let release: Release = serde_json::from_slice(&body).map_err(|error| error.to_string())?;
        if release.draft || release.prerelease || super::version_parts(&release.tag_name).is_none()
        {
            return Err("latest release is not a stable date version".into());
        }
        let asset = |name: &str| -> Result<String, String> {
            let matches = release
                .assets
                .iter()
                .filter(|asset| asset.name == name)
                .collect::<Vec<_>>();
            if matches.len() != 1 {
                return Err(format!("release needs one {name} asset"));
            }
            let url = &matches[0].browser_download_url;
            self.validate_url(url, &release.tag_name, name)?;
            Ok(url.clone())
        };
        Ok(Candidate {
            executable_url: asset("yt-dlp.exe")?,
            checksums_url: asset("SHA2-256SUMS")?,
            version: release.tag_name,
        })
    }

    pub(crate) fn update_info(
        &self,
        data: &Path,
        latest: &str,
    ) -> Result<EngineUpdateInfo, String> {
        let manifest = read_manifest(data)?;
        let failed = newer(latest, &manifest.yt_dlp.version)
            && manifest.failed_versions.contains(&latest.to_owned());
        let retry_available =
            failed && !manifest.manual_retry_versions.contains(&latest.to_owned());
        let pending = manifest.pending_version.as_deref() == Some(latest);
        let update_available =
            newer(latest, &manifest.yt_dlp.version) && !pending && (!failed || retry_available);
        let outcome = if pending {
            EngineUpdateOutcome::Pending
        } else if manifest.reverted_version.as_deref() == Some(latest) {
            EngineUpdateOutcome::Reverted
        } else if update_available {
            EngineUpdateOutcome::Available
        } else if failed {
            EngineUpdateOutcome::Failed
        } else if manifest.reverted_version.is_some() {
            EngineUpdateOutcome::Reverted
        } else {
            EngineUpdateOutcome::Current
        };
        Ok(EngineUpdateInfo {
            current: manifest.yt_dlp.version.clone(),
            latest: latest.to_owned(),
            update_available,
            outcome: Some(outcome),
            pending_version: manifest.pending_version,
            reverted_version: manifest.reverted_version,
            failed_version: failed.then(|| latest.to_owned()),
            manual_retry_available: failed.then_some(retry_available),
        })
    }

    /// Startup checks update the clock before contacting GitHub, so a network
    /// failure does not cause a request every time the app is opened.
    pub(crate) fn startup_check(
        &self,
        data: &Path,
        now: time::OffsetDateTime,
    ) -> Result<bool, String> {
        if !record_daily_check(data, now)? {
            return Ok(false);
        }
        let candidate = self.latest()?;
        let manifest = read_manifest(data)?;
        if !newer(&candidate.version, &manifest.yt_dlp.version)
            || manifest.failed_versions.contains(&candidate.version)
        {
            return Ok(false);
        }
        self.stage(data, &candidate)
    }

    /// A failed release is excluded from automatic checks. The Settings action
    /// can claim exactly one retry, persisted before any download starts.
    pub(crate) fn update_manually(
        &self,
        data: &Path,
        candidate: &Candidate,
    ) -> Result<bool, String> {
        let retry = claim_manual_retry(data, &candidate.version)?;
        self.stage_with_retry(data, candidate, retry, super::probe_version)
    }

    fn download(&self, url: &str, target: &Path) -> Result<(), String> {
        let response = self.open(url, MAX_EXECUTABLE)?;
        let mut file = File::create(target).map_err(|error| error.to_string())?;
        let count = io::copy(&mut response.take(MAX_EXECUTABLE + 1), &mut file)
            .map_err(|error| error.to_string())?;
        if count > MAX_EXECUTABLE {
            return Err("release asset too large".into());
        }
        file.flush().map_err(|error| error.to_string())?;
        file.sync_all().map_err(|error| error.to_string())
    }

    pub(crate) fn stage(&self, data: &Path, candidate: &Candidate) -> Result<bool, String> {
        self.stage_with(data, candidate, super::probe_version)
    }

    fn stage_with_retry(
        &self,
        data: &Path,
        candidate: &Candidate,
        allow_failed_retry: bool,
        check: impl Fn(&Path, &str) -> Result<(), String>,
    ) -> Result<bool, String> {
        self.stage_inner(data, candidate, allow_failed_retry, check)
    }

    fn stage_with(
        &self,
        data: &Path,
        candidate: &Candidate,
        check: impl Fn(&Path, &str) -> Result<(), String>,
    ) -> Result<bool, String> {
        self.stage_inner(data, candidate, false, check)
    }

    fn stage_inner(
        &self,
        data: &Path,
        candidate: &Candidate,
        allow_failed_retry: bool,
        check: impl Fn(&Path, &str) -> Result<(), String>,
    ) -> Result<bool, String> {
        let _manifest_guard = manifest_slot()
            .lock()
            .map_err(|_| "manifest slot poisoned")?;
        let mut manifest = read_manifest(data)?;
        if !newer(&candidate.version, &manifest.yt_dlp.version) {
            return Ok(false);
        }
        if manifest.failed_versions.contains(&candidate.version) && !allow_failed_retry {
            return Ok(false);
        }
        if manifest.pending_version.is_some() {
            return Err("verified update is already pending activation".into());
        }
        let original_manifest = manifest.clone();
        let checksums = self.small(&candidate.checksums_url, MAX_CHECKSUMS)?;
        let expected = checksum_for(&checksums, "yt-dlp.exe")?;
        let staging = data.join("engine/staging");
        fs::create_dir_all(&staging).map_err(|error| error.to_string())?;
        let temporary = staging.join("candidate-download.exe");
        let ready = staging.join("candidate.exe");
        let result = (|| {
            self.download(&candidate.executable_url, &temporary)?;
            if hash_file(&temporary)? != expected {
                return Err("release checksum mismatch".into());
            }
            // Never execute an unverified candidate.
            check(&temporary, &candidate.version)?;
            if ready.exists() {
                fs::remove_file(&ready).map_err(|error| error.to_string())?;
            }
            rename_after_probe(&temporary, &ready).map_err(|error| error.to_string())?;
            manifest.pending_version = Some(candidate.version.clone());
            manifest.pending_sha256 = Some(expected);
            write_manifest(data, &manifest)
        })();
        if result.is_err() {
            let _ = fs::remove_file(&temporary);
            let mut failed = original_manifest;
            if !failed.failed_versions.contains(&candidate.version) {
                failed.failed_versions.push(candidate.version.clone());
            }
            let _ = write_manifest(data, &failed);
        }
        result.map(|()| true)
    }
}

fn record_daily_check(data: &Path, now: time::OffsetDateTime) -> Result<bool, String> {
    let _manifest_guard = manifest_slot()
        .lock()
        .map_err(|_| "manifest slot poisoned")?;
    let mut manifest = read_manifest(data)?;
    let cutoff = (now - time::Duration::hours(24))
        .format(&time::format_description::well_known::Rfc3339)
        .map_err(|error| error.to_string())?;
    if manifest
        .last_update_check
        .as_deref()
        .is_some_and(|last| last > cutoff.as_str())
    {
        return Ok(false);
    }
    manifest.last_update_check = Some(
        now.format(&time::format_description::well_known::Rfc3339)
            .map_err(|error| error.to_string())?,
    );
    write_manifest(data, &manifest)?;
    Ok(true)
}

fn claim_manual_retry(data: &Path, version: &str) -> Result<bool, String> {
    let _manifest_guard = manifest_slot()
        .lock()
        .map_err(|_| "manifest slot poisoned")?;
    let mut manifest = read_manifest(data)?;
    if !manifest
        .failed_versions
        .iter()
        .any(|failed| failed == version)
    {
        return Ok(false);
    }
    if manifest
        .manual_retry_versions
        .iter()
        .any(|retried| retried == version)
    {
        return Err(format!("manual retry already used for {version}"));
    }
    manifest.manual_retry_versions.push(version.to_owned());
    write_manifest(data, &manifest)?;
    Ok(true)
}

fn checksum_for(bytes: &[u8], filename: &str) -> Result<String, String> {
    let text = std::str::from_utf8(bytes).map_err(|error| error.to_string())?;
    let found = text
        .lines()
        .filter_map(|line| {
            let (hash, name) = line.split_once(char::is_whitespace)?;
            let name = name.trim().trim_start_matches('*');
            (name == filename
                && hash.len() == 64
                && hash.bytes().all(|byte| byte.is_ascii_hexdigit()))
            .then(|| hash.to_ascii_lowercase())
        })
        .collect::<Vec<_>>();
    if found.len() != 1 {
        return Err(format!("checksum file needs exactly one {filename} entry"));
    }
    Ok(found[0].clone())
}

pub(super) fn rename_after_probe(from: &Path, to: &Path) -> io::Result<()> {
    // Windows can keep an exited executable's image section open briefly.
    // Activation callers hold the engine slot; staging uses the same bounded
    // wait after its candidate probe has exited.
    let deadline = Instant::now() + Duration::from_secs(5);
    loop {
        match fs::rename(from, to) {
            Ok(()) => return Ok(()),
            Err(error)
                if Instant::now() < deadline
                    && (error.kind() == io::ErrorKind::PermissionDenied
                        || matches!(error.raw_os_error(), Some(5 | 32))) =>
            {
                thread::sleep(Duration::from_millis(50));
            }
            Err(error) => return Err(error),
        }
    }
}

fn replace_dir(
    data: &Path,
    source: &EnginePaths,
    manifest: &EngineManifest,
    expected_hash: &str,
    check: impl Fn(&EnginePaths, &str) -> Result<(), String>,
) -> Result<(), String> {
    let stage = data.join(format!(".engine-stage-{}", uuid::Uuid::new_v4()));
    let backup = data.join(format!(".engine-backup-{}", uuid::Uuid::new_v4()));
    fs::create_dir(&stage).map_err(|error| error.to_string())?;
    let result = (|| {
        let target = EnginePaths::in_dir(&stage);
        fs::copy(&source.yt_dlp, &target.yt_dlp).map_err(|error| error.to_string())?;
        fs::copy(&source.ffmpeg, &target.ffmpeg).map_err(|error| error.to_string())?;
        fs::copy(&source.quickjs, &target.quickjs).map_err(|error| error.to_string())?;
        if hash_file(&target.yt_dlp)? != expected_hash
            || hash_file(&target.ffmpeg)? != BASELINE_HASHES.ffmpeg
            || hash_file(&target.quickjs)? != BASELINE_HASHES.quickjs
        {
            return Err("staged engine checksum mismatch".into());
        }
        check(&target, &manifest.yt_dlp.version)?;
        let mut file =
            File::create(stage.join("engine.json")).map_err(|error| error.to_string())?;
        serde_json::to_writer_pretty(&mut file, manifest).map_err(|error| error.to_string())?;
        file.sync_all().map_err(|error| error.to_string())?;
        drop(file);
        let active = data.join("engine");
        rename_after_probe(&active, &backup).map_err(|error| error.to_string())?;
        if let Err(error) = rename_after_probe(&stage, &active) {
            rename_after_probe(&backup, &active).map_err(|rollback| {
                format!("activation failed: {error}; rollback failed: {rollback}")
            })?;
            return Err(format!("activation failed: {error}"));
        }
        Ok(())
    })();
    if stage.exists() {
        let _ = fs::remove_dir_all(&stage);
    }
    if backup.exists() && data.join("engine").exists() {
        let _ = fs::remove_dir_all(&backup);
    }
    result
}

pub(crate) fn activate_pending(data: &Path) -> Result<Option<String>, String> {
    let _probation_guard = probation_slot()
        .lock()
        .map_err(|_| "probation slot poisoned")?;
    let _guard = slot().write().map_err(|_| "engine slot poisoned")?;
    let _manifest_guard = manifest_slot()
        .lock()
        .map_err(|_| "manifest slot poisoned")?;
    let mut manifest = read_manifest(data)?;
    let Some(version) = manifest.pending_version.clone() else {
        return Ok(None);
    };
    let expected = manifest
        .pending_sha256
        .as_deref()
        .ok_or("pending checksum missing")?
        .to_owned();
    let candidate = data.join("engine/staging/candidate.exe");
    if hash_file(&candidate).ok().as_deref() != Some(expected.as_str()) {
        manifest.pending_version = None;
        manifest.pending_sha256 = None;
        if !manifest.failed_versions.contains(&version) {
            manifest.failed_versions.push(version);
        }
        write_manifest(data, &manifest)?;
        return Err("pending candidate missing or changed".into());
    }
    let mut promoted = manifest;
    promoted.yt_dlp.version = version.clone();
    promoted.yt_dlp.source = "updated".into();
    promoted.yt_dlp.state = "probation".into();
    promoted.yt_dlp.sha256 = Some(expected.clone());
    promoted.yt_dlp.installed_at = time::OffsetDateTime::now_utc()
        .format(&time::format_description::well_known::Rfc3339)
        .map_err(|error| error.to_string())?;
    promoted.pending_version = None;
    promoted.pending_sha256 = None;
    promoted.reverted_version = None;
    let active = EnginePaths::in_dir(&data.join("engine"));
    let source = EnginePaths {
        yt_dlp: candidate,
        ffmpeg: active.ffmpeg,
        quickjs: active.quickjs,
    };
    if let Err(reason) = replace_dir(data, &source, &promoted, &expected, |paths, version| {
        super::probe_version(&paths.yt_dlp, version)
    }) {
        if reason.contains("version probe") || reason.contains("checksum mismatch") {
            let mut failed = read_manifest(data)?;
            failed.pending_version = None;
            failed.pending_sha256 = None;
            if !failed.failed_versions.contains(&version) {
                failed.failed_versions.push(version.clone());
            }
            write_manifest(data, &failed)?;
        }
        return Err(reason);
    }
    Ok(Some(version))
}

pub(crate) fn mark_good(data: &Path, version: &str) -> Result<(), String> {
    let _manifest_guard = manifest_slot()
        .lock()
        .map_err(|_| "manifest slot poisoned")?;
    let mut manifest = read_manifest(data)?;
    if manifest.yt_dlp.state == "probation" && manifest.yt_dlp.version == version {
        manifest.yt_dlp.state = "good".into();
        write_manifest(data, &manifest)?;
    }
    Ok(())
}

pub(crate) fn probation_version(data: &Path) -> Option<String> {
    read_manifest(data).ok().and_then(|manifest| {
        (manifest.yt_dlp.state == "probation").then_some(manifest.yt_dlp.version)
    })
}

pub(crate) fn restore_baseline(
    data: &Path,
    resources: &Path,
    expected_version: &str,
) -> Result<String, String> {
    let _probation_guard = probation_slot()
        .lock()
        .map_err(|_| "probation slot poisoned")?;
    let guard = slot().write().map_err(|_| "engine slot poisoned")?;
    restore_baseline_locked(data, resources, expected_version, &guard)
}

pub(crate) fn restore_baseline_locked(
    data: &Path,
    resources: &Path,
    expected_version: &str,
    _lease: &RwLockWriteGuard<'_, ()>,
) -> Result<String, String> {
    let _manifest_guard = manifest_slot()
        .lock()
        .map_err(|_| "manifest slot poisoned")?;
    let mut manifest = read_manifest(data)?;
    if manifest.yt_dlp.state != "probation" || manifest.yt_dlp.version != expected_version {
        return Err("engine probation version changed".into());
    }
    let broken = manifest.yt_dlp.version.clone();
    let bundled = EnginePaths::in_dir(resources);
    if hash_file(&bundled.yt_dlp)? != BASELINE_HASHES.yt_dlp {
        return Err("bundled yt-dlp checksum mismatch".into());
    }
    let active = EnginePaths::in_dir(&data.join("engine"));
    manifest.yt_dlp.version = YT_DLP_VERSION.into();
    manifest.yt_dlp.source = "bundled".into();
    manifest.yt_dlp.state = "good".into();
    manifest.yt_dlp.sha256 = None;
    manifest.reverted_version = Some(broken.clone());
    if !manifest.failed_versions.contains(&broken) {
        manifest.failed_versions.push(broken.clone());
    }
    let source = EnginePaths {
        yt_dlp: bundled.yt_dlp,
        ffmpeg: active.ffmpeg,
        quickjs: active.quickjs,
    };
    replace_dir(
        data,
        &source,
        &manifest,
        BASELINE_HASHES.yt_dlp,
        super::health_check,
    )?;
    Ok(broken)
}

#[cfg(test)]
mod tests {
    use super::*;
    use sha2::{Digest, Sha256};
    use std::{
        net::TcpListener,
        sync::{
            atomic::{AtomicBool, Ordering},
            Arc,
        },
        thread,
    };

    fn fixture_server(
        executable: Vec<u8>,
        checksum: String,
        valid_json: bool,
        requests: usize,
    ) -> (String, thread::JoinHandle<()>) {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let base = format!("http://{}", listener.local_addr().unwrap());
        let base_for_thread = base.clone();
        let handle = thread::spawn(move || {
            for _ in 0..requests {
                let (mut stream, _) = listener.accept().unwrap();
                let mut request = [0u8; 4096];
                let count = stream.read(&mut request).unwrap();
                let path = String::from_utf8_lossy(&request[..count]);
                let path = path.split_whitespace().nth(1).unwrap();
                let body = match path {
                    "/latest" if valid_json => format!(r#"{{"tag_name":"2026.10.21","draft":false,"prerelease":false,"assets":[{{"name":"yt-dlp.exe","browser_download_url":"{base_for_thread}/yt-dlp.exe"}},{{"name":"SHA2-256SUMS","browser_download_url":"{base_for_thread}/SHA2-256SUMS"}}]}}"#).into_bytes(),
                    "/latest" => b"invalid JSON".to_vec(),
                    "/SHA2-256SUMS" => format!("{checksum}  yt-dlp.exe\n").into_bytes(),
                    "/yt-dlp.exe" => executable.clone(),
                    other => panic!("unexpected fixture path {other}"),
                };
                write!(
                    stream,
                    "HTTP/1.1 200 OK\r\nContent-Length: {}\r\nConnection: close\r\n\r\n",
                    body.len()
                )
                .unwrap();
                stream.write_all(&body).unwrap();
            }
        });
        (base, handle)
    }

    fn test_data() -> std::path::PathBuf {
        let data =
            std::env::temp_dir().join(format!("zownload-update-test-{}", uuid::Uuid::new_v4()));
        fs::create_dir_all(data.join("engine")).unwrap();
        let manifest = super::super::make_manifest("0.0.1").unwrap();
        write_manifest(&data, &manifest).unwrap();
        data
    }

    #[test]
    fn checksums_require_exact_filename_once() {
        let hash = "a".repeat(64);
        let bytes = format!("{hash}  yt-dlp.exe\n{}  yt-dlp_arm64.exe\n", "b".repeat(64));
        assert_eq!(checksum_for(bytes.as_bytes(), "yt-dlp.exe").unwrap(), hash);
        assert!(checksum_for(
            format!("{bytes}{hash}  yt-dlp.exe\n").as_bytes(),
            "yt-dlp.exe"
        )
        .is_err());
        assert!(checksum_for(bytes.as_bytes(), "missing.exe").is_err());
    }

    #[test]
    fn same_and_older_releases_do_not_download() {
        let data = test_data();
        let client = ReleaseClient::new("http://127.0.0.1:1/latest", false).unwrap();
        for version in [YT_DLP_VERSION, "2026.07.04"] {
            let candidate = Candidate {
                version: version.into(),
                executable_url: "http://127.0.0.1:1/yt-dlp.exe".into(),
                checksums_url: "http://127.0.0.1:1/SHA2-256SUMS".into(),
            };
            assert!(!client.stage(&data, &candidate).unwrap());
        }
        fs::remove_dir_all(data).unwrap();
    }

    #[test]
    fn local_release_is_staged_only_after_exact_checksum() {
        let executable = b"stub executable bytes".to_vec();
        let checksum = format!("{:x}", Sha256::digest(&executable));
        let (base, server) = fixture_server(executable.clone(), checksum.clone(), true, 3);
        let client = ReleaseClient::new(&format!("{base}/latest"), false).unwrap();
        let candidate = client.latest().unwrap();
        assert_eq!(candidate.version, "2026.10.21");
        let data = test_data();
        let checked = Arc::new(AtomicBool::new(false));
        let observed = Arc::clone(&checked);
        assert!(client
            .stage_with(&data, &candidate, |path, version| {
                assert_eq!(version, "2026.10.21");
                assert_eq!(hash_file(path).unwrap(), checksum);
                observed.store(true, Ordering::SeqCst);
                Ok(())
            })
            .unwrap());
        assert!(checked.load(Ordering::SeqCst));
        assert_eq!(
            fs::read(data.join("engine/staging/candidate.exe")).unwrap(),
            executable
        );
        assert_eq!(
            read_manifest(&data).unwrap().pending_version.as_deref(),
            Some("2026.10.21")
        );
        assert!(client
            .stage(&data, &candidate)
            .unwrap_err()
            .contains("pending activation"));
        server.join().unwrap();
        fs::remove_dir_all(data).unwrap();
    }

    #[test]
    fn automatic_engine_check_is_throttled_for_24_hours() {
        let data = test_data();
        let now = time::OffsetDateTime::from_unix_timestamp(2_000_000).unwrap();
        assert!(record_daily_check(&data, now).unwrap());
        assert!(!record_daily_check(&data, now + time::Duration::hours(23)).unwrap());
        assert!(record_daily_check(&data, now + time::Duration::hours(24)).unwrap());
        fs::remove_dir_all(data).unwrap();
    }

    #[test]
    fn automatic_checks_skip_failed_versions_and_persist_the_clock() {
        let data = test_data();
        let mut manifest = read_manifest(&data).unwrap();
        manifest.failed_versions.push("2026.10.21".into());
        write_manifest(&data, &manifest).unwrap();
        let (base, server) = fixture_server(Vec::new(), String::new(), true, 1);
        let client = ReleaseClient::new(&format!("{base}/latest"), false).unwrap();
        let now = time::OffsetDateTime::from_unix_timestamp(2_000_000).unwrap();
        assert!(!client.startup_check(&data, now).unwrap());
        assert!(!client
            .startup_check(&data, now + time::Duration::hours(1))
            .unwrap());
        assert!(read_manifest(&data).unwrap().last_update_check.is_some());
        server.join().unwrap();
        fs::remove_dir_all(data).unwrap();
    }

    #[test]
    fn a_failed_release_gets_one_persisted_manual_retry() {
        let executable = b"stub executable bytes".to_vec();
        let checksum = format!("{:x}", Sha256::digest(&executable));
        let (base, server) = fixture_server(executable, checksum, true, 3);
        let client = ReleaseClient::new(&format!("{base}/latest"), false).unwrap();
        let candidate = client.latest().unwrap();
        let data = test_data();
        let mut manifest = read_manifest(&data).unwrap();
        manifest.failed_versions.push(candidate.version.clone());
        write_manifest(&data, &manifest).unwrap();

        assert!(claim_manual_retry(&data, &candidate.version).unwrap());
        assert!(claim_manual_retry(&data, &candidate.version).is_err());
        let info = client.update_info(&data, &candidate.version).unwrap();
        assert_eq!(info.outcome, Some(EngineUpdateOutcome::Failed));
        assert_eq!(
            info.failed_version.as_deref(),
            Some(candidate.version.as_str())
        );
        assert_eq!(info.manual_retry_available, Some(false));
        assert!(!info.update_available);
        assert!(client
            .stage_with_retry(&data, &candidate, true, |_, _| Ok(()))
            .unwrap());
        assert!(read_manifest(&data)
            .unwrap()
            .manual_retry_versions
            .contains(&candidate.version));
        server.join().unwrap();
        fs::remove_dir_all(data).unwrap();
    }

    #[test]
    fn checksum_mismatch_never_executes_and_preserves_active_manifest() {
        let (base, server) = fixture_server(b"wrong bytes".to_vec(), "a".repeat(64), true, 3);
        let client = ReleaseClient::new(&format!("{base}/latest"), false).unwrap();
        let candidate = client.latest().unwrap();
        let data = test_data();
        assert!(client
            .stage_with(&data, &candidate, |_, _| panic!(
                "unverified candidate executed"
            ))
            .unwrap_err()
            .contains("checksum mismatch"));
        let manifest = read_manifest(&data).unwrap();
        assert_eq!(manifest.yt_dlp.version, YT_DLP_VERSION);
        assert!(manifest.pending_version.is_none());
        assert!(manifest.failed_versions.contains(&"2026.10.21".into()));
        assert!(!data.join("engine/staging/candidate-download.exe").exists());
        server.join().unwrap();
        fs::remove_dir_all(data).unwrap();
    }

    #[test]
    fn malformed_release_and_non_executable_candidate_are_rejected() {
        let (base, server) = fixture_server(Vec::new(), "a".repeat(64), false, 1);
        let client = ReleaseClient::new(&format!("{base}/latest"), false).unwrap();
        assert!(client.latest().is_err());
        server.join().unwrap();
        let executable = b"not executable".to_vec();
        let checksum = format!("{:x}", Sha256::digest(&executable));
        let (base, server) = fixture_server(executable, checksum, true, 3);
        let client = ReleaseClient::new(&format!("{base}/latest"), false).unwrap();
        let candidate = client.latest().unwrap();
        let data = test_data();
        assert!(client
            .stage_with(&data, &candidate, |_, _| Err("not executable".into()))
            .unwrap_err()
            .contains("not executable"));
        assert!(read_manifest(&data)
            .unwrap()
            .failed_versions
            .contains(&"2026.10.21".into()));
        server.join().unwrap();
        fs::remove_dir_all(data).unwrap();
    }

    #[test]
    fn official_asset_and_redirect_hosts_are_narrow() {
        let client = ReleaseClient::official().unwrap();
        assert!(client
            .validate_url(
                "https://github.com/yt-dlp/yt-dlp/releases/download/2026.10.21/yt-dlp.exe",
                "2026.10.21",
                "yt-dlp.exe"
            )
            .is_ok());
        assert!(client
            .validate_url(
                "https://evil.example/yt-dlp.exe",
                "2026.10.21",
                "yt-dlp.exe"
            )
            .is_err());
        assert!(!official_redirect(
            &Url::parse("https://evil.example/file").unwrap()
        ));
        assert!(!official_redirect(
            &Url::parse("http://github.com/file").unwrap()
        ));
    }

    #[test]
    fn release_metadata_timeout_is_bounded() {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let url = format!("http://{}/latest", listener.local_addr().unwrap());
        let server = thread::spawn(move || {
            let (_stream, _) = listener.accept().unwrap();
            thread::sleep(Duration::from_millis(250));
        });
        let mut client = ReleaseClient::new(&url, false).unwrap();
        client.client = Client::builder()
            .timeout(Duration::from_millis(50))
            .build()
            .unwrap();
        assert!(client.latest().is_err());
        server.join().unwrap();
    }

    #[test]
    fn interrupted_executable_body_is_cleaned_before_probe() {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let base = format!("http://{}", listener.local_addr().unwrap());
        let server = thread::spawn(move || {
            for index in 0..2 {
                let (mut stream, _) = listener.accept().unwrap();
                let mut request = [0u8; 2048];
                let _ = stream.read(&mut request).unwrap();
                if index == 0 {
                    let body = format!("{}  yt-dlp.exe\n", "a".repeat(64));
                    write!(
                        stream,
                        "HTTP/1.1 200 OK\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",
                        body.len()
                    )
                    .unwrap();
                } else {
                    write!(
                        stream,
                        "HTTP/1.1 200 OK\r\nContent-Length: 100\r\nConnection: close\r\n\r\nshort"
                    )
                    .unwrap();
                }
            }
        });
        let candidate = Candidate {
            version: "2026.10.21".into(),
            checksums_url: format!("{base}/SHA2-256SUMS"),
            executable_url: format!("{base}/yt-dlp.exe"),
        };
        let client = ReleaseClient::new(&format!("{base}/latest"), false).unwrap();
        let data = test_data();
        assert!(client
            .stage_with(&data, &candidate, |_, _| panic!(
                "incomplete download executed"
            ))
            .is_err());
        assert!(!data.join("engine/staging/candidate-download.exe").exists());
        assert!(read_manifest(&data).unwrap().pending_version.is_none());
        server.join().unwrap();
        fs::remove_dir_all(data).unwrap();
    }

    #[test]
    fn verified_candidate_activates_from_app_data_and_fallback_restores_baseline() {
        let resources =
            std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("resources/windows-engine");
        if !resources.join("yt-dlp.exe").is_file() {
            return;
        }
        let data =
            std::env::temp_dir().join(format!("zownload-update-native-{}", uuid::Uuid::new_v4()));
        match super::super::bootstrap(&resources, &data, "0.0.1") {
            super::super::EngineStatus::Ready(_) => (),
            super::super::EngineStatus::Unavailable(reason) => {
                panic!("baseline unavailable: {reason}")
            }
        }
        let staging = data.join("engine/staging");
        fs::create_dir_all(&staging).unwrap();
        let source = staging.join("stub.rs");
        fs::write(&source, "// SPDX-License-Identifier: GPL-3.0-or-later\n// SPDX-FileCopyrightText: 2026 zahidzta\nfn main() { if std::env::args().any(|arg| arg == \"--version\") { println!(\"2026.10.21\"); } else { std::process::exit(7); } }\n").unwrap();
        let candidate = staging.join("candidate.exe");
        assert!(std::process::Command::new("rustc")
            .arg(&source)
            .arg("-o")
            .arg(&candidate)
            .status()
            .unwrap()
            .success());
        let mut manifest = read_manifest(&data).unwrap();
        manifest.pending_version = Some("2026.10.26".into());
        manifest.pending_sha256 = Some(hash_file(&candidate).unwrap());
        write_manifest(&data, &manifest).unwrap();
        assert!(activate_pending(&data)
            .unwrap_err()
            .contains("version probe"));
        assert_eq!(
            hash_file(&data.join("engine/yt-dlp.exe")).unwrap(),
            BASELINE_HASHES.yt_dlp
        );
        manifest.pending_version = Some("2026.10.21".into());
        write_manifest(&data, &manifest).unwrap();
        let active_lease = slot().read().unwrap();
        let waiting_data = data.clone();
        let finished = Arc::new(AtomicBool::new(false));
        let signal = Arc::clone(&finished);
        let activation = thread::spawn(move || {
            let result = activate_pending(&waiting_data);
            signal.store(true, Ordering::SeqCst);
            result
        });
        thread::sleep(Duration::from_millis(100));
        assert!(
            !finished.load(Ordering::SeqCst),
            "a running engine must hold the executable slot"
        );
        drop(active_lease);
        assert_eq!(
            activation.join().unwrap().unwrap(),
            Some("2026.10.21".into())
        );
        let promoted = read_manifest(&data).unwrap();
        assert_eq!(promoted.yt_dlp.state, "probation");
        assert_eq!(promoted.yt_dlp.source, "updated");
        assert!(promoted.pending_version.is_none());
        assert_eq!(
            super::super::hash_file(&data.join("engine/yt-dlp.exe")).unwrap(),
            manifest.pending_sha256.unwrap()
        );
        assert_eq!(
            restore_baseline(&data, &resources, "2026.10.21").unwrap(),
            "2026.10.21"
        );
        let restored = read_manifest(&data).unwrap();
        assert_eq!(restored.yt_dlp.source, "bundled");
        assert_eq!(restored.reverted_version.as_deref(), Some("2026.10.21"));
        assert!(restored.failed_versions.contains(&"2026.10.21".into()));
        assert_eq!(
            hash_file(&data.join("engine/yt-dlp.exe")).unwrap(),
            BASELINE_HASHES.yt_dlp
        );
        fs::remove_dir_all(data).unwrap();
    }

    #[test]
    fn normal_probation_completion_marks_good_without_replacing_copy() {
        let data = test_data();
        let mut manifest = read_manifest(&data).unwrap();
        manifest.yt_dlp.state = "probation".into();
        write_manifest(&data, &manifest).unwrap();
        mark_good(&data, YT_DLP_VERSION).unwrap();
        assert_eq!(read_manifest(&data).unwrap().yt_dlp.state, "good");
        fs::remove_dir_all(data).unwrap();
    }
}
