// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

use super::{paths::DownloadPaths, Database, Error, Result};
use crate::contract::{AppError, DownloadRequest, ItemStatus, Progress, QueueItem};
use crate::playlist::PlaylistSnapshot;
use rusqlite::{params, OptionalExtension};

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct PlaylistState {
    pub zip_enabled: bool,
    pub snapshot: Option<PlaylistSnapshot>,
}

fn status_text(status: ItemStatus) -> &'static str {
    match status {
        ItemStatus::Analyzing => "analyzing",
        ItemStatus::Queued => "queued",
        ItemStatus::Downloading => "downloading",
        ItemStatus::PostProcessing => "postProcessing",
        ItemStatus::Paused => "paused",
        ItemStatus::Packaging => "packaging",
        ItemStatus::Done => "done",
        ItemStatus::Failed => "failed",
    }
}

impl Database {
    pub fn get_queue(&self) -> Result<Vec<QueueItem>> {
        let mut statement = self.connection.prepare(
            "SELECT id, request, title, thumbnail, status, progress, error \
             FROM queue_items ORDER BY position, id",
        )?;
        let rows = statement.query_map([], |row| {
            Ok((
                row.get::<_, String>(0)?,
                row.get::<_, String>(1)?,
                row.get::<_, Option<String>>(2)?,
                row.get::<_, Option<String>>(3)?,
                row.get::<_, String>(4)?,
                row.get::<_, String>(5)?,
                row.get::<_, Option<String>>(6)?,
            ))
        })?;
        let mut items = Vec::new();
        for row in rows {
            let (id, request, title, thumbnail, status, progress, error) = row?;
            let status = serde_json::from_value(serde_json::Value::String(status))
                .map_err(|_| Error::InvalidStoredValue("queue.status"))?;
            items.push(QueueItem {
                id,
                request: serde_json::from_str::<DownloadRequest>(&request)?,
                title,
                thumbnail,
                status,
                progress: serde_json::from_str::<Progress>(&progress)?,
                error: error
                    .map(|value| serde_json::from_str::<AppError>(&value))
                    .transpose()?,
            });
        }
        Ok(items)
    }

    pub fn insert_queue_item(&mut self, item: &QueueItem) -> Result<()> {
        self.insert_queue_item_with_paths(item, None)
    }

    /// Insert the queue row and its private output choice in one commit.
    pub fn insert_queue_item_with_paths(
        &mut self,
        item: &QueueItem,
        paths: Option<&DownloadPaths>,
    ) -> Result<()> {
        self.insert_queue_item_with_options(item, paths, None)
    }

    /// Capture folder and ZIP preference with the request; later Settings edits cannot change it.
    pub fn insert_queue_item_with_options(
        &mut self,
        item: &QueueItem,
        paths: Option<&DownloadPaths>,
        zip_enabled: Option<bool>,
    ) -> Result<()> {
        uuid::Uuid::parse_str(&item.id).map_err(|_| Error::InvalidInput("queue id"))?;
        let request = serde_json::to_string(&item.request)?;
        let progress = serde_json::to_string(&item.progress)?;
        let error = item.error.as_ref().map(serde_json::to_string).transpose()?;
        let transaction = self.connection.transaction()?;
        // Positions are monotonic. Removing an earlier item never reorders later ones.
        let position: i64 = transaction.query_row(
            "SELECT COALESCE(MAX(position), 0) + 1 FROM queue_items",
            [],
            |row| row.get(0),
        )?;
        transaction.execute(
            "INSERT INTO queue_items (id, position, request, title, thumbnail, status, progress, error) \
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)",
            params![item.id, position, request, item.title, item.thumbnail,
                status_text(item.status), progress, error],
        )?;
        if let Some(paths) = paths {
            if paths.queue_id != item.id {
                return Err(Error::InvalidInput("download path owner"));
            }
            transaction.execute(
                "INSERT INTO download_paths (queue_id, output_dir, work_dir, reserved_path) \
                 VALUES (?1, ?2, ?3, NULL)",
                params![
                    paths.queue_id,
                    paths.output_dir.to_string_lossy(),
                    paths.work_dir.to_string_lossy()
                ],
            )?;
        }
        if item.request.is_playlist {
            transaction.execute(
                "INSERT INTO playlist_state (queue_id, zip_enabled) VALUES (?1, ?2)",
                params![item.id, i64::from(zip_enabled.unwrap_or(false))],
            )?;
        }
        transaction.commit()?;
        Ok(())
    }

    pub fn get_playlist_state(&self, id: &str) -> Result<Option<PlaylistState>> {
        let row: Option<(i64, Option<String>, i64)> = self
            .connection
            .query_row(
                "SELECT zip_enabled, entries, next_index FROM playlist_state WHERE queue_id = ?1",
                [id],
                |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
            )
            .optional()?;
        let Some((zip, entries, index)) = row else {
            return Ok(None);
        };
        if !matches!(zip, 0 | 1) || index < 0 {
            return Err(Error::InvalidStoredValue("playlist state"));
        }
        let snapshot = entries
            .map(|json| -> Result<PlaylistSnapshot> {
                if json.len() > 16 * 1024 * 1024 {
                    return Err(Error::InvalidStoredValue("playlist entries"));
                }
                let mut value: PlaylistSnapshot = serde_json::from_str(&json)?;
                value.next_index = usize::try_from(index)
                    .map_err(|_| Error::InvalidStoredValue("playlist index"))?;
                value
                    .validate()
                    .map_err(|_| Error::InvalidStoredValue("playlist snapshot"))?;
                Ok(value)
            })
            .transpose()?;
        if snapshot.is_none() && index != 0 {
            return Err(Error::InvalidStoredValue("playlist index"));
        }
        Ok(Some(PlaylistState {
            zip_enabled: zip == 1,
            snapshot,
        }))
    }

    /// The first expansion is durable before any entry starts. An existing snapshot is never replaced on resume.
    pub fn save_playlist_snapshot(
        &mut self,
        id: &str,
        title: &str,
        snapshot: &PlaylistSnapshot,
    ) -> Result<bool> {
        if title.trim().is_empty() || snapshot.next_index != 0 {
            return Err(Error::InvalidInput("playlist snapshot"));
        }
        snapshot
            .validate()
            .map_err(|_| Error::InvalidInput("playlist snapshot"))?;
        let entries = serde_json::to_string(snapshot)?;
        if entries.len() > 16 * 1024 * 1024 {
            return Err(Error::InvalidInput("playlist snapshot size"));
        }
        let progress = serde_json::to_string(&Progress::Playlist {
            done: 0,
            failed: 0,
            total: snapshot.entries.len() as u32,
            current_title: snapshot.entries.first().map(|entry| entry.title.clone()),
            current_percent: 0.0,
        })?;
        let tx = self.connection.transaction()?;
        let changed = tx.execute("UPDATE playlist_state SET entries = ?2, next_index = 0 WHERE queue_id = ?1 AND entries IS NULL", params![id, entries])?;
        if changed != 0 {
            tx.execute(
                "UPDATE queue_items SET title = ?2, progress = ?3 WHERE id = ?1",
                params![id, title, progress],
            )?;
        }
        tx.commit()?;
        Ok(changed != 0)
    }

    /// Settle one entry and its public counters in the same SQLite transaction.
    pub fn advance_playlist(&mut self, item: &QueueItem, expected_index: usize) -> Result<bool> {
        let next = expected_index
            .checked_add(1)
            .ok_or(Error::InvalidInput("playlist index"))?;
        let state = self
            .get_playlist_state(&item.id)?
            .ok_or(Error::NotFound("playlist state"))?;
        let snapshot = state
            .snapshot
            .ok_or(Error::InvalidStoredValue("playlist snapshot"))?;
        if snapshot.next_index != expected_index || next > snapshot.entries.len() {
            return Err(Error::InvalidInput("playlist index"));
        }
        let Progress::Playlist {
            done,
            failed,
            total,
            ..
        } = &item.progress
        else {
            return Err(Error::InvalidInput("playlist progress"));
        };
        if *total != snapshot.entries.len() as u32
            || u64::from(*done) + u64::from(*failed) != next as u64
        {
            return Err(Error::InvalidInput("playlist counters"));
        }
        let progress = serde_json::to_string(&item.progress)?;
        let tx = self.connection.transaction()?;
        let changed = tx.execute(
            "UPDATE playlist_state SET next_index = ?3 WHERE queue_id = ?1 AND next_index = ?2",
            params![item.id, expected_index as i64, next as i64],
        )?;
        if changed != 0 {
            tx.execute(
                "UPDATE queue_items SET progress = ?2 WHERE id = ?1",
                params![item.id, progress],
            )?;
        }
        tx.commit()?;
        Ok(changed != 0)
    }

    pub fn update_queue_item(&mut self, item: &QueueItem) -> Result<bool> {
        let request = serde_json::to_string(&item.request)?;
        let progress = serde_json::to_string(&item.progress)?;
        let error = item.error.as_ref().map(serde_json::to_string).transpose()?;
        let transaction = self.connection.transaction()?;
        let changed = transaction.execute(
            "UPDATE queue_items SET request = ?2, title = ?3, thumbnail = ?4, status = ?5, \
             progress = ?6, error = ?7 WHERE id = ?1",
            params![
                item.id,
                request,
                item.title,
                item.thumbnail,
                status_text(item.status),
                progress,
                error
            ],
        )?;
        transaction.commit()?;
        Ok(changed != 0)
    }

    pub fn remove_queue_item(&mut self, id: &str) -> Result<bool> {
        let transaction = self.connection.transaction()?;
        let changed = transaction.execute("DELETE FROM queue_items WHERE id = ?1", [id])?;
        transaction.commit()?;
        Ok(changed != 0)
    }

    pub(super) fn recover_interrupted_queue(&mut self) -> Result<()> {
        let transaction = self.connection.transaction()?;
        // A crash may leave one of these states. No engine is started on reopen.
        transaction.execute(
            "UPDATE queue_items SET status = 'paused' WHERE status IN \
             ('analyzing', 'downloading', 'postProcessing', 'packaging')",
            [],
        )?;
        transaction.commit()?;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{
        contract::{ErrorCode, Format, Quality},
        persistence::test_path,
    };

    #[test]
    fn playlist_snapshot_and_index_survive_restart_and_advance_atomically() {
        let path = test_path();
        let mut db = Database::open_at(&path).unwrap();
        let mut row = item(ItemStatus::Downloading);
        row.progress = Progress::Playlist {
            done: 0,
            failed: 0,
            total: 0,
            current_title: None,
            current_percent: 0.0,
        };
        db.insert_queue_item_with_options(&row, None, Some(true))
            .unwrap();
        let snapshot = PlaylistSnapshot {
            entries: vec![
                crate::playlist::PlaylistEntry {
                    url: "https://example.com/one".into(),
                    title: "One".into(),
                },
                crate::playlist::PlaylistEntry {
                    url: "https://example.com/two".into(),
                    title: "Two".into(),
                },
            ],
            next_index: 0,
        };
        assert!(db
            .save_playlist_snapshot(&row.id, "Set", &snapshot)
            .unwrap());
        assert!(!db
            .save_playlist_snapshot(&row.id, "Changed", &snapshot)
            .unwrap());
        row = db.get_queue().unwrap().remove(0);
        row.progress = Progress::Playlist {
            done: 1,
            failed: 0,
            total: 2,
            current_title: Some("Two".into()),
            current_percent: 0.0,
        };
        assert!(db.advance_playlist(&row, 0).unwrap());
        assert!(db.advance_playlist(&row, 0).is_err());
        drop(db);
        let mut db = Database::open_at(&path).unwrap();
        let restored = db.get_queue().unwrap().remove(0);
        assert_eq!(restored.status, ItemStatus::Paused);
        assert_eq!(restored.title.as_deref(), Some("Set"));
        assert_eq!(
            serde_json::to_value(&restored.progress).unwrap(),
            serde_json::to_value(&row.progress).unwrap()
        );
        let state = db.get_playlist_state(&row.id).unwrap().unwrap();
        assert!(state.zip_enabled);
        assert_eq!(state.snapshot.unwrap().next_index, 1);
        db.remove_queue_item(&row.id).unwrap();
        assert!(db.get_playlist_state(&row.id).unwrap().is_none());
        drop(db);
        std::fs::remove_file(path).unwrap();
    }

    #[test]
    fn malformed_snapshot_is_rejected_and_new_request_expands_fresh() {
        let path = test_path();
        let mut db = Database::open_at(&path).unwrap();
        let first = item(ItemStatus::Queued);
        db.insert_queue_item_with_options(&first, None, Some(false))
            .unwrap();
        let second = item(ItemStatus::Queued);
        db.insert_queue_item_with_options(&second, None, Some(false))
            .unwrap();
        assert!(db
            .get_playlist_state(&second.id)
            .unwrap()
            .unwrap()
            .snapshot
            .is_none());
        let valid = PlaylistSnapshot {
            entries: vec![crate::playlist::PlaylistEntry {
                url: "https://example.com/one".into(),
                title: "One".into(),
            }],
            next_index: 0,
        };
        db.save_playlist_snapshot(&first.id, "Old", &valid).unwrap();
        assert!(db
            .get_playlist_state(&second.id)
            .unwrap()
            .unwrap()
            .snapshot
            .is_none());
        db.connection
            .execute(
                "UPDATE playlist_state SET entries = '{bad' WHERE queue_id = ?1",
                [&first.id],
            )
            .unwrap();
        assert!(db.get_playlist_state(&first.id).is_err());
        db.connection
            .execute(
                "UPDATE playlist_state SET entries = ?2, next_index = 2 WHERE queue_id = ?1",
                params![first.id, serde_json::to_string(&valid).unwrap()],
            )
            .unwrap();
        assert!(db.get_playlist_state(&first.id).is_err());
        db.connection
            .execute(
                "UPDATE playlist_state SET entries = ?2, next_index = 0 WHERE queue_id = ?1",
                params![first.id, " ".repeat(16 * 1024 * 1024 + 1)],
            )
            .unwrap();
        assert!(matches!(
            db.get_playlist_state(&first.id),
            Err(Error::InvalidStoredValue("playlist entries"))
        ));
        drop(db);
        std::fs::remove_file(path).unwrap();
    }

    fn item(status: ItemStatus) -> QueueItem {
        QueueItem {
            id: uuid::Uuid::new_v4().to_string(),
            request: DownloadRequest {
                url: "https://example.com/list".into(),
                format: Format::Mp4,
                quality: Quality::Max,
                is_playlist: true,
            },
            title: Some("Playlist".into()),
            thumbnail: Some("data:image/svg+xml,example".into()),
            status,
            progress: Progress::Playlist {
                done: 2,
                failed: 1,
                total: 5,
                current_title: Some("third".into()),
                current_percent: 37.5,
            },
            error: Some(AppError::new(ErrorCode::NoInternet, Some("offline".into()))),
        }
    }

    #[test]
    fn snapshots_round_trip_and_positions_survive_removal_and_reopen() {
        let path = test_path();
        let mut db = Database::open_at(&path).unwrap();
        let first = item(ItemStatus::Queued);
        let mut second = item(ItemStatus::Queued);
        second.request.url = "https://example.com/second".into();
        db.insert_queue_item(&first).unwrap();
        db.insert_queue_item(&second).unwrap();
        assert!(db.remove_queue_item(&first.id).unwrap());
        let mut third = item(ItemStatus::Paused);
        third.request.url = "https://example.com/third".into();
        db.insert_queue_item(&third).unwrap();
        drop(db);
        let db = Database::open_at(&path).unwrap();
        let snapshots = db.get_queue().unwrap();
        assert_eq!(
            snapshots.iter().map(|item| &item.id).collect::<Vec<_>>(),
            vec![&second.id, &third.id]
        );
        assert_eq!(
            serde_json::to_value(&snapshots[0]).unwrap(),
            serde_json::to_value(&second).unwrap()
        );
        assert_eq!(
            serde_json::to_value(&snapshots[1]).unwrap(),
            serde_json::to_value(&third).unwrap()
        );
        drop(db);
        std::fs::remove_file(path).unwrap();
    }

    #[test]
    fn reopening_pauses_each_interrupted_state_without_losing_progress() {
        let path = test_path();
        let mut db = Database::open_at(&path).unwrap();
        let states = [
            ItemStatus::Analyzing,
            ItemStatus::Downloading,
            ItemStatus::PostProcessing,
            ItemStatus::Packaging,
            ItemStatus::Queued,
            ItemStatus::Paused,
        ];
        let items: Vec<_> = states.into_iter().map(item).collect();
        for item in &items {
            db.insert_queue_item(item).unwrap();
        }
        drop(db);
        for _ in 0..2 {
            let db = Database::open_at(&path).unwrap();
            let restored = db.get_queue().unwrap();
            for (index, value) in restored.iter().enumerate() {
                assert_eq!(
                    value.status,
                    if index < 4 {
                        ItemStatus::Paused
                    } else {
                        states[index]
                    }
                );
                assert_eq!(
                    serde_json::to_value(&value.progress).unwrap(),
                    serde_json::to_value(&items[index].progress).unwrap()
                );
            }
        }
        std::fs::remove_file(path).unwrap();
    }

    #[test]
    fn update_keeps_position_and_invalid_ids_do_not_enter_queue() {
        let path = test_path();
        let mut db = Database::open_at(&path).unwrap();
        let mut one = item(ItemStatus::Queued);
        let two = item(ItemStatus::Queued);
        db.insert_queue_item(&one).unwrap();
        db.insert_queue_item(&two).unwrap();
        one.status = ItemStatus::Paused;
        assert!(db.update_queue_item(&one).unwrap());
        assert_eq!(db.get_queue().unwrap()[0].status, ItemStatus::Paused);
        assert!(matches!(db.insert_queue_item(&one), Err(Error::Sql(_))));
        let mut invalid = item(ItemStatus::Queued);
        invalid.id = "not-a-uuid".into();
        assert!(matches!(
            db.insert_queue_item(&invalid),
            Err(Error::InvalidInput(_))
        ));
        assert_eq!(db.get_queue().unwrap().len(), 2);
        drop(db);
        std::fs::remove_file(path).unwrap();
    }
}
