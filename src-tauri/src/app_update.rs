// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

//! Separate, persisted discovery and installation for signed desktop app updates.

use crate::contract::AppUpdateInfo;
use serde::{Deserialize, Serialize};
use std::{
    fs::{self, File},
    io::Write,
    path::Path,
    time::{Duration, SystemTime, UNIX_EPOCH},
};
#[cfg(target_os = "linux")]
use std::{
    io::Read,
    process::{Command, Stdio},
};
use tauri::{AppHandle, Manager};
use tauri_plugin_updater::UpdaterExt;
use url::Url;

const CHECK_INTERVAL: i64 = 24 * 60 * 60;
const STATUS_FILE: &str = "app-update.json";

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct AppUpdateState {
    #[serde(default)]
    checked_at: Option<i64>,
    #[serde(default)]
    latest: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    latest_url: Option<String>,
    #[serde(default)]
    error: Option<String>,
}

impl AppUpdateState {
    fn info(&self, current: String) -> AppUpdateInfo {
        let update_available = self
            .latest
            .as_deref()
            .is_some_and(|latest| stable_version_is_newer(latest, &current));
        AppUpdateInfo {
            current,
            latest: self.latest.clone(),
            update_available,
            checked_at: self.checked_at,
            error: self.error.clone(),
        }
    }
}

fn status_path(data: &Path) -> std::path::PathBuf {
    data.join(STATUS_FILE)
}

fn read_state(data: &Path) -> Result<AppUpdateState, String> {
    let path = status_path(data);
    match fs::read(&path) {
        Ok(bytes) => serde_json::from_slice(&bytes).map_err(|error| error.to_string()),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(AppUpdateState::default()),
        Err(error) => Err(format!("{}: {error}", path.display())),
    }
}

fn write_state(data: &Path, state: &AppUpdateState) -> Result<(), String> {
    fs::create_dir_all(data).map_err(|error| error.to_string())?;
    let path = status_path(data);
    let temporary = data.join(format!("{STATUS_FILE}.tmp"));
    let mut file = File::create(&temporary).map_err(|error| error.to_string())?;
    serde_json::to_writer_pretty(&mut file, state).map_err(|error| error.to_string())?;
    file.write_all(b"\n").map_err(|error| error.to_string())?;
    file.sync_all().map_err(|error| error.to_string())?;
    drop(file);
    fs::rename(temporary, path).map_err(|error| error.to_string())
}

fn check_is_due(checked_at: Option<i64>, now: i64) -> bool {
    checked_at.is_none_or(|last| now.saturating_sub(last) >= CHECK_INTERVAL)
}

fn stable_version_is_newer(candidate: &str, current: &str) -> bool {
    fn parts(value: &str) -> Option<[u64; 3]> {
        let value = value.strip_prefix('v').unwrap_or(value);
        if value.contains('-') || value.contains('+') {
            return None;
        }
        let mut numbers = value.split('.').map(str::parse::<u64>);
        Some([
            numbers.next()?.ok()?,
            numbers.next()?.ok()?,
            numbers.next()?.ok()?,
        ])
        .filter(|_| numbers.next().is_none())
    }
    matches!((parts(candidate), parts(current)), (Some(new), Some(old)) if new > old)
}

#[cfg(target_os = "windows")]
fn target_for_bundle(bundle: &str) -> Result<String, String> {
    if !matches!(bundle, "nsis" | "msi") {
        return Err(format!("unsupported Windows updater bundle: {bundle}"));
    }
    Ok(format!("windows-{}-{bundle}", std::env::consts::ARCH))
}

#[cfg(target_os = "windows")]
fn installed_target() -> Result<String, String> {
    let bundle = tauri::utils::platform::bundle_type()
        .map(|kind| kind.to_string())
        .or_else(|| cfg!(debug_assertions).then(|| "nsis".to_owned()))
        .ok_or_else(|| "could not determine the installed Windows bundle type".to_owned())?;
    target_for_bundle(&bundle)
}

#[cfg(target_os = "linux")]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum LinuxBundle {
    AppImage,
    Deb,
}

#[cfg(target_os = "linux")]
fn linux_bundle(appimage: Option<&std::ffi::OsStr>) -> LinuxBundle {
    if appimage.is_some_and(|path| !path.is_empty()) {
        LinuxBundle::AppImage
    } else {
        LinuxBundle::Deb
    }
}

#[cfg(target_os = "linux")]
fn installed_linux_bundle() -> LinuxBundle {
    linux_bundle(std::env::var_os("APPIMAGE").as_deref())
}

#[cfg(target_os = "linux")]
#[derive(Deserialize)]
struct GithubRelease {
    tag_name: String,
    draft: bool,
    prerelease: bool,
    assets: Vec<GithubReleaseAsset>,
}

#[cfg(target_os = "linux")]
#[derive(Deserialize)]
struct GithubReleaseAsset {
    name: String,
    browser_download_url: String,
}

#[cfg(target_os = "linux")]
fn is_amd64_deb(name: &str, version: &str) -> bool {
    let name = name.to_ascii_lowercase();
    let amd64 = format!("_{version}_amd64.deb");
    let x86_64 = format!("_{version}_x86_64.deb");
    name.ends_with(amd64.as_str()) || name.ends_with(x86_64.as_str())
}

#[cfg(target_os = "linux")]
fn validate_deb_download_url(value: &str, tag: &str, name: &str) -> Result<(), String> {
    let url = Url::parse(value).map_err(|error| error.to_string())?;
    let expected_path = format!("/zahidzta/zownload_application/releases/download/{tag}/{name}");
    if url.scheme() != "https"
        || url.host_str() != Some("github.com")
        || url.path() != expected_path
        || url.query().is_some()
        || url.fragment().is_some()
    {
        return Err("release asset URL is outside the expected GitHub .deb asset".into());
    }
    Ok(())
}

#[cfg(target_os = "linux")]
fn select_deb_asset(release: &GithubRelease) -> Result<(String, String), String> {
    if release.draft || release.prerelease {
        return Err("latest release is not stable".into());
    }
    let version = release
        .tag_name
        .strip_prefix("app-v")
        .ok_or_else(|| "latest release has an unexpected tag".to_owned())?;
    if !stable_version_is_newer(version, "0.0.0") {
        return Err("latest release has an invalid stable version".into());
    }
    let matches = release
        .assets
        .iter()
        .filter(|asset| is_amd64_deb(&asset.name, version))
        .collect::<Vec<_>>();
    if matches.len() != 1 {
        return Err("latest release needs one x86_64 .deb asset".into());
    }
    let asset = matches[0];
    validate_deb_download_url(&asset.browser_download_url, &release.tag_name, &asset.name)?;
    Ok((version.to_owned(), asset.browser_download_url.clone()))
}

#[cfg(target_os = "linux")]
fn fetch_latest_deb() -> Result<(String, String), String> {
    const RELEASES_API: &str =
        "https://api.github.com/repos/zahidzta/zownload_application/releases/latest";
    const MAX_RESPONSE: u64 = 512 * 1024;
    let client = reqwest::blocking::Client::builder()
        .timeout(Duration::from_secs(30))
        .build()
        .map_err(|error| error.to_string())?;
    let response = client
        .get(RELEASES_API)
        .header("Accept", "application/vnd.github+json")
        .header("User-Agent", "Zownload app updater")
        .send()
        .map_err(|error| error.to_string())?
        .error_for_status()
        .map_err(|error| error.to_string())?;
    if response
        .content_length()
        .is_some_and(|size| size > MAX_RESPONSE)
    {
        return Err("GitHub release metadata is too large".into());
    }
    let mut bytes = Vec::new();
    response
        .take(MAX_RESPONSE + 1)
        .read_to_end(&mut bytes)
        .map_err(|error| error.to_string())?;
    if bytes.len() as u64 > MAX_RESPONSE {
        return Err("GitHub release metadata is too large".into());
    }
    let release: GithubRelease =
        serde_json::from_slice(&bytes).map_err(|error| error.to_string())?;
    select_deb_asset(&release)
}

#[cfg(target_os = "linux")]
async fn fetch_latest_deb_async() -> Result<(String, String), String> {
    tauri::async_runtime::spawn_blocking(fetch_latest_deb)
        .await
        .map_err(|error| error.to_string())?
}

#[cfg(target_os = "linux")]
fn open_deb_download(url: &str, version: &str) -> Result<(), String> {
    let parsed = Url::parse(url).map_err(|error| error.to_string())?;
    let name = parsed
        .path_segments()
        .and_then(|mut segments| segments.next_back())
        .ok_or_else(|| "saved .deb link has no asset name".to_owned())?;
    validate_deb_download_url(url, &format!("app-v{version}"), name)?;
    if !is_amd64_deb(name, version) {
        return Err("saved update link is not an x86_64 .deb asset".into());
    }
    Command::new("xdg-open")
        .arg(parsed.as_str())
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .map_err(|error| format!("could not open the .deb download link: {error}"))?;
    Ok(())
}

fn updater_builder(app: &AppHandle) -> Result<tauri_plugin_updater::UpdaterBuilder, String> {
    let mut builder = app.updater_builder().timeout(Duration::from_secs(30));
    #[cfg(target_os = "windows")]
    {
        builder = builder.target(installed_target()?);
    }
    #[cfg(target_os = "linux")]
    {
        if installed_linux_bundle() != LinuxBundle::AppImage {
            return Err("Tauri updater is enabled only for AppImage installs".into());
        }
        let target = tauri_plugin_updater::target()
            .ok_or_else(|| "Tauri updater is unavailable for this Linux target".to_owned())?;
        builder = builder.target(target);
    }

    // A debug-only endpoint override lets the native updater use a loopback fixture.
    #[cfg(debug_assertions)]
    if let Ok(endpoint) = std::env::var("ZOWNLOAD_TEST_UPDATER_ENDPOINT") {
        let endpoint = Url::parse(&endpoint).map_err(|error| error.to_string())?;
        builder = builder
            .endpoints(vec![endpoint])
            .map_err(|error| error.to_string())?;
    }

    Ok(builder)
}

fn now_unix_seconds() -> Result<i64, String> {
    let duration = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(|error| error.to_string())?;
    i64::try_from(duration.as_secs()).map_err(|error| error.to_string())
}

pub(crate) async fn check_daily(app: &AppHandle) -> Result<AppUpdateInfo, String> {
    let data = app
        .path()
        .app_local_data_dir()
        .map_err(|error| error.to_string())?;
    let current = app.package_info().version.to_string();
    let now = now_unix_seconds()?;
    let mut state = read_state(&data)?;
    if check_is_due(state.checked_at, now) {
        // Persist the attempt first so a network error still respects the daily limit.
        state.checked_at = Some(now);
        state.error = None;
        write_state(&data, &state)?;
        #[cfg(target_os = "windows")]
        match updater_builder(app)?
            .build()
            .map_err(|error| error.to_string())?
            .check()
            .await
        {
            Ok(Some(update)) => {
                state.latest = Some(update.version.clone());
                state.latest_url = None;
                state.error = None;
            }
            Ok(None) => {
                state.latest = None;
                state.latest_url = None;
                state.error = None;
            }
            Err(error) => state.error = Some(error.to_string()),
        }
        #[cfg(target_os = "linux")]
        match installed_linux_bundle() {
            LinuxBundle::AppImage => match updater_builder(app)
                .and_then(|builder| builder.build().map_err(|error| error.to_string()))
            {
                Ok(updater) => match updater.check().await {
                    Ok(Some(update)) => {
                        state.latest = Some(update.version.clone());
                        state.latest_url = None;
                        state.error = None;
                    }
                    Ok(None) => {
                        state.latest = None;
                        state.latest_url = None;
                        state.error = None;
                    }
                    Err(error) => state.error = Some(error.to_string()),
                },
                Err(error) => state.error = Some(error),
            },
            LinuxBundle::Deb => match fetch_latest_deb_async().await {
                Ok((version, url)) => {
                    state.latest = Some(version);
                    state.latest_url = Some(url);
                    state.error = None;
                }
                Err(error) => state.error = Some(error),
            },
        }
        write_state(&data, &state)?;
    }
    Ok(state.info(current))
}

pub(crate) async fn install_available(app: &AppHandle) -> Result<(), String> {
    let data = app
        .path()
        .app_local_data_dir()
        .map_err(|error| error.to_string())?;
    let current = app.package_info().version.to_string();
    let state = read_state(&data)?;
    if !state.info(current).update_available {
        return Err("no stable app update is available".into());
    }
    #[cfg(target_os = "linux")]
    if installed_linux_bundle() == LinuxBundle::Deb {
        let (latest, url) = fetch_latest_deb_async().await?;
        if Some(latest.as_str()) != state.latest.as_deref() {
            return Err("saved .deb update is no longer available".into());
        }
        if state
            .latest_url
            .as_deref()
            .is_some_and(|saved| saved != url)
        {
            return Err("saved .deb download link changed; check for updates again".into());
        }
        return open_deb_download(&url, &latest);
    }
    let updater = updater_builder(app)?
        .build()
        .map_err(|error| error.to_string())?;
    // Recheck the signed feed when the user acts; the UI's saved offer only
    // controls whether the install button is shown after a restart.
    let update = updater
        .check()
        .await
        .map_err(|error| error.to_string())?
        .filter(|update| Some(update.version.as_str()) == state.latest.as_deref())
        .ok_or_else(|| "saved app update is no longer available".to_owned())?;
    // Download verifies the updater signature before installation.
    let bytes = update
        .download(|_, _| {}, || {})
        .await
        .map_err(|error| error.to_string())?;
    #[cfg(target_os = "windows")]
    {
        app.state::<std::sync::Arc<crate::engine::process::Supervisor>>()
            .launch_installer(|| update.install(bytes))
            .map_err(|error| error.to_string())?
            .map_err(|error| error.to_string())
    }
    #[cfg(target_os = "linux")]
    {
        update.install(bytes).map_err(|error| error.to_string())?;
        // Stop the download queue before restarting into the installed AppImage.
        // Installing first keeps the current queue usable if installation fails.
        app.state::<std::sync::Arc<crate::engine::queue::QueueCoordinator>>()
            .close();
        app.restart();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn app_clock_is_separate_and_throttles_for_a_full_day() {
        assert!(check_is_due(None, 100_000));
        assert!(!check_is_due(Some(100_000), 100_000 + CHECK_INTERVAL - 1));
        assert!(check_is_due(Some(100_000), 100_000 + CHECK_INTERVAL));
        assert!(!check_is_due(Some(100_000), 99_999));
    }

    #[test]
    fn only_stable_newer_semver_versions_create_an_action() {
        let state = AppUpdateState {
            latest: Some("v1.2.0".into()),
            ..AppUpdateState::default()
        };
        assert!(state.info("1.1.9".into()).update_available);
        assert!(!state.info("1.2.0".into()).update_available);
        assert!(!stable_version_is_newer("1.3.0-beta.1", "1.2.0"));
        assert!(!stable_version_is_newer("1.2", "1.1.9"));
    }

    #[test]
    #[cfg(target_os = "windows")]
    fn custom_targets_keep_nsis_and_msi_releases_separate() {
        assert_eq!(target_for_bundle("nsis").unwrap(), "windows-x86_64-nsis");
        assert_eq!(target_for_bundle("msi").unwrap(), "windows-x86_64-msi");
        assert!(target_for_bundle("appimage").is_err());
    }

    #[test]
    fn update_action_survives_state_file_recreation() {
        let directory =
            std::env::temp_dir().join(format!("zownload-app-update-{}", uuid::Uuid::new_v4()));
        let state = AppUpdateState {
            checked_at: Some(1_800_000_000),
            latest: Some("1.2.0".into()),
            latest_url: Some("https://github.com/zahidzta/zownload_application/releases/download/app-v1.2.0/zownload_1.2.0_amd64.deb".into()),
            error: None,
        };
        write_state(&directory, &state).unwrap();
        let reloaded = read_state(&directory).unwrap();
        assert!(reloaded.info("1.1.0".into()).update_available);
        assert_eq!(reloaded.latest, state.latest);
        assert_eq!(reloaded.latest_url, state.latest_url);
        fs::remove_dir_all(directory).unwrap();
    }

    #[cfg(target_os = "linux")]
    #[test]
    fn linux_update_path_separates_appimage_and_deb_installs() {
        assert_eq!(linux_bundle(None), LinuxBundle::Deb);
        assert_eq!(
            linux_bundle(Some(std::ffi::OsStr::new("/tmp/Zownload.AppImage"))),
            LinuxBundle::AppImage
        );
        assert_eq!(
            linux_bundle(Some(std::ffi::OsStr::new(""))),
            LinuxBundle::Deb
        );
    }

    #[cfg(target_os = "linux")]
    #[test]
    fn deb_release_selection_uses_the_exact_x64_package_asset() {
        let release = GithubRelease {
            tag_name: "app-v1.2.0".into(),
            draft: false,
            prerelease: false,
            assets: vec![
                GithubReleaseAsset {
                    name: "Zownload_1.2.0_amd64.deb".into(),
                    browser_download_url: "https://github.com/zahidzta/zownload_application/releases/download/app-v1.2.0/Zownload_1.2.0_amd64.deb".into(),
                },
                GithubReleaseAsset {
                    name: "Zownload_1.2.0_x86_64.AppImage".into(),
                    browser_download_url: "https://github.com/zahidzta/zownload_application/releases/download/app-v1.2.0/Zownload_1.2.0_x86_64.AppImage".into(),
                },
            ],
        };
        let selected = select_deb_asset(&release).unwrap();
        assert_eq!(selected.0, "1.2.0");
        assert!(selected.1.ends_with("Zownload_1.2.0_amd64.deb"));
    }

    #[cfg(target_os = "linux")]
    #[test]
    fn deb_selection_rejects_wrong_architecture_duplicate_and_untrusted_links() {
        let wrong_arch = GithubRelease {
            tag_name: "app-v1.2.0".into(),
            draft: false,
            prerelease: false,
            assets: vec![GithubReleaseAsset {
                name: "Zownload_1.2.0_arm64.deb".into(),
                browser_download_url: "https://github.com/zahidzta/zownload_application/releases/download/app-v1.2.0/Zownload_1.2.0_arm64.deb".into(),
            }],
        };
        assert!(select_deb_asset(&wrong_arch).is_err());

        let duplicate = GithubRelease {
            assets: vec![
                GithubReleaseAsset {
                    name: "Zownload_1.2.0_amd64.deb".into(),
                    browser_download_url: "https://github.com/zahidzta/zownload_application/releases/download/app-v1.2.0/Zownload_1.2.0_amd64.deb".into(),
                },
                GithubReleaseAsset {
                    name: "zownload_1.2.0_x86_64.deb".into(),
                    browser_download_url: "https://github.com/zahidzta/zownload_application/releases/download/app-v1.2.0/zownload_1.2.0_x86_64.deb".into(),
                },
            ],
            ..wrong_arch
        };
        assert!(select_deb_asset(&duplicate).is_err());

        assert!(validate_deb_download_url(
            "https://evil.example/zownload_1.2.0_amd64.deb",
            "app-v1.2.0",
            "zownload_1.2.0_amd64.deb"
        )
        .is_err());
    }
}
