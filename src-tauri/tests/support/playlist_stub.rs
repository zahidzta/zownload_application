// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

use std::{env, fs, io::Write, path::PathBuf};

fn main() {
    let args = env::args().skip(1).collect::<Vec<_>>();
    assert!(args.iter().any(|arg| arg == "--no-playlist"));
    assert_eq!(args[args.len() - 2], "--");
    let url = args.last().unwrap();
    assert!(url.starts_with("https://example.com/entry/"));
    let id = url.rsplit('/').next().unwrap();
    if args.iter().any(|arg| arg == "--dump-single-json") {
        println!("{{\"id\":\"{id}\",\"title\":\"Track\",\"artist\":\"Artist\",\"ext\":\"wav\"}}");
        return;
    }
    let format = args.iter().position(|arg| arg == "-f").map(|index| args[index + 1].as_str()).unwrap();
    let (extension, source) = if format == "ba/b" {
        ("wav", env::var_os("ZOWNLOAD_PLAYLIST_STUB_AUDIO").unwrap())
    } else {
        ("mp4", env::var_os("ZOWNLOAD_PLAYLIST_STUB_VIDEO").unwrap())
    };
    let target = args.iter().position(|arg| arg == "-o").map(|index| &args[index + 1]).unwrap();
    let target = PathBuf::from(target.replace("%(ext)s", extension));
    let bytes = fs::copy(source, target).unwrap();
    let mut trace = fs::OpenOptions::new().create(true).append(true)
        .open(env::var_os("ZOWNLOAD_PLAYLIST_STUB_TRACE").unwrap()).unwrap();
    writeln!(trace, "{id}|{format}").unwrap();
    println!("ZP1|{id}|downloading|{bytes}|{bytes}");
    println!("ZP1|{id}|finished|{bytes}|{bytes}");
}
