#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 zahidzta

set -euo pipefail

# linuxdeploy adjusts the AppImage's executable RPATHs. These four files are
# data resources for Zownload: the app verifies them before copying them into
# app data, where they run outside the AppImage. Keep their audited bytes exact.
if [[ $# -eq 3 && "$1" == --set-rpath ]]; then
  case "$3" in
    */bundle/appimage/*.AppDir/usr/lib/*/binaries/yt-dlp|\
    */bundle/appimage/*.AppDir/usr/lib/*/binaries/qjs|\
    */bundle/appimage/*.AppDir/usr/lib/*/binaries/ffmpeg|\
    */bundle/appimage/*.AppDir/usr/lib/*/binaries/ffprobe)
      exit 0
      ;;
  esac
fi

exec /usr/bin/patchelf "$@"
