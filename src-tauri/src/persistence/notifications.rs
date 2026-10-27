// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

use super::{history::record_in_transaction, Database, Error, Result};
use crate::contract::{
    AppError, DownloadRequest, ErrorCode, ErrorNotification, ItemStatus, Progress,
};
use rusqlite::{params, OptionalExtension};

/// Internal result of engine work. The engine will call this in a later stage.
pub enum TerminalOutcome {
    Completed { successful_files: u32 },
    Failed(AppError),
}

impl Database {
    pub(super) fn recover_terminal_queue(&mut self) -> Result<()> {
        // A crash between the transient terminal write and its settlement must
        // not leave a finished item stuck in Queue on the next launch.
        for item in self.get_queue()? {
            match item.status {
                ItemStatus::Done => {
                    let successful_files = match item.progress {
                        Progress::Single { .. } => 1,
                        Progress::Playlist { done, .. } => done,
                    };
                    self.settle_queue_item(
                        &item.id,
                        TerminalOutcome::Completed { successful_files },
                    )?;
                }
                ItemStatus::Failed => {
                    let error = item.error.unwrap_or_else(|| {
                        AppError::new(
                            ErrorCode::Unknown,
                            Some("failed queue item had no stored error".into()),
                        )
                    });
                    self.settle_queue_item(&item.id, TerminalOutcome::Failed(error))?;
                }
                _ => {}
            }
        }
        Ok(())
    }

    pub fn get_error_notifications(&self) -> Result<Vec<ErrorNotification>> {
        let mut statement = self
            .connection
            .prepare("SELECT id, title, error FROM error_notifications ORDER BY rowid DESC")?;
        let rows = statement.query_map([], |row| {
            Ok((
                row.get::<_, String>(0)?,
                row.get::<_, Option<String>>(1)?,
                row.get::<_, String>(2)?,
            ))
        })?;
        let mut notifications = Vec::new();
        for row in rows {
            let (id, title, error) = row?;
            notifications.push(ErrorNotification {
                id,
                title,
                error: serde_json::from_str(&error)?,
            });
        }
        Ok(notifications)
    }

    pub fn dismiss_error_notification(&mut self, id: &str) -> Result<bool> {
        let transaction = self.connection.transaction()?;
        let deleted = transaction.execute("DELETE FROM error_notifications WHERE id = ?1", [id])?;
        transaction.commit()?;
        Ok(deleted != 0)
    }

    pub fn settle_queue_item(&mut self, id: &str, outcome: TerminalOutcome) -> Result<()> {
        let transaction = self.connection.transaction()?;
        let stored: Option<(String, Option<String>, String)> = transaction
            .query_row(
                "SELECT request, title, status FROM queue_items WHERE id = ?1",
                [id],
                |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
            )
            .optional()?;
        let (request, title, status) = stored.ok_or(Error::NotFound("queue item"))?;
        match outcome {
            TerminalOutcome::Completed { successful_files }
                if status == "done" && successful_files > 0 =>
            {
                let request: DownloadRequest = serde_json::from_str(&request)?;
                record_in_transaction(&transaction, &request, title.as_deref())?;
            }
            TerminalOutcome::Failed(error) if status == "failed" => {
                transaction.execute(
                    "INSERT INTO error_notifications (id, title, error) VALUES (?1, ?2, ?3)",
                    params![id, title, serde_json::to_string(&error)?],
                )?;
            }
            _ => return Err(Error::InvalidInput("terminal queue status or outcome")),
        }
        transaction.execute("DELETE FROM queue_items WHERE id = ?1", [id])?;
        transaction.commit()?;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{
        contract::{DownloadRequest, ErrorCode, Format, ItemStatus, Progress, Quality, QueueItem},
        persistence::test_path,
    };

    fn item(status: ItemStatus) -> QueueItem {
        QueueItem {
            id: uuid::Uuid::new_v4().to_string(),
            request: DownloadRequest {
                url: "https://example.com/media".into(),
                format: Format::Mp3,
                quality: Quality::Audio { bitrate: 192 },
                is_playlist: false,
            },
            title: Some("Media".into()),
            thumbnail: None,
            status,
            progress: Progress::Single { percent: 100.0 },
            error: None,
        }
    }

    #[test]
    fn reopening_settles_committed_terminal_rows_before_the_ui_reads_them() {
        let path = test_path();
        let mut db = Database::open_at(&path).unwrap();
        let done = item(ItemStatus::Done);
        let failed = item(ItemStatus::Failed);
        db.insert_queue_item(&done).unwrap();
        db.insert_queue_item(&failed).unwrap();
        drop(db);
        let db = Database::open_at(&path).unwrap();
        assert!(db.get_queue().unwrap().is_empty());
        assert_eq!(db.get_history().unwrap().len(), 1);
        assert_eq!(db.get_error_notifications().unwrap()[0].id, failed.id);
        drop(db);
        std::fs::remove_file(path).unwrap();
    }

    #[test]
    fn success_and_partial_success_replace_history_before_queue_removal() {
        let path = test_path();
        let mut db = Database::open_at(&path).unwrap();
        let first = item(ItemStatus::Done);
        db.insert_queue_item(&first).unwrap();
        db.settle_queue_item(
            &first.id,
            TerminalOutcome::Completed {
                successful_files: 1,
            },
        )
        .unwrap();
        let first_history_id = db.get_history().unwrap()[0].id;
        let mut repeated = item(ItemStatus::Done);
        repeated.title = Some("New title".into());
        db.insert_queue_item(&repeated).unwrap();
        db.settle_queue_item(
            &repeated.id,
            TerminalOutcome::Completed {
                successful_files: 1,
            },
        )
        .unwrap();
        let mut partial = item(ItemStatus::Done);
        partial.request.is_playlist = true;
        partial.request.quality = Quality::Max;
        partial.progress = Progress::Playlist {
            done: 2,
            failed: 1,
            total: 3,
            current_title: None,
            current_percent: 100.0,
        };
        db.insert_queue_item(&partial).unwrap();
        db.settle_queue_item(
            &partial.id,
            TerminalOutcome::Completed {
                successful_files: 2,
            },
        )
        .unwrap();
        drop(db);
        let db = Database::open_at(&path).unwrap();
        let history = db.get_history().unwrap();
        assert_eq!(history.len(), 2);
        assert!(history[1].id > first_history_id);
        assert_eq!(history[1].title.as_deref(), Some("New title"));
        assert!(history[0].request.is_playlist);
        assert!(db.get_queue().unwrap().is_empty());
        drop(db);
        std::fs::remove_file(path).unwrap();
    }

    #[test]
    fn all_failed_notification_survives_reopen_until_dismissal() {
        let path = test_path();
        let mut db = Database::open_at(&path).unwrap();
        let failed = item(ItemStatus::Failed);
        let error = AppError::new(ErrorCode::NoInternet, Some("network offline".into()));
        db.insert_queue_item(&failed).unwrap();
        db.settle_queue_item(&failed.id, TerminalOutcome::Failed(error))
            .unwrap();
        drop(db);
        let mut db = Database::open_at(&path).unwrap();
        let notifications = db.get_error_notifications().unwrap();
        assert_eq!(notifications.len(), 1);
        assert_eq!(notifications[0].id, failed.id);
        assert_eq!(notifications[0].error.code, ErrorCode::NoInternet);
        assert!(db.get_history().unwrap().is_empty());
        assert!(db.get_queue().unwrap().is_empty());
        assert!(db.dismiss_error_notification(&failed.id).unwrap());
        assert!(!db.dismiss_error_notification(&failed.id).unwrap());
        drop(db);
        let db = Database::open_at(&path).unwrap();
        assert!(db.get_error_notifications().unwrap().is_empty());
        drop(db);
        std::fs::remove_file(path).unwrap();
    }

    #[test]
    fn failed_write_or_wrong_status_rolls_back_without_removing_queue_item() {
        let path = test_path();
        let mut db = Database::open_at(&path).unwrap();
        let queued = item(ItemStatus::Queued);
        db.insert_queue_item(&queued).unwrap();
        assert!(matches!(
            db.settle_queue_item(
                &queued.id,
                TerminalOutcome::Completed {
                    successful_files: 1
                }
            ),
            Err(Error::InvalidInput(_))
        ));
        let done_without_success = item(ItemStatus::Done);
        db.insert_queue_item(&done_without_success).unwrap();
        assert!(matches!(
            db.settle_queue_item(
                &done_without_success.id,
                TerminalOutcome::Completed {
                    successful_files: 0
                }
            ),
            Err(Error::InvalidInput(_))
        ));
        let failed = item(ItemStatus::Failed);
        db.insert_queue_item(&failed).unwrap();
        db.connection
            .execute(
                "INSERT INTO error_notifications (id, title, error) VALUES (?1, NULL, ?2)",
                params![failed.id, r#"{"code":"unknown","detail":null}"#],
            )
            .unwrap();
        let error = AppError::new(ErrorCode::Unknown, None);
        assert!(matches!(
            db.settle_queue_item(&failed.id, TerminalOutcome::Failed(error)),
            Err(Error::Sql(_))
        ));
        let ids: Vec<_> = db
            .get_queue()
            .unwrap()
            .into_iter()
            .map(|item| item.id)
            .collect();
        assert_eq!(ids, vec![queued.id, done_without_success.id, failed.id]);
        assert!(db.get_history().unwrap().is_empty());
        drop(db);
        std::fs::remove_file(path).unwrap();
    }
}
