// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

use super::{Database, Error, Result};
use crate::contract::{DownloadRequest, Format, HistoryEntry, Quality};
use rusqlite::params;

impl Database {
    pub fn get_history(&self) -> Result<Vec<HistoryEntry>> {
        let mut statement = self.connection.prepare(
            "SELECT id, url, format, is_playlist, quality, title FROM history ORDER BY id DESC",
        )?;
        let rows = statement.query_map([], |row| {
            Ok((
                row.get::<_, i64>(0)?,
                row.get::<_, String>(1)?,
                row.get::<_, String>(2)?,
                row.get::<_, i64>(3)?,
                row.get::<_, String>(4)?,
                row.get::<_, Option<String>>(5)?,
            ))
        })?;
        let mut entries = Vec::new();
        for row in rows {
            let (id, url, format, is_playlist, quality, title) = row?;
            let format = match format.as_str() {
                "mp3" => Format::Mp3,
                "mp4" => Format::Mp4,
                _ => return Err(Error::InvalidStoredValue("history.format")),
            };
            let is_playlist = match is_playlist {
                0 => false,
                1 => true,
                _ => return Err(Error::InvalidStoredValue("history.is_playlist")),
            };
            let quality: Quality = serde_json::from_str(&quality)?;
            entries.push(HistoryEntry {
                id,
                request: DownloadRequest {
                    url,
                    format,
                    quality,
                    is_playlist,
                },
                title,
            });
        }
        Ok(entries)
    }

    pub fn record_history(
        &mut self,
        request: &DownloadRequest,
        title: Option<&str>,
    ) -> Result<i64> {
        let format = match request.format {
            Format::Mp3 => "mp3",
            Format::Mp4 => "mp4",
        };
        let quality = serde_json::to_string(&request.quality)?;
        let is_playlist = i64::from(request.is_playlist);
        let transaction = self.connection.transaction()?;
        // A repeated exact request receives a fresh id, which moves it to the top.
        transaction.execute(
            "DELETE FROM history WHERE url = ?1 AND format = ?2 AND is_playlist = ?3 AND quality = ?4",
            params![request.url, format, is_playlist, quality],
        )?;
        transaction.execute(
            "INSERT INTO history (url, format, is_playlist, quality, title) VALUES (?1, ?2, ?3, ?4, ?5)",
            params![request.url, format, is_playlist, quality, title],
        )?;
        let id = transaction.last_insert_rowid();
        transaction.commit()?;
        Ok(id)
    }

    pub fn delete_history_entry(&mut self, id: i64) -> Result<bool> {
        let transaction = self.connection.transaction()?;
        let deleted = transaction.execute("DELETE FROM history WHERE id = ?1", [id])?;
        transaction.commit()?;
        Ok(deleted != 0)
    }

    pub fn clear_history(&mut self) -> Result<usize> {
        let transaction = self.connection.transaction()?;
        let deleted = transaction.execute("DELETE FROM history", [])?;
        transaction.commit()?;
        Ok(deleted)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::persistence::test_path;

    fn request(url: &str, quality: Quality) -> DownloadRequest {
        DownloadRequest {
            url: url.to_string(),
            format: Format::Mp4,
            quality,
            is_playlist: false,
        }
    }

    #[test]
    fn exact_request_replaces_older_row_and_moves_to_top_across_reopen() {
        let path = test_path();
        let mut db = Database::open_at(&path).unwrap();
        let first = request("https://example.com/one", Quality::Video { height: 720 });
        let second = request("https://example.com/two", Quality::Video { height: 720 });
        let first_id = db.record_history(&first, Some("Same title")).unwrap();
        let second_id = db.record_history(&second, Some("Same title")).unwrap();
        let replacement_id = db.record_history(&first, Some("New title")).unwrap();
        assert!(first_id < second_id && second_id < replacement_id);
        drop(db);

        let db = Database::open_at(&path).unwrap();
        let entries = db.get_history().unwrap();
        assert_eq!(entries.len(), 2);
        assert_eq!((entries[0].id, entries[1].id), (replacement_id, second_id));
        assert_eq!(entries[0].request, first);
        assert_eq!(entries[0].title.as_deref(), Some("New title"));
        assert_eq!(entries[1].request, second);
        drop(db);
        std::fs::remove_file(path).unwrap();
    }

    #[test]
    fn duplicate_titles_and_quality_json_round_trip() {
        let path = test_path();
        let mut db = Database::open_at(&path).unwrap();
        let one = request("https://example.com/video", Quality::Video { height: 1080 });
        let another_quality = request("https://example.com/video", Quality::Video { height: 720 });
        db.record_history(&one, Some("Same title")).unwrap();
        db.record_history(&another_quality, Some("Same title"))
            .unwrap();
        let playlist = DownloadRequest {
            url: "https://example.com/playlist".to_string(),
            format: Format::Mp3,
            quality: Quality::Max,
            is_playlist: true,
        };
        db.record_history(&playlist, None).unwrap();
        drop(db);

        let db = Database::open_at(&path).unwrap();
        let entries = db.get_history().unwrap();
        assert_eq!(entries.len(), 3);
        assert_eq!(entries[0].request, playlist);
        assert_eq!(entries[0].title, None);
        assert_eq!(entries[1].request, another_quality);
        assert_eq!(entries[2].request, one);
        assert_eq!(entries[1].title, entries[2].title);
        drop(db);
        std::fs::remove_file(path).unwrap();
    }

    #[test]
    fn delete_and_clear_only_affect_requested_history_rows() {
        let path = test_path();
        let mut db = Database::open_at(&path).unwrap();
        let first = db
            .record_history(&request("one", Quality::Video { height: 720 }), None)
            .unwrap();
        let second = db
            .record_history(&request("two", Quality::Video { height: 720 }), None)
            .unwrap();
        assert!(!db.delete_history_entry(-1).unwrap());
        assert!(db.delete_history_entry(first).unwrap());
        assert_eq!(db.get_history().unwrap()[0].id, second);
        assert_eq!(db.clear_history().unwrap(), 1);
        assert!(db.get_history().unwrap().is_empty());
        drop(db);
        std::fs::remove_file(path).unwrap();
    }
}
