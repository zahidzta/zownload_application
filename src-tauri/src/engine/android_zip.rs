// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

//! Durable, bounded ZIP output on Android backed by a pending MediaStore
//! Downloads row. Rust owns entry order, naming, CRC verification, and
//! central-directory recovery; Kotlin only creates, opens, publishes, or deletes
//! the MediaStore row.

use crate::{
    android_contract::{PendingZipHandle, PublishedZipResult},
    contract::{AppError, ErrorCode},
};
use serde::{Deserialize, Serialize};
use std::{
    fs::{self, File, OpenOptions},
    io::{self, Read, Seek, SeekFrom, Write},
    path::{Path, PathBuf},
};
use zip::{
    read::ZipArchive,
    write::{SimpleFileOptions, ZipWriter},
    CompressionMethod,
};

const MANIFEST_FILE: &str = "playlist-zip.json";
const JOURNAL_FILE: &str = "playlist-zip.journal";
const RECOVERY_FILE: &str = "playlist-zip.recovery";
const MAX_SUFFIX: u32 = 10_000;

pub(crate) trait PendingArchiveStore: Send + Sync {
    fn create_pending(&self, display_name: &str) -> Result<PendingZipHandle, AppError>;
    fn open_rw(&self, handle: &PendingZipHandle) -> Result<File, AppError>;
    fn publish(
        &self,
        handle: &PendingZipHandle,
        expected_bytes: u64,
    ) -> Result<PublishedZipResult, AppError>;
    fn delete_pending(&self, handle: &PendingZipHandle) -> Result<(), AppError>;
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub(crate) struct CommittedEntry {
    pub index: usize,
    pub name: String,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
struct Manifest {
    uri: String,
    display_name: String,
    base_name: String,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
struct JournalRecord {
    archive_len: u64,
    #[serde(default)]
    entry: Option<CommittedEntry>,
}

/// A pending MediaStore ZIP archive whose committed entries survive crashes.
pub(crate) struct AndroidZipOutput<'a, S: PendingArchiveStore + ?Sized> {
    store: &'a S,
    work_dir: PathBuf,
    manifest: Manifest,
    entries: Vec<CommittedEntry>,
    archive_len: u64,
    finalized: Option<PublishedZipResult>,
}

impl<'a, S: PendingArchiveStore + ?Sized> AndroidZipOutput<'a, S> {
    pub fn open(store: &'a S, work_dir: &Path, playlist_title: &str) -> Result<Self, AppError> {
        fs::create_dir_all(work_dir).map_err(zip_io_error)?;
        let manifest_path = work_dir.join(MANIFEST_FILE);
        let manifest = if manifest_path.exists() {
            read_manifest(&manifest_path)?
        } else {
            let base_name = safe_component(playlist_title);
            let initial_name = format!("{base_name}.zip");
            let pending = store.create_pending(&initial_name)?;
            let manifest = Manifest {
                uri: pending.uri,
                display_name: pending.display_name,
                base_name,
            };
            if let Err(error) = write_manifest(&manifest_path, &manifest) {
                let _ = store.delete_pending(&PendingZipHandle {
                    uri: manifest.uri.clone(),
                    display_name: manifest.display_name.clone(),
                });
                return Err(error);
            }
            manifest
        };

        let mut output = Self {
            store,
            work_dir: work_dir.to_path_buf(),
            manifest,
            entries: Vec::new(),
            archive_len: 0,
            finalized: None,
        };
        output.recover()?;
        Ok(output)
    }

    pub fn committed_entries(&self) -> &[CommittedEntry] {
        &self.entries
    }

    fn handle(&self) -> PendingZipHandle {
        PendingZipHandle {
            uri: self.manifest.uri.clone(),
            display_name: self.manifest.display_name.clone(),
        }
    }

    /// Appends one completed media file uncompressed (`Stored`), verifies it in
    /// the archive, journals the new length, and removes the temporary file.
    pub fn append_entry(
        &mut self,
        index: usize,
        title: &str,
        media_path: &Path,
    ) -> Result<CommittedEntry, AppError> {
        if self.finalized.is_some() {
            return Err(AppError::new(
                ErrorCode::Unknown,
                Some("cannot append to a finalized Android playlist archive".into()),
            ));
        }
        if let Some(position) = self.entries.iter().position(|entry| entry.index == index) {
            let existing = &self.entries[position];
            if media_path.is_file() {
                let extension = media_extension(media_path).map_err(zip_io_error)?;
                if unique_entry_name(title, &extension, &self.entries[..position]) != existing.name
                {
                    return Err(AppError::new(
                        ErrorCode::Unknown,
                        Some("committed playlist index does not match the media entry".into()),
                    ));
                }
                fs::remove_file(media_path).map_err(zip_io_error)?;
            }
            return Ok(existing.clone());
        }
        let extension = media_extension(media_path).map_err(zip_io_error)?;
        if self
            .entries
            .last()
            .is_some_and(|entry| entry.index >= index)
        {
            return Err(AppError::new(
                ErrorCode::Unknown,
                Some("playlist entries must be committed in order".into()),
            ));
        }
        if !media_path.is_file() {
            return Err(AppError::new(
                ErrorCode::EngineMissing,
                Some("completed playlist media file is missing".into()),
            ));
        }

        let name = unique_entry_name(title, &extension, &self.entries);
        let committed = CommittedEntry { index, name };
        let handle = self.handle();

        let mut file = self.store.open_rw(&handle)?;
        backup_central_directory(&mut file, &self.work_dir.join(RECOVERY_FILE))
            .map_err(zip_io_error)?;

        file.seek(SeekFrom::Start(0)).map_err(zip_io_error)?;
        let mut writer = ZipWriter::new_append(file).map_err(zip_to_app_error)?;
        let options = SimpleFileOptions::default().compression_method(CompressionMethod::Stored);
        writer
            .start_file(&committed.name, options)
            .map_err(zip_to_app_error)?;
        let mut media = File::open(media_path).map_err(zip_io_error)?;
        io::copy(&mut media, &mut writer).map_err(zip_io_error)?;
        drop(media);
        let mut file = writer.finish().map_err(zip_to_app_error)?;
        file.sync_all().map_err(zip_io_error)?;

        let mut expected_entries = self.entries.clone();
        expected_entries.push(committed.clone());
        let archive_len =
            verify_archive_file(&mut file, &expected_entries, expected_entries.len() - 1)
                .map_err(zip_io_error)?;
        drop(file);

        append_journal(
            &self.work_dir.join(JOURNAL_FILE),
            JournalRecord {
                archive_len,
                entry: Some(committed.clone()),
            },
        )
        .map_err(zip_io_error)?;

        self.entries.push(committed.clone());
        self.archive_len = archive_len;
        fs::remove_file(media_path).map_err(zip_io_error)?;
        match fs::remove_file(self.work_dir.join(RECOVERY_FILE)) {
            Ok(()) => {}
            Err(error) if error.kind() == io::ErrorKind::NotFound => {}
            Err(error) => return Err(zip_io_error(error)),
        }
        Ok(committed)
    }

    /// Publishes the completed archive in MediaStore. If no entry succeeded,
    /// deletes the pending row instead of publishing an empty ZIP.
    pub fn finalize(&mut self) -> Result<Option<PublishedZipResult>, AppError> {
        if let Some(published) = &self.finalized {
            return Ok(Some(published.clone()));
        }
        if self.entries.is_empty() {
            self.remove_incomplete()?;
            return Ok(None);
        }

        let handle = self.handle();
        let mut file = self.store.open_rw(&handle)?;
        let actual_len = verify_archive_file(&mut file, &self.entries, 0).map_err(zip_io_error)?;
        drop(file);
        if actual_len != self.archive_len {
            return Err(AppError::new(
                ErrorCode::Unknown,
                Some("pending Android ZIP size differs from its committed boundary".into()),
            ));
        }

        let published = self.store.publish(&handle, self.archive_len)?;
        remove_metadata_files(&self.work_dir).map_err(zip_io_error)?;
        self.finalized = Some(published.clone());
        Ok(Some(published))
    }

    /// Removes the pending MediaStore ZIP and its private journal/manifest files.
    pub fn remove_incomplete(&self) -> Result<(), AppError> {
        let mut delete_err = self.store.delete_pending(&self.handle()).err();
        if let Err(error) = remove_metadata_files(&self.work_dir) {
            if delete_err.is_none() {
                delete_err = Some(zip_io_error(error));
            }
        }
        if let Some(error) = delete_err {
            return Err(error);
        }
        Ok(())
    }

    pub fn remove_unrecoverable_pending(store: &S, work_dir: &Path) -> Result<(), AppError> {
        let manifest_path = work_dir.join(MANIFEST_FILE);
        if manifest_path.exists() {
            if let Ok(manifest) = read_manifest(&manifest_path) {
                let _ = store.delete_pending(&PendingZipHandle {
                    uri: manifest.uri,
                    display_name: manifest.display_name,
                });
            }
        }
        remove_metadata_files(work_dir).map_err(zip_io_error)
    }

    fn recover(&mut self) -> Result<(), AppError> {
        let journal_path = self.work_dir.join(JOURNAL_FILE);
        let recovery_path = self.work_dir.join(RECOVERY_FILE);
        let (records, valid_journal_len) = read_journal(&journal_path).map_err(zip_io_error)?;

        let handle = self.handle();
        let mut file = self.store.open_rw(&handle)?;

        let Some(_initial) = records.first() else {
            file.set_len(0).map_err(zip_io_error)?;
            file.seek(SeekFrom::Start(0)).map_err(zip_io_error)?;
            let mut archive = ZipWriter::new(file).finish().map_err(zip_to_app_error)?;
            archive.sync_all().map_err(zip_io_error)?;
            let archive_len = archive.seek(SeekFrom::End(0)).map_err(zip_io_error)?;
            create_journal(&journal_path, archive_len).map_err(zip_io_error)?;
            self.archive_len = archive_len;
            return Ok(());
        };

        let archive_len = file.seek(SeekFrom::End(0)).map_err(zip_io_error)?;
        let committed_len = records
            .last()
            .expect("initial journal record exists")
            .archive_len;
        if archive_len < committed_len {
            return Err(AppError::new(
                ErrorCode::Unknown,
                Some("pending Android ZIP is shorter than its durable recovery point".into()),
            ));
        }
        file.set_len(committed_len).map_err(zip_io_error)?;
        file.sync_all().map_err(zip_io_error)?;
        if valid_journal_len < fs::metadata(&journal_path).map_err(zip_io_error)?.len() {
            let journal = OpenOptions::new()
                .write(true)
                .open(&journal_path)
                .map_err(zip_io_error)?;
            journal.set_len(valid_journal_len).map_err(zip_io_error)?;
            journal.sync_all().map_err(zip_io_error)?;
        }

        self.entries = records
            .iter()
            .filter_map(|record| record.entry.clone())
            .collect();
        self.archive_len = committed_len;
        if let Err(original) = verify_archive_file(&mut file, &self.entries, 0) {
            if !recovery_path.exists() {
                return Err(zip_io_error(original));
            }
            restore_central_directory(&mut file, &recovery_path, committed_len)
                .map_err(zip_io_error)?;
            verify_archive_file(&mut file, &self.entries, 0).map_err(zip_io_error)?;
        }
        if recovery_path.exists() {
            fs::remove_file(recovery_path).map_err(zip_io_error)?;
        }
        Ok(())
    }
}

fn remove_metadata_files(work_dir: &Path) -> io::Result<()> {
    for name in [JOURNAL_FILE, RECOVERY_FILE, MANIFEST_FILE] {
        match fs::remove_file(work_dir.join(name)) {
            Ok(()) => {}
            Err(error) if error.kind() == io::ErrorKind::NotFound => {}
            Err(error) => return Err(error),
        }
    }
    Ok(())
}

fn read_manifest(path: &Path) -> Result<Manifest, AppError> {
    let bytes = fs::read(path).map_err(zip_io_error)?;
    let manifest: Manifest = serde_json::from_slice(&bytes).map_err(invalid_data)?;
    if manifest.uri.trim().is_empty()
        || manifest.display_name.trim().is_empty()
        || manifest.base_name.trim().is_empty()
    {
        return Err(AppError::new(
            ErrorCode::Unknown,
            Some("invalid Android ZIP manifest".into()),
        ));
    }
    Ok(manifest)
}

fn write_manifest(path: &Path, manifest: &Manifest) -> Result<(), AppError> {
    let temp = path.with_extension(format!("{}.tmp", uuid::Uuid::new_v4()));
    let mut file = OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(&temp)
        .map_err(zip_io_error)?;
    serde_json::to_writer(&mut file, manifest).map_err(invalid_data)?;
    file.flush().map_err(zip_io_error)?;
    file.sync_all().map_err(zip_io_error)?;
    fs::rename(&temp, path).map_err(zip_io_error)?;
    Ok(())
}

fn backup_central_directory(file: &mut File, recovery_path: &Path) -> io::Result<()> {
    file.seek(SeekFrom::Start(0))?;
    let archive_len = file.seek(SeekFrom::End(0))?;
    file.seek(SeekFrom::Start(0))?;
    let archive = ZipArchive::new(&mut *file).map_err(zip_error)?;
    let start = archive.central_directory_start();
    drop(archive);
    if start > archive_len {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            "ZIP central directory starts beyond the archive",
        ));
    }
    file.seek(SeekFrom::Start(start))?;
    if recovery_path.exists() {
        fs::remove_file(recovery_path)?;
    }
    let mut recovery = OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(recovery_path)?;
    recovery.write_all(&archive_len.to_le_bytes())?;
    recovery.write_all(&start.to_le_bytes())?;
    if io::copy(file, &mut recovery)? != archive_len - start {
        return Err(io::Error::new(
            io::ErrorKind::UnexpectedEof,
            "ZIP central directory changed during backup",
        ));
    }
    recovery.sync_all()
}

fn restore_central_directory(
    archive: &mut File,
    recovery_path: &Path,
    committed_len: u64,
) -> io::Result<()> {
    let metadata = fs::symlink_metadata(recovery_path)?;
    if !metadata.file_type().is_file() {
        return Err(io::Error::new(
            io::ErrorKind::PermissionDenied,
            "ZIP recovery path is not a regular file",
        ));
    }
    let mut recovery = File::open(recovery_path)?;
    let mut header = [0_u8; 16];
    recovery.read_exact(&mut header)?;
    let saved_len = u64::from_le_bytes(header[..8].try_into().expect("fixed header"));
    let start = u64::from_le_bytes(header[8..].try_into().expect("fixed header"));
    let expected_len = 16_u64.checked_add(saved_len.saturating_sub(start));
    if saved_len != committed_len || start > saved_len || expected_len != Some(metadata.len()) {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            "ZIP recovery directory does not match the committed boundary",
        ));
    }
    archive.seek(SeekFrom::Start(start))?;
    if io::copy(&mut recovery, archive)? != saved_len - start {
        return Err(io::Error::new(
            io::ErrorKind::UnexpectedEof,
            "ZIP recovery directory is incomplete",
        ));
    }
    archive.set_len(saved_len)?;
    archive.sync_all()
}

fn create_journal(path: &Path, archive_len: u64) -> io::Result<()> {
    let record = JournalRecord {
        archive_len,
        entry: None,
    };
    let mut file = OpenOptions::new()
        .write(true)
        .create(true)
        .truncate(true)
        .open(path)?;
    write_record(&mut file, &record)?;
    file.sync_all()
}

fn append_journal(path: &Path, record: JournalRecord) -> io::Result<()> {
    let mut file = OpenOptions::new().append(true).open(path)?;
    write_record(&mut file, &record)?;
    file.sync_all()
}

fn write_record(file: &mut File, record: &JournalRecord) -> io::Result<()> {
    serde_json::to_writer(&mut *file, record)
        .map_err(|error| io::Error::new(io::ErrorKind::InvalidData, error.to_string()))?;
    file.write_all(b"\n")
}

fn read_journal(path: &Path) -> io::Result<(Vec<JournalRecord>, u64)> {
    if !path.exists() {
        return Ok((Vec::new(), 0));
    }
    let bytes = fs::read(path)?;
    let mut records = Vec::new();
    let mut valid_len = 0usize;
    for line in bytes.split_inclusive(|byte| *byte == b'\n') {
        if !line.ends_with(b"\n") {
            break;
        }
        let record: JournalRecord = serde_json::from_slice(&line[..line.len() - 1])
            .map_err(|error| io::Error::new(io::ErrorKind::InvalidData, error.to_string()))?;
        if let Some(previous) = records.last() {
            let previous: &JournalRecord = previous;
            if record.archive_len <= previous.archive_len
                || record.entry.is_none()
                || record.entry.as_ref().is_some_and(|entry| {
                    previous.entry.as_ref().is_some_and(|previous| {
                        entry.index <= previous.index
                            || entry.name.to_lowercase() == previous.name.to_lowercase()
                    })
                })
            {
                return Err(io::Error::new(
                    io::ErrorKind::InvalidData,
                    "playlist ZIP journal is out of order",
                ));
            }
        } else if record.entry.is_some() {
            return Err(io::Error::new(
                io::ErrorKind::InvalidData,
                "playlist ZIP journal has no initial boundary",
            ));
        }
        records.push(record);
        valid_len += line.len();
    }
    Ok((records, valid_len as u64))
}

fn verify_archive_file(
    file: &mut File,
    expected: &[CommittedEntry],
    verify_content_from: usize,
) -> io::Result<u64> {
    let archive_len = file.seek(SeekFrom::End(0))?;
    file.seek(SeekFrom::Start(0))?;
    let mut archive = ZipArchive::new(&mut *file).map_err(zip_error)?;
    if archive.len() != expected.len() {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            "pending ZIP entry count does not match its journal",
        ));
    }
    for (index, expected_entry) in expected.iter().enumerate() {
        let mut entry = archive.by_index(index).map_err(zip_error)?;
        if entry.name().map_err(zip_error)?.as_ref() != expected_entry.name
            || entry.compression() != CompressionMethod::Stored
        {
            return Err(io::Error::new(
                io::ErrorKind::InvalidData,
                "pending ZIP metadata does not match its journal",
            ));
        }
        if index >= verify_content_from {
            io::copy(&mut entry, &mut io::sink())?;
        }
    }
    Ok(archive_len)
}

fn safe_component(value: &str) -> String {
    let clean = value
        .chars()
        .map(|ch| {
            if ch < ' ' || "<>:\"/\\|?*".contains(ch) {
                '_'
            } else {
                ch
            }
        })
        .take(120)
        .collect::<String>()
        .trim()
        .trim_end_matches(['.', ' '])
        .to_owned();
    let stem = clean.split('.').next().unwrap_or("").to_ascii_uppercase();
    if clean.is_empty()
        || matches!(
            stem.as_str(),
            "CON"
                | "PRN"
                | "AUX"
                | "NUL"
                | "COM1"
                | "COM2"
                | "COM3"
                | "COM4"
                | "COM5"
                | "COM6"
                | "COM7"
                | "COM8"
                | "COM9"
                | "LPT1"
                | "LPT2"
                | "LPT3"
                | "LPT4"
                | "LPT5"
                | "LPT6"
                | "LPT7"
                | "LPT8"
                | "LPT9"
        )
    {
        "download".into()
    } else {
        clean
    }
}

fn unique_entry_name(title: &str, extension: &str, existing: &[CommittedEntry]) -> String {
    let base = safe_component(title);
    for suffix in 0..MAX_SUFFIX {
        let name = if suffix == 0 {
            format!("{base}.{extension}")
        } else {
            format!("{base} ({suffix}).{extension}")
        };
        if !existing
            .iter()
            .any(|entry| entry.name.to_lowercase() == name.to_lowercase())
        {
            return name;
        }
    }
    format!("{base} ({}).{extension}", MAX_SUFFIX)
}

fn media_extension(path: &Path) -> io::Result<String> {
    path.extension()
        .and_then(|value| value.to_str())
        .map(str::to_ascii_lowercase)
        .filter(|value| matches!(value.as_str(), "mp3" | "mp4"))
        .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidInput, "unsupported media extension"))
}

pub(crate) fn zip_io_error(error: io::Error) -> AppError {
    let code = match error.kind() {
        io::ErrorKind::StorageFull => ErrorCode::DiskFull,
        io::ErrorKind::PermissionDenied => ErrorCode::PermissionDenied,
        _ => match error.raw_os_error() {
            Some(28 | 112 | 39) => ErrorCode::DiskFull,
            Some(1 | 5 | 13 | 30) => ErrorCode::PermissionDenied,
            _ => {
                let text = error.to_string().to_ascii_lowercase();
                if text.contains("no space") || text.contains("disk full") {
                    ErrorCode::DiskFull
                } else {
                    ErrorCode::Unknown
                }
            }
        },
    };
    AppError::new(code, Some(error.to_string()))
}

fn zip_error(error: zip::result::ZipError) -> io::Error {
    match error {
        zip::result::ZipError::Io(error) => error,
        other => io::Error::new(io::ErrorKind::InvalidData, other),
    }
}

fn zip_to_app_error(error: zip::result::ZipError) -> AppError {
    zip_io_error(zip_error(error))
}

fn invalid_data(error: impl std::fmt::Display) -> AppError {
    AppError::new(ErrorCode::Unknown, Some(error.to_string()))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Mutex;

    struct MockPendingArchiveStore {
        root: PathBuf,
        existing_downloads: Mutex<Vec<String>>,
        fail_open_with: Mutex<Option<ErrorCode>>,
        published: Mutex<Vec<PublishedZipResult>>,
        deleted: Mutex<Vec<String>>,
    }

    impl MockPendingArchiveStore {
        fn new(root: PathBuf) -> Self {
            fs::create_dir_all(&root).unwrap();
            Self {
                root,
                existing_downloads: Mutex::new(Vec::new()),
                fail_open_with: Mutex::new(None),
                published: Mutex::new(Vec::new()),
                deleted: Mutex::new(Vec::new()),
            }
        }

        fn pending_file_path(&self, handle: &PendingZipHandle) -> PathBuf {
            let id = handle
                .uri
                .strip_prefix("content://mock/downloads/")
                .unwrap();
            self.root.join(format!("pending-{id}.zip"))
        }
    }

    impl PendingArchiveStore for MockPendingArchiveStore {
        fn create_pending(&self, display_name: &str) -> Result<PendingZipHandle, AppError> {
            let mut existing = self.existing_downloads.lock().unwrap();
            let chosen = if !existing.contains(&display_name.to_string()) {
                display_name.to_string()
            } else {
                let stem = display_name.strip_suffix(".zip").unwrap_or(display_name);
                let mut suffix = 1;
                loop {
                    let candidate = format!("{stem} ({suffix}).zip");
                    if !existing.contains(&candidate) {
                        break candidate;
                    }
                    suffix += 1;
                }
            };
            existing.push(chosen.clone());
            let id = uuid::Uuid::new_v4().to_string();
            let handle = PendingZipHandle {
                uri: format!("content://mock/downloads/{id}"),
                display_name: chosen,
            };
            File::create(self.pending_file_path(&handle)).unwrap();
            Ok(handle)
        }

        fn open_rw(&self, handle: &PendingZipHandle) -> Result<File, AppError> {
            if let Some(code) = self.fail_open_with.lock().unwrap().take() {
                return Err(AppError::new(code, Some("injected storage error".into())));
            }
            OpenOptions::new()
                .read(true)
                .write(true)
                .open(self.pending_file_path(handle))
                .map_err(zip_io_error)
        }

        fn publish(
            &self,
            handle: &PendingZipHandle,
            expected_bytes: u64,
        ) -> Result<PublishedZipResult, AppError> {
            let actual = fs::metadata(self.pending_file_path(handle))
                .map_err(zip_io_error)?
                .len();
            assert_eq!(actual, expected_bytes);
            let result = PublishedZipResult {
                uri: handle.uri.clone(),
                display_name: handle.display_name.clone(),
                bytes: actual,
            };
            self.published.lock().unwrap().push(result.clone());
            Ok(result)
        }

        fn delete_pending(&self, handle: &PendingZipHandle) -> Result<(), AppError> {
            self.deleted.lock().unwrap().push(handle.uri.clone());
            let path = self.pending_file_path(handle);
            if path.exists() {
                fs::remove_file(path).map_err(zip_io_error)?;
            }
            Ok(())
        }
    }

    fn temp_root() -> PathBuf {
        std::env::temp_dir().join(format!("zownload-android-zip-{}", uuid::Uuid::new_v4()))
    }

    #[test]
    fn appends_stored_entries_resolves_collisions_and_deletes_sources_before_next() {
        let root = temp_root();
        let store = MockPendingArchiveStore::new(root.join("downloads"));
        let work = root.join("work");
        let media1 = root.join("entry1.mp3");
        let media2 = root.join("entry2.mp3");
        fs::write(&media1, b"first-audio-bytes").unwrap();
        fs::write(&media2, b"second-audio-bytes").unwrap();

        let mut zip = AndroidZipOutput::open(&store, &work, "My Mix").unwrap();
        let first = zip.append_entry(0, "Track", &media1).unwrap();
        assert_eq!(first.name, "Track.mp3");
        assert!(!media1.exists(), "work file must be removed immediately");

        let second = zip.append_entry(1, "track", &media2).unwrap();
        assert_eq!(second.name, "track (1).mp3");
        assert!(!media2.exists(), "work file must be removed immediately");

        let published = zip.finalize().unwrap().unwrap();
        assert_eq!(published.display_name, "My Mix.zip");

        let handle = PendingZipHandle {
            uri: published.uri.clone(),
            display_name: published.display_name.clone(),
        };
        let file = File::open(store.pending_file_path(&handle)).unwrap();
        let mut archive = ZipArchive::new(file).unwrap();
        assert_eq!(archive.len(), 2);
        {
            let mut e0 = archive.by_index(0).unwrap();
            assert_eq!(e0.name().unwrap(), "Track.mp3");
            assert_eq!(e0.compression(), CompressionMethod::Stored);
            let mut buf = Vec::new();
            e0.read_to_end(&mut buf).unwrap();
            assert_eq!(buf, b"first-audio-bytes");
        }
        {
            let mut e1 = archive.by_index(1).unwrap();
            assert_eq!(e1.name().unwrap(), "track (1).mp3");
            assert_eq!(e1.compression(), CompressionMethod::Stored);
            let mut buf = Vec::new();
            e1.read_to_end(&mut buf).unwrap();
            assert_eq!(buf, b"second-audio-bytes");
        }
        drop(archive);
        let _ = fs::remove_dir_all(root);
    }

    #[test]
    fn resume_recovers_central_directory_after_interrupted_append() {
        let root = temp_root();
        let store = MockPendingArchiveStore::new(root.join("downloads"));
        store
            .existing_downloads
            .lock()
            .unwrap()
            .push("Mix.zip".into());
        let work = root.join("work");
        let media1 = root.join("one.mp3");
        let media2 = root.join("two.mp3");
        fs::write(&media1, b"entry-one-payload").unwrap();
        fs::write(&media2, b"entry-two-payload").unwrap();

        let mut zip = AndroidZipOutput::open(&store, &work, "Mix").unwrap();
        assert_eq!(zip.manifest.display_name, "Mix (1).zip");
        zip.append_entry(0, "One", &media1).unwrap();
        let handle = zip.handle();
        let committed_len = zip.archive_len;
        drop(zip);

        // Simulate a mid-append crash: central directory backup exists and
        // trailing garbage was written to the pending MediaStore ZIP.
        let mut file = store.open_rw(&handle).unwrap();
        backup_central_directory(&mut file, &work.join(RECOVERY_FILE)).unwrap();
        file.seek(SeekFrom::End(-4)).unwrap();
        file.write_all(b"CORRUPT_TAIL_EXTRA_BYTES").unwrap();
        file.sync_all().unwrap();
        drop(file);

        let mut reopened = AndroidZipOutput::open(&store, &work, "Mix").unwrap();
        assert_eq!(reopened.committed_entries().len(), 1);
        assert_eq!(reopened.archive_len, committed_len);
        reopened.append_entry(1, "Two", &media2).unwrap();
        let published = reopened.finalize().unwrap().unwrap();
        assert_eq!(published.display_name, "Mix (1).zip");

        let file = File::open(store.pending_file_path(&handle)).unwrap();
        let archive = ZipArchive::new(file).unwrap();
        assert_eq!(archive.len(), 2);
        drop(archive);
        let _ = fs::remove_dir_all(root);
    }

    #[test]
    fn all_failed_or_aborted_zip_deletes_pending_row_without_publishing() {
        let root = temp_root();
        let store = MockPendingArchiveStore::new(root.join("downloads"));
        let work = root.join("work");

        let mut zip = AndroidZipOutput::open(&store, &work, "Empty").unwrap();
        assert!(zip.finalize().unwrap().is_none());
        assert!(store.published.lock().unwrap().is_empty());
        assert_eq!(store.deleted.lock().unwrap().len(), 1);
        assert!(!work.join(MANIFEST_FILE).exists());

        // Disk-full error maps cleanly and remove_incomplete cleans up.
        *store.fail_open_with.lock().unwrap() = Some(ErrorCode::DiskFull);
        let err = match AndroidZipOutput::open(&store, &work, "Fail") {
            Ok(_) => panic!("expected disk_full error"),
            Err(error) => error,
        };
        assert_eq!(err.code, ErrorCode::DiskFull);
        AndroidZipOutput::remove_unrecoverable_pending(&store, &work).unwrap();
        assert_eq!(store.deleted.lock().unwrap().len(), 2);
        let _ = fs::remove_dir_all(root);
    }
}
