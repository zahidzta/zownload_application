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

fn target_for_bundle(bundle: &str) -> Result<String, String> {
    if !matches!(bundle, "nsis" | "msi") {
        return Err(format!("unsupported Windows updater bundle: {bundle}"));
    }
    Ok(format!("windows-{}-{bundle}", std::env::consts::ARCH))
}

fn installed_target() -> Result<String, String> {
    let bundle = tauri::utils::platform::bundle_type()
        .map(|kind| kind.to_string())
        .or_else(|| cfg!(debug_assertions).then(|| "nsis".to_owned()))
        .ok_or_else(|| "could not determine the installed Windows bundle type".to_owned())?;
    target_for_bundle(&bundle)
}

fn updater_builder(app: &AppHandle) -> Result<tauri_plugin_updater::UpdaterBuilder, String> {
    let mut builder = app
        .updater_builder()
        .target(installed_target()?)
        .timeout(Duration::from_secs(30));

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
        match updater_builder(app)?
            .build()
            .map_err(|error| error.to_string())?
            .check()
            .await
        {
            Ok(Some(update)) => {
                state.latest = Some(update.version.clone());
                state.error = None;
            }
            Ok(None) => {
                state.latest = None;
                state.error = None;
            }
            Err(error) => state.error = Some(error.to_string()),
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
    update
        .download_and_install(|_, _| {}, || {})
        .await
        .map_err(|error| error.to_string())
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
            error: None,
        };
        write_state(&directory, &state).unwrap();
        let reloaded = read_state(&directory).unwrap();
        assert!(reloaded.info("1.1.0".into()).update_available);
        assert_eq!(reloaded.latest, state.latest);
        fs::remove_dir_all(directory).unwrap();
    }
}
