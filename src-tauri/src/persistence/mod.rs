// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

mod migrations;

use rusqlite::Connection;
use std::{fmt, fs, path::Path};

pub struct Database {
    connection: Connection,
}

#[derive(Debug)]
pub enum Error {
    Io(std::io::Error),
    Sql(rusqlite::Error),
    Json(serde_json::Error),
    UnsupportedSchema(i64),
    InvalidStoredValue(&'static str),
}

pub type Result<T> = std::result::Result<T, Error>;

impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Io(error) => write!(f, "database I/O: {error}"),
            Self::Sql(error) => write!(f, "database SQL: {error}"),
            Self::Json(error) => write!(f, "database JSON: {error}"),
            Self::UnsupportedSchema(version) => {
                write!(f, "unsupported database schema version {version}")
            }
            Self::InvalidStoredValue(field) => write!(f, "invalid stored {field}"),
        }
    }
}

impl std::error::Error for Error {}

impl From<std::io::Error> for Error {
    fn from(error: std::io::Error) -> Self {
        Self::Io(error)
    }
}

impl From<rusqlite::Error> for Error {
    fn from(error: rusqlite::Error) -> Self {
        Self::Sql(error)
    }
}

impl From<serde_json::Error> for Error {
    fn from(error: serde_json::Error) -> Self {
        Self::Json(error)
    }
}

impl Database {
    pub fn open_at(path: &Path) -> Result<Self> {
        if let Some(parent) = path
            .parent()
            .filter(|parent| !parent.as_os_str().is_empty())
        {
            fs::create_dir_all(parent)?;
        }
        let mut connection = Connection::open(path)?;
        migrations::apply(&mut connection)?;
        Ok(Self { connection })
    }
}

#[cfg(test)]
pub(crate) fn test_path() -> std::path::PathBuf {
    std::env::temp_dir().join(format!(
        "zownload-persistence-{}.sqlite3",
        uuid::Uuid::new_v4()
    ))
}
