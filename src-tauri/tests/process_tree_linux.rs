// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

#![cfg(target_os = "linux")]

use std::{
    ffi::OsString,
    path::Path,
    sync::{
        atomic::{AtomicBool, Ordering},
        Arc,
    },
    thread,
    time::{Duration, Instant},
};
use zownload_lib::engine::process::{RunError, Supervisor};

fn start_sleeping_tree(pid_file: &Path) -> Vec<OsString> {
    let path = pid_file.to_string_lossy().replace('\'', "'\\''");
    vec![
        OsString::from("-c"),
        OsString::from(format!("sleep 60 & echo $! > '{path}'; wait")),
    ]
}

fn wait_for_pid_file(path: &Path) -> i32 {
    let deadline = Instant::now() + Duration::from_secs(3);
    while Instant::now() < deadline {
        if let Ok(value) = std::fs::read_to_string(path) {
            if let Ok(pid) = value.trim().parse() {
                return pid;
            }
        }
        thread::sleep(Duration::from_millis(10));
    }
    panic!("child PID was not written to {}", path.display());
}

fn assert_process_stopped(pid: i32) {
    let deadline = Instant::now() + Duration::from_secs(3);
    while Instant::now() < deadline {
        // Signal zero checks whether the child remains addressable without
        // sending it another signal. A killed orphan may briefly remain as a
        // zombie until the system reaps it, which is already stopped work.
        if unsafe { libc::kill(pid, 0) } != 0 || process_is_reaped_or_zombie(pid) {
            return;
        }
        thread::sleep(Duration::from_millis(20));
    }
    panic!("engine descendant {pid} remained after its process group was stopped");
}

fn process_is_reaped_or_zombie(pid: i32) -> bool {
    let Ok(stat) = std::fs::read_to_string(format!("/proc/{pid}/stat")) else {
        return true;
    };
    stat.rsplit_once(')')
        .and_then(|(_, rest)| rest.split_whitespace().next())
        .is_none_or(|state| state == "Z" || state == "X")
}

#[test]
fn timeout_and_shutdown_stop_the_complete_engine_process_group() {
    let supervisor = Supervisor::install().unwrap();
    let root =
        std::env::temp_dir().join(format!("zownload-linux-process-{}", uuid::Uuid::new_v4()));
    std::fs::create_dir_all(&root).unwrap();

    let timeout_pid_file = root.join("timeout-child.pid");
    let result = supervisor.run(
        Path::new("/bin/sh"),
        &start_sleeping_tree(&timeout_pid_file),
        Duration::from_millis(150),
        4096,
        &AtomicBool::new(false),
    );
    assert!(matches!(result, Err(RunError::TimedOut)));
    assert_process_stopped(wait_for_pid_file(&timeout_pid_file));

    let shutdown_pid_file = root.join("shutdown-child.pid");
    let worker_supervisor = Arc::clone(&supervisor);
    let worker_path = shutdown_pid_file.clone();
    let worker = thread::spawn(move || {
        worker_supervisor.run(
            Path::new("/bin/sh"),
            &start_sleeping_tree(&worker_path),
            Duration::from_secs(30),
            4096,
            &AtomicBool::new(false),
        )
    });
    let child_pid = wait_for_pid_file(&shutdown_pid_file);
    supervisor.shutdown();
    assert!(matches!(worker.join().unwrap(), Err(RunError::Cancelled)));
    assert_process_stopped(child_pid);

    std::fs::remove_dir_all(root).unwrap();
}
