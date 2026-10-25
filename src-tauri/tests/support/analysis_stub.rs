// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

fn main() {
    let args = std::env::args().skip(1).collect::<Vec<_>>();
    let trace = std::env::var_os("ZOWNLOAD_ANALYSIS_STUB_TRACE").unwrap();
    std::fs::write(trace, args.join("\n")).unwrap();
    print!("{}", include_str!("../fixtures/2b/single.json"));
}
