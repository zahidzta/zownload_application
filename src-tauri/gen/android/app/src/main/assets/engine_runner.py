# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 zahidzta

"""Small request runner for the embedded Android yt-dlp package."""

from __future__ import annotations

import json
import os
import pathlib
import sys
import traceback


def write_json(path: str, value: object) -> None:
    temporary = path + ".tmp"
    with open(temporary, "w", encoding="utf-8") as output:
        json.dump(value, output, ensure_ascii=True)
        output.flush()
        os.fsync(output.fileno())
    os.replace(temporary, path)


def append_progress(path: str, value: dict[str, object]) -> None:
    with open(path, "a", encoding="utf-8") as output:
        output.write(json.dumps(value, ensure_ascii=True, separators=(",", ":")) + "\n")
        output.flush()


def prepare_imports(request: dict[str, object]) -> None:
    home = pathlib.Path(str(request["pythonHome"]))
    package_dirs = sorted(home.glob("lib/python*/site-packages"))
    if not package_dirs:
        raise RuntimeError("The embedded Python package directory is missing")
    sys.path.insert(0, str(package_dirs[0]))
    overlay = str(request.get("ytDlpOverlay") or "")
    if overlay and os.path.isfile(overlay):
        sys.path.insert(0, overlay)


def engine_options(request: dict[str, object]) -> dict[str, object]:
    options: dict[str, object] = {
        "quiet": True,
        "no_warnings": False,
        "noplaylist": True,
        "overwrites": False,
        "continuedl": True,
        "part": True,
        "ffmpeg_location": str(request["ffmpegPath"]),
        "js_runtimes": ["quickjs:" + str(request["quickJsPath"])],
    }
    return options


def analyze(request: dict[str, object]) -> dict[str, object]:
    import yt_dlp

    with yt_dlp.YoutubeDL(engine_options(request)) as downloader:
        info = downloader.extract_info(str(request["url"]), download=False)

    if not isinstance(info, dict):
        raise RuntimeError("yt-dlp returned no video information")
    author = info.get("uploader") or info.get("channel") or info.get("creator") or ""
    thumbnail = info.get("thumbnail")
    site = info.get("extractor_key") or info.get("extractor") or ""
    base: dict[str, object] = {
        "url": str(request["url"]),
        "title": str(info.get("title") or ""),
        "author": str(author),
        "thumbnail": str(thumbnail) if thumbnail else None,
        "site": str(site),
    }

    if info.get("_type") in ("playlist", "multi_video") or isinstance(info.get("entries"), list):
        entries = [entry for entry in (info.get("entries") or []) if isinstance(entry, dict)]
        base.update({
            "kind": "playlist",
            "itemCount": int(info.get("playlist_count") or len(entries)),
            "itemTitles": [str(entry.get("title") or entry.get("id") or "") for entry in entries],
        })
        return base

    heights = sorted({
        int(item["height"])
        for item in info.get("formats", [])
        if isinstance(item, dict)
        and item.get("height")
        and item.get("vcodec") != "none"
    })
    base.update({
        "kind": "single",
        "durationSec": max(0, int(info.get("duration") or 0)),
        "videoHeights": heights,
        "audioOutputBitrates": [320, 256, 192, 128],
    })
    return base


def format_selector(request: dict[str, object]) -> str:
    format_name = str(request.get("format") or "mp3").lower()
    quality = request.get("quality") or {}
    quality_type = str(quality.get("type") or "max").lower() if isinstance(quality, dict) else "max"
    if format_name == "mp4":
        if quality_type == "video":
            height = max(1, int(quality.get("height") or 1))
            return f"bestvideo[height<={height}]+bestaudio/best[height<={height}]"
        if quality_type == "min":
            return "worstvideo+bestaudio/best"
        return "bestvideo+bestaudio/best"
    return "bestaudio/best"


def download(request: dict[str, object], progress_path: str, cancel_path: str) -> dict[str, object]:
    import yt_dlp

    quality = request.get("quality") or {}
    quality_type = str(quality.get("type") or "max").lower() if isinstance(quality, dict) else "max"
    bitrate = int(quality.get("bitrate") or (128 if quality_type == "min" else 320)) if isinstance(quality, dict) else 320
    output_template = str(request["outputTemplate"])

    def progress_hook(event: dict[str, object]) -> None:
        if os.path.exists(cancel_path):
            raise yt_dlp.utils.DownloadError("Zownload cancellation requested")
        total = event.get("total_bytes") or event.get("total_bytes_estimate") or 0
        downloaded = event.get("downloaded_bytes") or 0
        percent = float(downloaded) * 100.0 / float(total) if total else 0.0
        append_progress(progress_path, {
            "status": str(event.get("status") or "downloading"),
            "percent": max(0.0, min(100.0, percent)),
            "downloadedBytes": int(downloaded),
            "totalBytes": int(total),
            "title": str(event.get("info_dict", {}).get("title") or ""),
        })

    options = engine_options(request)
    options["format"] = format_selector(request)
    options["outtmpl"] = output_template
    options["progress_hooks"] = [progress_hook]
    if str(request.get("format") or "mp3").lower() == "mp3":
        options["postprocessors"] = [{
            "key": "FFmpegExtractAudio",
            "preferredcodec": "mp3",
            "preferredquality": str(bitrate),
        }]

    with yt_dlp.YoutubeDL(options) as downloader:
        info = downloader.extract_info(str(request["url"]), download=True)
        if not isinstance(info, dict):
            raise RuntimeError("yt-dlp completed without returning an output file")
        path = info.get("filepath") or info.get("_filename") or downloader.prepare_filename(info)
        if str(request.get("format") or "mp3").lower() == "mp3":
            path = str(pathlib.Path(str(path)).with_suffix(".mp3"))
        output = pathlib.Path(str(path))
        if not output.is_file():
            raise RuntimeError("yt-dlp reported success but the output file is missing")
        return {
            "path": str(output),
            "title": str(info.get("title") or ""),
            "thumbnail": info.get("thumbnail"),
            "bytes": output.stat().st_size,
        }


def error_code(error: BaseException, cancelled: bool) -> str:
    if cancelled:
        return "cancelled"
    message = str(error).lower()
    if "unsupported url" in message:
        return "unsupported_site"
    if "private" in message or "login required" in message or "not available in your country" in message:
        return "private_or_restricted"
    if "not found" in message or "404" in message or "no longer available" in message:
        return "not_found"
    if "no space left" in message or "disk full" in message:
        return "disk_full"
    if "permission denied" in message:
        return "permission_denied"
    if "network is unreachable" in message or "name or service not known" in message or "timed out" in message:
        return "no_internet"
    if "invalid url" in message:
        return "invalid_url"
    return "unknown"


def main() -> None:
    request_path, result_path, progress_path, cancel_path = sys.argv[1:5]
    request = json.loads(pathlib.Path(request_path).read_text(encoding="utf-8"))
    try:
        prepare_imports(request)
        operation = str(request["operation"])
        if operation == "analyze":
            value = analyze(request)
        elif operation == "download":
            value = download(request, progress_path, cancel_path)
        elif operation == "versions":
            import importlib.metadata
            import platform
            import yt_dlp

            value = {
                "python": platform.python_version(),
                "ytDlp": str(yt_dlp.version.__version__),
                "ejs": importlib.metadata.version("yt-dlp-ejs"),
            }
        else:
            raise ValueError("Unknown engine operation")
        write_json(result_path, {"ok": True, "value": value})
    except BaseException as error:
        cancelled = os.path.exists(cancel_path)
        write_json(result_path, {
            "ok": False,
            "error": {
                "code": error_code(error, cancelled),
                "detail": str(error) or error.__class__.__name__,
            },
        })
        if not isinstance(error, Exception):
            traceback.print_exc()


if __name__ == "__main__":
    main()
