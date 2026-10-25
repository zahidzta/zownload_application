// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

use std::{env, fs, process::Command, thread, time::Duration};

fn main() {
    let args: Vec<_> = env::args_os().collect();
    let mode = args[1].to_string_lossy();
    let marker = &args[2];
    if mode == "echo" {
        println!("{}", marker.to_string_lossy());
        return;
    }
    if mode == "flood" {
        println!("{}", "x".repeat(8192));
        loop { thread::sleep(Duration::from_millis(100)); }
    }
    if mode == "parent" || mode == "child" {
        let next = if mode == "parent" { "child" } else { "grandchild" };
        let child = Command::new(&args[0]).arg(next).arg(marker).spawn().unwrap();
        fs::write(format!("{}-{next}.pid", marker.to_string_lossy()), child.id().to_string()).unwrap();
    }
    println!("{mode}:{}", std::process::id());
    loop {
        thread::sleep(Duration::from_millis(100));
    }
}
