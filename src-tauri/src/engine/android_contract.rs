// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

//! Private JSON shapes for the Kotlin engine bridge. These are not part of the
//! JavaScript contract; Android may add engine-only metadata without changing it.

use crate::contract::{AnalyzeResult, AppError, EngineUpdateInfo, ErrorCode, Format, Quality};
use serde::{Deserialize, Serialize};
use std::path::PathBuf;

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct BridgeReply<T> {
    pub ok: bool,
    pub value: Option<T>,
    pub error: Option<BridgeFailure>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct BridgeFailure {
    pub code: String,
    pub detail: String,
}

impl<T> BridgeReply<T> {
    pub fn into_result(self) -> Result<T, AppError> {
        if self.ok {
            return self.value.ok_or_else(|| {
                AppError::new(
                    ErrorCode::EngineMissing,
                    Some("Android engine returned no value".into()),
                )
            });
        }
        let failure = self.error.unwrap_or(BridgeFailure {
            code: "engine_missing".into(),
            detail: "Android engine returned an invalid error".into(),
        });
        Err(map_failure(failure))
    }
}

pub(crate) fn map_failure(failure: BridgeFailure) -> AppError {
    let code = match failure.code.as_str() {
        "invalid_url" => ErrorCode::InvalidUrl,
        "unsupported_site" => ErrorCode::UnsupportedSite,
        "private_or_restricted" => ErrorCode::PrivateOrRestricted,
        "not_found" => ErrorCode::NotFound,
        "no_internet" => ErrorCode::NoInternet,
        "disk_full" => ErrorCode::DiskFull,
        "permission_denied" => ErrorCode::PermissionDenied,
        "engine_missing" => ErrorCode::EngineMissing,
        // The public contract has no cancellation variant. The queue uses its
        // own pause/remove intent to distinguish an expected cancellation.
        "cancelled" | "unknown" => ErrorCode::Unknown,
        _ => ErrorCode::Unknown,
    };
    AppError::new(code, Some(failure.detail))
}

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct EngineProgress {
    pub percent: f32,
    #[serde(default)]
    pub status: String,
    #[serde(default)]
    pub title: String,
    #[serde(default)]
    pub downloaded_bytes: u64,
    #[serde(default)]
    pub total_bytes: u64,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct DownloadResult {
    pub path: PathBuf,
    pub title: String,
    pub thumbnail: Option<String>,
    pub bytes: u64,
}

#[derive(Clone, Debug)]
pub(crate) struct PlaylistEntry {
    pub url: String,
    pub title: String,
}

#[derive(Debug)]
pub(crate) struct EngineAnalysis {
    pub result: AnalyzeResult,
    pub entries: Vec<PlaylistEntry>,
}

pub(crate) fn parse_analysis(value: serde_json::Value) -> Result<EngineAnalysis, AppError> {
    let public_value = value.clone();
    let result = serde_json::from_value(public_value).map_err(|error| {
        AppError::new(
            ErrorCode::EngineMissing,
            Some(format!("invalid Android analysis response: {error}")),
        )
    })?;
    let entries = if matches!(result, AnalyzeResult::Playlist { .. }) {
        let urls = value
            .get("itemUrls")
            .and_then(serde_json::Value::as_array)
            .ok_or_else(|| {
                AppError::new(
                    ErrorCode::EngineMissing,
                    Some("Android playlist URLs are missing".into()),
                )
            })?;
        let titles = value
            .get("itemTitles")
            .and_then(serde_json::Value::as_array)
            .ok_or_else(|| {
                AppError::new(
                    ErrorCode::EngineMissing,
                    Some("Android playlist titles are missing".into()),
                )
            })?;
        if urls.len() != titles.len() {
            return Err(AppError::new(
                ErrorCode::EngineMissing,
                Some("Android playlist URL and title counts differ".into()),
            ));
        }
        urls.iter()
            .zip(titles)
            .map(|(url, title)| {
                let url = url
                    .as_str()
                    .filter(|url| url.starts_with("https://") || url.starts_with("http://"))
                    .ok_or_else(|| {
                        AppError::new(
                            ErrorCode::EngineMissing,
                            Some("Android playlist contains an invalid URL".into()),
                        )
                    })?;
                let title = title.as_str().unwrap_or("");
                Ok(PlaylistEntry {
                    url: url.to_owned(),
                    title: title.to_owned(),
                })
            })
            .collect::<Result<Vec<_>, AppError>>()?
    } else {
        Vec::new()
    };
    if matches!(result, AnalyzeResult::Playlist { .. }) && entries.is_empty() {
        return Err(AppError::new(
            ErrorCode::EngineMissing,
            Some("Android engine did not return downloadable playlist entries".into()),
        ));
    }
    Ok(EngineAnalysis { result, entries })
}

pub(crate) fn entry_request(
    url: String,
    format: Format,
    quality: Quality,
) -> crate::contract::DownloadRequest {
    crate::contract::DownloadRequest {
        url,
        format,
        quality,
        is_playlist: false,
    }
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct CancelResult {
    pub cancelled: bool,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct EngineUpdateResult {
    pub current: String,
    pub latest: String,
    pub update_available: bool,
    pub outcome: Option<crate::contract::EngineUpdateOutcome>,
    pub pending_version: Option<String>,
    pub reverted_version: Option<String>,
    pub failed_version: Option<String>,
    pub manual_retry_available: Option<bool>,
}

impl From<EngineUpdateResult> for EngineUpdateInfo {
    fn from(value: EngineUpdateResult) -> Self {
        Self {
            current: value.current,
            latest: value.latest,
            update_available: value.update_available,
            outcome: value.outcome,
            pending_version: value.pending_version,
            reverted_version: value.reverted_version,
            failed_version: value.failed_version,
            manual_retry_available: value.manual_retry_available,
        }
    }
}

pub(crate) fn safe_output_name(title: &str, id: &str, format: Format) -> String {
    let stem = title
        .chars()
        .map(|character| {
            if character.is_control()
                || matches!(
                    character,
                    '<' | '>' | ':' | '"' | '/' | '\\' | '|' | '?' | '*'
                )
            {
                '_'
            } else {
                character
            }
        })
        .take(120)
        .collect::<String>()
        .trim_matches([' ', '.'])
        .to_owned();
    let stem = if stem.is_empty() { "download" } else { &stem };
    let extension = match format {
        Format::Mp3 => "mp3",
        Format::Mp4 => "mp4",
    };
    format!("{stem} [{id}].{extension}")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn analysis_progress_download_and_update_payloads_match_the_private_bridge() {
        let analysis = parse_analysis(serde_json::json!({
            "kind": "playlist", "url": "https://example.test/list", "title": "mix",
            "author": "artist", "thumbnail": null, "site": "Example",
            "itemCount": 1, "itemTitles": ["song"],
            "itemUrls": ["https://example.test/song"]
        }))
        .unwrap();
        assert_eq!(analysis.entries[0].url, "https://example.test/song");
        assert!(serde_json::to_value(&analysis.result)
            .unwrap()
            .get("itemUrls")
            .is_none());
        assert!(matches!(
            analysis.result,
            AnalyzeResult::Playlist { item_count: 1, .. }
        ));

        let progress: EngineProgress = serde_json::from_value(serde_json::json!({
            "status": "downloading", "percent": 37.5, "downloadedBytes": 15,
            "totalBytes": 40, "title": "song"
        }))
        .unwrap();
        assert_eq!(progress.percent, 37.5);
        assert_eq!(progress.downloaded_bytes, 15);
        let download: DownloadResult = serde_json::from_value(serde_json::json!({
            "path": "cache/song.mp3", "title": "song", "thumbnail": null, "bytes": 12
        }))
        .unwrap();
        assert_eq!(download.bytes, 12);

        let update: EngineUpdateInfo = serde_json::from_value(serde_json::json!({
            "current": "2026.11.23", "latest": "2026.11.23",
            "updateAvailable": false, "outcome": "current"
        }))
        .unwrap();
        assert_eq!(update.current, "2026.11.23");
        assert_eq!(
            update.outcome,
            Some(crate::contract::EngineUpdateOutcome::Current)
        );

        let cancelled: CancelResult = serde_json::from_value(serde_json::json!({
            "cancelled": true
        }))
        .unwrap();
        assert!(cancelled.cancelled);
        let ok: BridgeReply<serde_json::Value> = serde_json::from_value(serde_json::json!({
            "ok": true, "value": {"ready": true}
        }))
        .unwrap();
        assert_eq!(ok.into_result().unwrap()["ready"], true);
    }

    #[test]
    fn engine_failures_keep_the_public_typed_error_code() {
        let codes = [
            ("invalid_url", ErrorCode::InvalidUrl),
            ("unsupported_site", ErrorCode::UnsupportedSite),
            ("private_or_restricted", ErrorCode::PrivateOrRestricted),
            ("not_found", ErrorCode::NotFound),
            ("no_internet", ErrorCode::NoInternet),
            ("disk_full", ErrorCode::DiskFull),
            ("permission_denied", ErrorCode::PermissionDenied),
            ("engine_missing", ErrorCode::EngineMissing),
        ];
        for (code, expected) in codes {
            let error = BridgeReply::<serde_json::Value> {
                ok: false,
                value: None,
                error: Some(BridgeFailure {
                    code: code.into(),
                    detail: "reason".into(),
                }),
            }
            .into_result()
            .unwrap_err();
            assert_eq!(error.code, expected);
            assert_eq!(error.detail.as_deref(), Some("reason"));
        }
    }

    #[test]
    fn malformed_playlist_metadata_is_rejected_and_output_names_are_safe() {
        assert!(parse_analysis(serde_json::json!({
            "kind": "playlist", "url": "u", "title": "t", "author": "a",
            "thumbnail": null, "site": "s", "itemCount": 1, "itemTitles": ["x"]
        }))
        .is_err());
        assert_eq!(
            safe_output_name("../song?.mp3", "abc", Format::Mp3),
            "_song_.mp3 [abc].mp3"
        );
    }
}
