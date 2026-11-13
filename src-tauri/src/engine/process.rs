// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

#[cfg(any(target_os = "linux", target_os = "macos"))]
#[path = "process/unix.rs"]
mod platform;
#[cfg(target_os = "windows")]
#[path = "process/windows.rs"]
mod platform;

pub use platform::*;
