// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

//! Private playlist work state shared by Windows engine code and SQLite persistence.
//! These types are intentionally separate from the public Tauri contract.

use crate::contract::{AppError, ErrorCode};
use serde::{Deserialize, Serialize};
use url::Url;

pub const MAX_PLAYLIST_ENTRIES: usize = 10_000;
const URL_LIMIT: usize = 8 * 1024;

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct PlaylistEntry {
    pub url: String,
    pub title: String,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct PlaylistSnapshot {
    pub entries: Vec<PlaylistEntry>,
    pub next_index: usize,
}

impl PlaylistSnapshot {
    pub fn validate(&self) -> Result<(), AppError> {
        if self.entries.is_empty()
            || self.entries.len() > MAX_PLAYLIST_ENTRIES
            || self.next_index > self.entries.len()
            || self.entries.iter().any(|entry| {
                entry.title.trim().is_empty()
                    || entry.title.len() > 1024
                    || valid_entry_url(&entry.url).is_err()
            })
        {
            return Err(AppError::new(
                ErrorCode::Unknown,
                Some("invalid playlist snapshot".into()),
            ));
        }
        Ok(())
    }
}

fn valid_entry_url(value: &str) -> Result<(), AppError> {
    if value.len() > URL_LIMIT {
        return Err(AppError::new(
            ErrorCode::InvalidUrl,
            Some("playlist entry URL is too long".into()),
        ));
    }
    let url = Url::parse(value)
        .map_err(|error| AppError::new(ErrorCode::InvalidUrl, Some(error.to_string())))?;
    if !matches!(url.scheme(), "http" | "https") || url.host_str().is_none() {
        return Err(AppError::new(
            ErrorCode::InvalidUrl,
            Some("playlist entry must use HTTP(S)".into()),
        ));
    }
    Ok(())
}
