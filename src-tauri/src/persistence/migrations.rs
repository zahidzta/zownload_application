// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

use super::{Error, Result};
use rusqlite::Connection;

const CURRENT_VERSION: i64 = 2;

const VERSION_1: &str = "
    CREATE TABLE settings (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        language TEXT NOT NULL,
        zip_playlists INTEGER NOT NULL,
        download_dir TEXT
    );
    INSERT INTO settings (id, language, zip_playlists, download_dir)
    VALUES (1, 'en', 0, NULL);
    CREATE TABLE history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        url TEXT NOT NULL,
        format TEXT NOT NULL,
        is_playlist INTEGER NOT NULL,
        quality TEXT NOT NULL,
        title TEXT,
        UNIQUE (url, format, is_playlist, quality)
    );
";

const VERSION_2: &str = "
    CREATE TABLE queue_items (
        id TEXT PRIMARY KEY,
        position INTEGER NOT NULL UNIQUE,
        request TEXT NOT NULL,
        title TEXT,
        thumbnail TEXT,
        status TEXT NOT NULL,
        progress TEXT NOT NULL,
        error TEXT
    );
    CREATE TABLE error_notifications (
        id TEXT PRIMARY KEY,
        title TEXT,
        error TEXT NOT NULL
    );
";

pub(super) fn apply(connection: &mut Connection) -> Result<()> {
    let version: i64 = connection.pragma_query_value(None, "user_version", |row| row.get(0))?;
    if !(0..=CURRENT_VERSION).contains(&version) {
        return Err(Error::UnsupportedSchema(version));
    }
    for (next, sql) in [(1, VERSION_1), (2, VERSION_2)] {
        if version < next {
            // Schema and version advance together, so a failure leaves the prior data intact.
            let transaction = connection.transaction()?;
            transaction.execute_batch(sql)?;
            transaction.pragma_update(None, "user_version", next)?;
            transaction.commit()?;
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::persistence::{test_path, Database};

    #[test]
    fn fresh_open_and_reopen_seed_one_settings_row() {
        let path = test_path();
        let db = Database::open_at(&path).unwrap();
        let version: i64 = db
            .connection
            .pragma_query_value(None, "user_version", |r| r.get(0))
            .unwrap();
        assert_eq!(version, CURRENT_VERSION);
        let count: i64 = db
            .connection
            .query_row("SELECT COUNT(*) FROM settings", [], |r| r.get(0))
            .unwrap();
        assert_eq!(count, 1);
        db.connection
            .execute("UPDATE settings SET language = 'es' WHERE id = 1", [])
            .unwrap();
        drop(db);
        let reopened = Database::open_at(&path).unwrap();
        let language: String = reopened
            .connection
            .query_row("SELECT language FROM settings", [], |r| r.get(0))
            .unwrap();
        assert_eq!(language, "es");
        drop(reopened);
        std::fs::remove_file(path).unwrap();
    }

    #[test]
    fn upgrades_an_earlier_version_without_replacing_data() {
        let path = test_path();
        let connection = Connection::open(&path).unwrap();
        connection.execute_batch(VERSION_1).unwrap();
        connection
            .execute("UPDATE settings SET language = 'es'", [])
            .unwrap();
        connection.pragma_update(None, "user_version", 1).unwrap();
        drop(connection);
        let db = Database::open_at(&path).unwrap();
        let language: String = db
            .connection
            .query_row("SELECT language FROM settings", [], |r| r.get(0))
            .unwrap();
        assert_eq!(language, "es");
        let count: i64 = db
            .connection
            .query_row("SELECT COUNT(*) FROM queue_items", [], |r| r.get(0))
            .unwrap();
        assert_eq!(count, 0);
        drop(db);
        std::fs::remove_file(path).unwrap();
    }

    #[test]
    fn newer_schema_is_rejected_without_changing_data() {
        let path = test_path();
        let connection = Connection::open(&path).unwrap();
        connection
            .execute_batch("CREATE TABLE keep_me (value TEXT); INSERT INTO keep_me VALUES ('safe')")
            .unwrap();
        connection
            .pragma_update(None, "user_version", CURRENT_VERSION + 1)
            .unwrap();
        drop(connection);
        assert!(matches!(
            Database::open_at(&path),
            Err(Error::UnsupportedSchema(3))
        ));
        let connection = Connection::open(&path).unwrap();
        let value: String = connection
            .query_row("SELECT value FROM keep_me", [], |r| r.get(0))
            .unwrap();
        assert_eq!(value, "safe");
        drop(connection);
        std::fs::remove_file(path).unwrap();
    }

    #[test]
    fn failed_migration_rolls_back_schema_and_version() {
        let path = test_path();
        let connection = Connection::open(&path).unwrap();
        connection
            .execute_batch(
                "CREATE TABLE settings (marker TEXT); INSERT INTO settings VALUES ('safe')",
            )
            .unwrap();
        drop(connection);
        assert!(matches!(Database::open_at(&path), Err(Error::Sql(_))));
        let connection = Connection::open(&path).unwrap();
        let version: i64 = connection
            .pragma_query_value(None, "user_version", |r| r.get(0))
            .unwrap();
        let marker: String = connection
            .query_row("SELECT marker FROM settings", [], |r| r.get(0))
            .unwrap();
        assert_eq!((version, marker.as_str()), (0, "safe"));
        drop(connection);
        std::fs::remove_file(path).unwrap();
    }
}
