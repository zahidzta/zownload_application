// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

//! Unix child supervision. Each engine process gets its own process group so
//! cancellation and window close terminate its complete descendant tree.

use std::{
    collections::HashMap,
    ffi::OsString,
    io::{self, Read},
    os::unix::process::CommandExt,
    path::Path,
    process::{Command, ExitStatus, Stdio},
    sync::{
        atomic::{AtomicBool, AtomicU64, Ordering},
        Arc, Mutex, OnceLock,
    },
    thread,
    time::{Duration, Instant},
};

struct ProcessGroup(i32);

impl ProcessGroup {
    fn terminate(&self) {
        // The negative ID targets only this supervised engine's process group.
        unsafe { libc::kill(-self.0, libc::SIGKILL) };
    }
}

impl Drop for ProcessGroup {
    fn drop(&mut self) {
        self.terminate();
    }
}

#[derive(Debug)]
pub struct Output {
    pub status: ExitStatus,
    pub stdout: Vec<u8>,
    pub stderr: Vec<u8>,
}

#[derive(Debug)]
pub enum RunError {
    Io(io::Error),
    TimedOut,
    Cancelled,
    OutputLimit,
}

impl std::fmt::Display for RunError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Io(error) => write!(f, "{error}"),
            Self::TimedOut => write!(f, "process timed out"),
            Self::Cancelled => write!(f, "process cancelled"),
            Self::OutputLimit => write!(f, "process output exceeded limit"),
        }
    }
}

pub struct Supervisor {
    launch_lock: Mutex<()>,
    active: Mutex<HashMap<u64, Arc<ProcessGroup>>>,
    next_id: AtomicU64,
    closing: AtomicBool,
}

static SUPERVISOR: OnceLock<Mutex<Option<Arc<Supervisor>>>> = OnceLock::new();

impl Supervisor {
    pub fn install() -> io::Result<Arc<Self>> {
        let slot = SUPERVISOR.get_or_init(|| Mutex::new(None));
        let mut guard = slot
            .lock()
            .map_err(|_| io::Error::other("supervisor lock poisoned"))?;
        if let Some(supervisor) = guard.as_ref() {
            return Ok(Arc::clone(supervisor));
        }
        let supervisor = Arc::new(Self {
            launch_lock: Mutex::new(()),
            active: Mutex::new(HashMap::new()),
            next_id: AtomicU64::new(1),
            closing: AtomicBool::new(false),
        });
        *guard = Some(Arc::clone(&supervisor));
        Ok(supervisor)
    }

    pub fn shutdown(&self) {
        self.closing.store(true, Ordering::SeqCst);
        if let Ok(active) = self.active.lock() {
            for group in active.values() {
                group.terminate();
            }
        }
    }

    pub fn run(
        &self,
        executable: &Path,
        args: &[OsString],
        timeout: Duration,
        max_output_bytes: usize,
        cancel: &AtomicBool,
    ) -> Result<Output, RunError> {
        self.run_inner(executable, args, timeout, max_output_bytes, cancel, None)
    }

    /// Streams stdout to a bounded parser while retaining only a diagnostic
    /// tail. The observer must not block; process ownership remains here.
    pub fn run_observed(
        &self,
        executable: &Path,
        args: &[OsString],
        timeout: Duration,
        max_output_bytes: usize,
        cancel: &AtomicBool,
        observer: Arc<dyn Fn(&[u8]) + Send + Sync>,
    ) -> Result<Output, RunError> {
        self.run_inner(
            executable,
            args,
            timeout,
            max_output_bytes,
            cancel,
            Some(observer),
        )
    }

    fn run_inner(
        &self,
        executable: &Path,
        args: &[OsString],
        timeout: Duration,
        max_output_bytes: usize,
        cancel: &AtomicBool,
        observer: Option<Arc<dyn Fn(&[u8]) + Send + Sync>>,
    ) -> Result<Output, RunError> {
        if self.closing.load(Ordering::SeqCst) || cancel.load(Ordering::SeqCst) {
            return Err(RunError::Cancelled);
        }
        let launch_guard = self
            .launch_lock
            .lock()
            .map_err(|_| RunError::Io(io::Error::other("process launch lock poisoned")))?;
        if self.closing.load(Ordering::SeqCst) {
            return Err(RunError::Cancelled);
        }

        let mut command = Command::new(executable);
        command
            .args(args)
            .stdin(Stdio::null())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .process_group(0);
        let mut child = command.spawn().map_err(RunError::Io)?;
        let group = Arc::new(ProcessGroup(child.id() as i32));
        drop(launch_guard);

        let id = self.next_id.fetch_add(1, Ordering::Relaxed);
        {
            let mut active = self.active.lock().map_err(|_| {
                group.terminate();
                let _ = child.wait();
                RunError::Cancelled
            })?;
            if self.closing.load(Ordering::SeqCst) {
                group.terminate();
                let _ = child.wait();
                return Err(RunError::Cancelled);
            }
            active.insert(id, Arc::clone(&group));
        }

        let exceeded = Arc::new(AtomicBool::new(false));
        let stdout = capture(
            child.stdout.take().expect("piped stdout"),
            max_output_bytes,
            Arc::clone(&exceeded),
            observer.clone(),
            observer.is_some(),
        );
        let stderr = capture(
            child.stderr.take().expect("piped stderr"),
            max_output_bytes,
            Arc::clone(&exceeded),
            None,
            observer.is_some(),
        );
        let start = Instant::now();
        let result = loop {
            if self.closing.load(Ordering::SeqCst) || cancel.load(Ordering::SeqCst) {
                break Err(RunError::Cancelled);
            }
            if exceeded.load(Ordering::SeqCst) {
                break Err(RunError::OutputLimit);
            }
            match child.try_wait() {
                Ok(Some(status)) => break Ok(status),
                Ok(None) => {}
                Err(error) => break Err(RunError::Io(error)),
            }
            if start.elapsed() >= timeout {
                break Err(RunError::TimedOut);
            }
            thread::sleep(Duration::from_millis(20));
        };

        // Kill any engine descendants that kept inherited output pipes open.
        group.terminate();
        let _ = child.wait();
        self.active.lock().expect("supervisor lock").remove(&id);
        let stdout = stdout
            .join()
            .map_err(|_| RunError::Io(io::Error::other("stdout reader panicked")))?
            .map_err(RunError::Io)?;
        let stderr = stderr
            .join()
            .map_err(|_| RunError::Io(io::Error::other("stderr reader panicked")))?
            .map_err(RunError::Io)?;
        if exceeded.load(Ordering::SeqCst) {
            return Err(RunError::OutputLimit);
        }
        Ok(Output {
            status: result?,
            stdout,
            stderr,
        })
    }
}

fn capture(
    mut reader: impl Read + Send + 'static,
    limit: usize,
    exceeded: Arc<AtomicBool>,
    observer: Option<Arc<dyn Fn(&[u8]) + Send + Sync>>,
    tail_only: bool,
) -> thread::JoinHandle<io::Result<Vec<u8>>> {
    thread::spawn(move || {
        let mut bytes = Vec::new();
        let mut chunk = [0u8; 8192];
        loop {
            let count = reader.read(&mut chunk)?;
            if count == 0 {
                return Ok(bytes);
            }
            if let Some(observer) = &observer {
                observer(&chunk[..count]);
            }
            if tail_only {
                if count >= limit {
                    bytes.clear();
                    bytes.extend_from_slice(&chunk[count - limit..count]);
                } else {
                    let overflow = bytes.len().saturating_add(count).saturating_sub(limit);
                    bytes.drain(..overflow);
                    bytes.extend_from_slice(&chunk[..count]);
                }
                continue;
            }
            let keep = count.min(limit.saturating_sub(bytes.len()));
            bytes.extend_from_slice(&chunk[..keep]);
            if keep < count {
                exceeded.store(true, Ordering::SeqCst);
            }
        }
    })
}
