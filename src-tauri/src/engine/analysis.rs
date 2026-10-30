// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

//! Metadata-only yt-dlp analysis. The contract conversion deliberately omits
//! size estimates: format transfer sizes do not reliably include merged audio
//! or later MP3 copy/reencode decisions.

use super::{
    process::{RunError, Supervisor},
    EnginePaths,
};
use crate::contract::{AnalyzeResult, AppError, ErrorCode};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::{collections::BTreeSet, ffi::OsString, sync::atomic::AtomicBool, time::Duration};
use url::Url;

const ANALYSIS_TIMEOUT: Duration = Duration::from_secs(180);
const OUTPUT_LIMIT: usize = 16 * 1024 * 1024;
const URL_LIMIT: usize = 8 * 1024;
pub const MAX_PLAYLIST_ENTRIES: usize = 10_000;

/// Private ordered work list. The public analyze result intentionally contains titles only.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct PlaylistEntry {
    pub url: String,
    pub title: String,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct PlaylistSnapshot {
    pub entries: Vec<PlaylistEntry>,
    pub next_index: usize,
}

impl PlaylistSnapshot {
    pub fn validate(&self) -> Result<(), AppError> {
        if self.entries.is_empty()
            || self.entries.len() > MAX_PLAYLIST_ENTRIES
            || self.next_index > self.entries.len()
            || self.entries.iter().any(|entry| {
                entry.title.trim().is_empty()
                    || entry.title.len() > 1024
                    || parsed_url(&entry.url).is_err()
            })
        {
            return Err(AppError::new(
                ErrorCode::Unknown,
                Some("invalid playlist snapshot".into()),
            ));
        }
        Ok(())
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Mode {
    Single,
    Playlist,
}

fn parsed_url(input: &str) -> Result<Url, AppError> {
    if input.len() > URL_LIMIT {
        return Err(AppError::new(
            ErrorCode::InvalidUrl,
            Some(format!("URL exceeds {URL_LIMIT} bytes")),
        ));
    }
    let parsed = Url::parse(input)
        .map_err(|error| AppError::new(ErrorCode::InvalidUrl, Some(error.to_string())))?;
    if !matches!(parsed.scheme(), "http" | "https") || parsed.host_str().is_none() {
        return Err(AppError::new(
            ErrorCode::InvalidUrl,
            Some("URL must have an HTTP(S) host".into()),
        ));
    }
    Ok(parsed)
}

fn mode_for_url(url: &Url) -> Mode {
    let host = url.host_str().unwrap_or_default();
    let youtube = host == "youtube.com" || host.ends_with(".youtube.com") || host == "youtu.be";
    let watch_video = url.path() == "/watch"
        && url
            .query_pairs()
            .any(|(name, value)| name == "v" && !value.is_empty());
    if youtube && (watch_video || host == "youtu.be") {
        return Mode::Single;
    }
    // Other extractors can decide whether a URL is a video or a playlist.
    // Flat extraction avoids fetching every entry's full metadata.
    Mode::Playlist
}

fn arguments(paths: &EnginePaths, url: &str, mode: Mode) -> Vec<OsString> {
    let mut runtime = OsString::from("quickjs:");
    runtime.push(&paths.quickjs);
    let mut args = vec![
        "--ignore-config".into(),
        "--no-plugin-dirs".into(),
        "--no-remote-components".into(),
        "--no-cache-dir".into(),
        "--no-js-runtimes".into(),
        "--js-runtimes".into(),
        runtime,
        "--skip-download".into(),
        "--dump-single-json".into(),
        "--socket-timeout".into(),
        "15".into(),
        "--retries".into(),
        "0".into(),
        "--extractor-retries".into(),
        "0".into(),
    ];
    args.push(match mode {
        Mode::Single => "--no-playlist".into(),
        Mode::Playlist => "--flat-playlist".into(),
    });
    args.push("--".into());
    args.push(url.into());
    args
}

pub fn analyze(
    paths: &EnginePaths,
    supervisor: &Supervisor,
    input: &str,
    cancel: &AtomicBool,
) -> Result<AnalyzeResult, AppError> {
    analyze_classified(paths, supervisor, input, cancel).0
}

pub(crate) fn analyze_classified(
    paths: &EnginePaths,
    supervisor: &Supervisor,
    input: &str,
    cancel: &AtomicBool,
) -> (Result<AnalyzeResult, AppError>, bool) {
    let mut broken = false;
    let result = (|| {
        let url = input.trim();
        let parsed = parsed_url(url)?;
        let args = arguments(paths, url, mode_for_url(&parsed));
        let output = supervisor
            .run(&paths.yt_dlp, &args, ANALYSIS_TIMEOUT, OUTPUT_LIMIT, cancel)
            .map_err(|error| {
                broken = run_failure_is_breakage(&error);
                process_error(error)
            })?;
        if !output.status.success() {
            broken = nonzero_is_breakage(output.status.code(), &output.stderr);
            return Err(extraction_error(&output.stderr, output.status.code()));
        }
        if serde_json::from_slice::<Value>(&output.stdout).is_err() {
            broken = true;
        }
        parse_result(url, &output.stdout)
    })();
    (result, broken)
}

/// Resolve flat entries once. A resumed queue item reads the stored list instead.
pub fn expand_playlist(
    paths: &EnginePaths,
    supervisor: &Supervisor,
    input: &str,
    cancel: &AtomicBool,
) -> Result<(String, PlaylistSnapshot), AppError> {
    expand_playlist_classified(paths, supervisor, input, cancel).0
}

pub(crate) fn expand_playlist_classified(
    paths: &EnginePaths,
    supervisor: &Supervisor,
    input: &str,
    cancel: &AtomicBool,
) -> (Result<(String, PlaylistSnapshot), AppError>, bool) {
    let mut broken = false;
    let result = (|| {
        let url = input.trim();
        parsed_url(url)?;
        let output = supervisor
            .run(
                paths.yt_dlp.as_path(),
                &arguments(paths, url, Mode::Playlist),
                ANALYSIS_TIMEOUT,
                OUTPUT_LIMIT,
                cancel,
            )
            .map_err(|error| {
                broken = run_failure_is_breakage(&error);
                process_error(error)
            })?;
        if !output.status.success() {
            broken = nonzero_is_breakage(output.status.code(), &output.stderr);
            return Err(extraction_error(&output.stderr, output.status.code()));
        }
        if serde_json::from_slice::<Value>(&output.stdout).is_err() {
            broken = true;
        }
        parse_playlist_snapshot(&output.stdout)
    })();
    (result, broken)
}

pub fn parse_playlist_snapshot(json: &[u8]) -> Result<(String, PlaylistSnapshot), AppError> {
    if json.len() > OUTPUT_LIMIT {
        return Err(AppError::new(
            ErrorCode::Unknown,
            Some("playlist JSON is too large".into()),
        ));
    }
    let value: Value = serde_json::from_slice(json).map_err(|error| {
        AppError::new(
            ErrorCode::Unknown,
            Some(format!("invalid playlist JSON: {error}")),
        )
    })?;
    if nonempty(&value, "_type") != Some("playlist") {
        return Err(AppError::new(
            ErrorCode::Unknown,
            Some("source is not a playlist".into()),
        ));
    }
    let title = nonempty(&value, "title")
        .ok_or_else(|| AppError::new(ErrorCode::Unknown, Some("playlist has no title".into())))?
        .to_owned();
    let raw = value
        .get("entries")
        .and_then(Value::as_array)
        .ok_or_else(|| AppError::new(ErrorCode::Unknown, Some("playlist has no entries".into())))?;
    if raw.is_empty() || raw.len() > MAX_PLAYLIST_ENTRIES {
        return Err(AppError::new(
            ErrorCode::Unknown,
            Some("invalid playlist entry count".into()),
        ));
    }
    let mut entries = Vec::with_capacity(raw.len());
    for (index, entry) in raw.iter().enumerate() {
        if nonempty(entry, "_type") == Some("playlist") {
            return Err(AppError::new(
                ErrorCode::Unknown,
                Some(format!("entry {} is a nested playlist", index + 1)),
            ));
        }
        let title = nonempty(entry, "title")
            .or_else(|| nonempty(entry, "id"))
            .ok_or_else(|| {
                AppError::new(
                    ErrorCode::Unknown,
                    Some(format!("entry {} has no title", index + 1)),
                )
            })?;
        let candidate = nonempty(entry, "webpage_url")
            .or_else(|| {
                nonempty(entry, "url")
                    .filter(|url| url.starts_with("http://") || url.starts_with("https://"))
            })
            .map(str::to_owned)
            .or_else(|| {
                let key = nonempty(entry, "ie_key").or_else(|| nonempty(entry, "extractor_key"));
                let id = nonempty(entry, "id")?;
                if matches!(key, Some("Youtube"))
                    && id.len() <= 64
                    && id
                        .chars()
                        .all(|ch| ch.is_ascii_alphanumeric() || "-_".contains(ch))
                {
                    Some(format!("https://www.youtube.com/watch?v={id}"))
                } else {
                    None
                }
            })
            .ok_or_else(|| {
                AppError::new(
                    ErrorCode::Unknown,
                    Some(format!("entry {} has no executable URL", index + 1)),
                )
            })?;
        parsed_url(&candidate)?;
        entries.push(PlaylistEntry {
            url: candidate,
            title: title.to_owned(),
        });
    }
    let snapshot = PlaylistSnapshot {
        entries,
        next_index: 0,
    };
    snapshot.validate()?;
    Ok((title, snapshot))
}

pub(crate) fn reported_site_error(stderr: &[u8]) -> bool {
    String::from_utf8_lossy(stderr).lines().any(|line| {
        let line = line.trim_start();
        line.starts_with("ERROR:") || line.starts_with("WARNING:")
    })
}

pub(crate) fn nonzero_is_breakage(code: Option<i32>, stderr: &[u8]) -> bool {
    code.is_none_or(|code| code < 0) || !reported_site_error(stderr)
}

pub(crate) fn run_failure_is_breakage(error: &RunError) -> bool {
    !matches!(error, RunError::Cancelled)
}

fn process_error(error: RunError) -> AppError {
    let code = match &error {
        RunError::Io(error) if error.kind() == std::io::ErrorKind::NotFound => {
            ErrorCode::EngineMissing
        }
        RunError::Io(_) | RunError::TimedOut | RunError::Cancelled | RunError::OutputLimit => {
            ErrorCode::Unknown
        }
    };
    AppError::new(code, Some(format!("analysis process: {error}")))
}

pub(super) fn extraction_error(stderr: &[u8], status: Option<i32>) -> AppError {
    let raw = String::from_utf8_lossy(stderr).into_owned();
    let diagnostic = raw
        .lines()
        .find(|line| line.trim_start().starts_with("ERROR:"))
        .unwrap_or(&raw)
        .to_ascii_lowercase();
    // Keep the original diagnostic in detail; classification is deliberately
    // narrow so an unfamiliar extractor failure is not mislabeled as a site error.
    let code = if diagnostic.contains("not a valid url") {
        ErrorCode::InvalidUrl
    } else if diagnostic.contains("unsupported url") || diagnostic.contains("no suitable extractor")
    {
        ErrorCode::UnsupportedSite
    } else if [
        "http error 401",
        "http error 403",
        "private video",
        "this video is private",
        "members-only",
        "age-restricted",
        "geo-restricted",
        "not available in your country",
        "sign in to confirm your age",
    ]
    .iter()
    .any(|pattern| diagnostic.contains(pattern))
    {
        ErrorCode::PrivateOrRestricted
    } else if [
        "http error 404",
        "video not found",
        "video unavailable",
        "video has been removed",
        "this video is unavailable",
    ]
    .iter()
    .any(|pattern| diagnostic.contains(pattern))
    {
        ErrorCode::NotFound
    } else if [
        "network is unreachable",
        "no internet connection",
        "connection refused",
        "connection timed out",
        "temporary failure in name resolution",
        "failed to resolve",
        "getaddrinfo failed",
        "unable to resolve host",
    ]
    .iter()
    .any(|pattern| diagnostic.contains(pattern))
    {
        ErrorCode::NoInternet
    } else if [
        "no supported javascript runtime",
        "quickjs is not installed",
        "failed to execute quickjs",
    ]
    .iter()
    .any(|pattern| diagnostic.contains(pattern))
    {
        ErrorCode::EngineMissing
    } else {
        ErrorCode::Unknown
    };
    let detail = if raw.is_empty() {
        format!("yt-dlp exited with status {status:?} without stderr")
    } else {
        raw
    };
    AppError::new(code, Some(detail))
}

fn nonempty<'a>(value: &'a Value, key: &str) -> Option<&'a str> {
    value
        .get(key)?
        .as_str()
        .filter(|text| !text.trim().is_empty())
}

fn author(value: &Value) -> String {
    ["artist", "creator", "uploader", "channel", "uploader_id"]
        .into_iter()
        .find_map(|key| nonempty(value, key))
        .unwrap_or("Unknown")
        .to_owned()
}

fn site(value: &Value, url: &Url) -> String {
    match nonempty(value, "extractor_key") {
        Some("Youtube" | "YoutubeTab") => "YouTube".into(),
        Some("InternetArchive") => "Internet Archive".into(),
        Some(name) => name.to_owned(),
        None => url.host_str().unwrap_or("Unknown site").to_owned(),
    }
}

fn cover(value: &Value) -> Option<String> {
    if let Some(image) = nonempty(value, "thumbnail") {
        return Some(image.to_owned());
    }
    value
        .get("thumbnails")?
        .as_array()?
        .iter()
        .rev()
        .find_map(|item| nonempty(item, "url"))
        .map(str::to_owned)
}

fn video_heights(value: &Value) -> Vec<u32> {
    let mut heights = BTreeSet::new();
    if let Some(formats) = value.get("formats").and_then(Value::as_array) {
        for format in formats {
            if nonempty(format, "vcodec") == Some("none")
                || nonempty(format, "ext") == Some("mhtml")
            {
                continue;
            }
            if let Some(height) = format
                .get("height")
                .and_then(Value::as_u64)
                .and_then(|height| u32::try_from(height).ok())
                .filter(|height| *height > 0)
            {
                heights.insert(height);
            }
        }
    }
    heights.into_iter().rev().collect()
}

fn duration_seconds(value: &Value) -> u64 {
    let Some(duration) = value.get("duration").and_then(Value::as_f64) else {
        return 0;
    };
    if duration.is_finite() && duration > 0.0 {
        duration.round() as u64
    } else {
        0
    }
}

pub fn parse_result(input_url: &str, json: &[u8]) -> Result<AnalyzeResult, AppError> {
    let url = parsed_url(input_url)?;
    if json.len() > OUTPUT_LIMIT {
        return Err(AppError::new(
            ErrorCode::Unknown,
            Some(format!("analysis JSON exceeds {OUTPUT_LIMIT} bytes")),
        ));
    }
    let value: Value = serde_json::from_slice(json).map_err(|error| {
        AppError::new(
            ErrorCode::Unknown,
            Some(format!("invalid analysis JSON: {error}")),
        )
    })?;
    let title = nonempty(&value, "title")
        .ok_or_else(|| AppError::new(ErrorCode::Unknown, Some("analysis has no title".into())))?
        .to_owned();
    let author = author(&value);
    let site = site(&value, &url);
    if nonempty(&value, "_type") == Some("playlist") {
        let entries = value
            .get("entries")
            .and_then(Value::as_array)
            .ok_or_else(|| {
                AppError::new(ErrorCode::Unknown, Some("playlist has no entries".into()))
            })?;
        let item_titles = entries
            .iter()
            .enumerate()
            .map(|(index, entry)| {
                nonempty(entry, "title")
                    .or_else(|| nonempty(entry, "id"))
                    .map(str::to_owned)
                    .unwrap_or_else(|| format!("Item {}", index + 1))
            })
            .collect::<Vec<_>>();
        let item_count = u32::try_from(item_titles.len())
            .map_err(|_| AppError::new(ErrorCode::Unknown, Some("playlist is too large".into())))?;
        let thumbnail = cover(&value).or_else(|| entries.first().and_then(cover));
        Ok(AnalyzeResult::Playlist {
            url: input_url.to_owned(),
            title,
            author,
            thumbnail,
            site,
            item_count,
            item_titles,
        })
    } else if matches!(nonempty(&value, "_type"), None | Some("video")) {
        Ok(AnalyzeResult::Single {
            url: input_url.to_owned(),
            title,
            author,
            thumbnail: cover(&value),
            duration_sec: duration_seconds(&value),
            site,
            video_heights: video_heights(&value),
            audio_output_bitrates: vec![320, 256, 192, 128],
            estimates: None,
        })
    } else {
        Err(AppError::new(
            ErrorCode::Unknown,
            Some("analysis did not return a video or playlist".into()),
        ))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;
    use std::path::PathBuf;

    const SINGLE: &[u8] = include_bytes!("../../tests/fixtures/2b/single.json");
    const PLAYLIST: &[u8] = include_bytes!("../../tests/fixtures/2b/playlist.json");
    const MIXED: &[u8] = include_bytes!("../../tests/fixtures/2b/mixed.json");
    const SINGLE_URL: &str = "https://www.youtube.com/watch?v=uW13KuRrg1g";
    const PLAYLIST_URL: &str = "https://www.youtube.com/playlist?list=PL6B3937A5D230E335";
    const MIXED_URL: &str = "https://www.youtube.com/watch?v=u9lj-c29dxI&list=PL6B3937A5D230E335";

    #[test]
    fn probation_distinguishes_process_breakage_from_reported_site_errors() {
        assert!(nonzero_is_breakage(Some(7), b"plain crash"));
        assert!(nonzero_is_breakage(None, b"ERROR: unavailable"));
        assert!(nonzero_is_breakage(Some(-1), b"WARNING: crash"));
        assert!(!nonzero_is_breakage(Some(2), b"ERROR: HTTP Error 403"));
        assert!(!nonzero_is_breakage(Some(2), b"WARNING: network issue"));
        assert!(run_failure_is_breakage(&RunError::Io(
            std::io::Error::from(std::io::ErrorKind::NotFound)
        )));
        assert!(run_failure_is_breakage(&RunError::TimedOut));
        assert!(run_failure_is_breakage(&RunError::OutputLimit));
        assert!(!run_failure_is_breakage(&RunError::Cancelled));
    }

    #[test]
    fn gate_0b_single_has_real_video_heights_and_fixed_audio_maxima() {
        let result = parse_result(SINGLE_URL, SINGLE).unwrap();
        let value = serde_json::to_value(result).unwrap();
        assert_eq!(value["kind"], "single");
        assert_eq!(value["title"], "10號風...");
        assert_eq!(value["author"], "vgocyl");
        assert_eq!(value["durationSec"], 15);
        assert_eq!(value["site"], "YouTube");
        assert_eq!(value["videoHeights"], json!([720, 360, 144]));
        assert_eq!(value["audioOutputBitrates"], json!([320, 256, 192, 128]));
        assert!(value.get("estimates").is_none());
    }

    #[test]
    fn gate_0b_playlist_keeps_its_own_cover_and_all_titles() {
        let result = parse_result(PLAYLIST_URL, PLAYLIST).unwrap();
        let value = serde_json::to_value(result).unwrap();
        assert_eq!(value["kind"], "playlist");
        assert_eq!(value["title"], "Official Blender Open Movies");
        assert_eq!(value["author"], "Blender");
        assert_eq!(value["itemCount"], 17);
        assert_eq!(value["itemTitles"].as_array().unwrap().len(), 17);
        assert_eq!(value["itemTitles"][1], "WING IT! - Blender Open Movie");
        assert!(value["thumbnail"].as_str().unwrap().contains("WhWc3b3KhnY"));
    }

    #[test]
    fn mixed_watch_list_remains_one_video_and_preserves_request_url() {
        let result = parse_result(MIXED_URL, MIXED).unwrap();
        let value = serde_json::to_value(result).unwrap();
        assert_eq!(value["kind"], "single");
        assert_eq!(value["url"], MIXED_URL);
        assert_eq!(
            value["videoHeights"],
            json!([1080, 720, 480, 360, 240, 144])
        );
        assert_eq!(value["durationSec"], 238);
    }

    #[test]
    fn playlist_cover_falls_back_to_first_entry_only_when_own_cover_absent() {
        let mut value: Value = serde_json::from_slice(PLAYLIST).unwrap();
        value["thumbnail"] = Value::Null;
        value["thumbnails"] = json!([]);
        let parsed = parse_result(PLAYLIST_URL, &serde_json::to_vec(&value).unwrap()).unwrap();
        let parsed = serde_json::to_value(parsed).unwrap();
        assert!(parsed["thumbnail"]
            .as_str()
            .unwrap()
            .contains("l5OZu-IrXpw"));
    }

    #[test]
    fn fractional_duration_and_unknown_video_codec_keep_real_metadata() {
        let mut value: Value = serde_json::from_slice(SINGLE).unwrap();
        value["duration"] = json!(9.74);
        value["formats"] = json!([
            {"height": 360, "ext": "mp4"},
            {"height": 24, "ext": "mhtml", "vcodec": "none"}
        ]);
        let parsed = parse_result(SINGLE_URL, &serde_json::to_vec(&value).unwrap()).unwrap();
        let parsed = serde_json::to_value(parsed).unwrap();
        assert_eq!(parsed["durationSec"], 10);
        assert_eq!(parsed["videoHeights"], json!([360]));
    }

    #[test]
    fn command_uses_argv_checked_quickjs_and_correct_modes() {
        let paths = EnginePaths {
            yt_dlp: PathBuf::from(r"C:\App Data\engine\yt-dlp.exe"),
            ffmpeg: PathBuf::from(r"C:\App Data\engine\ffmpeg.exe"),
            quickjs: PathBuf::from(r"C:\App Data\engine\qjs.exe"),
        };
        for (url, mode) in [
            (SINGLE_URL, Mode::Single),
            (PLAYLIST_URL, Mode::Playlist),
            (MIXED_URL, Mode::Single),
        ] {
            let selected = mode_for_url(&parsed_url(url).unwrap());
            assert_eq!(selected, mode);
            let args = arguments(&paths, url, selected);
            assert_eq!(args.last().unwrap(), url);
            assert_eq!(args[args.len() - 2], "--");
            assert!(args.contains(&OsString::from(if mode == Mode::Single {
                "--no-playlist"
            } else {
                "--flat-playlist"
            })));
            assert!(args.contains(&OsString::from(r"quickjs:C:\App Data\engine\qjs.exe")));
            assert_eq!(args[0], "--ignore-config");
        }
        assert_eq!(
            mode_for_url(
                &parsed_url("https://www.youtube.com/watch?list=PL6B3937A5D230E335").unwrap()
            ),
            Mode::Playlist
        );
    }

    #[test]
    fn rejects_invalid_and_oversized_urls_before_launch() {
        for input in [
            "not-a-url".to_owned(),
            "file:///C:/secret".to_owned(),
            "https:///".to_owned(),
            format!("https://example.com/{}", "x".repeat(URL_LIMIT)),
        ] {
            assert_eq!(parsed_url(&input).unwrap_err().code, ErrorCode::InvalidUrl);
        }
    }

    #[test]
    fn observed_and_known_extraction_errors_keep_diagnostics() {
        let cases = [
            (
                "ERROR: [generic] 'not-a-url' is not a valid URL",
                ErrorCode::InvalidUrl,
            ),
            (
                "ERROR: Unsupported URL: https://example.invalid",
                ErrorCode::UnsupportedSite,
            ),
            (
                "ERROR: HTTP Error 401: Unauthorized",
                ErrorCode::PrivateOrRestricted,
            ),
            (
                "ERROR: HTTP Error 403: Forbidden",
                ErrorCode::PrivateOrRestricted,
            ),
            (
                "ERROR: Sign in to confirm your age",
                ErrorCode::PrivateOrRestricted,
            ),
            ("ERROR: HTTP Error 404: Not Found", ErrorCode::NotFound),
            ("ERROR: Video unavailable", ErrorCode::NotFound),
            ("ERROR: Network is unreachable", ErrorCode::NoInternet),
            ("ERROR: Failed to resolve host", ErrorCode::NoInternet),
            (
                "ERROR: No supported JavaScript runtime",
                ErrorCode::EngineMissing,
            ),
            ("ERROR: opening play-av tag not found", ErrorCode::Unknown),
            ("ERROR: extractor changed unexpectedly", ErrorCode::Unknown),
        ];
        for (diagnostic, expected) in cases {
            let error = extraction_error(diagnostic.as_bytes(), Some(1));
            assert_eq!(error.code, expected, "{diagnostic}");
            assert_eq!(error.detail.as_deref(), Some(diagnostic));
        }
        let empty = extraction_error(b"", Some(1));
        assert_eq!(empty.code, ErrorCode::Unknown);
        assert!(empty.detail.unwrap().contains("status Some(1)"));
    }

    #[test]
    fn process_failures_and_response_bounds_are_typed() {
        let missing = process_error(RunError::Io(std::io::ErrorKind::NotFound.into()));
        assert_eq!(missing.code, ErrorCode::EngineMissing);
        for failure in [
            RunError::TimedOut,
            RunError::Cancelled,
            RunError::OutputLimit,
        ] {
            let error = process_error(failure);
            assert_eq!(error.code, ErrorCode::Unknown);
            assert!(error.detail.unwrap().starts_with("analysis process:"));
        }
        let malformed = parse_result(SINGLE_URL, b"{no json").unwrap_err();
        assert_eq!(malformed.code, ErrorCode::Unknown);
        assert!(malformed.detail.unwrap().contains("invalid analysis JSON"));
        let oversized = parse_result(SINGLE_URL, &vec![b' '; OUTPUT_LIMIT + 1]).unwrap_err();
        assert_eq!(oversized.code, ErrorCode::Unknown);
        assert!(oversized.detail.unwrap().contains("exceeds"));
    }

    #[test]
    fn flat_snapshot_resolves_ordered_urls_and_rejects_bad_entries() {
        let value = serde_json::json!({
            "_type": "playlist", "title": "Set", "entries": [
                {"title": "First", "webpage_url": "https://example.com/first"},
                {"title": "Second", "id": "abc-12", "ie_key": "Youtube", "url": "abc-12"}
            ]
        });
        let (title, snapshot) =
            parse_playlist_snapshot(&serde_json::to_vec(&value).unwrap()).unwrap();
        assert_eq!(title, "Set");
        assert_eq!(snapshot.entries[0].url, "https://example.com/first");
        assert_eq!(
            snapshot.entries[1].url,
            "https://www.youtube.com/watch?v=abc-12"
        );
        assert_eq!(snapshot.entries[1].title, "Second");
        assert_eq!(snapshot.next_index, 0);
        for bad in [
            serde_json::json!({"_type":"playlist", "title":"Set", "entries": []}),
            serde_json::json!({"_type":"playlist", "title":"Set", "entries": [null]}),
            serde_json::json!({"_type":"playlist", "title":"Set", "entries": [{"title":"Bad", "url":"file:///secret"}]}),
            serde_json::json!({"_type":"playlist", "title":"Set", "entries": [{"_type":"playlist", "title":"Nested", "webpage_url":"https://example.com/nested"}]}),
        ] {
            assert!(parse_playlist_snapshot(&serde_json::to_vec(&bad).unwrap()).is_err());
        }
        assert!(parse_playlist_snapshot(&vec![b' '; OUTPUT_LIMIT + 1]).is_err());
        let too_many = PlaylistSnapshot {
            entries: vec![snapshot.entries[0].clone(); MAX_PLAYLIST_ENTRIES + 1],
            next_index: 0,
        };
        assert!(too_many.validate().is_err());
    }
}
