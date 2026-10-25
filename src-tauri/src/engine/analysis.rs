// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

//! Metadata-only yt-dlp analysis. The contract conversion deliberately omits
//! size estimates: format transfer sizes do not reliably include merged audio
//! or later MP3 copy/reencode decisions.

use super::{process::Supervisor, EnginePaths};
use crate::contract::{AnalyzeResult, AppError, ErrorCode};
use serde_json::Value;
use std::{collections::BTreeSet, ffi::OsString, sync::atomic::AtomicBool, time::Duration};
use url::Url;

const ANALYSIS_TIMEOUT: Duration = Duration::from_secs(180);
const OUTPUT_LIMIT: usize = 16 * 1024 * 1024;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Mode {
    Single,
    Playlist,
}

fn parsed_url(input: &str) -> Result<Url, AppError> {
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
    let mut args = vec![
        "--ignore-config".into(),
        "--no-plugin-dirs".into(),
        "--no-remote-components".into(),
        "--no-cache-dir".into(),
        "--no-js-runtimes".into(),
        "--js-runtimes".into(),
        OsString::from(format!("quickjs:{}", paths.quickjs.display())),
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
    let url = input.trim();
    let parsed = parsed_url(url)?;
    let args = arguments(paths, url, mode_for_url(&parsed));
    let output = supervisor
        .run(&paths.yt_dlp, &args, ANALYSIS_TIMEOUT, OUTPUT_LIMIT, cancel)
        .map_err(|error| AppError::new(ErrorCode::Unknown, Some(error.to_string())))?;
    if !output.status.success() {
        return Err(AppError::new(
            ErrorCode::Unknown,
            Some(String::from_utf8_lossy(&output.stderr).into_owned()),
        ));
    }
    parse_result(url, &output.stdout)
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
            if matches!(nonempty(format, "vcodec"), None | Some("none"))
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

pub fn parse_result(input_url: &str, json: &[u8]) -> Result<AnalyzeResult, AppError> {
    let url = parsed_url(input_url)?;
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
            duration_sec: value.get("duration").and_then(Value::as_u64).unwrap_or(0),
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
}
