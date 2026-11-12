# Windows v0.0.2 engine hash regression

The installed Windows v0.0.2 package contained engine resources whose hashes
did not match the fixed FFmpeg and QuickJS values compiled into the app:

| Resource | Compiled value before the fix | Installed v0.0.2 value |
|---|---|---|
| `yt-dlp.exe` | `66674953fe251b89f4d08c5f0e35e0728679bd67ab3d7d05c0562af101dd3e7a` | `66674953fe251b89f4d08c5f0e35e0728679bd67ab3d7d05c0562af101dd3e7a` |
| `ffmpeg.exe` | `fa050630ddf5b7c3303d8dab5e5a42e7023547fb78ec9b90b5be0a4f788a7e66` | `9bff33e5d9f3de4f54f30aa623e8969bab946715231146e7c18d17785e7a640d` |
| `qjs.exe` | `bec67f8f87fa22958d3ab8be5508088116b8bff90032323d82c94545e1698b83` | `209926180fd5ac23827b72bc7f9a29534d7c10cbb26ec8a5917e858c0f808851` |

The app-data engine still had the previous `0.0.1` baseline manifest. On the
`0.0.2` startup refresh, bootstrap rejected the newly installed FFmpeg and
QuickJS files before activating the refreshed engine, so URL analysis reported
`engine_missing`.

Windows builds now embed hashes computed from the exact staged FFmpeg and
QuickJS resources. Release builds require both files to be staged first, and
the runtime continues checking copied engine files against those embedded
hashes. This accommodates the documented FFmpeg build timestamp variation.

`cargo check --lib --locked` passed with the CI resource override, with one
existing `restore_baseline` dead-code warning. `cargo fmt --check` and
`git diff --check` passed. No Windows installer rebuild or native runtime test
was run; a new Windows build and release are required to deliver the repair.
