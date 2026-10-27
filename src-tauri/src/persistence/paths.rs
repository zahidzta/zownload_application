// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

//! Private filesystem ownership for one queue item. The chosen output folder
//! is captured at enqueue, so changing Settings cannot redirect a resume.

use super::{Database, Error, Result};
use rusqlite::{params, OptionalExtension};
use std::path::{Path, PathBuf};

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct DownloadPaths {
    pub queue_id: String,
    pub output_dir: PathBuf,
    pub work_dir: PathBuf,
    pub reserved_path: Option<PathBuf>,
}

impl DownloadPaths {
    pub fn new(
        queue_id: &str,
        app_data: &Path,
        chosen_dir: Option<&Path>,
        system_downloads: &Path,
    ) -> Result<Self> {
        uuid::Uuid::parse_str(queue_id).map_err(|_| Error::InvalidInput("queue id"))?;
        let output_dir = chosen_dir.unwrap_or(system_downloads);
        if !output_dir.is_absolute() || !app_data.is_absolute() {
            return Err(Error::InvalidInput("download path"));
        }
        Ok(Self {
            queue_id: queue_id.into(),
            output_dir: output_dir.into(),
            work_dir: app_data.join("downloads").join(queue_id),
            reserved_path: None,
        })
    }

    pub fn clear_reserved(&mut self) -> std::io::Result<()> {
        if let Some(path) = &self.reserved_path {
            if path.parent() != Some(self.output_dir.as_path()) {
                return Err(std::io::Error::new(
                    std::io::ErrorKind::PermissionDenied,
                    "reserved file is outside the output directory",
                ));
            }
            if path.exists() {
                std::fs::remove_file(path)?;
            }
        }
        self.reserved_path = None;
        Ok(())
    }

    pub fn clean_owned(&self, app_data: &Path) -> std::io::Result<()> {
        let expected = app_data.join("downloads").join(&self.queue_id);
        if self.work_dir != expected {
            return Err(std::io::Error::new(
                std::io::ErrorKind::PermissionDenied,
                "work directory is not owned by this queue item",
            ));
        }
        let mut owned = self.clone();
        owned.clear_reserved()?;
        if self.work_dir.exists() {
            if std::fs::symlink_metadata(&self.work_dir)?
                .file_type()
                .is_symlink()
            {
                return Err(std::io::Error::new(
                    std::io::ErrorKind::PermissionDenied,
                    "work directory is a symlink",
                ));
            }
            std::fs::remove_dir_all(&self.work_dir)?;
        }
        Ok(())
    }
}

impl Database {
    pub fn get_download_paths(&self, id: &str) -> Result<Option<DownloadPaths>> {
        self.connection
            .query_row(
                "SELECT queue_id, output_dir, work_dir, reserved_path FROM download_paths WHERE queue_id = ?1",
                [id],
                |row| {
                    Ok(DownloadPaths {
                        queue_id: row.get(0)?,
                        output_dir: PathBuf::from(row.get::<_, String>(1)?),
                        work_dir: PathBuf::from(row.get::<_, String>(2)?),
                        reserved_path: row.get::<_, Option<String>>(3)?.map(PathBuf::from),
                    })
                },
            )
            .optional()
            .map_err(Into::into)
    }

    pub fn put_download_paths(&mut self, paths: &DownloadPaths) -> Result<()> {
        self.connection.execute(
            "INSERT INTO download_paths (queue_id, output_dir, work_dir, reserved_path)
             VALUES (?1, ?2, ?3, ?4)
             ON CONFLICT(queue_id) DO UPDATE SET reserved_path = excluded.reserved_path",
            params![
                paths.queue_id,
                paths.output_dir.to_string_lossy(),
                paths.work_dir.to_string_lossy(),
                paths
                    .reserved_path
                    .as_ref()
                    .map(|path| path.to_string_lossy()),
            ],
        )?;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{
        contract::{DownloadRequest, Format, ItemStatus, Progress, Quality, QueueItem},
        persistence::test_path,
    };

    #[test]
    fn captures_folder_and_survives_reopen() {
        let db_path = test_path();
        let id = uuid::Uuid::new_v4().to_string();
        let root = std::env::temp_dir().join(format!("zownload-paths-{id}"));
        let mut db = Database::open_at(&db_path).unwrap();
        db.insert_queue_item(&QueueItem {
            id: id.clone(),
            request: DownloadRequest {
                url: "https://example.com/a".into(),
                format: Format::Mp3,
                quality: Quality::Audio { bitrate: 128 },
                is_playlist: false,
            },
            title: None,
            thumbnail: None,
            status: ItemStatus::Queued,
            progress: Progress::Single { percent: 0.0 },
            error: None,
        })
        .unwrap();
        let paths = DownloadPaths::new(&id, &root, None, &root.join("Downloads")).unwrap();
        db.put_download_paths(&paths).unwrap();
        // A later Settings change must not redirect this already queued job.
        let changed = DownloadPaths::new(
            &id,
            &root,
            Some(&root.join("Elsewhere")),
            &root.join("Downloads"),
        )
        .unwrap();
        db.put_download_paths(&changed).unwrap();
        drop(db);
        let mut db = Database::open_at(&db_path).unwrap();
        assert_eq!(db.get_download_paths(&id).unwrap(), Some(paths.clone()));
        std::fs::create_dir_all(&paths.work_dir).unwrap();
        std::fs::write(paths.work_dir.join("source.mp3.part"), b"partial").unwrap();
        let other = root.join("other.part");
        std::fs::create_dir_all(&root).unwrap();
        std::fs::write(&other, b"not owned").unwrap();
        assert_eq!(
            std::fs::read(paths.work_dir.join("source.mp3.part")).unwrap(),
            b"partial"
        );
        paths.clean_owned(&root).unwrap();
        assert!(!paths.work_dir.exists());
        assert_eq!(std::fs::read(&other).unwrap(), b"not owned");
        db.remove_queue_item(&id).unwrap();
        assert!(db.get_download_paths(&id).unwrap().is_none());
        drop(db);
        std::fs::remove_dir_all(root).unwrap();
        std::fs::remove_file(db_path).unwrap();
    }
}
