#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 zahidzta

set -euo pipefail

if [[ $# -ne 1 || "$1" != --verify ]]; then
  echo 'Usage: bash scripts/gate-4a/build-linux-engine.sh --verify' >&2
  exit 2
fi

fail() { echo "Linux engine build: $*" >&2; exit 1; }
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 && -f /etc/os-release ]] || fail 'requires Linux x86_64'
. /etc/os-release
[[ "$ID" == ubuntu && "$VERSION_ID" == 24.04 ]] || fail "requires Ubuntu 24.04, found ${PRETTY_NAME:-unknown}"

for tool in curl tar xz gcc-13 g++-13 make ar ranlib nm strip sha256sum file ldd; do
  command -v "$tool" >/dev/null || fail "missing build tool: $tool"
done
[[ "$(gcc-13 -dumpmachine)" == x86_64-linux-gnu ]] || fail 'gcc-13 has an unexpected target'
[[ "$(gcc-13 -dumpfullversion)" == 13.* ]] || fail 'requires GCC 13'
[[ "$(g++-13 -dumpmachine)" == x86_64-linux-gnu ]] || fail 'g++-13 has an unexpected target'

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
downloads="$repo_root/work/engine/downloads"
build_root="$repo_root/work/engine/build/ffmpeg/linux-x64"
recipe="$build_root/recipe"
resources="$repo_root/src-tauri/resources/linux-engine"
mkdir -p "$downloads" "$build_root" "$resources"
[[ "$(cd "$build_root" && pwd -P)" == "$repo_root/work/engine/build/ffmpeg/linux-x64" ]] || fail 'build path resolves outside the workspace'

hash_file() { sha256sum "$1" | awk '{print $1}'; }
fetch_locked() {
  local name="$1" expected="$2" path="$downloads/$1" candidate partial
  shift 2
  if [[ ! -f "$path" ]]; then
    for candidate in "$@"; do
      partial="$path.partial.$$"
      if curl --fail --location --silent --show-error --retry 3 --proto '=https' --proto-redir '=https' \
        --output "$partial" "$candidate" && [[ "$(hash_file "$partial")" == "$expected" ]]; then
        mv -- "$partial" "$path"
        echo "Verified $name source from $candidate"
        break
      fi
      rm -f -- "$partial"
    done
    [[ -f "$path" ]] || fail "$name source checksum mismatch or no locked source available"
  fi
  [[ "$(hash_file "$path")" == "$expected" ]] || fail "$name source checksum mismatch"
}

fetch_locked 'yt-dlp-2026.08.19-linux' \
  '58162f9bfdc27458ea47bfcb311cf47028f17d8154a8bf7d689861d46399230a' \
  'https://github.com/yt-dlp/yt-dlp/releases/download/2026.08.19/yt-dlp_linux'
install -m 0755 "$downloads/yt-dlp-2026.08.19-linux" "$resources/yt-dlp"

bash "$repo_root/scripts/gate-0b/build-quickjs.sh" linux-x64 --verify
install -m 0755 "$repo_root/work/engine/build/quickjs/linux-x64/qjs" "$resources/qjs"

fetch_locked 'ffmpeg-8.1.3.tar.xz' \
  '7138d28c96d9d3e3af4ee3d8cad72741f8ffb40da90c1112235dea3ecd3178a3' \
  'https://ffmpeg.org/releases/ffmpeg-8.1.3.tar.xz' \
  'https://mirror.math.princeton.edu/pub/macports/distfiles/ffmpeg/ffmpeg-8.1.3.tar.xz'
fetch_locked 'lame-3.100.tar.gz' \
  'ddfe36cab873794038ae2c1210557ad34857a4b6bdc515785d1da9e175b1da1e' \
  'https://sourceforge.net/projects/lame/files/lame/3.100/lame-3.100.tar.gz/download'
fetch_locked 'zlib-1.3.2.tar.gz' \
  'bb329a0a2cd0274d05519d61c667c062e06990d72e125ee2dfa8de64f0119d16' \
  'https://zlib.net/fossils/zlib-1.3.2.tar.gz' \
  'https://github.com/madler/zlib/releases/download/v1.3.2/zlib-1.3.2.tar.gz'

if [[ -e "$recipe" ]]; then
  resolved_recipe="$(cd "$recipe" && pwd -P)"
  resolved_parent="$(cd "$(dirname "$resolved_recipe")" && pwd -P)"
  [[ "$resolved_recipe" == "$build_root/recipe" && "$resolved_parent" == "$build_root" ]] || fail 'refusing to clean outside the fixed recipe directory'
  rm -rf -- "$resolved_recipe"
fi
mkdir -p "$recipe"
tar -xf "$downloads/ffmpeg-8.1.3.tar.xz" -C "$recipe"
tar -xf "$downloads/lame-3.100.tar.gz" -C "$recipe"
tar -xf "$downloads/zlib-1.3.2.tar.gz" -C "$recipe"

export CC=gcc-13 CXX=g++-13 AR=ar RANLIB=ranlib NM=nm STRIP=strip
export SOURCE_DATE_EPOCH=0
lame="$recipe/lame-3.100"
zlib="$recipe/zlib-1.3.2"
ffmpeg="$recipe/ffmpeg-8.1.3"
deps="$recipe/deps"

(
  cd "$lame"
  ./configure --disable-decoder --disable-frontend --disable-shared --enable-static \
    --disable-mp3x --disable-mp3rtp CC=gcc-13 CFLAGS=-O2 AR=ar RANLIB=ranlib
  grep -Eq '^/\* #undef HAVE_MPGLIB \*/$' config.h || fail 'LAME GPL decoder is enabled'
  grep -Eq '^decoder_ldadd =[[:space:]]*$' libmp3lame/Makefile || fail 'LAME decoder linkage is not empty'
  make -C libmp3lame -j2
  ar t libmp3lame/.libs/libmp3lame.a > "$build_root/lame-members.txt"
  if grep -Eq '^(decode|dct64|layer[123]|tabinit|interface)\.o$' "$build_root/lame-members.txt"; then
    fail 'GPL-only LAME decoder object entered the archive'
  fi
)

(
  cd "$zlib"
  ./configure --static
  make -j2
)
mkdir -p "$deps/include/lame" "$deps/lib"
install -m 0644 "$lame/include/lame.h" "$deps/include/lame/lame.h"
install -m 0644 "$lame/libmp3lame/.libs/libmp3lame.a" "$deps/lib/libmp3lame.a"
install -m 0644 "$zlib/zlib.h" "$zlib/zconf.h" "$deps/include/"
install -m 0644 "$zlib/libz.a" "$deps/lib/libz.a"

(
  cd "$ffmpeg"
  ./configure --target-os=linux --arch=x86_64 --cc=gcc-13 --cxx=g++-13 \
    --ar=ar --ranlib=ranlib --nm=nm --strip=strip --pkg-config=false \
    --disable-autodetect --disable-x86asm --disable-ffplay --disable-doc --disable-debug \
    --disable-gpl --disable-nonfree --disable-version3 --enable-static --disable-shared \
    --enable-libmp3lame --enable-zlib \
    --extra-cflags="-I$deps/include" --extra-ldflags="-L$deps/lib" \
    > "$build_root/ffmpeg-configure.log" 2>&1 || { tail -n 50 "$build_root/ffmpeg-configure.log"; fail 'FFmpeg configure failed'; }
  for macro in CONFIG_GPL CONFIG_NONFREE CONFIG_VERSION3; do
    grep -Eq "^#define $macro 0$" config.h || fail "FFmpeg license flag $macro is not disabled"
  done
  grep -q '^License: LGPL version 2\.1 or later$' "$build_root/ffmpeg-configure.log" || fail 'FFmpeg did not report LGPL-2.1-or-later'
  for macro in CONFIG_LIBMP3LAME_ENCODER CONFIG_AAC_ENCODER CONFIG_PNG_DECODER CONFIG_MJPEG_ENCODER \
    CONFIG_SCALE_FILTER CONFIG_MP3_MUXER CONFIG_MOV_MUXER CONFIG_MP4_MUXER; do
    grep -Eq "^#define $macro 1$" config_components.h || fail "required FFmpeg feature is missing: $macro"
  done
  for macro in CONFIG_FFMPEG CONFIG_FFPROBE; do
    grep -Eq "^#define $macro 1$" config.h || fail "required FFmpeg tool is missing: $macro"
  done
  make -j2 V=1 ffmpeg ffprobe > "$build_root/ffmpeg-build.log" 2>&1 || { tail -n 50 "$build_root/ffmpeg-build.log"; fail 'FFmpeg build failed'; }
)

"$ffmpeg/ffmpeg" -version | head -n 1 | grep -F 'ffmpeg version 8.1.3' >/dev/null || fail 'FFmpeg version check failed'
"$ffmpeg/ffprobe" -version | head -n 1 | grep -F 'ffprobe version 8.1.3' >/dev/null || fail 'ffprobe version check failed'
buildconf="$($ffmpeg/ffmpeg -buildconf)"
if grep -Eq -- '--enable-(gpl|nonfree|version3)( |$)' <<< "$buildconf"; then fail 'forbidden FFmpeg license option is enabled'; fi

smoke="$(mktemp -d "$build_root/smoke.XXXXXX")"
trap 'rm -rf -- "$smoke"' EXIT
"$ffmpeg/ffmpeg" -nostdin -v error -f lavfi -i 'sine=frequency=1000:duration=1' \
  -c:a libmp3lame -b:a 128k -y "$smoke/sample.mp3"
mp3_codec="$("$ffmpeg/ffprobe" -v error -select_streams a:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "$smoke/sample.mp3")"
[[ "$mp3_codec" == mp3 ]] || fail 'LAME MP3 smoke test failed'
"$ffmpeg/ffmpeg" -nostdin -v error -f lavfi -i 'color=c=black:s=64x64:d=1' \
  -f lavfi -i 'anullsrc=r=44100:cl=stereo' -shortest -c:v mpeg4 -pix_fmt yuv420p \
  -c:a aac -y "$smoke/sample.mp4"
mp4_codecs="$("$ffmpeg/ffprobe" -v error -show_entries stream=codec_name -of csv=p=0 "$smoke/sample.mp4")"
grep -qx 'mpeg4' <<< "$mp4_codecs" || fail 'MP4 video smoke test failed'
grep -qx 'aac' <<< "$mp4_codecs" || fail 'AAC audio smoke test failed'

install -m 0755 "$ffmpeg/ffmpeg" "$resources/ffmpeg"
install -m 0755 "$ffmpeg/ffprobe" "$resources/ffprobe"
echo "Ubuntu: $PRETTY_NAME"
echo "Compiler: $(gcc-13 --version | head -n 1)"
echo "yt-dlp SHA-256: $(hash_file "$resources/yt-dlp")"
echo "QuickJS SHA-256: $(hash_file "$resources/qjs")"
echo "FFmpeg SHA-256: $(hash_file "$resources/ffmpeg")"
echo "ffprobe SHA-256: $(hash_file "$resources/ffprobe")"
echo 'MP3 and MP4 smoke tests passed.'
