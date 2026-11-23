# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 zahidzta
#!/usr/bin/env bash
set -Eeuo pipefail

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

hash_file() {
  sha256sum "$1" | awk '{print $1}'
}

fetch_locked() {
  local name="$1"
  local expected="$2"
  local path="$downloads/$name"
  shift 2

  if [[ -f "$path" ]]; then
    [[ "$(hash_file "$path")" == "$expected" ]] || fail "$name exists with an unexpected SHA-256; preserving it for review"
    return
  fi

  local url
  local part="$path.part.$$"
  for url in "$@"; do
    if curl --fail --location --retry 3 --silent --show-error "$url" --output "$part"; then
      if [[ "$(hash_file "$part")" == "$expected" ]]; then
        mv -- "$part" "$path"
        return
      fi
    fi
    rm -f -- "$part"
  done
  fail "could not acquire $name with its locked SHA-256"
}

root="$(cd "$(dirname "$0")/../.." && pwd -P)"
out="$root/work/android/gate-5a/5a-04-ffmpeg"
downloads="$out/downloads"
mkdir -p "$downloads"

[[ -f /etc/os-release ]] || fail 'Ubuntu 24.04 host details are unavailable'
source /etc/os-release
[[ "$ID" == ubuntu && "$VERSION_ID" == 24.04 ]] || fail "expected Ubuntu 24.04, found $PRETTY_NAME"

ndk_root=''
if [[ -v ANDROID_NDK_HOME ]]; then ndk_root="$ANDROID_NDK_HOME"; fi
if [[ -z "$ndk_root" && -v NDK_HOME ]]; then ndk_root="$NDK_HOME"; fi
if [[ -z "$ndk_root" && -v ANDROID_HOME ]]; then ndk_root="$ANDROID_HOME/ndk/30.0.16248370"; fi
[[ -d "$ndk_root" ]] || fail 'set ANDROID_NDK_HOME or NDK_HOME to the pinned Android NDK r30 directory'
ndk_root="$(cd "$ndk_root" && pwd -P)"
grep -Eq '^Pkg.Revision[[:space:]]*=[[:space:]]*30[.]0[.]16248370[[:space:]]*$' "$ndk_root/source.properties" \
  || fail 'NDK source.properties does not identify 30.0.16248370'

toolchain="$ndk_root/toolchains/llvm/prebuilt/linux-x86_64"
toolbin="$toolchain/bin"
sysroot="$toolchain/sysroot"
export PATH="$toolbin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export LC_ALL=C
export TZ=UTC
cc="$toolbin/aarch64-linux-android24-clang"
cxx="$toolbin/aarch64-linux-android24-clang++"
ar="$toolbin/llvm-ar"
ranlib="$toolbin/llvm-ranlib"
nm="$toolbin/llvm-nm"
strip="$toolbin/llvm-strip"
readelf="$toolbin/llvm-readelf"
for tool in "$cc" "$cxx" "$ar" "$ranlib" "$nm" "$strip" "$readelf"; do
  [[ -x "$tool" ]] || fail "missing pinned NDK tool: $tool"
done

clang_version="$("$cc" --version | head -n 1)"
[[ "$clang_version" == *"clang version 21.0.0"* ]] || fail "unexpected NDK compiler: $clang_version"
make_version="$(make --version | head -n 1)"
host_gcc_version="$(gcc --version | head -n 1)"
[[ "$make_version" == 'GNU Make 4.3' ]] || fail "unexpected GNU Make: $make_version"
[[ "$host_gcc_version" == *'13.3.0'* ]] || fail "unexpected host GCC: $host_gcc_version"
api_level=''
if [[ -v ANDROID_API_LEVEL ]]; then api_level="$ANDROID_API_LEVEL"; fi
[[ "$api_level" == 24 ]] || fail 'ANDROID_API_LEVEL must be 24'

fetch_locked 'ffmpeg-8.1.3.tar.xz' \
  '7138d28c96d9d3e3af4ee3d8cad72741f8ffb40da90c1112235dea3ecd3178a3' \
  'https://ffmpeg.org/releases/ffmpeg-8.1.3.tar.xz' \
  'https://mirror.math.princeton.edu/pub/macports/distfiles/ffmpeg/ffmpeg-8.1.3.tar.xz'
fetch_locked 'ffmpeg-8.1.3.tar.xz.asc' \
  '5f2880c7fea01f8694d30cb9d06362f77241ee67ce5926b157a226b18f08a538' \
  'https://ffmpeg.org/releases/ffmpeg-8.1.3.tar.xz.asc' \
  'https://mirrors.mit.edu/gentoo-distfiles/distfiles/85/ffmpeg-8.1.3.tar.xz.asc'
fetch_locked 'ffmpeg-devel.asc' \
  '397b3becedcd5a98769967ff1ff8501ddc89f8368b8f766e4701377d7dbaabe5' \
  'https://ffmpeg.org/ffmpeg-devel.asc' \
  'https://raw.githubusercontent.com/FFmpeg/web/2d2f5f72996cdbc9420a5f0dc9c22a97d54871ae/htdocs/ffmpeg-devel.asc'
fetch_locked 'lame-3.100.tar.gz' \
  'ddfe36cab873794038ae2c1210557ad34857a4b6bdc515785d1da9e175b1da1e' \
  'https://sourceforge.net/projects/lame/files/lame/3.100/lame-3.100.tar.gz/download'
fetch_locked 'zlib-1.3.2.tar.gz' \
  'bb329a0a2cd0274d05519d61c667c062e06990d72e125ee2dfa8de64f0119d16' \
  'https://zlib.net/fossils/zlib-1.3.2.tar.gz' \
  'https://github.com/madler/zlib/releases/download/v1.3.2/zlib-1.3.2.tar.gz'

tmp="$(mktemp -d /tmp/zownload-5a-04-ffmpeg.XXXXXX)"
success=0
cleanup() {
  if [[ "$success" == 1 && "$tmp" == /tmp/zownload-5a-04-ffmpeg.* ]]; then
    rm -rf -- "$tmp"
  else
    printf 'Retained build workspace: %s\n' "$tmp" >&2
  fi
}
trap cleanup EXIT

mkdir -p "$tmp/gnupg" "$tmp/sources"
chmod 700 "$tmp/gnupg"
GNUPGHOME="$tmp/gnupg" gpg --batch --import "$downloads/ffmpeg-devel.asc" > "$out/ffmpeg-key-import.log" 2>&1
fingerprint="$(GNUPGHOME="$tmp/gnupg" gpg --batch --with-colons --fingerprint | awk -F: '$1 == "fpr" { print $10; exit }')"
[[ "$fingerprint" == FCF986EA15E6E293A5644F10B4322F04D67658D8 ]] || fail "unexpected FFmpeg signing key: $fingerprint"
if ! GNUPGHOME="$tmp/gnupg" gpg --batch --verify "$downloads/ffmpeg-8.1.3.tar.xz.asc" "$downloads/ffmpeg-8.1.3.tar.xz" > "$out/ffmpeg-signature.log" 2>&1; then
  tail -n 50 "$out/ffmpeg-signature.log" >&2
  fail 'FFmpeg release signature verification failed'
fi

tar -xf "$downloads/ffmpeg-8.1.3.tar.xz" -C "$tmp/sources"
tar -xf "$downloads/lame-3.100.tar.gz" -C "$tmp/sources"
tar -xf "$downloads/zlib-1.3.2.tar.gz" -C "$tmp/sources"
ffmpeg_src="$tmp/sources/ffmpeg-8.1.3"
lame_src="$tmp/sources/lame-3.100"
zlib_src="$tmp/sources/zlib-1.3.2"
deps="$tmp/deps"
mkdir -p "$deps"

if ! (
  cd "$lame_src"
  env CC="$cc" AR="$ar" RANLIB="$ranlib" NM="$nm" CFLAGS='-O2 -fPIC' \
    ./configure --build="$(gcc -dumpmachine)" --host=aarch64-linux-android \
      --disable-decoder --disable-frontend --disable-shared --enable-static \
      --disable-mp3x --disable-mp3rtp
) > "$out/lame-configure.log" 2>&1; then
  tail -n 50 "$out/lame-configure.log" >&2
  fail 'LAME Android configuration failed'
fi
grep -Eq '^/\* #undef HAVE_MPGLIB \*/$' "$lame_src/config.h" || fail 'GPL-only LAME decoder is enabled'
if ! make -C "$lame_src" -j2 > "$out/lame-build.log" 2>&1; then
  tail -n 50 "$out/lame-build.log" >&2
  fail 'LAME Android build failed'
fi
make -C "$lame_src" install "prefix=$deps" > "$out/lame-install.log" 2>&1 \
  || { tail -n 50 "$out/lame-install.log" >&2; fail 'LAME install failed'; }

if ! (
  cd "$zlib_src"
  env CHOST=aarch64-linux-android CC="$cc" AR="$ar" RANLIB="$ranlib" CFLAGS='-O2 -fPIC' \
    ./configure --static --prefix="$deps"
) > "$out/zlib-configure.log" 2>&1; then
  tail -n 50 "$out/zlib-configure.log" >&2
  fail 'zlib Android configuration failed'
fi
if ! make -C "$zlib_src" -j2 > "$out/zlib-build.log" 2>&1; then
  tail -n 50 "$out/zlib-build.log" >&2
  fail 'zlib Android build failed'
fi
make -C "$zlib_src" install > "$out/zlib-install.log" 2>&1 \
  || { tail -n 50 "$out/zlib-install.log" >&2; fail 'zlib install failed'; }

relink="$out/relink-materials"
mkdir -p "$relink/include" "$relink/lib"
cp -a "$deps/include/." "$relink/include/"
cp -a "$deps/lib/." "$relink/lib/"
for path in "$relink/lib/libmp3lame.a" "$relink/lib/libz.a" \
  "$relink/include/lame/lame.h" "$relink/include/zlib.h" "$relink/include/zconf.h"; do
  [[ -f "$path" ]] || fail "missing relinking input: $path"
done

configure_args="--target-os=android --arch=aarch64 --cpu=armv8-a --enable-cross-compile --cc=$cc --cxx=$cxx --ar=$ar --ranlib=$ranlib --nm=$nm --strip=$strip --sysroot=$sysroot --pkg-config=false --disable-autodetect --disable-x86asm --disable-network --disable-doc --disable-debug --disable-programs --disable-everything --enable-ffmpeg --enable-ffprobe --enable-gpl --disable-nonfree --disable-version3 --enable-static --disable-shared --enable-avdevice --enable-avfilter --enable-swresample --enable-swscale --enable-libmp3lame --enable-zlib --enable-protocol=file --enable-protocol=pipe --enable-indev=lavfi --enable-demuxer=aac --enable-demuxer=flac --enable-demuxer=image2 --enable-demuxer=matroska --enable-demuxer=mov --enable-demuxer=mp3 --enable-demuxer=ogg --enable-demuxer=wav --enable-muxer=mp3 --enable-muxer=mov --enable-decoder=aac --enable-decoder=alac --enable-decoder=av1 --enable-decoder=flac --enable-decoder=h264 --enable-decoder=hevc --enable-decoder=mjpeg --enable-decoder=mp3 --enable-decoder=mpeg4 --enable-decoder=opus --enable-decoder=png --enable-decoder=pcm_f32le --enable-decoder=pcm_s16le --enable-decoder=pcm_s24le --enable-decoder=pcm_s32le --enable-decoder=vorbis --enable-decoder=vp8 --enable-decoder=vp9 --enable-encoder=aac --enable-encoder=libmp3lame --enable-encoder=mjpeg --enable-encoder=mpeg4 --enable-parser=aac --enable-parser=av1 --enable-parser=flac --enable-parser=h264 --enable-parser=hevc --enable-parser=mjpeg --enable-parser=mpegaudio --enable-parser=mpeg4video --enable-parser=opus --enable-parser=png --enable-parser=vorbis --enable-parser=vp8 --enable-parser=vp9 --enable-bsf=aac_adtstoasc --enable-bsf=extract_extradata --enable-bsf=h264_mp4toannexb --enable-bsf=hevc_mp4toannexb --enable-filter=aformat --enable-filter=anull --enable-filter=color --enable-filter=format --enable-filter=scale --enable-filter=sine"
configure_args="$configure_args --enable-filter=aresample --enable-muxer=mp4 --enable-decoder=wrapped_avframe"
printf '%s\n' $configure_args > "$out/ffmpeg-configure-args.txt"
if ! (
  cd "$ffmpeg_src"
  set -- $configure_args
  env CFLAGS="-O2 -fPIC -I$deps/include" LDFLAGS="-L$deps/lib" ./configure "$@"
) > "$out/ffmpeg-configure.log" 2>&1; then
  tail -n 50 "$out/ffmpeg-configure.log" >&2
  fail 'FFmpeg Android configuration failed'
fi
grep -Fx 'License: GPL version 2 or later' "$out/ffmpeg-configure.log" >/dev/null \
  || fail 'FFmpeg did not report the selected GPL configuration'

check_macro() {
  local name="$1"
  local value="$2"
  local header="$ffmpeg_src/config_components.h"
  case "$name" in
    CONFIG_GPL|CONFIG_NONFREE|CONFIG_VERSION3|CONFIG_LIBMP3LAME|CONFIG_ZLIB)
      header="$ffmpeg_src/config.h"
      ;;
  esac
  grep -Eq "^#define $name $value$" "$header" || fail "$(basename "$header") does not set $name to $value"
}
check_macro CONFIG_GPL 1
check_macro CONFIG_NONFREE 0
check_macro CONFIG_VERSION3 0
check_macro CONFIG_LIBMP3LAME 1
check_macro CONFIG_ZLIB 1
for name in CONFIG_LIBX264_ENCODER CONFIG_LIBX265_ENCODER; do
  if grep -Eq "^#define $name 1$" "$ffmpeg_src/config_components.h"; then fail "$name is enabled"; fi
done
unexpected_external="$(grep -E '^#define CONFIG_LIB[A-Z0-9_]+ 1$' "$ffmpeg_src/config.h" \
  | awk '{print $2}' | grep -Ev '^CONFIG_LIBMP3LAME(_ENCODER)?$' || true)"
[[ -z "$unexpected_external" ]] || fail "unexpected external library configuration: $unexpected_external"
for name in CONFIG_LIBMP3LAME_ENCODER CONFIG_AAC_ENCODER CONFIG_MPEG4_ENCODER CONFIG_H264_DECODER CONFIG_HEVC_DECODER CONFIG_VP9_DECODER CONFIG_AV1_DECODER CONFIG_OPUS_DECODER CONFIG_VORBIS_DECODER CONFIG_PNG_DECODER CONFIG_WRAPPED_AVFRAME_DECODER CONFIG_ARESAMPLE_FILTER CONFIG_MOV_MUXER CONFIG_MP4_MUXER CONFIG_MP3_MUXER; do
  check_macro "$name" 1
done

if ! make -C "$ffmpeg_src" -j2 V=1 ffmpeg ffprobe > "$out/ffmpeg-build.log" 2>&1; then
  tail -n 50 "$out/ffmpeg-build.log" >&2
  fail 'FFmpeg Android build failed'
fi

ffmpeg_bin="$ffmpeg_src/ffmpeg"
ffprobe_bin="$ffmpeg_src/ffprobe"
"$strip" --strip-unneeded "$ffmpeg_bin"
"$strip" --strip-unneeded "$ffprobe_bin"

for bin in "$ffmpeg_bin" "$ffprobe_bin"; do
  file_header="$("$readelf" -h "$bin")"
  [[ "$file_header" == *AArch64* ]] || fail "$bin is not AArch64 ELF"
  program_headers="$("$readelf" -l "$bin")"
  grep -q '/system/bin/linker64' <<< "$program_headers" || fail "$bin has the wrong Android interpreter"
  strings "$bin" | grep -F 'FFmpeg version 8.1.3' >/dev/null || fail "$bin does not contain the locked FFmpeg version"
  needed="$("$readelf" -d "$bin" | sed -n 's/.*Shared library: \[\(.*\)\]/\1/p')"
  [[ -n "$needed" ]] || fail "$bin has no dynamic system libraries"
  while IFS= read -r library; do
    case "$library" in
      libc.so|libm.so|libdl.so|liblog.so|libandroid.so) ;;
      *) fail "$bin has unexpected ELF dependency $library" ;;
    esac
  done <<< "$needed"
  if [[ "$bin" == "$ffmpeg_bin" ]]; then
    printf '%s\n' "$needed" > "$out/ffmpeg-needed-libs.txt"
  else
    printf '%s\n' "$needed" > "$out/ffprobe-needed-libs.txt"
  fi
done

install -m 0755 "$ffmpeg_bin" "$out/ffmpeg"
install -m 0755 "$ffprobe_bin" "$out/ffprobe"

python3 - "$out/android-ffmpeg-manifest.json" "$out/ffmpeg" "$out/ffprobe" "$clang_version" "$make_version" "$host_gcc_version" "$configure_args" <<'PY'
import hashlib
import json
import os
import shlex
import sys

def artifact(path):
    digest = hashlib.sha256()
    with open(path, "rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return {"path": os.path.basename(path), "size": os.path.getsize(path), "sha256": digest.hexdigest()}

manifest = {
    "schema": 1,
    "engine": "FFmpeg",
    "version": "8.1.3",
    "target": "aarch64-linux-android",
    "abi": "arm64-v8a",
    "apiLevel": 24,
    "license": "GPL-2.0-or-later",
    "configuration": {"gpl": True, "nonfree": False, "version3": False, "x264": False, "x265": False},
    "sources": {
        "ffmpeg": {"version": "8.1.3", "sha256": "7138d28c96d9d3e3af4ee3d8cad72741f8ffb40da90c1112235dea3ecd3178a3"},
        "lame": {"version": "3.100", "sha256": "ddfe36cab873794038ae2c1210557ad34857a4b6bdc515785d1da9e175b1da1e"},
        "zlib": {"version": "1.3.2", "sha256": "bb329a0a2cd0274d05519d61c667c062e06990d72e125ee2dfa8de64f0119d16"},
        "ffmpegSignature": {"sha256": "5f2880c7fea01f8694d30cb9d06362f77241ee67ce5926b157a226b18f08a538", "keyFingerprint": "FCF986EA15E6E293A5644F10B4322F04D67658D8"},
    },
    "toolchain": {"host": "Ubuntu 24.04", "ndk": "30.0.16248370", "clang": sys.argv[4], "make": sys.argv[5], "hostGcc": sys.argv[6]},
    "configureArgs": shlex.split(sys.argv[7]),
    "artifacts": {"ffmpeg": artifact(sys.argv[2]), "ffprobe": artifact(sys.argv[3])},
    "elfDependencies": {
        "ffmpeg": open(os.path.join(os.path.dirname(sys.argv[2]), "ffmpeg-needed-libs.txt"), encoding="utf-8").read().splitlines(),
        "ffprobe": open(os.path.join(os.path.dirname(sys.argv[2]), "ffprobe-needed-libs.txt"), encoding="utf-8").read().splitlines(),
    },
    "relinkMaterials": {
        "libmp3lame.a": artifact(os.path.join(os.path.dirname(sys.argv[2]), "relink-materials", "lib", "libmp3lame.a")),
        "libz.a": artifact(os.path.join(os.path.dirname(sys.argv[2]), "relink-materials", "lib", "libz.a")),
        "lame.h": artifact(os.path.join(os.path.dirname(sys.argv[2]), "relink-materials", "include", "lame", "lame.h")),
        "zlib.h": artifact(os.path.join(os.path.dirname(sys.argv[2]), "relink-materials", "include", "zlib.h")),
        "zconf.h": artifact(os.path.join(os.path.dirname(sys.argv[2]), "relink-materials", "include", "zconf.h")),
    },
}
with open(sys.argv[1], "w", encoding="utf-8", newline="\n") as stream:
    json.dump(manifest, stream, indent=2)
    stream.write("\n")
PY

success=1
printf 'PASS: built FFmpeg/ffprobe 8.1.3 for Android arm64-v8a with GPL enabled, nonfree/x264/x265 disabled.\n'
printf 'FFmpeg SHA-256: %s\n' "$(hash_file "$out/ffmpeg")"
printf 'ffprobe SHA-256: %s\n' "$(hash_file "$out/ffprobe")"
printf 'Manifest: %s\n' "$out/android-ffmpeg-manifest.json"

