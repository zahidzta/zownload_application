// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

//! Durable, bounded ZIP output for one sequential playlist.
//!
//! The journal is the commit record. An archive append is not committed until
//! it has been flushed, read back (including CRC verification), and journaled.
//! On restart, bytes after the last journaled boundary are discarded.

use serde::{Deserialize, Serialize};
use std::{
    fs::{self, File, OpenOptions},
    io::{self, Seek, SeekFrom, Write},
    path::{Component, Path, PathBuf},
};
use zip::{
    read::ZipArchive,
    write::{SimpleFileOptions, ZipWriter},
    CompressionMethod,
};

const MANIFEST_FILE: &str = "playlist-zip.json";
const JOURNAL_FILE: &str = "playlist-zip.journal";
const MAX_SUFFIX: u32 = 10_000;

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct CommittedEntry {
    pub index: usize,
    pub name: String,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
struct Manifest {
    base_name: String,
    suffix: u32,
    part_suffix: u32,
    part_name: String,
    final_name: String,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
struct JournalRecord {
    archive_len: u64,
    #[serde(default)]
    entry: Option<CommittedEntry>,
}

/// A playlist ZIP whose completed entries survive process interruption.
pub struct ZipOutput {
    output_dir: PathBuf,
    work_dir: PathBuf,
    manifest: Manifest,
    entries: Vec<CommittedEntry>,
    archive_len: u64,
    finalized: Option<PathBuf>,
}

impl ZipOutput {
    /// Opens the queue-owned ZIP staging state, creating it if this is the first run.
    pub fn open(output_dir: &Path, work_dir: &Path, playlist_title: &str) -> io::Result<Self> {
        fs::create_dir_all(output_dir)?;
        fs::create_dir_all(work_dir)?;
        let manifest_path = work_dir.join(MANIFEST_FILE);
        let manifest = if manifest_path.exists() {
            read_manifest(&manifest_path, output_dir)?
        } else {
            let base_name = safe_component(playlist_title);
            let manifest = choose_initial_manifest(output_dir, &base_name)?;
            write_manifest(&manifest_path, &manifest)?;
            manifest
        };

        let mut output = Self {
            output_dir: output_dir.to_path_buf(),
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

    pub fn pending_path(&self) -> PathBuf {
        self.output_dir.join(&self.manifest.part_name)
    }

    /// Adds one finished media file and removes that file only after its ZIP
    /// entry and its recovery record are both durable.
    pub fn append_entry(
        &mut self,
        index: usize,
        title: &str,
        media_path: &Path,
    ) -> io::Result<CommittedEntry> {
        if self.finalized.is_some() {
            return Err(io::Error::new(
                io::ErrorKind::InvalidInput,
                "cannot append to a finalized playlist archive",
            ));
        }
        if let Some(position) = self.entries.iter().position(|entry| entry.index == index) {
            let existing = &self.entries[position];
            if media_path.is_file() {
                let extension = media_extension(media_path)?;
                if unique_entry_name(title, &extension, &self.entries[..position]) != existing.name
                {
                    return Err(io::Error::new(
                        io::ErrorKind::InvalidInput,
                        "committed playlist index does not match the media entry",
                    ));
                }
                fs::remove_file(media_path)?;
            }
            return Ok(existing.clone());
        }
        let extension = media_extension(media_path)?;
        if self
            .entries
            .last()
            .is_some_and(|entry| entry.index >= index)
        {
            return Err(io::Error::new(
                io::ErrorKind::InvalidInput,
                "playlist entries must be committed in order",
            ));
        }
        if !media_path.is_file() {
            return Err(io::Error::new(
                io::ErrorKind::NotFound,
                "completed playlist media file is missing",
            ));
        }

        let name = unique_entry_name(title, &extension, &self.entries);
        let committed = CommittedEntry { index, name };
        let part_path = self.pending_path();
        let file = open_regular_file(&part_path, true)?;
        let mut writer = ZipWriter::new_append(file).map_err(zip_error)?;
        let options = SimpleFileOptions::default().compression_method(CompressionMethod::Stored);
        writer
            .start_file(&committed.name, options)
            .map_err(zip_error)?;
        let mut media = File::open(media_path)?;
        io::copy(&mut media, &mut writer)?;
        let archive = writer.finish().map_err(zip_error)?;
        archive.sync_all()?;

        let mut expected_entries = self.entries.clone();
        expected_entries.push(committed.clone());
        let archive_len =
            verify_archive(&part_path, &expected_entries, expected_entries.len() - 1)?;
        append_journal(
            &self.work_dir.join(JOURNAL_FILE),
            JournalRecord {
                archive_len,
                entry: Some(committed.clone()),
            },
        )?;

        self.entries.push(committed.clone());
        self.archive_len = archive_len;
        fs::remove_file(media_path)?;
        Ok(committed)
    }

    /// Publishes a valid archive with a no-overwrite rename. Returns `None` for
    /// an all-failed playlist so an empty ZIP is never published.
    pub fn finalize(&mut self) -> io::Result<Option<PathBuf>> {
        if let Some(path) = &self.finalized {
            return Ok(Some(path.clone()));
        }
        if self.entries.is_empty() {
            self.remove_incomplete()?;
            return Ok(None);
        }

        let part_path = self.pending_path();
        let mut final_path = self.output_dir.join(&self.manifest.final_name);
        if !part_path.exists() && final_path.exists() {
            verify_archive(&final_path, &self.entries, 0)?;
            self.finalized = Some(final_path.clone());
            return Ok(Some(final_path));
        }
        verify_archive(&part_path, &self.entries, 0)?;

        for suffix in self.manifest.suffix..MAX_SUFFIX {
            if suffix != self.manifest.suffix {
                self.manifest.suffix = suffix;
                self.manifest.final_name = final_name(&self.manifest.base_name, suffix);
                write_manifest(&self.work_dir.join(MANIFEST_FILE), &self.manifest)?;
                final_path = self.output_dir.join(&self.manifest.final_name);
            }
            match rename_no_replace(&part_path, &final_path) {
                Ok(()) => {
                    sync_directory(&self.output_dir)?;
                    if fs::metadata(&final_path)?.len() != self.archive_len {
                        return Err(io::Error::new(
                            io::ErrorKind::InvalidData,
                            "published ZIP size differs from its committed boundary",
                        ));
                    }
                    self.finalized = Some(final_path.clone());
                    return Ok(Some(final_path));
                }
                Err(cause) if cause.kind() == io::ErrorKind::AlreadyExists => continue,
                Err(cause) => {
                    // On filesystems using a hard-link based no-overwrite move,
                    // a crash or unlink error can leave both names for the same
                    // completed bytes. Recognize that state on retry.
                    if final_path.exists() && part_path.exists() {
                        verify_archive(&final_path, &self.entries, 0)?;
                        verify_archive(&part_path, &self.entries, 0)?;
                        fs::remove_file(&part_path)?;
                        sync_directory(&self.output_dir)?;
                        self.finalized = Some(final_path.clone());
                        return Ok(Some(final_path));
                    }
                    return Err(cause);
                }
            }
        }
        Err(io::Error::new(
            io::ErrorKind::AlreadyExists,
            "too many files with the same playlist title",
        ))
    }

    /// Removes this queue item's unpublished ZIP state after cancellation.
    pub fn remove_incomplete(&self) -> io::Result<()> {
        for path in [
            self.pending_path(),
            self.work_dir.join(JOURNAL_FILE),
            self.work_dir.join(MANIFEST_FILE),
        ] {
            match fs::remove_file(path) {
                Ok(()) => {}
                Err(cause) if cause.kind() == io::ErrorKind::NotFound => {}
                Err(cause) => return Err(cause),
            }
        }
        Ok(())
    }

    fn recover(&mut self) -> io::Result<()> {
        let part_path = self.pending_path();
        let final_path = self.output_dir.join(&self.manifest.final_name);
        let journal_path = self.work_dir.join(JOURNAL_FILE);

        if !part_path.exists() && final_path.exists() {
            let (records, _) = read_journal(&journal_path)?;
            self.entries = records
                .iter()
                .filter_map(|record| record.entry.clone())
                .collect();
            if self.entries.is_empty() {
                self.reselect_names(self.manifest.suffix.saturating_add(1))?;
                return self.recover();
            }
            verify_archive(&final_path, &self.entries, 0)?;
            self.finalized = Some(final_path);
            return Ok(());
        }

        if part_path.exists() && final_path.exists() {
            let (records, _) = read_journal(&journal_path)?;
            let entries = records
                .iter()
                .filter_map(|record| record.entry.clone())
                .collect::<Vec<_>>();
            if !entries.is_empty() && verify_archive(&final_path, &entries, 0).is_ok() {
                verify_archive(&part_path, &entries, 0)?;
                fs::remove_file(&part_path)?;
                self.entries = entries;
                self.archive_len = records.last().map_or(0, |record| record.archive_len);
                self.finalized = Some(final_path);
                return Ok(());
            }
        }

        let (records, valid_journal_len) = read_journal(&journal_path)?;
        if !part_path.exists() {
            if records.iter().any(|record| record.entry.is_some()) {
                return Err(io::Error::new(
                    io::ErrorKind::InvalidData,
                    "pending ZIP is missing after a committed entry",
                ));
            }
            match create_empty_archive(&part_path) {
                Ok(()) => {}
                Err(cause) if cause.kind() == io::ErrorKind::AlreadyExists => {
                    self.reselect_names(self.manifest.part_suffix.saturating_add(1))?;
                    return self.recover();
                }
                Err(cause) => return Err(cause),
            }
        }
        let mut part = open_regular_file(&part_path, true)?;
        let Some(initial) = records.first() else {
            part.set_len(0)?;
            part.seek(SeekFrom::Start(0))?;
            let archive = ZipWriter::new(part).finish().map_err(zip_error)?;
            archive.sync_all()?;
            let archive_len = fs::metadata(&part_path)?.len();
            create_journal(&journal_path, archive_len)?;
            self.archive_len = archive_len;
            return Ok(());
        };

        let archive_len = fs::metadata(&part_path)?.len();
        if archive_len < initial.archive_len {
            return Err(io::Error::new(
                io::ErrorKind::InvalidData,
                "pending ZIP is shorter than its durable recovery point",
            ));
        }
        part.set_len(
            records
                .last()
                .expect("initial journal record exists")
                .archive_len,
        )?;
        part.sync_all()?;
        drop(part);
        if valid_journal_len < fs::metadata(&journal_path)?.len() {
            let journal = OpenOptions::new().write(true).open(&journal_path)?;
            journal.set_len(valid_journal_len)?;
            journal.sync_all()?;
        }

        self.entries = records
            .iter()
            .filter_map(|record| record.entry.clone())
            .collect();
        self.archive_len = records
            .last()
            .expect("initial journal record exists")
            .archive_len;
        verify_archive(&part_path, &self.entries, 0)?;
        Ok(())
    }

    fn reselect_names(&mut self, start_suffix: u32) -> io::Result<()> {
        self.manifest =
            choose_manifest_from(&self.output_dir, &self.manifest.base_name, start_suffix)?;
        write_manifest(&self.work_dir.join(MANIFEST_FILE), &self.manifest)
    }
}

fn choose_initial_manifest(output_dir: &Path, base_name: &str) -> io::Result<Manifest> {
    choose_manifest_from(output_dir, base_name, 0)
}

fn choose_manifest_from(output_dir: &Path, base_name: &str, start: u32) -> io::Result<Manifest> {
    for suffix in start..MAX_SUFFIX {
        let part_name = part_name(base_name, suffix);
        let final_name = final_name(base_name, suffix);
        if output_dir.join(&part_name).exists() || output_dir.join(&final_name).exists() {
            continue;
        }
        return Ok(Manifest {
            base_name: base_name.to_owned(),
            suffix,
            part_suffix: suffix,
            part_name,
            final_name,
        });
    }
    Err(io::Error::new(
        io::ErrorKind::AlreadyExists,
        "too many pending playlist archives with the same title",
    ))
}

fn read_manifest(path: &Path, output_dir: &Path) -> io::Result<Manifest> {
    let manifest: Manifest = serde_json::from_slice(&fs::read(path)?).map_err(invalid_data)?;
    if !valid_name(&manifest.base_name)
        || !valid_name(&manifest.part_name)
        || !valid_name(&manifest.final_name)
        || manifest.part_suffix >= MAX_SUFFIX
        || manifest.suffix >= MAX_SUFFIX
        || manifest.part_name != part_name(&manifest.base_name, manifest.part_suffix)
        || manifest.final_name != final_name(&manifest.base_name, manifest.suffix)
    {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            format!("invalid ZIP output manifest for {}", output_dir.display()),
        ));
    }
    Ok(manifest)
}

fn write_manifest(path: &Path, manifest: &Manifest) -> io::Result<()> {
    let temp = path.with_extension(format!("{}.tmp", uuid::Uuid::new_v4()));
    let mut file = OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(&temp)?;
    serde_json::to_writer(&mut file, manifest).map_err(invalid_data)?;
    file.flush()?;
    file.sync_all()?;
    fs::rename(&temp, path)?;
    sync_directory(path.parent().unwrap_or_else(|| Path::new(".")))
}

fn create_empty_archive(path: &Path) -> io::Result<()> {
    let file = OpenOptions::new().write(true).create_new(true).open(path)?;
    let archive = ZipWriter::new(file).finish().map_err(zip_error)?;
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
    serde_json::to_writer(&mut *file, record).map_err(invalid_data)?;
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
        let record: JournalRecord =
            serde_json::from_slice(&line[..line.len() - 1]).map_err(invalid_data)?;
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

fn verify_archive(
    path: &Path,
    expected: &[CommittedEntry],
    verify_content_from: usize,
) -> io::Result<u64> {
    let file = File::open(path)?;
    let archive_len = file.metadata()?.len();
    let mut archive = ZipArchive::new(file).map_err(zip_error)?;
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

fn open_regular_file(path: &Path, read: bool) -> io::Result<File> {
    let metadata = fs::symlink_metadata(path)?;
    if !metadata.file_type().is_file() {
        return Err(io::Error::new(
            io::ErrorKind::PermissionDenied,
            "pending ZIP path is not a regular file",
        ));
    }
    OpenOptions::new().read(read).write(true).open(path)
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
    let extension = path
        .extension()
        .and_then(|value| value.to_str())
        .map(str::to_ascii_lowercase)
        .filter(|value| matches!(value.as_str(), "mp3" | "mp4"))
        .ok_or_else(|| {
            io::Error::new(io::ErrorKind::InvalidInput, "unsupported media extension")
        })?;
    Ok(extension)
}

fn valid_name(value: &str) -> bool {
    let path = Path::new(value);
    path.file_name().and_then(|name| name.to_str()) == Some(value)
        && path
            .components()
            .all(|component| matches!(component, Component::Normal(_)))
}

fn part_name(base: &str, suffix: u32) -> String {
    format!("{}{}.zip.part", base, suffix_text(suffix))
}

fn final_name(base: &str, suffix: u32) -> String {
    format!("{}{}.zip", base, suffix_text(suffix))
}

fn suffix_text(suffix: u32) -> String {
    if suffix == 0 {
        String::new()
    } else {
        format!(" ({suffix})")
    }
}

fn zip_error(error: zip::result::ZipError) -> io::Error {
    match error {
        zip::result::ZipError::Io(error) => error,
        other => io::Error::new(io::ErrorKind::InvalidData, other),
    }
}

fn invalid_data(error: impl std::fmt::Display) -> io::Error {
    io::Error::new(io::ErrorKind::InvalidData, error.to_string())
}

#[cfg(windows)]
fn rename_no_replace(from: &Path, to: &Path) -> io::Result<()> {
    use std::os::windows::ffi::OsStrExt;
    use windows_sys::Win32::Storage::FileSystem::{MoveFileExW, MOVEFILE_WRITE_THROUGH};

    let from = from
        .as_os_str()
        .encode_wide()
        .chain(Some(0))
        .collect::<Vec<_>>();
    let to = to
        .as_os_str()
        .encode_wide()
        .chain(Some(0))
        .collect::<Vec<_>>();
    let result = unsafe { MoveFileExW(from.as_ptr(), to.as_ptr(), MOVEFILE_WRITE_THROUGH) };
    if result == 0 {
        Err(io::Error::last_os_error())
    } else {
        Ok(())
    }
}

#[cfg(not(windows))]
fn rename_no_replace(from: &Path, to: &Path) -> io::Result<()> {
    // A hard link publishes the already-complete bytes atomically and fails if
    // the destination exists. Removing the staging name does not copy the ZIP.
    fs::hard_link(from, to)?;
    fs::remove_file(from)
}

fn sync_directory(path: &Path) -> io::Result<()> {
    #[cfg(unix)]
    File::open(path)?.sync_all()?;
    #[cfg(not(unix))]
    let _ = path;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Read;

    struct TempRoot(PathBuf);

    impl TempRoot {
        fn new() -> Self {
            let id = uuid::Uuid::new_v4();
            let path = std::env::temp_dir().join(format!("zownload-zip-{id}"));
            fs::create_dir_all(&path).unwrap();
            Self(path)
        }

        fn output(&self) -> PathBuf {
            self.0.join("Downloads")
        }

        fn work(&self) -> PathBuf {
            self.0.join("work")
        }

        fn media(&self, name: &str, bytes: &[u8]) -> PathBuf {
            let dir = self.0.join("media");
            fs::create_dir_all(&dir).unwrap();
            let path = dir.join(name);
            fs::write(&path, bytes).unwrap();
            path
        }
    }

    impl Drop for TempRoot {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.0);
        }
    }

    #[test]
    fn stores_entries_uncompressed_and_deletes_each_media_file_after_commit() {
        let root = TempRoot::new();
        let media = root.media("ready.mp3", b"bounded media bytes");
        let mut output = ZipOutput::open(&root.output(), &root.work(), "Set: One").unwrap();
        let entry = output.append_entry(0, "Track / One", &media).unwrap();

        assert_eq!(entry.name, "Track _ One.mp3");
        assert!(!media.exists());
        assert_eq!(output.committed_entries(), &[entry.clone()]);
        let pending = output.pending_path();
        assert!(pending.is_file());
        let mut archive = ZipArchive::new(File::open(&pending).unwrap()).unwrap();
        let mut file = archive.by_name("Track _ One.mp3").unwrap();
        assert_eq!(file.compression(), CompressionMethod::Stored);
        assert_eq!(file.size(), b"bounded media bytes".len() as u64);
        let mut content = Vec::new();
        file.read_to_end(&mut content).unwrap();
        assert_eq!(content, b"bounded media bytes");
        drop(file);
        assert_eq!(fs::read_dir(root.output()).unwrap().count(), 1);
        assert_eq!(fs::read_dir(root.0.join("media")).unwrap().count(), 0);
    }

    #[test]
    fn numbers_duplicate_entry_names_and_never_overwrites_an_existing_archive() {
        let root = TempRoot::new();
        fs::create_dir_all(root.output()).unwrap();
        fs::write(root.output().join("Set.zip"), b"owner file").unwrap();
        let mut output = ZipOutput::open(&root.output(), &root.work(), "Set").unwrap();
        let first = root.media("first.mp4", b"one");
        let second = root.media("second.mp4", b"two");
        let one = output.append_entry(0, "Same", &first).unwrap();
        let two = output.append_entry(1, "Same", &second).unwrap();

        assert_eq!(one.name, "Same.mp4");
        assert_eq!(two.name, "Same (1).mp4");
        let third = root.media("third.mp4", b"three");
        assert_eq!(
            output.append_entry(2, "sAmE", &third).unwrap().name,
            "sAmE (2).mp4"
        );
        let final_path = output.finalize().unwrap().unwrap();
        assert_eq!(final_path.file_name().unwrap(), "Set (1).zip");
        assert_eq!(
            fs::read(root.output().join("Set.zip")).unwrap(),
            b"owner file"
        );
        assert!(!output.pending_path().exists());
    }

    #[test]
    fn a_final_name_created_during_download_is_skipped_at_atomic_publish() {
        let root = TempRoot::new();
        let media = root.media("ready.mp3", b"track");
        let mut output = ZipOutput::open(&root.output(), &root.work(), "Set").unwrap();
        output.append_entry(0, "Track", &media).unwrap();
        fs::write(root.output().join("Set.zip"), b"another process won").unwrap();

        let final_path = output.finalize().unwrap().unwrap();
        assert_eq!(final_path.file_name().unwrap(), "Set (1).zip");
        assert_eq!(
            fs::read(root.output().join("Set.zip")).unwrap(),
            b"another process won"
        );
    }

    #[test]
    fn recovery_discards_an_interrupted_archive_append_and_keeps_last_commit() {
        let root = TempRoot::new();
        let first = root.media("first.mp3", b"first track");
        let mut output = ZipOutput::open(&root.output(), &root.work(), "Set").unwrap();
        output.append_entry(0, "First", &first).unwrap();
        let committed_len = output.archive_len;
        let mut file = OpenOptions::new()
            .append(true)
            .open(output.pending_path())
            .unwrap();
        file.write_all(b"interrupted entry bytes").unwrap();
        file.sync_all().unwrap();
        drop(file);
        drop(output);

        let mut resumed = ZipOutput::open(&root.output(), &root.work(), "ignored title").unwrap();
        assert_eq!(resumed.committed_entries().len(), 1);
        assert_eq!(
            fs::metadata(resumed.pending_path()).unwrap().len(),
            committed_len
        );
        assert_eq!(resumed.append_entry(0, "First", &first).unwrap().index, 0);
        let second = root.media("second.mp3", b"second track");
        resumed.append_entry(1, "Second", &second).unwrap();
        let final_path = resumed.finalize().unwrap().unwrap();
        let archive = ZipArchive::new(File::open(final_path).unwrap()).unwrap();
        assert_eq!(archive.len(), 2);
    }

    #[test]
    fn recovery_after_final_rename_is_idempotent() {
        let root = TempRoot::new();
        let media = root.media("ready.mp4", b"track bytes");
        let mut output = ZipOutput::open(&root.output(), &root.work(), "Set").unwrap();
        output.append_entry(0, "Track", &media).unwrap();
        let final_path = output.finalize().unwrap().unwrap();
        drop(output);

        let mut recovered = ZipOutput::open(&root.output(), &root.work(), "Set").unwrap();
        assert_eq!(recovered.finalize().unwrap(), Some(final_path.clone()));
        assert_eq!(fs::read_dir(root.output()).unwrap().count(), 1);
        let archive = ZipArchive::new(File::open(final_path).unwrap()).unwrap();
        assert_eq!(archive.len(), 1);
    }

    #[test]
    fn all_failed_playlist_removes_pending_archive_without_publishing_an_empty_zip() {
        let root = TempRoot::new();
        let mut output = ZipOutput::open(&root.output(), &root.work(), "Empty").unwrap();
        let pending = output.pending_path();
        assert_eq!(output.finalize().unwrap(), None);
        assert!(!pending.exists());
        assert_eq!(fs::read_dir(root.output()).unwrap().count(), 0);
    }

    #[test]
    fn names_are_safe_for_windows_paths_and_entry_collisions() {
        let root = TempRoot::new();
        let media = root.media("ready.mp3", b"track");
        let mut output = ZipOutput::open(&root.output(), &root.work(), "CON").unwrap();
        let entry = output.append_entry(0, "../CON", &media).unwrap();
        assert_eq!(entry.name, ".._CON.mp3");
        let reserved = root.media("reserved.mp3", b"reserved title");
        assert_eq!(
            output.append_entry(1, "CON", &reserved).unwrap().name,
            "download.mp3"
        );
        assert_eq!(
            output.pending_path().file_name().unwrap(),
            "download.zip.part"
        );
    }

    #[test]
    fn committed_archive_is_bounded_to_zip_and_one_current_media_file() {
        let root = TempRoot::new();
        let first = root.media("first.mp4", &vec![7; 128 * 1024]);
        let mut output = ZipOutput::open(&root.output(), &root.work(), "Large Set").unwrap();
        let original_size = fs::metadata(&first).unwrap().len();
        output.append_entry(0, "First", &first).unwrap();
        assert!(!first.exists());
        let second = root.media("second.mp4", &vec![8; 128 * 1024]);
        assert_eq!(fs::metadata(&second).unwrap().len(), original_size);
        assert_eq!(fs::read_dir(root.output()).unwrap().count(), 1);
        assert_eq!(fs::read_dir(root.0.join("media")).unwrap().count(), 1);
        assert!(fs::metadata(output.pending_path()).unwrap().len() >= original_size);
    }
}
