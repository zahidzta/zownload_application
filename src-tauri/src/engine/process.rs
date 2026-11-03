// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

#[cfg(target_os = "linux")]
#[path = "process/linux.rs"]
mod platform;
#[cfg(target_os = "windows")]
#[path = "process/windows.rs"]
mod platform;

pub use platform::*;
