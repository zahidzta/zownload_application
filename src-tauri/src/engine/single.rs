// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

//! One Windows single download. Queue scheduling and UI event throttling are
//! owned by 2C-03; this module owns its child tree and its private files.

use super::{
    analysis::{self, PlaylistEntry},
    process::{RunError, Supervisor},
    EnginePaths,
};
use crate::{
    contract::{AppError, DownloadRequest, ErrorCode, Format, Quality},
    persistence::paths::DownloadPaths,
};
use serde_json::Value;
use std::{
    ffi::OsString,
    fs::{self, File, OpenOptions},
    io::{self, Write},
    path::{Path, PathBuf},
    sync::{atomic::AtomicBool, Arc, Mutex},
    time::Duration,
};
use url::Url;

const PROBE_LIMIT: usize = 16 * 1024 * 1024;
const DIAGNOSTIC_LIMIT: usize = 64 * 1024;
const TIMEOUT: Duration = Duration::from_secs(60 * 60 * 4);
const PROBE_TIMEOUT: Duration = Duration::from_secs(180);
const MAX_LINE: usize = 8 * 1024;
const PROGRESS: &str = "ZP1|%(info.id)s|%(progress.status)s|%(progress.downloaded_bytes|0)d|%(progress.total_bytes,progress.total_bytes_estimate|0)d";

#[derive(Clone, Debug, PartialEq)]
pub enum Observation {
    Title(String),
    Downloaded {
        bytes: u64,
        total: u64,
        percent: f64,
    },
    PostProcessing,
}

#[derive(Debug)]
pub struct Completed {
    pub path: PathBuf,
    pub title: String,
    pub selected_height: Option<u32>,
}

#[derive(Debug)]
struct Source {
    id: String,
    title: String,
    artist: String,
    extension: String,
    bitrate: Option<f64>,
    heights: Vec<u32>,
}

fn error(code: ErrorCode, detail: impl Into<String>) -> AppError {
    AppError::new(code, Some(detail.into()))
}

fn io_error(cause: io::Error) -> AppError {
    let code = match cause.raw_os_error() {
        Some(112 | 39) => ErrorCode::DiskFull,
        Some(5 | 13) => ErrorCode::PermissionDenied,
        _ if cause.kind() == io::ErrorKind::PermissionDenied => ErrorCode::PermissionDenied,
        _ => ErrorCode::Unknown,
    };
    error(code, cause.to_string())
}

fn run_error(cause: RunError) -> AppError {
    match cause {
        RunError::Io(cause) if cause.kind() == io::ErrorKind::NotFound => {
            error(ErrorCode::EngineMissing, cause.to_string())
        }
        RunError::Io(cause) => io_error(cause),
        other => error(ErrorCode::Unknown, other.to_string()),
    }
}

fn download_failure(stderr: &[u8], status: Option<i32>) -> AppError {
    let diagnostic = String::from_utf8_lossy(stderr);
    let lowered = diagnostic.to_ascii_lowercase();
    let code = if [
        "no space left on device",
        "disk full",
        "not enough space",
        "winerror 112",
        "errno 28",
    ]
    .iter()
    .any(|pattern| lowered.contains(pattern))
    {
        Some(ErrorCode::DiskFull)
    } else if [
        "permission denied",
        "access is denied",
        "winerror 5",
        "errno 13",
    ]
    .iter()
    .any(|pattern| lowered.contains(pattern))
    {
        Some(ErrorCode::PermissionDenied)
    } else {
        None
    };
    code.map(|code| error(code, diagnostic.into_owned()))
        .unwrap_or_else(|| analysis::extraction_error(stderr, status))
}

fn valid_request(request: &DownloadRequest) -> Result<(), AppError> {
    let parsed = Url::parse(&request.url)
        .map_err(|cause| error(ErrorCode::InvalidUrl, cause.to_string()))?;
    if request.url.len() > 8192
        || !matches!(parsed.scheme(), "http" | "https")
        || parsed.host_str().is_none()
    {
        return Err(error(
            ErrorCode::InvalidUrl,
            "URL must have an HTTP(S) host",
        ));
    }
    match (&request.format, &request.quality) {
        (Format::Mp3 | Format::Mp4, Quality::Max | Quality::Min) if request.is_playlist => Ok(()),
        (
            Format::Mp3,
            Quality::Audio {
                bitrate: 128 | 192 | 256 | 320,
            },
        ) if !request.is_playlist => Ok(()),
        (Format::Mp4, Quality::Video { height })
            if !request.is_playlist && *height > 0 && *height <= 4320 =>
        {
            Ok(())
        }
        _ => Err(error(ErrorCode::Unknown, "invalid format or quality")),
    }
}

fn common(paths: &EnginePaths) -> Vec<OsString> {
    let mut runtime = OsString::from("quickjs:");
    runtime.push(&paths.quickjs);
    vec![
        "--ignore-config".into(),
        "--no-plugin-dirs".into(),
        "--no-remote-components".into(),
        "--no-cache-dir".into(),
        "--no-js-runtimes".into(),
        "--js-runtimes".into(),
        runtime,
        "--no-playlist".into(),
        "--socket-timeout".into(),
        "15".into(),
        "--retries".into(),
        "0".into(),
        "--extractor-retries".into(),
        "0".into(),
    ]
}

fn probe_args(paths: &EnginePaths, request: &DownloadRequest) -> Vec<OsString> {
    let mut args = common(paths);
    args.extend([
        "-f".into(),
        "ba/b".into(),
        "--dump-single-json".into(),
        "--skip-download".into(),
        "--".into(),
        request.url.clone().into(),
    ]);
    args
}

fn source_from_json(bytes: &[u8]) -> Result<Source, AppError> {
    let value: Value = serde_json::from_slice(bytes).map_err(|cause| {
        error(
            ErrorCode::Unknown,
            format!("invalid source metadata: {cause}"),
        )
    })?;
    let text = |key: &str| {
        value
            .get(key)
            .and_then(Value::as_str)
            .filter(|text| !text.trim().is_empty())
    };
    let title = text("title").ok_or_else(|| error(ErrorCode::Unknown, "source has no title"))?;
    let id = text("id").ok_or_else(|| error(ErrorCode::Unknown, "source has no id"))?;
    let artist = ["artist", "creator", "uploader", "author"]
        .into_iter()
        .find_map(text)
        .unwrap_or("");
    let mut heights = value
        .get("formats")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .filter(|format| {
            format.get("vcodec").and_then(Value::as_str) != Some("none")
                && format.get("ext").and_then(Value::as_str) != Some("mhtml")
        })
        .filter_map(|format| format.get("height").and_then(Value::as_u64))
        .filter_map(|height| u32::try_from(height).ok())
        .filter(|height| *height > 0)
        .collect::<Vec<_>>();
    heights.sort_unstable();
    heights.dedup();
    Ok(Source {
        id: id.into(),
        title: title.into(),
        artist: artist.into(),
        extension: text("ext").unwrap_or("").into(),
        bitrate: value
            .get("abr")
            .or_else(|| value.get("tbr"))
            .and_then(Value::as_f64),
        heights,
    })
}

fn chosen_height(requested: u32, heights: &[u32]) -> Result<u32, AppError> {
    heights
        .iter()
        .copied()
        .filter(|height| *height <= requested)
        .max()
        .ok_or_else(|| {
            error(
                ErrorCode::Unknown,
                format!("no available video height at or below {requested}p"),
            )
        })
}

fn download_args(
    paths: &EnginePaths,
    request: &DownloadRequest,
    source: &Source,
    work_dir: &Path,
    height: Option<u32>,
) -> Vec<OsString> {
    let mut args = common(paths);
    args.extend([
        "--ffmpeg-location".into(),
        paths.ffmpeg.as_os_str().into(),
        "--continue".into(),
        "--part".into(),
        "--newline".into(),
        "--progress-template".into(),
        PROGRESS.into(),
        "--progress-template".into(),
        "postprocess:ZP2|%(progress.postprocessor)s|%(progress.status)s".into(),
        "--no-overwrites".into(),
        "--write-thumbnail".into(),
        "--convert-thumbnails".into(),
        "jpg".into(),
        "-o".into(),
        work_dir.join("source.%(ext)s").as_os_str().into(),
    ]);
    match (request.format, &request.quality) {
        (Format::Mp3, Quality::Audio { .. } | Quality::Max | Quality::Min) => {
            args.extend(["-f".into(), "ba/b".into()]);
        }
        (Format::Mp4, Quality::Max | Quality::Min) => {
            let selector = if request.quality == Quality::Max {
                "bv*+ba/b"
            } else {
                "wv*+ba/w"
            };
            args.extend([
                "-f".into(),
                selector.into(),
                "--merge-output-format".into(),
                "mp4".into(),
                "--recode-video".into(),
                "mp4".into(),
                "--postprocessor-args".into(),
                "Merger+ffmpeg_o:-c:a aac".into(),
                "--embed-metadata".into(),
                "--embed-thumbnail".into(),
                "--parse-metadata".into(),
                "%(artist,creator,uploader|)s:%(meta_artist)s".into(),
            ]);
        }
        (Format::Mp4, Quality::Video { .. }) => {
            let selected = height.expect("validated height");
            args.extend([
                "-f".into(),
                format!("bv*[height={selected}]+ba/b[height={selected}]").into(),
                "--merge-output-format".into(),
                "mp4".into(),
                "--recode-video".into(),
                "mp4".into(),
                "--postprocessor-args".into(),
                "Merger+ffmpeg_o:-c:a aac".into(),
                "--postprocessor-args".into(),
                format!("VideoConvertor+ffmpeg_o:-vf scale=-2:{selected}").into(),
                "--embed-metadata".into(),
                "--embed-thumbnail".into(),
                "--parse-metadata".into(),
                "%(artist,creator,uploader|)s:%(meta_artist)s".into(),
                "--parse-metadata".into(),
                "%(playlist_title|)s:%(meta_album)s".into(),
            ]);
        }
        _ => unreachable!("request checked before argument construction"),
    }
    let _ = source;
    args.extend(["--".into(), request.url.clone().into()]);
    args
}

#[derive(Default)]
struct Lines {
    pending: Vec<u8>,
    discard: bool,
    expected_id: Option<String>,
    media_finished: bool,
}

impl Lines {
    fn feed(&mut self, bytes: &[u8], observe: &dyn Fn(Observation)) {
        for byte in bytes {
            if *byte == b'\n' {
                if !self.discard {
                    self.line(observe);
                }
                self.pending.clear();
                self.discard = false;
            } else if !self.discard {
                if self.pending.len() == MAX_LINE {
                    self.pending.clear();
                    self.discard = true;
                } else {
                    self.pending.push(*byte);
                }
            }
        }
    }

    fn line(&mut self, observe: &dyn Fn(Observation)) {
        let Ok(line) = std::str::from_utf8(&self.pending) else {
            return;
        };
        let line = line.trim_end_matches('\r');
        // yt-dlp may convert a thumbnail before it starts transferring media.
        // Keep Stop available until the media progress stream has finished.
        if self.media_finished
            && (line.starts_with("ZP2|")
                || line.starts_with("[Merger]")
                || line.starts_with("[VideoConvertor]")
                || line.starts_with("[Metadata]")
                || line.starts_with("[EmbedThumbnail]")
                || line.starts_with("[ExtractAudio]"))
        {
            observe(Observation::PostProcessing);
        }
        let Some(fields) = line.strip_prefix("ZP1|") else {
            return;
        };
        let fields = fields.split('|').collect::<Vec<_>>();
        if fields.len() != 4
            || !matches!(fields[1], "downloading" | "finished")
            || self
                .expected_id
                .as_deref()
                .is_some_and(|id| id != fields[0])
        {
            return;
        }
        let (Ok(bytes), Ok(total)) = (fields[2].parse::<u64>(), fields[3].parse::<u64>()) else {
            return;
        };
        if total == 0 || bytes > total {
            return;
        }
        self.media_finished = fields[1] == "finished";
        observe(Observation::Downloaded {
            bytes,
            total,
            percent: (bytes as f64 / total as f64 * 100.0).min(100.0),
        });
    }
}

fn safe_title(title: &str) -> String {
    let mut clean = title
        .chars()
        .map(|ch| {
            if ch < ' ' || "<>:\"/\\|?*".contains(ch) {
                '_'
            } else {
                ch
            }
        })
        .take(120)
        .collect::<String>();
    clean = clean.trim().trim_end_matches(['.', ' ']).to_owned();
    let stem = clean.split('.').next().unwrap_or("").to_ascii_uppercase();
    if clean.is_empty()
        || matches!(
            stem.as_str(),
            "CON"
                | "PRN"
                | "AUX"
                | "NUL"
                | "COM1"
                | "COM2"
                | "COM3"
                | "COM4"
                | "COM5"
                | "COM6"
                | "COM7"
                | "COM8"
                | "COM9"
                | "LPT1"
                | "LPT2"
                | "LPT3"
                | "LPT4"
                | "LPT5"
                | "LPT6"
                | "LPT7"
                | "LPT8"
                | "LPT9"
        )
    {
        "download".into()
    } else {
        clean
    }
}

fn source_file(work_dir: &Path) -> Result<PathBuf, AppError> {
    fs::read_dir(work_dir)
        .map_err(io_error)?
        .filter_map(Result::ok)
        .map(|entry| entry.path())
        .find(|path| {
            path.file_stem().is_some_and(|stem| stem == "source")
                && path
                    .extension()
                    .is_some_and(|ext| ext != "jpg" && ext != "part")
        })
        .ok_or_else(|| error(ErrorCode::Unknown, "download produced no source file"))
}

fn mp3_args(
    source: &Source,
    input: &Path,
    cover: &Path,
    output: &Path,
    bitrate: u32,
    album: &str,
) -> Vec<OsString> {
    let mut args: Vec<OsString> = vec![
        "-nostdin".into(),
        "-y".into(),
        "-i".into(),
        input.as_os_str().into(),
    ];
    if cover.is_file() {
        args.extend(["-i".into(), cover.as_os_str().into()]);
    }
    args.extend(["-map".into(), "0:a:0".into()]);
    if cover.is_file() {
        args.extend([
            "-map".into(),
            "1:v:0".into(),
            "-c:v".into(),
            "mjpeg".into(),
            "-disposition:v:0".into(),
            "attached_pic".into(),
        ]);
    }
    let copy = source.extension.eq_ignore_ascii_case("mp3")
        && source
            .bitrate
            .is_some_and(|actual| actual <= bitrate as f64);
    if copy {
        args.extend(["-c:a".into(), "copy".into()]);
    } else {
        args.extend([
            "-c:a".into(),
            "libmp3lame".into(),
            "-b:a".into(),
            format!("{bitrate}k").into(),
        ]);
    }
    args.extend([
        "-id3v2_version".into(),
        "3".into(),
        "-metadata".into(),
        format!("title={}", source.title).into(),
    ]);
    if !source.artist.is_empty() {
        args.extend([
            "-metadata".into(),
            format!("artist={}", source.artist).into(),
        ]);
    }
    args.extend([
        "-metadata".into(),
        format!("album={album}").into(),
        "-f".into(),
        "mp3".into(),
        output.as_os_str().into(),
    ]);
    args
}

fn mp4_tag_args(source: &Source, input: &Path, output: &Path, album: &str) -> Vec<OsString> {
    // yt-dlp's selected derivative can carry a different embedded title than
    // the analyzed item. Copy every stream, including the JPEG cover, and set
    // the same title and creator used by the Queue and History.
    let mut args: Vec<OsString> = vec![
        "-nostdin".into(),
        "-y".into(),
        "-i".into(),
        input.as_os_str().into(),
        "-map".into(),
        "0".into(),
        "-c".into(),
        "copy".into(),
        "-metadata".into(),
        format!("title={}", source.title).into(),
    ];
    if !source.artist.is_empty() {
        args.extend([
            "-metadata".into(),
            format!("artist={}", source.artist).into(),
        ]);
    }
    args.extend([
        "-metadata".into(),
        format!("album={album}").into(),
        "-f".into(),
        "mp4".into(),
        output.as_os_str().into(),
    ]);
    args
}

fn ffmpeg_mp3_bitrate(stderr: &[u8]) -> Option<f64> {
    let text = String::from_utf8_lossy(stderr);
    text.lines()
        .filter(|line| line.contains("Audio: mp3"))
        .find_map(|line| {
            let before = line.split("kb/s").next()?;
            before.split_whitespace().last()?.parse::<f64>().ok()
        })
}

fn inspect_mp3_bitrate(
    paths: &EnginePaths,
    supervisor: &Supervisor,
    input: &Path,
    cancel: &AtomicBool,
) -> Result<f64, AppError> {
    // The metadata JSON can omit `abr` for a direct MP3. Ask the pinned local
    // FFmpeg about the downloaded stream before deciding copy versus encode.
    let args = [
        OsString::from("-hide_banner"),
        OsString::from("-i"),
        input.as_os_str().into(),
    ];
    let output = supervisor
        .run(
            &paths.ffmpeg,
            &args,
            PROBE_TIMEOUT,
            DIAGNOSTIC_LIMIT,
            cancel,
        )
        .map_err(run_error)?;
    ffmpeg_mp3_bitrate(&output.stderr)
        .ok_or_else(|| error(ErrorCode::Unknown, "cannot determine MP3 source bitrate"))
}

fn finalize(
    stage: &Path,
    paths: &mut DownloadPaths,
    persist: &mut dyn FnMut(&DownloadPaths) -> Result<(), AppError>,
    title: &str,
    extension: &str,
) -> Result<PathBuf, AppError> {
    fs::create_dir_all(&paths.output_dir).map_err(io_error)?;
    let base = safe_title(title);
    for suffix in 0..10_000 {
        let name = if suffix == 0 {
            base.clone()
        } else {
            format!("{base} ({suffix})")
        };
        let candidate = paths.output_dir.join(format!("{name}.{extension}"));
        let mut target = match OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&candidate)
        {
            Ok(file) => file,
            Err(cause) if cause.kind() == io::ErrorKind::AlreadyExists => continue,
            Err(cause) => return Err(io_error(cause)),
        };
        paths.reserved_path = Some(candidate.clone());
        if let Err(cause) = persist(paths) {
            drop(target);
            let _ = fs::remove_file(&candidate);
            return Err(cause);
        }
        let result = (|| {
            let mut source = File::open(stage)?;
            io::copy(&mut source, &mut target)?;
            target.flush()?;
            target.sync_all()
        })();
        if let Err(cause) = result {
            drop(target);
            let _ = fs::remove_file(&candidate);
            paths.reserved_path = None;
            let _ = persist(paths);
            return Err(io_error(cause));
        }
        paths.reserved_path = None;
        if let Err(cause) = persist(paths) {
            // The final file has no committed owner yet. Remove it and retain
            // the reservation so restart cleanup also knows the candidate.
            paths.reserved_path = Some(candidate.clone());
            drop(target);
            let _ = fs::remove_file(&candidate);
            return Err(cause);
        }
        return Ok(candidate);
    }
    Err(error(
        ErrorCode::Unknown,
        "too many files with the same title",
    ))
}

fn ensure_work_dir(
    disk: &DownloadPaths,
    app_data: &Path,
    queue_id: &str,
    entry_index: Option<usize>,
) -> Result<(), AppError> {
    let root = app_data.join("downloads").join(queue_id);
    let expected =
        entry_index.map_or_else(|| root.clone(), |index| root.join(format!("entry-{index}")));
    if disk.queue_id != queue_id || disk.work_dir != expected {
        return Err(error(
            ErrorCode::PermissionDenied,
            "work path does not belong to queue item",
        ));
    }
    let parent = app_data.join("downloads");
    fs::create_dir_all(&parent).map_err(io_error)?;
    if fs::symlink_metadata(&parent)
        .map_err(io_error)?
        .file_type()
        .is_symlink()
    {
        return Err(error(
            ErrorCode::PermissionDenied,
            "work parent is a symlink",
        ));
    }
    if entry_index.is_some() {
        fs::create_dir_all(&root).map_err(io_error)?;
        if fs::symlink_metadata(&root)
            .map_err(io_error)?
            .file_type()
            .is_symlink()
        {
            return Err(error(ErrorCode::PermissionDenied, "work root is a symlink"));
        }
    }
    fs::create_dir_all(&disk.work_dir).map_err(io_error)?;
    if fs::symlink_metadata(&disk.work_dir)
        .map_err(io_error)?
        .file_type()
        .is_symlink()
    {
        return Err(error(ErrorCode::PermissionDenied, "work path is a symlink"));
    }
    Ok(())
}

pub fn run_single(
    paths: &EnginePaths,
    supervisor: &Supervisor,
    disk: &mut DownloadPaths,
    app_data: &Path,
    queue_id: &str,
    request: &DownloadRequest,
    cancel: &AtomicBool,
    observe: Arc<dyn Fn(Observation) + Send + Sync>,
    persist: &mut dyn FnMut(&DownloadPaths) -> Result<(), AppError>,
) -> Result<Completed, AppError> {
    run_single_classified(
        paths, supervisor, disk, app_data, queue_id, request, cancel, observe, persist, &mut false,
    )
}

pub(crate) fn run_single_classified(
    paths: &EnginePaths,
    supervisor: &Supervisor,
    disk: &mut DownloadPaths,
    app_data: &Path,
    queue_id: &str,
    request: &DownloadRequest,
    cancel: &AtomicBool,
    observe: Arc<dyn Fn(Observation) + Send + Sync>,
    persist: &mut dyn FnMut(&DownloadPaths) -> Result<(), AppError>,
    broken: &mut bool,
) -> Result<Completed, AppError> {
    if request.is_playlist {
        return Err(error(
            ErrorCode::Unknown,
            "single worker received playlist request",
        ));
    }
    run_media_classified(
        paths, supervisor, disk, app_data, queue_id, request, None, None, cancel, observe, persist,
        broken,
    )
}

/// One resolved entry only. The queue owns iteration and commits its index before moving on.
pub fn run_playlist_entry(
    paths: &EnginePaths,
    supervisor: &Supervisor,
    disk: &mut DownloadPaths,
    app_data: &Path,
    queue_id: &str,
    request: &DownloadRequest,
    entry: &PlaylistEntry,
    index: usize,
    playlist_title: &str,
    cancel: &AtomicBool,
    observe: Arc<dyn Fn(Observation) + Send + Sync>,
    persist: &mut dyn FnMut(&DownloadPaths) -> Result<(), AppError>,
) -> Result<Completed, AppError> {
    run_playlist_entry_classified(
        paths,
        supervisor,
        disk,
        app_data,
        queue_id,
        request,
        entry,
        index,
        playlist_title,
        cancel,
        observe,
        persist,
        &mut false,
    )
}

pub(crate) fn run_playlist_entry_classified(
    paths: &EnginePaths,
    supervisor: &Supervisor,
    disk: &mut DownloadPaths,
    app_data: &Path,
    queue_id: &str,
    request: &DownloadRequest,
    entry: &PlaylistEntry,
    index: usize,
    playlist_title: &str,
    cancel: &AtomicBool,
    observe: Arc<dyn Fn(Observation) + Send + Sync>,
    persist: &mut dyn FnMut(&DownloadPaths) -> Result<(), AppError>,
    broken: &mut bool,
) -> Result<Completed, AppError> {
    if !request.is_playlist || playlist_title.trim().is_empty() {
        return Err(error(ErrorCode::Unknown, "invalid playlist entry request"));
    }
    analysis::PlaylistSnapshot {
        entries: vec![entry.clone()],
        next_index: 0,
    }
    .validate()?;
    let mut entry_request = request.clone();
    entry_request.url = entry.url.clone();
    let root = disk.work_dir.clone();
    disk.work_dir = root.join(format!("entry-{index}"));
    let result = run_media_classified(
        paths,
        supervisor,
        disk,
        app_data,
        queue_id,
        &entry_request,
        Some(playlist_title),
        Some(index),
        cancel,
        observe,
        persist,
        broken,
    );
    disk.work_dir = root;
    result
}

fn run_media_classified(
    paths: &EnginePaths,
    supervisor: &Supervisor,
    disk: &mut DownloadPaths,
    app_data: &Path,
    queue_id: &str,
    request: &DownloadRequest,
    playlist_title: Option<&str>,
    entry_index: Option<usize>,
    cancel: &AtomicBool,
    observe: Arc<dyn Fn(Observation) + Send + Sync>,
    persist: &mut dyn FnMut(&DownloadPaths) -> Result<(), AppError>,
    broken: &mut bool,
) -> Result<Completed, AppError> {
    valid_request(request)?;
    ensure_work_dir(disk, app_data, queue_id, entry_index)?;
    if disk.reserved_path.is_some() {
        disk.clear_reserved().map_err(io_error)?;
        persist(disk)?;
    }
    let result = (|| {
        let metadata = supervisor
            .run(
                &paths.yt_dlp,
                &probe_args(paths, request),
                PROBE_TIMEOUT,
                PROBE_LIMIT,
                cancel,
            )
            .map_err(|error| {
                *broken = analysis::run_failure_is_breakage(&error);
                run_error(error)
            })?;
        if !metadata.status.success() {
            *broken = analysis::nonzero_is_breakage(metadata.status.code(), &metadata.stderr);
            return Err(download_failure(&metadata.stderr, metadata.status.code()));
        }
        if serde_json::from_slice::<serde_json::Value>(&metadata.stdout).is_err() {
            *broken = true;
        }
        let mut source = source_from_json(&metadata.stdout)?;
        observe(Observation::Title(source.title.clone()));
        let height = match request.quality {
            Quality::Video { height } => Some(chosen_height(height, &source.heights)?),
            _ => None,
        };
        let parser = Arc::new(Mutex::new(Lines {
            expected_id: Some(source.id.clone()),
            ..Lines::default()
        }));
        let sink: Arc<dyn Fn(&[u8]) + Send + Sync> = {
            let parser = Arc::clone(&parser);
            let observe = Arc::clone(&observe);
            Arc::new(move |chunk| {
                if let Ok(mut parser) = parser.lock() {
                    parser.feed(chunk, observe.as_ref());
                }
            })
        };
        let args = download_args(paths, request, &source, &disk.work_dir, height);
        let result = supervisor
            .run_observed(
                &paths.yt_dlp,
                &args,
                TIMEOUT,
                DIAGNOSTIC_LIMIT,
                cancel,
                sink,
            )
            .map_err(|error| {
                *broken = analysis::run_failure_is_breakage(&error);
                run_error(error)
            })?;
        if !result.status.success() {
            *broken = analysis::nonzero_is_breakage(result.status.code(), &result.stderr);
            return Err(download_failure(&result.stderr, result.status.code()));
        }
        observe(Observation::PostProcessing);
        let stage = match (request.format, &request.quality) {
            (Format::Mp3, quality) => {
                let bitrate = match quality {
                    Quality::Audio { bitrate } => *bitrate,
                    Quality::Max => 320,
                    Quality::Min => 128,
                    _ => unreachable!(),
                };
                let input = source_file(&disk.work_dir)?;
                if input
                    .extension()
                    .is_some_and(|ext| ext.eq_ignore_ascii_case("mp3"))
                {
                    source.extension = "mp3".into();
                    source.bitrate = Some(inspect_mp3_bitrate(paths, supervisor, &input, cancel)?);
                }
                let output = disk.work_dir.join("ready.mp3");
                let args = mp3_args(
                    &source,
                    &input,
                    &disk.work_dir.join("source.jpg"),
                    &output,
                    bitrate,
                    playlist_title.unwrap_or(""),
                );
                let result = supervisor
                    .run(&paths.ffmpeg, &args, TIMEOUT, DIAGNOSTIC_LIMIT, cancel)
                    .map_err(run_error)?;
                if !result.status.success() {
                    return Err(download_failure(&result.stderr, result.status.code()));
                }
                output
            }
            (Format::Mp4, _) => {
                let input = disk.work_dir.join("source.mp4");
                let output = disk.work_dir.join("ready.mp4");
                let args = mp4_tag_args(&source, &input, &output, playlist_title.unwrap_or(""));
                let result = supervisor
                    .run(&paths.ffmpeg, &args, TIMEOUT, DIAGNOSTIC_LIMIT, cancel)
                    .map_err(run_error)?;
                if !result.status.success() {
                    return Err(download_failure(&result.stderr, result.status.code()));
                }
                output
            }
        };
        if !stage.is_file() {
            return Err(error(
                ErrorCode::Unknown,
                "download produced no output file",
            ));
        }
        let extension = if request.format == Format::Mp3 {
            "mp3"
        } else {
            "mp4"
        };
        let path = finalize(&stage, disk, persist, &source.title, extension)?;
        Ok(Completed {
            path,
            title: source.title,
            selected_height: height,
        })
    })();
    if !*broken
        && matches!(
            &result,
            Err(AppError {
                code: ErrorCode::DiskFull | ErrorCode::PermissionDenied,
                ..
            })
        )
    {
        // A failed output cannot be resumed safely; remove only this id's files.
        let _ = disk.clean_owned(app_data);
    }
    result
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::contract::{ItemStatus, Progress, QueueItem};
    use crate::persistence::Database;

    #[test]
    fn safe_arguments_quality_and_progress() {
        let paths = EnginePaths {
            yt_dlp: "C:/Data/yt-dlp.exe".into(),
            ffmpeg: "C:/Data/ffmpeg.exe".into(),
            quickjs: "C:/Data/qjs.exe".into(),
        };
        let request = DownloadRequest {
            url: "https://example.com/watch?v=1".into(),
            format: Format::Mp4,
            quality: Quality::Video { height: 720 },
            is_playlist: false,
        };
        valid_request(&request).unwrap();
        let source = Source {
            id: "item".into(),
            title: "a".into(),
            artist: "b".into(),
            extension: "mp4".into(),
            bitrate: None,
            heights: vec![360, 720],
        };
        let args = download_args(
            &paths,
            &request,
            &source,
            Path::new("C:/Data/partial"),
            Some(720),
        );
        assert_eq!(args.first().unwrap(), "--ignore-config");
        assert_eq!(args[args.len() - 2], "--");
        assert_eq!(args.last().unwrap(), &OsString::from(&request.url));
        assert!(args.contains(&OsString::from("--no-playlist")));
        assert!(args.contains(&OsString::from("Merger+ffmpeg_o:-c:a aac")));
        assert!(args.contains(&OsString::from("VideoConvertor+ffmpeg_o:-vf scale=-2:720")));
        assert!(args.contains(&OsString::from("bv*[height=720]+ba/b[height=720]")));
        let tags = mp4_tag_args(
            &source,
            Path::new("C:/Data/partial/source.mp4"),
            Path::new("C:/Data/partial/ready.mp4"),
            "",
        );
        assert!(tags.windows(2).any(|pair| pair == ["-map", "0"]));
        assert!(tags.windows(2).any(|pair| pair == ["-c", "copy"]));
        assert!(tags.windows(2).any(|pair| pair == ["-metadata", "title=a"]));
        assert!(tags
            .windows(2)
            .any(|pair| pair == ["-metadata", "artist=b"]));
        assert!(tags.windows(2).any(|pair| pair == ["-metadata", "album="]));
        for flag in [
            "--continue",
            "--part",
            "--embed-metadata",
            "--embed-thumbnail",
            "--convert-thumbnails",
            "--parse-metadata",
            "--no-overwrites",
        ] {
            assert!(args.contains(&OsString::from(flag)), "missing {flag}");
        }
        assert_eq!(chosen_height(1080, &source.heights).unwrap(), 720);
        assert!(chosen_height(240, &source.heights).is_err());
        let records = Arc::new(Mutex::new(Vec::new()));
        let collected = Arc::clone(&records);
        let mut parser = Lines {
            expected_id: Some("item".into()),
            ..Lines::default()
        };
        parser.feed(
            b"ZP2|ThumbnailsConvertor|started\nZP1|wrong|downloading|1|10\nZP1|item|downloading|5|10\nZP1|item|downloading|oops|10\nZP1|item|finished|10|10\nZP2|Metadata|started\n",
            &move |event| collected.lock().unwrap().push(event),
        );
        assert_eq!(
            *records.lock().unwrap(),
            vec![
                Observation::Downloaded {
                    bytes: 5,
                    total: 10,
                    percent: 50.0
                },
                Observation::Downloaded {
                    bytes: 10,
                    total: 10,
                    percent: 100.0
                },
                Observation::PostProcessing
            ]
        );
    }

    #[test]
    fn mp3_copy_and_reencode_are_explicit() {
        let mut source = Source {
            id: "item".into(),
            title: "title".into(),
            artist: "artist".into(),
            extension: "mp3".into(),
            bitrate: Some(128.0),
            heights: vec![],
        };
        let make = |source: &Source| {
            mp3_args(
                source,
                Path::new("source.mp3"),
                Path::new("missing.jpg"),
                Path::new("ready.mp3"),
                192,
                "",
            )
        };
        assert!(make(&source)
            .windows(2)
            .any(|pair| pair == ["-c:a", "copy"]));
        source.bitrate = Some(256.0);
        assert!(make(&source)
            .windows(2)
            .any(|pair| pair == ["-b:a", "192k"]));
        source.extension = "webm".into();
        source.bitrate = Some(64.0);
        assert!(make(&source)
            .windows(2)
            .any(|pair| pair == ["-c:a", "libmp3lame"]));
        source.artist.clear();
        assert!(!make(&source).contains(&OsString::from("artist=")));
        let download = DownloadRequest {
            url: "https://example.com/audio".into(),
            format: Format::Mp3,
            quality: Quality::Audio { bitrate: 192 },
            is_playlist: false,
        };
        let paths = EnginePaths {
            yt_dlp: "C:/Data/yt-dlp.exe".into(),
            ffmpeg: "C:/Data/ffmpeg.exe".into(),
            quickjs: "C:/Data/qjs.exe".into(),
        };
        let args = download_args(
            &paths,
            &download,
            &source,
            Path::new("C:/Data/partial"),
            None,
        );
        assert!(args.windows(2).any(|pair| pair == ["-f", "ba/b"]));
        assert!(args.contains(&OsString::from("--no-playlist")));
        assert_eq!(args[args.len() - 2], "--");
        assert_eq!(
            ffmpeg_mp3_bitrate(
                b"Stream #0:0: Audio: mp3 (mp3float), 44100 Hz, stereo, fltp, 128 kb/s\n"
            ),
            Some(128.0)
        );
    }

    #[test]
    fn playlist_profiles_isolate_entry_url_and_set_album() {
        let paths = EnginePaths {
            yt_dlp: "C:/Data/engine/yt-dlp.exe".into(),
            ffmpeg: "C:/Data/engine/ffmpeg.exe".into(),
            quickjs: "C:/Data/engine/qjs.exe".into(),
        };
        let source = Source {
            id: "one".into(),
            title: "Track".into(),
            artist: "Artist".into(),
            extension: "wav".into(),
            bitrate: None,
            heights: vec![240, 720],
        };
        for (format, quality, expected) in [
            (Format::Mp4, Quality::Max, "bv*+ba/b"),
            (Format::Mp4, Quality::Min, "wv*+ba/w"),
            (Format::Mp3, Quality::Max, "ba/b"),
            (Format::Mp3, Quality::Min, "ba/b"),
        ] {
            let request = DownloadRequest {
                url: "https://example.com/entry/one".into(),
                format,
                quality: quality.clone(),
                is_playlist: true,
            };
            valid_request(&request).unwrap();
            let args = download_args(
                &paths,
                &request,
                &source,
                Path::new("C:/Data/work/entry-0"),
                None,
            );
            assert!(args.windows(2).any(|pair| pair == ["-f", expected]));
            assert!(args.contains(&OsString::from("--no-playlist")));
            assert_eq!(args[args.len() - 2], "--");
            assert_eq!(args.last().unwrap(), &OsString::from(&request.url));
            assert!(!args
                .iter()
                .any(|arg| arg.to_string_lossy().contains(".zip")));
            if format == Format::Mp3 {
                let bitrate = if quality == Quality::Max { 320 } else { 128 };
                let tags = mp3_args(
                    &source,
                    Path::new("source.wav"),
                    Path::new("missing.jpg"),
                    Path::new("ready.mp3"),
                    bitrate,
                    "Playlist",
                );
                assert!(tags
                    .windows(2)
                    .any(|pair| pair == ["-metadata", "album=Playlist"]));
                assert!(tags
                    .windows(2)
                    .any(|pair| pair == ["-b:a", format!("{bitrate}k").as_str()]));
            } else {
                let tags = mp4_tag_args(
                    &source,
                    Path::new("source.mp4"),
                    Path::new("ready.mp4"),
                    "Playlist",
                );
                assert!(tags
                    .windows(2)
                    .any(|pair| pair == ["-metadata", "album=Playlist"]));
            }
        }
    }

    #[test]
    fn collision_reservation_keeps_prior_file_and_cleans_failed_copy() {
        let id = uuid::Uuid::new_v4().to_string();
        let root = std::env::temp_dir().join(format!("zownload-finalize-{id}"));
        fs::create_dir_all(&root).unwrap();
        let db_path = root.join("state.sqlite3");
        let mut db = Database::open_at(&db_path).unwrap();
        db.insert_queue_item(&QueueItem {
            id: id.clone(),
            request: DownloadRequest {
                url: "https://example.com/a".into(),
                format: Format::Mp3,
                quality: Quality::Audio { bitrate: 128 },
                is_playlist: false,
            },
            title: None,
            thumbnail: None,
            status: ItemStatus::Queued,
            progress: Progress::Single { percent: 0.0 },
            error: None,
        })
        .unwrap();
        let mut disk = DownloadPaths::new(
            &id,
            &root,
            Some(&root.join("chosen")),
            &root.join("Downloads"),
        )
        .unwrap();
        db.put_download_paths(&disk).unwrap();
        fs::create_dir_all(&disk.work_dir).unwrap();
        let stage = disk.work_dir.join("ready.mp3");
        fs::write(&stage, b"new content").unwrap();
        fs::create_dir_all(&disk.output_dir).unwrap();
        fs::write(disk.output_dir.join("song.mp3"), b"old content").unwrap();
        let mut persist = |paths: &DownloadPaths| {
            db.put_download_paths(paths)
                .map_err(|cause| error(ErrorCode::Unknown, cause.to_string()))
        };
        let final_path = finalize(&stage, &mut disk, &mut persist, "song", "mp3").unwrap();
        drop(persist);
        assert_eq!(final_path.file_name().unwrap(), "song (1).mp3");
        assert_eq!(
            fs::read(disk.output_dir.join("song.mp3")).unwrap(),
            b"old content"
        );
        assert_eq!(fs::read(&final_path).unwrap(), b"new content");
        assert!(db
            .get_download_paths(&id)
            .unwrap()
            .unwrap()
            .reserved_path
            .is_none());
        fs::remove_file(&stage).unwrap();
        let mut persist = |paths: &DownloadPaths| {
            db.put_download_paths(paths)
                .map_err(|cause| error(ErrorCode::Unknown, cause.to_string()))
        };
        assert!(finalize(&stage, &mut disk, &mut persist, "song", "mp3").is_err());
        drop(persist);
        assert!(!disk.output_dir.join("song (2).mp3").exists());
        fs::write(&stage, b"again").unwrap();
        let mut writes = 0;
        let mut persist = |paths: &DownloadPaths| {
            writes += 1;
            if writes == 2 {
                Err(error(ErrorCode::Unknown, "simulated final record failure"))
            } else {
                db.put_download_paths(paths)
                    .map_err(|cause| error(ErrorCode::Unknown, cause.to_string()))
            }
        };
        assert!(finalize(&stage, &mut disk, &mut persist, "song", "mp3").is_err());
        drop(persist);
        assert!(!disk.output_dir.join("song (2).mp3").exists());
        assert_eq!(
            db.get_download_paths(&id).unwrap().unwrap().reserved_path,
            Some(disk.output_dir.join("song (2).mp3"))
        );
        drop(db);
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn malformed_progress_and_filesystem_errors_are_bounded_and_typed() {
        let records = Arc::new(Mutex::new(Vec::new()));
        let collected = Arc::clone(&records);
        let first = Arc::clone(&records);
        let mut parser = Lines::default();
        parser.feed(&vec![b'x'; MAX_LINE + 100], &move |event| {
            first.lock().unwrap().push(event)
        });
        parser.feed(
            b"\nZP1|item|downloading|20|10\nZP1|item|downloading|10|0\nZP1|item|downloading|1|4\n",
            &move |event| records.lock().unwrap().push(event),
        );
        assert_eq!(collected.lock().unwrap().len(), 1);
        assert_eq!(
            io_error(io::Error::from_raw_os_error(112)).code,
            ErrorCode::DiskFull
        );
        assert_eq!(
            io_error(io::Error::from_raw_os_error(5)).code,
            ErrorCode::PermissionDenied
        );
        assert_eq!(
            download_failure(b"ERROR: No space left on device", Some(1)).code,
            ErrorCode::DiskFull
        );
        assert_eq!(
            download_failure(b"Permission denied", Some(1)).code,
            ErrorCode::PermissionDenied
        );
        let id = uuid::Uuid::new_v4().to_string();
        let app_data = std::env::temp_dir().join(format!("zownload-guard-{id}"));
        let mut paths =
            DownloadPaths::new(&id, &app_data, None, &app_data.join("Downloads")).unwrap();
        paths.work_dir = app_data.join("somewhere-else");
        assert_eq!(
            ensure_work_dir(&paths, &app_data, &id, None)
                .unwrap_err()
                .code,
            ErrorCode::PermissionDenied
        );
    }
}
