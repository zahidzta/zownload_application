// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

use super::{Database, Error, Result};
use crate::contract::{AppError, DownloadRequest, ItemStatus, Progress, QueueItem};
use rusqlite::params;

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
        transaction.commit()?;
        Ok(())
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
