// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

//! Windows child supervision. The app joins a root Job Object once, so OS
//! process death closes its last handle and kills every inherited descendant.
//! Each command also gets a nested job for timeout, cancel, and window close.

use std::{
    collections::HashMap,
    ffi::OsString,
    io::{self, Read},
    os::windows::io::AsRawHandle,
    path::Path,
    process::{Command, ExitStatus, Stdio},
    sync::{
        atomic::{AtomicBool, AtomicU64, Ordering},
        Arc, Mutex, OnceLock,
    },
    thread,
    time::{Duration, Instant},
};
use windows_sys::Win32::{
    Foundation::{CloseHandle, HANDLE},
    System::{
        JobObjects::{
            AssignProcessToJobObject, CreateJobObjectW, JobObjectExtendedLimitInformation,
            SetInformationJobObject, TerminateJobObject, JOBOBJECT_EXTENDED_LIMIT_INFORMATION,
            JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE,
        },
        Threading::GetCurrentProcess,
    },
};

struct Job(HANDLE);

// Windows handles can be passed between threads; all operations below use OS
// synchronization, and Drop closes exactly one owned handle.
unsafe impl Send for Job {}
unsafe impl Sync for Job {}

impl Job {
    fn new() -> io::Result<Self> {
        let handle = unsafe { CreateJobObjectW(std::ptr::null(), std::ptr::null()) };
        if handle.is_null() {
            return Err(io::Error::last_os_error());
        }
        let job = Self(handle);
        let mut limits = JOBOBJECT_EXTENDED_LIMIT_INFORMATION::default();
        limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
        let ok = unsafe {
            SetInformationJobObject(
                job.0,
                JobObjectExtendedLimitInformation,
                &limits as *const _ as _,
                std::mem::size_of_val(&limits) as u32,
            )
        };
        if ok == 0 {
            return Err(io::Error::last_os_error());
        }
        Ok(job)
    }

    fn assign(&self, process: HANDLE) -> io::Result<()> {
        if unsafe { AssignProcessToJobObject(self.0, process) } == 0 {
            Err(io::Error::last_os_error())
        } else {
            Ok(())
        }
    }

    fn terminate(&self) {
        unsafe { TerminateJobObject(self.0, 1) };
    }
}

impl Drop for Job {
    fn drop(&mut self) {
        unsafe { CloseHandle(self.0) };
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
    // Held until process exit; closing it while this app is still a member
    // would also terminate the app, so window close terminates nested jobs.
    _root: Job,
    active: Mutex<HashMap<u64, Arc<Job>>>,
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
        let root = Job::new()?;
        root.assign(unsafe { GetCurrentProcess() })?;
        let supervisor = Arc::new(Self {
            _root: root,
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
            for job in active.values() {
                job.terminate();
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
        if self.closing.load(Ordering::SeqCst) || cancel.load(Ordering::SeqCst) {
            return Err(RunError::Cancelled);
        }
        let job = Arc::new(Job::new().map_err(RunError::Io)?);
        let mut child = Command::new(executable)
            .args(args)
            .stdin(Stdio::null())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .map_err(RunError::Io)?;
        if let Err(error) = job.assign(child.as_raw_handle() as HANDLE) {
            let _ = child.kill();
            let _ = child.wait();
            return Err(RunError::Io(error));
        }
        let id = self.next_id.fetch_add(1, Ordering::Relaxed);
        {
            let mut active = self.active.lock().map_err(|_| RunError::Cancelled)?;
            if self.closing.load(Ordering::SeqCst) {
                job.terminate();
                let _ = child.wait();
                return Err(RunError::Cancelled);
            }
            active.insert(id, Arc::clone(&job));
        }
        let exceeded = Arc::new(AtomicBool::new(false));
        let stdout = capture(
            child.stdout.take().expect("piped stdout"),
            max_output_bytes,
            Arc::clone(&exceeded),
        );
        let stderr = capture(
            child.stderr.take().expect("piped stderr"),
            max_output_bytes,
            Arc::clone(&exceeded),
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
        // This also closes descendant-held pipe handles before joining readers.
        job.terminate();
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
) -> thread::JoinHandle<io::Result<Vec<u8>>> {
    thread::spawn(move || {
        let mut bytes = Vec::new();
        let mut chunk = [0u8; 8192];
        loop {
            let count = reader.read(&mut chunk)?;
            if count == 0 {
                return Ok(bytes);
            }
            let keep = count.min(limit.saturating_sub(bytes.len()));
            bytes.extend_from_slice(&chunk[..keep]);
            if keep < count {
                exceeded.store(true, Ordering::SeqCst);
            }
        }
    })
}
