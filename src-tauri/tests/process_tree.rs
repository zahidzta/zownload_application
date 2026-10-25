// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

#![cfg(target_os = "windows")]

use std::{
    ffi::OsString,
    fs, io,
    path::{Path, PathBuf},
    process::Command,
    sync::{
        atomic::{AtomicBool, Ordering},
        Arc,
    },
    thread,
    time::{Duration, Instant},
};
use windows_sys::Win32::{
    Foundation::{CloseHandle, WAIT_OBJECT_0},
    System::Threading::{OpenProcess, WaitForSingleObject, PROCESS_QUERY_LIMITED_INFORMATION},
};
use zownload_lib::engine::process::{RunError, Supervisor};

fn stub() -> PathBuf {
    let binary = std::env::current_exe()
        .unwrap()
        .parent()
        .unwrap()
        .join("tree_stub.exe");
    let source = Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/support/tree_stub.rs");
    let status = Command::new("rustc")
        .arg(source)
        .arg("-o")
        .arg(&binary)
        .status()
        .unwrap();
    assert!(status.success());
    binary
}

fn marker(root: &Path, label: &str) -> PathBuf {
    root.join(label)
}

fn pids(path: &Path) -> Vec<u32> {
    ["child", "grandchild"]
        .iter()
        .map(|name| {
            fs::read_to_string(format!("{}-{name}.pid", path.display()))
                .unwrap()
                .parse()
                .unwrap()
        })
        .collect()
}

fn wait_for_tree(path: &Path) -> Vec<u32> {
    let start = Instant::now();
    loop {
        if ["child", "grandchild"]
            .iter()
            .all(|name| PathBuf::from(format!("{}-{name}.pid", path.display())).exists())
        {
            return pids(path);
        }
        assert!(
            start.elapsed() < Duration::from_secs(5),
            "stub did not spawn descendants"
        );
        thread::sleep(Duration::from_millis(20));
    }
}

fn alive(pid: u32) -> bool {
    const SYNCHRONIZE: u32 = 0x0010_0000;
    let handle = unsafe { OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION | SYNCHRONIZE, 0, pid) };
    if handle.is_null() {
        return false;
    }
    let alive = unsafe { WaitForSingleObject(handle, 0) != WAIT_OBJECT_0 };
    unsafe { CloseHandle(handle) };
    alive
}

fn assert_gone(ids: &[u32]) {
    let start = Instant::now();
    while ids.iter().any(|id| alive(*id)) && start.elapsed() < Duration::from_secs(5) {
        thread::sleep(Duration::from_millis(20));
    }
    assert!(
        ids.iter().all(|id| !alive(*id)),
        "descendant survived: {ids:?}"
    );
}

#[test]
fn windows_supervisor_cleans_timeout_cancel_close_and_parent_exit() {
    let root = std::env::temp_dir().join(format!("zownload-tree-{}", uuid::Uuid::new_v4()));
    fs::create_dir(&root).unwrap();
    let binary = stub();
    let supervisor = Supervisor::install().unwrap();

    let arg = OsString::from("literal & | > spaces");
    let output = supervisor
        .run(
            &binary,
            &[OsString::from("echo"), arg.clone()],
            Duration::from_secs(2),
            4096,
            &AtomicBool::new(false),
        )
        .unwrap();
    assert!(output.status.success());
    assert_eq!(
        String::from_utf8(output.stdout).unwrap().trim(),
        arg.to_string_lossy()
    );
    let overflow = supervisor.run(
        &binary,
        &[OsString::from("flood"), OsString::from("unused")],
        Duration::from_secs(2),
        64,
        &AtomicBool::new(false),
    );
    assert!(matches!(overflow, Err(RunError::OutputLimit)));

    let time_marker = marker(&root, "timeout");
    let result = supervisor.run(
        &binary,
        &[OsString::from("parent"), time_marker.as_os_str().into()],
        Duration::from_secs(2),
        4096,
        &AtomicBool::new(false),
    );
    assert!(matches!(result, Err(RunError::TimedOut)));
    assert_gone(&wait_for_tree(&time_marker));

    let cancel_marker = marker(&root, "cancel");
    let cancel = Arc::new(AtomicBool::new(false));
    let signal = Arc::clone(&cancel);
    let work = thread::spawn(move || {
        supervisor.run(
            &binary,
            &[OsString::from("parent"), cancel_marker.as_os_str().into()],
            Duration::from_secs(10),
            4096,
            &signal,
        )
    });
    let ids = wait_for_tree(&marker(&root, "cancel"));
    cancel.store(true, Ordering::SeqCst);
    assert!(matches!(work.join().unwrap(), Err(RunError::Cancelled)));
    assert_gone(&ids);

    for mode in ["close", "abrupt"] {
        let path = marker(&root, mode);
        let status = Command::new(std::env::current_exe().unwrap())
            .args(["--ignored", "--exact", "supervisor_helper"])
            .env("ZOWNLOAD_TREE_MODE", mode)
            .env("ZOWNLOAD_TREE_MARKER", &path)
            .status()
            .unwrap();
        assert!(status.success());
        assert_gone(&wait_for_tree(&path));
    }
    fs::remove_dir_all(root).unwrap();
}

#[test]
#[ignore]
fn supervisor_helper() -> io::Result<()> {
    let mode = std::env::var("ZOWNLOAD_TREE_MODE").unwrap();
    let marker = PathBuf::from(std::env::var_os("ZOWNLOAD_TREE_MARKER").unwrap());
    let binary = std::env::current_exe()?
        .parent()
        .unwrap()
        .join("tree_stub.exe");
    let supervisor = Supervisor::install()?;
    let runner = Arc::clone(&supervisor);
    let args = vec![OsString::from("parent"), marker.as_os_str().into()];
    thread::spawn(move || {
        runner.run(
            &binary,
            &args,
            Duration::from_secs(30),
            4096,
            &AtomicBool::new(false),
        )
    });
    let ids = wait_for_tree(&marker);
    assert!(ids.iter().all(|id| alive(*id)));
    if mode == "close" {
        supervisor.shutdown();
        assert_gone(&ids);
    } else {
        // Simulate abrupt process exit: the root job's last handle closes.
        std::process::exit(0);
    }
    Ok(())
}
