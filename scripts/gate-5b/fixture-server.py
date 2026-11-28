# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 zahidzta

"""Deterministic throttled HTTP range fixture server for Gate 5B device tests."""

from __future__ import annotations

import argparse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import pathlib
import re
import threading
import time


def build_silent_mp3(frame_count: int = 1250) -> bytes:
    # MPEG-1 Layer 3, 128 kbps, 44100 Hz, padding=0 -> 417 bytes per frame.
    frame = bytes([0xFF, 0xFB, 0x90, 0x00]) + (b"\x00" * 413)
    return frame * frame_count


MP3_PAYLOAD = build_silent_mp3()
RECREATE_MP3_PAYLOAD = build_silent_mp3(frame_count=5400)
HOME_MP3_PAYLOAD = build_silent_mp3(frame_count=13000)
CHUNK_SIZE = 4096
RANGE_RE = re.compile(r"^bytes=(\d*)-(\d*)$")


def build_rss(port: int) -> bytes:
    base = f"http://127.0.0.1:{port}"
    xml = f"""<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0">
  <channel>
    <title>Zownload Gate 5B Mix</title>
    <link>{base}/playlist.xml</link>
    <description>Deterministic Gate 5B playlist fixture</description>
    <item>
      <title>Fixture Track</title>
      <enclosure url="{base}/entry-1/fixture.mp3" length="{len(MP3_PAYLOAD)}" type="audio/mpeg" />
    </item>
    <item>
      <title>Fixture Track</title>
      <enclosure url="{base}/entry-2/fixture.mp3" length="{len(MP3_PAYLOAD)}" type="audio/mpeg" />
    </item>
  </channel>
</rss>
"""
    return xml.encode("utf-8")


class FixtureHandler(BaseHTTPRequestHandler):
    server_version = "ZownloadFixture/1.0"

    def log_message(self, format: str, *args: object) -> None:
        self.server.write_log(f"{self.command} {self.path} range={self.headers.get('Range')} :: {format % args}")

    def do_HEAD(self) -> None:
        self._serve(send_body=False)

    def do_GET(self) -> None:
        self._serve(send_body=True)

    def _serve(self, send_body: bool) -> None:
        clean_path = self.path.split("?", 1)[0]
        if clean_path == "/playlist.xml":
            body = build_rss(self.server.server_port)
            self.send_response(200)
            self.send_header("Content-Type", "application/rss+xml; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            if send_body:
                self.wfile.write(body)
            return

        payloads = {
            "/track-1.mp3": MP3_PAYLOAD,
            "/track-2.mp3": MP3_PAYLOAD,
            "/entry-1/fixture.mp3": MP3_PAYLOAD,
            "/entry-2/fixture.mp3": MP3_PAYLOAD,
            "/long.mp3": MP3_PAYLOAD,
            "/recreate-long.mp3": RECREATE_MP3_PAYLOAD,
            "/home-long.mp3": HOME_MP3_PAYLOAD,
        }
        payload = payloads.get(clean_path)
        if payload is None:
            self.send_error(404, "Not found")
            return

        total = len(payload)
        range_header = self.headers.get("Range")
        start = 0
        end = total - 1
        status = 200
        if range_header:
            match = RANGE_RE.match(range_header.strip())
            if not match:
                self.send_error(416, "Invalid range")
                return
            raw_start, raw_end = match.groups()
            if raw_start == "" and raw_end == "":
                self.send_error(416, "Empty range")
                return
            if raw_start == "":
                suffix = int(raw_end)
                start = max(0, total - suffix)
            else:
                start = int(raw_start)
                if raw_end != "":
                    end = min(total - 1, int(raw_end))
            if start >= total or start > end:
                self.send_error(416, "Range not satisfiable")
                return
            status = 206

        length = end - start + 1
        self.send_response(status)
        self.send_header("Content-Type", "audio/mpeg")
        self.send_header("Accept-Ranges", "bytes")
        self.send_header("Content-Length", str(length))
        if status == 206:
            self.send_header("Content-Range", f"bytes {start}-{end}/{total}")
        self.end_headers()

        if not send_body:
            return

        rate_bps = self.server.rate_bps
        pos = start
        try:
            while pos <= end:
                stop = min(end + 1, pos + CHUNK_SIZE)
                chunk = payload[pos:stop]
                self.wfile.write(chunk)
                self.wfile.flush()
                pos = stop
                if rate_bps > 0:
                    time.sleep(len(chunk) / float(rate_bps))
        except (BrokenPipeError, ConnectionResetError):
            return


class FixtureServer(ThreadingHTTPServer):
    allow_reuse_address = True

    def __init__(self, port: int, rate_bps: int, log_path: str | None) -> None:
        self.rate_bps = rate_bps
        self._log_lock = threading.Lock()
        self._log_path = pathlib.Path(log_path) if log_path else None
        super().__init__(("127.0.0.1", port), FixtureHandler)

    def write_log(self, line: str) -> None:
        if not self._log_path:
            return
        with self._log_lock:
            self._log_path.parent.mkdir(parents=True, exist_ok=True)
            with self._log_path.open("a", encoding="utf-8") as handle:
                handle.write(line + "\n")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=18550)
    parser.add_argument("--rate-bps", type=int, default=24000)
    parser.add_argument("--log", type=str, default=None)
    args = parser.parse_args()

    server = FixtureServer(args.port, args.rate_bps, args.log)
    print(f"LISTENING http://127.0.0.1:{server.server_port}/", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
