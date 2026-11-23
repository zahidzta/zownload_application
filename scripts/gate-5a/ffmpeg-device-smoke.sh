# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 zahidzta
#!/system/bin/sh
set -eu

work=/data/local/tmp/5a-04-ffmpeg
ffmpeg="$work/ffmpeg"
ffprobe="$work/ffprobe"

"$ffmpeg" -version | head -n 1 | grep -F 'ffmpeg version 8.1.3' >/dev/null
"$ffprobe" -version | head -n 1 | grep -F 'ffprobe version 8.1.3' >/dev/null

"$ffmpeg" -nostdin -hide_banner -loglevel error -f lavfi \
  -i 'sine=frequency=1000:duration=1' -c:a libmp3lame -b:a 128k -y "$work/sample.mp3"
mp3_codec="$("$ffprobe" -v error -select_streams a:0 -show_entries stream=codec_name \
  -of default=noprint_wrappers=1:nokey=1 "$work/sample.mp3")"
[ "$mp3_codec" = mp3 ]

"$ffmpeg" -nostdin -hide_banner -loglevel error \
  -f lavfi -i 'color=c=black:s=64x64:d=1' \
  -f lavfi -i 'sine=frequency=440:duration=1' \
  -c:v mpeg4 -q:v 10 -c:a aac -shortest -y "$work/sample.mp4"
mp4_codecs="$("$ffprobe" -v error -show_entries stream=codec_name \
  -of csv=p=0 "$work/sample.mp4")"
printf '%s\n' "$mp4_codecs" | grep -qx mpeg4
printf '%s\n' "$mp4_codecs" | grep -qx aac

"$ffmpeg" -nostdin -hide_banner -loglevel error -i "$work/sample.mp4" \
  -map 0 -c copy -y "$work/remux.mp4"
"$ffprobe" -v error -show_entries format=format_name -of default=noprint_wrappers=1:nokey=1 \
  "$work/remux.mp4" | grep -q mp4

if "$ffmpeg" -hide_banner -encoders 2>&1 | grep -Eiq 'libx26[45]'; then
  echo 'x264/x265 encoder found in Android build' >&2
  exit 1
fi

printf 'PASS: FFmpeg 8.1.3 MP3 encode/probe, MP4 encode/remux/probe passed on Android.\n'

