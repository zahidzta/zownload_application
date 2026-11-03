#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 zahidzta

set -euo pipefail

[[ $# -eq 1 ]] || { echo 'Usage: verify-linux-bundles.sh BUNDLE_ROOT' >&2; exit 2; }
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
bundle_root="$(cd "$1" && pwd -P)"
version="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$repo_root/src-tauri/tauri.conf.json")"
appimage="$bundle_root/appimage/Zownload_${version}_amd64.AppImage"
deb="$bundle_root/deb/Zownload_${version}_amd64.deb"
resources="$repo_root/src-tauri/resources/linux-engine"
[[ -f "$appimage" && -f "$deb" ]] || { echo 'Linux packages are missing' >&2; exit 1; }
[[ "$(dpkg-deb -f "$deb" Architecture)" == amd64 ]] || { echo 'Debian architecture mismatch' >&2; exit 1; }
dpkg-deb -f "$deb" Depends | grep -F 'libwebkit2gtk-4.1-0' >/dev/null || {
  echo 'Debian WebKitGTK runtime dependency is missing' >&2; exit 1;
}
appimage_format="$(file -b "$appimage")"
[[ "$appimage_format" == *'ELF 64-bit'* && "$appimage_format" == *'x86-64'* ]] || {
  echo 'AppImage architecture mismatch' >&2; exit 1;
}

work="$(mktemp -d "${RUNNER_TEMP:-/tmp}/zownload-4a-bundles.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
mkdir -p "$work/deb" "$work/appimage"
dpkg-deb -x "$deb" "$work/deb"
(cd "$work/appimage" && "$appimage" --appimage-extract >/dev/null)

for package in deb appimage; do
  for name in yt-dlp qjs ffmpeg ffprobe; do
    mapfile -t copies < <(find "$work/$package" -type f -path "*/binaries/$name")
    [[ ${#copies[@]} -eq 1 ]] || { echo "$package: expected one bundled $name" >&2; exit 1; }
    [[ -x "${copies[0]}" ]] || { echo "$package: $name is not executable" >&2; exit 1; }
    cmp -s "$resources/$name" "${copies[0]}" || {
      echo "$package: $name differs from verified engine input" >&2
      echo "Bundled path: ${copies[0]}" >&2
      sha256sum "$resources/$name" "${copies[0]}" >&2
      stat -c '%n %s bytes' "$resources/$name" "${copies[0]}" >&2
      echo "Input RPATH: $(patchelf --print-rpath "$resources/$name" 2>/dev/null || true)" >&2
      echo "Bundled RPATH: $(patchelf --print-rpath "${copies[0]}" 2>/dev/null || true)" >&2
      echo 'First differing byte positions:' >&2
      cmp -l "$resources/$name" "${copies[0]}" | head -n 5 >&2 || true
      exit 1
    }
  done
done
echo 'AppImage and .deb contain the exact verified executable engine resources.'
