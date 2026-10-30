// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

//! Deterministic yt-dlp stand-in for the Windows queue integration test.
use std::{env, fs::{self, OpenOptions}, io::{self, Write}, path::PathBuf, thread, time::Duration};

fn main() {
    let args: Vec<String> = env::args().skip(1).collect();
    if args.first().map(String::as_str) == Some("-nostdin") {
        // The MP4 finishing pass copies streams and updates tags. The queue
        // lifecycle test only needs its output file, so copy the stub media.
        let input = &args[args.iter().position(|arg| arg == "-i").unwrap() + 1];
        fs::copy(input, args.last().unwrap()).unwrap();
        return;
    }
    if args.contains(&"--flat-playlist".into()) {
        assert_eq!(args[args.len() - 2], "--");
        println!("{{\"_type\":\"playlist\",\"title\":\"Playlist\",\"entries\":[{{\"title\":\"First\",\"webpage_url\":\"https://example.com/entry/first\"}},{{\"title\":\"Second\",\"webpage_url\":\"https://example.com/entry/second\"}}]}}");
        return;
    }
    assert!(args.contains(&"--no-playlist".into()));
    let url = args.last().unwrap();
    let id = url.rsplit('/').next().unwrap();
    if args.contains(&"--dump-single-json".into()) {
        println!("{{\"id\":\"{id}\",\"title\":\"{id}\",\"ext\":\"mp4\",\"formats\":[{{\"ext\":\"mp4\",\"height\":240,\"vcodec\":\"h264\"}}]}}");
        return;
    }
    if id == "fail" {
        eprintln!("ERROR: simulated source failure");
        std::process::exit(4);
    }
    let output = PathBuf::from(&args[args.iter().position(|arg| arg == "-o").unwrap() + 1].replace("%(ext)s", "mp4"));
    let partial = output.with_extension("mp4.part");
    let offset = partial.metadata().map(|file| file.len()).unwrap_or(0);
    if offset == 0 {
        fs::write(&partial, b"1234567890").unwrap();
        println!("ZP1|{id}|downloading|10|20");
        io::stdout().flush().unwrap();
        thread::sleep(Duration::from_millis(700));
    } else {
        assert_eq!(offset, 10, "resume must see the saved byte offset");
    }
    OpenOptions::new().append(true).open(&partial).unwrap().write_all(b"abcdefghij").unwrap();
    println!("ZP1|{id}|finished|20|20");
    println!("ZP2|Metadata|started");
    io::stdout().flush().unwrap();
    fs::rename(partial, output).unwrap();
}
