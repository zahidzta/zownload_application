// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

use std::{env, fs, path::PathBuf};

fn main() {
    let args = env::args().skip(1).collect::<Vec<_>>();
    assert!(args.contains(&"--no-playlist".to_owned()));
    assert_eq!(args[args.len() - 2], "--");
    if args.contains(&"--dump-single-json".to_owned()) {
        println!("{}", r#"{"id":"local-high","title":"local-high","ext":"mp3","acodec":"mp3","formats":[{"ext":"mp3","acodec":"mp3","vcodec":"none"}]}"#);
        return;
    }
    assert!(args.contains(&"--continue".to_owned()));
    assert!(args.contains(&"--part".to_owned()));
    let position = args.iter().position(|arg| arg == "-o").expect("output option");
    let output = PathBuf::from(args[position + 1].replace("%(ext)s", "mp3"));
    let source = PathBuf::from(env::var_os("ZOWNLOAD_SINGLE_STUB_SOURCE").expect("fixture path"));
    let bytes = fs::copy(source, output).expect("copy fixture into private work folder");
    println!("ZP1|local-high|downloading|{bytes}|{bytes}");
    println!("ZP1|local-high|finished|{bytes}|{bytes}");
}
