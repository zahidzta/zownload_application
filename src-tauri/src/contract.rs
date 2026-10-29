//! zownload — UI <-> engine contract (Rust side).
//! Mirror of shared/contract.ts. JSON is camelCase.
//!
//! Cargo.toml needs: serde = { version = "1", features = ["derive"] }
//! (`rename_all_fields` requires serde >= 1.0.185)
//!
//! Tauri commands to implement (all return Result<T, AppError>):
//!
//!   analyze_url(url: String)                    -> AnalyzeResult
//!   enqueue_download(request: DownloadRequest)  -> String   (queue item id)
//!   pause_download(id: String)                  -> ()
//!   resume_download(id: String)                 -> ()
//!   remove_download(id: String)                 -> ()
//!   get_queue()                                 -> Vec<QueueItem>
//!   get_history()                               -> Vec<HistoryEntry>
//!   delete_history_entry(id: i64)               -> ()
//!   clear_history()                             -> ()
//!   get_error_notifications()                   -> Vec<ErrorNotification>
//!   dismiss_error_notification(id: String)      -> ()
//!   get_settings()                              -> Settings
//!   set_settings(settings: Settings)            -> ()
//!   engine_check_update()                       -> EngineUpdateInfo
//!   engine_update()                             -> EngineUpdateInfo
//!
//! Events emitted with app.emit(...):
//!   "queue:item-updated"  payload: QueueItem   (throttled, ~5/s per item)
//!   "queue:item-removed"  payload: String      (id)
//!   "history:changed"     payload: ()
//!   "error-notifications:changed" payload: ()
//!
//! JS runtime: QuickJS on ALL platforms for now. Launch yt-dlp with
//! `--js-runtimes quickjs:<path>`. Use QuickJS >= 2025-4-26 (or QuickJS-NG
//! >= 0.12.0); older builds can take minutes. Missing/broken runtime =>
//! ErrorCode::EngineMissing.
//!
//! Suggested SQLite schema for history. Newest first = ORDER BY id DESC.
//! On a repeat download, DELETE the old row and INSERT a new one (moves it
//! to the top, no duplicate):
//!
//!   CREATE TABLE history (
//!     id          INTEGER PRIMARY KEY AUTOINCREMENT,
//!     url         TEXT    NOT NULL,
//!     format      TEXT    NOT NULL,          -- 'mp3' | 'mp4'
//!     is_playlist INTEGER NOT NULL,          -- 0 | 1
//!     quality     TEXT    NOT NULL,          -- Quality as JSON
//!     title       TEXT,                      -- display only
//!     UNIQUE (url, format, is_playlist, quality)
//!   );

use serde::{Deserialize, Serialize};

// ───────────────────────── Core types ─────────────────────────

#[derive(Serialize, Deserialize, Clone, Copy, Debug, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum Format {
    Mp3,
    Mp4,
}

/// Playlist: only Max | Min. Single: Video (mp4) or Audio (MP3 requested maximum).
/// MP3 always uses the best source audio. Copy an MP3 source at or below the
/// selected bitrate; reencode a higher-bitrate MP3 source down to it; encode
/// a non-MP3 source to it. Playlist Max requests 320 kbps; Min requests 128 kbps.
/// Serialized as {"type":"max"} / {"type":"video","height":720} ...
#[derive(Serialize, Deserialize, Clone, Debug, PartialEq, Eq)]
#[serde(
    tag = "type",
    rename_all = "camelCase",
    rename_all_fields = "camelCase"
)]
pub enum Quality {
    Max,
    Min,
    Video { height: u32 },
    Audio { bitrate: u32 },
}

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct DownloadRequest {
    pub url: String,
    pub format: Format,
    pub quality: Quality,
    pub is_playlist: bool,
}

// ───────────────────────── Analyze ─────────────────────────

// These narrow quality types keep each estimate's format paired with its
// matching quality variant in the JSON contract.
#[derive(Serialize, Deserialize, Clone, Debug, PartialEq, Eq)]
#[serde(
    tag = "type",
    rename_all = "camelCase",
    rename_all_fields = "camelCase"
)]
pub enum AudioEstimateQuality {
    Audio { bitrate: u32 },
}

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq, Eq)]
#[serde(
    tag = "type",
    rename_all = "camelCase",
    rename_all_fields = "camelCase"
)]
pub enum VideoEstimateQuality {
    Video { height: u32 },
}

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq, Eq)]
#[serde(
    tag = "format",
    rename_all = "camelCase",
    rename_all_fields = "camelCase"
)]
pub enum SingleEstimate {
    Mp3 {
        quality: AudioEstimateQuality,
        estimated_bytes: u64,
    },
    Mp4 {
        quality: VideoEstimateQuality,
        estimated_bytes: u64,
    },
}

#[derive(Serialize, Deserialize, Clone, Debug)]
#[serde(
    tag = "kind",
    rename_all = "camelCase",
    rename_all_fields = "camelCase"
)]
pub enum AnalyzeResult {
    Single {
        url: String,
        title: String,
        author: String,
        thumbnail: Option<String>,
        duration_sec: u64,
        site: String,
        video_heights: Vec<u32>,
        audio_output_bitrates: Vec<u32>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        estimates: Option<Vec<SingleEstimate>>,
    },
    Playlist {
        url: String,
        title: String,
        author: String,
        thumbnail: Option<String>,
        site: String,
        item_count: u32,
        item_titles: Vec<String>,
    },
}

// ───────────────────────── Queue ─────────────────────────

#[derive(Serialize, Deserialize, Clone, Copy, Debug, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum ItemStatus {
    Analyzing,
    Queued,
    Downloading,
    /// ffmpeg extraction, merging or metadata work. Pause is disabled.
    PostProcessing,
    Paused,
    /// ZIP writing or finalization. Pause is disabled.
    Packaging,
    /// Transient: history is written and then the item leaves the queue.
    Done,
    /// Transient: an error notification is persisted, then the item leaves the queue.
    Failed,
}

#[derive(Serialize, Deserialize, Clone, Debug)]
#[serde(
    tag = "kind",
    rename_all = "camelCase",
    rename_all_fields = "camelCase"
)]
pub enum Progress {
    Single {
        percent: f32,
    },
    Playlist {
        done: u32,
        failed: u32,
        total: u32,
        current_title: Option<String>,
        current_percent: f32,
    },
}

#[derive(Serialize, Deserialize, Clone, Debug)]
#[serde(rename_all = "camelCase")]
pub struct QueueItem {
    pub id: String,
    pub request: DownloadRequest,
    pub title: Option<String>,
    pub thumbnail: Option<String>,
    pub status: ItemStatus,
    pub progress: Progress,
    pub error: Option<AppError>,
}

// ───────────────────────── History ─────────────────────────

#[derive(Serialize, Deserialize, Clone, Debug)]
#[serde(rename_all = "camelCase")]
pub struct HistoryEntry {
    pub id: i64,
    pub request: DownloadRequest,
    pub title: Option<String>,
}

/// Persisted until dismissed, even though the failed item leaves the queue.
#[derive(Serialize, Deserialize, Clone, Debug)]
#[serde(rename_all = "camelCase")]
pub struct ErrorNotification {
    /// Id of the queue item that failed.
    pub id: String,
    pub title: Option<String>,
    pub error: AppError,
}

// ───────────────────────── Settings ─────────────────────────

#[derive(Serialize, Deserialize, Clone, Copy, Debug, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum Language {
    En,
    Es,
}

#[derive(Serialize, Deserialize, Clone, Debug)]
#[serde(rename_all = "camelCase")]
pub struct Settings {
    pub language: Language,
    pub zip_playlists: bool,
    /// None = system Downloads folder. Ignored on Android (MediaStore).
    pub download_dir: Option<String>,
}

// ───────────────────────── Engine updates ─────────────────────────

#[derive(Serialize, Deserialize, Clone, Debug)]
#[serde(rename_all = "camelCase")]
pub struct EngineUpdateInfo {
    pub current: String,
    pub latest: String,
    pub update_available: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub pending_version: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub reverted_version: Option<String>,
}

// ───────────────────────── Errors ─────────────────────────

#[derive(Serialize, Deserialize, Clone, Copy, Debug, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum ErrorCode {
    InvalidUrl,
    UnsupportedSite,
    PrivateOrRestricted,
    NotFound,
    NoInternet,
    DiskFull,
    PermissionDenied,
    EngineMissing,
    Unknown,
}

/// Returned as the Err side of every command. Tauri only needs `Serialize`.
#[derive(Serialize, Deserialize, Clone, Debug)]
#[serde(rename_all = "camelCase")]
pub struct AppError {
    pub code: ErrorCode,
    pub detail: Option<String>,
}

impl AppError {
    pub fn new(code: ErrorCode, detail: impl Into<Option<String>>) -> Self {
        Self {
            code,
            detail: detail.into(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn update_status_additions_are_optional_and_camel_case() {
        let legacy: EngineUpdateInfo = serde_json::from_value(serde_json::json!({
            "current": "2026.08.19", "latest": "2026.10.26", "updateAvailable": true
        }))
        .unwrap();
        assert!(legacy.pending_version.is_none());
        let status = EngineUpdateInfo {
            pending_version: Some("2026.10.26".into()),
            reverted_version: Some("2026.10.21".into()),
            ..legacy
        };
        let value = serde_json::to_value(status).unwrap();
        assert_eq!(value["pendingVersion"], "2026.10.26");
        assert_eq!(value["revertedVersion"], "2026.10.21");
    }

    #[test]
    fn request_serializes_with_the_frontend_contract_shape() {
        let request = DownloadRequest {
            url: "https://example.com/media".to_string(),
            format: Format::Mp3,
            quality: Quality::Audio { bitrate: 320 },
            is_playlist: false,
        };

        let json = serde_json::to_value(request).expect("request should serialize");
        assert_eq!(json["format"], "mp3");
        assert_eq!(json["quality"]["type"], "audio");
        assert_eq!(json["quality"]["bitrate"], 320);
        assert_eq!(json["isPlaylist"], false);
    }

    #[test]
    fn playlist_progress_serializes_with_camel_case_fields() {
        let progress = Progress::Playlist {
            done: 2,
            failed: 1,
            total: 5,
            current_title: Some("Example".to_string()),
            current_percent: 42.5,
        };

        let json = serde_json::to_value(progress).expect("progress should serialize");
        assert_eq!(json["kind"], "playlist");
        assert_eq!(json["currentTitle"], "Example");
        assert_eq!(json["currentPercent"], 42.5);
    }

    #[test]
    fn shared_fixture_deserializes_with_the_rust_contract_shape() {
        let fixture: serde_json::Value =
            serde_json::from_str(include_str!("../../tests/contract-fixtures.json"))
                .expect("shared fixture should be valid JSON");
        let request: DownloadRequest = serde_json::from_value(fixture["downloadRequest"].clone())
            .expect("download request fixture should match the Rust contract");
        let progress: Progress = serde_json::from_value(fixture["playlistProgress"].clone())
            .expect("playlist progress fixture should match the Rust contract");
        let single: AnalyzeResult = serde_json::from_value(fixture["singleAnalyzeResult"].clone())
            .expect("single result fixture should match the Rust contract");

        assert_eq!(request.format, Format::Mp3);
        assert_eq!(request.quality, Quality::Audio { bitrate: 320 });
        assert_eq!(request.is_playlist, false);
        match progress {
            Progress::Playlist {
                done,
                failed,
                total,
                current_title,
                current_percent,
            } => {
                assert_eq!(done, 2);
                assert_eq!(failed, 1);
                assert_eq!(total, 5);
                assert_eq!(current_title.as_deref(), Some("Example"));
                assert_eq!(current_percent, 42.5);
            }
            Progress::Single { .. } => panic!("fixture should be playlist progress"),
        }
        let single_json = serde_json::to_value(single).expect("single result should serialize");
        assert_eq!(single_json, fixture["singleAnalyzeResult"]);
    }

    #[test]
    fn single_estimates_are_optional_and_format_matches_quality() {
        let mut single: serde_json::Value =
            serde_json::from_str(include_str!("../../tests/contract-fixtures.json"))
                .expect("shared fixture should be valid JSON");
        let single = &mut single["singleAnalyzeResult"];

        single.as_object_mut().unwrap().remove("estimates");
        let without_estimates: AnalyzeResult = serde_json::from_value(single.clone())
            .expect("an absent estimate field should deserialize");
        let round_trip = serde_json::to_value(without_estimates).unwrap();
        assert!(round_trip.get("estimates").is_none());

        single["estimates"] = serde_json::json!([{
            "format": "mp3",
            "quality": { "type": "video", "height": 720 },
            "estimatedBytes": 8000000
        }]);
        assert!(serde_json::from_value::<AnalyzeResult>(single.clone()).is_err());
    }
}
