// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

use super::{Database, Error, Result};
use crate::contract::{Language, Settings};
use rusqlite::params;

impl Database {
    pub fn get_settings(&self) -> Result<Settings> {
        let (language, zip_playlists, download_dir): (String, i64, Option<String>) =
            self.connection.query_row(
                "SELECT language, zip_playlists, download_dir FROM settings WHERE id = 1",
                [],
                |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
            )?;
        let language = match language.as_str() {
            "en" => Language::En,
            "es" => Language::Es,
            _ => return Err(Error::InvalidStoredValue("settings.language")),
        };
        let zip_playlists = match zip_playlists {
            0 => false,
            1 => true,
            _ => return Err(Error::InvalidStoredValue("settings.zip_playlists")),
        };
        Ok(Settings {
            language,
            zip_playlists,
            download_dir,
        })
    }

    pub fn set_settings(&mut self, settings: &Settings) -> Result<()> {
        let transaction = self.connection.transaction()?;
        let language = match settings.language {
            Language::En => "en",
            Language::Es => "es",
        };
        let updated = transaction.execute(
            "UPDATE settings SET language = ?1, zip_playlists = ?2, download_dir = ?3 WHERE id = 1",
            params![
                language,
                i64::from(settings.zip_playlists),
                settings.download_dir
            ],
        )?;
        if updated != 1 {
            return Err(Error::InvalidStoredValue("settings singleton row"));
        }
        transaction.commit()?;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::persistence::test_path;

    #[test]
    fn defaults_replace_all_fields_and_survive_reopen() {
        let path = test_path();
        let mut db = Database::open_at(&path).unwrap();
        let defaults = db.get_settings().unwrap();
        assert_eq!(defaults.language, Language::En);
        assert!(!defaults.zip_playlists);
        assert_eq!(defaults.download_dir, None);

        db.set_settings(&Settings {
            language: Language::Es,
            zip_playlists: true,
            download_dir: Some("C:\\Downloads\\Music".to_string()),
        })
        .unwrap();
        drop(db);

        let mut db = Database::open_at(&path).unwrap();
        let saved = db.get_settings().unwrap();
        assert_eq!(saved.language, Language::Es);
        assert!(saved.zip_playlists);
        assert_eq!(saved.download_dir.as_deref(), Some("C:\\Downloads\\Music"));
        db.set_settings(&Settings {
            language: Language::En,
            zip_playlists: false,
            download_dir: None,
        })
        .unwrap();
        let reset = db.get_settings().unwrap();
        assert_eq!(reset.language, Language::En);
        assert!(!reset.zip_playlists);
        assert_eq!(reset.download_dir, None);
        let count: i64 = db
            .connection
            .query_row("SELECT COUNT(*) FROM settings", [], |row| row.get(0))
            .unwrap();
        assert_eq!(count, 1);
        drop(db);
        std::fs::remove_file(path).unwrap();
    }

    #[test]
    fn invalid_stored_values_are_reported() {
        let path = test_path();
        let db = Database::open_at(&path).unwrap();
        db.connection
            .execute("UPDATE settings SET language = 'fr'", [])
            .unwrap();
        assert!(matches!(
            db.get_settings(),
            Err(Error::InvalidStoredValue("settings.language"))
        ));
        db.connection
            .execute("UPDATE settings SET language = 'en', zip_playlists = 2", [])
            .unwrap();
        assert!(matches!(
            db.get_settings(),
            Err(Error::InvalidStoredValue("settings.zip_playlists"))
        ));
        drop(db);
        std::fs::remove_file(path).unwrap();
    }
}
