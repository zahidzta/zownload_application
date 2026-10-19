# Gate 0B real test fixtures

Checked on **2026-10-18**. These are input fixtures and expected observations, not CLI results. Run `powershell -NoProfile -File scripts/gate-0b/verify-fixtures.ps1` immediately before each dependent CLI task. It checks public metadata and playlist membership without downloading media or invoking yt-dlp. A failed preflight marks the fixture unavailable; record that separately from a CLI failure. Replace a disappeared fixture only through a separate fixture task under the gate stop rule.

## Locked URLs and observations

| Name | URL and intended cases | Expected observation and permission basis |
|---|---|---|
| `youtube-short` | `https://www.youtube.com/watch?v=uW13KuRrg1g`; 0B-13 single analysis and QuickJS/ejs | YouTube oEmbed reports `10號風...` by `vgocyl`. Wikimedia Commons independently [reviewed this upload's CC BY 3.0 status](https://commons.wikimedia.org/wiki/File:10%E8%99%9F%E9%A2%A8....webm), names the original YouTube ID and reports a 15-second VP8/Vorbis copy. Use this YouTube URL for analysis; the Commons copy is a rights/codec reference, not a substitute for the JS-runtime probe. |
| `blender-playlist` | `https://www.youtube.com/playlist?list=PL6B3937A5D230E335`; 0B-13 pure playlist/benchmark and 0B-16 video playlist | YouTube's public playlist page reports **Official Blender Open Movies** and contains `u9lj-c29dxI` (Wing It!) and `UXqq0ZvbOnk` (Charge). For video conversion, process only the two locked entries by ID; check their current playlist positions before constructing `--playlist-items` values. [Blender Studio says Wing It! is CC BY 4.0](https://studio.blender.org/projects/wing-it/pages/licensing/) and [states its published films are generally CC BY](https://studio.blender.org/remixing/). Attribution: Blender Foundation / Blender Studio. No claim is made that every other playlist entry has been rights-checked. |
| `blender-mixed` | `https://www.youtube.com/watch?v=u9lj-c29dxI&list=PL6B3937A5D230E335`; 0B-13 mixed video-plus-playlist | The video ID is in the above playlist; with `--no-playlist`, expect one video result, not the whole playlist (D-28). The playlist can change, so membership is rechecked. |
| `archive-audio-playlist` | `https://archive.org/details/PureDataSoundEffects`; 0B-14/15 MP3 presets and playlist, 0B-18 album/creator/cover | Internet Archive metadata names Andy Farnell and states CC BY 3.0; [item metadata](https://archive.org/metadata/PureDataSoundEffects) and [embed playlist](https://archive.org/embed/PureDataSoundEffects) expose 39 tracks. The bounded fixture is exactly `effect-acid.mp3`, `effect-alarm-siren.mp3`, and `effect-alarmclock.mp3` (currently entries 2–4; about 11, 9.5, and 8 seconds). Each embed entry points to a PNG artwork file, making JPEG conversion observable. Use `--playlist-items` for those three only, and process all three in a playlist test. Expect MP3 sources, a playlist title and creator; actual mapped fields and embedded JPEG cover remain 0B-18 checks. Attribution: Andy Farnell and the [CC BY 3.0 license](https://creativecommons.org/licenses/by/3.0/). The Archive item is a backup copy of his Pure Data sound effects; its license is asserted by the item metadata. |
| `archive-video` | `https://archive.org/details/Justin_Cone_-_Building_On_The_Past_-_640x480`; 0B-16 bounded-height single, 0B-17 non-AAC source, 0B-18 thumbnail, 0B-19 resume/progress | The [Creative Commons project page](https://creativecommons.org/about/videos/building-on-the-past/) names Justin Cone, grants CC BY and links this Archive item. [Archive metadata](https://archive.org/metadata/Justin_Cone_-_Building_On_The_Past_-_640x480) exposes a 120-second Ogg video derivative (~8 MB), a 240-line MP4 derivative and JPEG thumbnails. Ogg is the non-AAC candidate; 0B-17 must inspect its actual audio codec before claiming AAC conversion. Throttle the transfer for 0B-19 so interruption leaves a `.part` file. Attribution: Justin Cone, *Building on the Past*, CC BY, with a link to the Creative Commons project page. |
| `archive-short-video` | `https://archive.org/details/2026-02-16-public-short-video`; 0B-16 short MP4 single and 0B-18 thumbnail | [Archive metadata](https://archive.org/metadata/2026-02-16-public-short-video) identifies a 9.74-second 640×360 original MP4, generated JPEG thumbnails, and an uploader CC0 declaration. No creator field is present, so this fixture cannot prove artist fallback. |
| `missing-archive-item` | `https://archive.org/details/zownload-fixture-intentionally-missing-0b02`; 0B-20 unavailable | The Archive metadata endpoint returns `{}` rather than a named item. Recheck that it remains absent before expecting an unavailable-content error. No media is involved. |
| `restricted-archive-item` | `https://archive.org/details/lp_the-music-of-russia_various-artists-a-askaryan-alexander-melik`; 0B-20 access restricted | [Archive metadata](https://archive.org/metadata/lp_the-music-of-russia_various-artists-a-askaryan-alexander-melik) marks `disc1/01.01. Bells Of Rostov.mp3` as `private: true`. Probe only metadata/extraction failure; do not attempt to download or bypass access controls. |
| `invalid-input` | `not-a-url`; 0B-20 invalid URL | A deliberately malformed, local input. No permission or availability check is needed. |

YouTube access and format selection can vary by location, rate limits and site policy. A public page, CC content license, and successful preflight do not prove that yt-dlp extraction or media transfer will succeed. The later CLI tasks must record the exact result. Media made for these tests stays in ignored `work/engine/` and must not be committed or redistributed.

## Capability map

| Gate probe | Fixtures |
|---|---|
| Single, pure playlist, mixed URL, YouTube JS runtime and playlist timing | `youtube-short`, `blender-playlist`, `blender-mixed` |
| MP3 320/256/192/128 output, playlist Max/Min | `archive-audio-playlist` (one entry for singles; all three bounded entries for playlist) |
| MP4 Max/Min playlist and bounded-height single | `blender-playlist` (two checked entries), `archive-video`, `archive-short-video` |
| Non-AAC to AAC in MP4 | `archive-video` Ogg candidate, after ffprobe confirms source codec |
| Title, creator/uploader fallback, playlist album, thumbnail-to-JPEG cover | `archive-audio-playlist`, `archive-video`, `archive-short-video` |
| Interrupted transfer, `.part` resume, parseable progress | `archive-video` with a low `--limit-rate` during the interruption phase |
| Unavailable, invalid, access restricted and executable startup failures | `missing-archive-item`, `invalid-input`, `restricted-archive-item`; executable failure uses the pinned local binary path rather than an external URL |

## Machine-readable preflight lock

The JSON below supplies the verifier's IDs and expected metadata. Changing its URLs, membership, or rights assertions is fixture maintenance, not a way to make a failed CLI probe pass.

```json fixture-lock
{
  "schema": 1,
  "checkedOn": "2026-10-18",
  "youtubeShort": {
    "url": "https://www.youtube.com/watch?v=uW13KuRrg1g",
    "id": "uW13KuRrg1g",
    "title": "10號風...",
    "author": "vgocyl"
  },
  "blenderPlaylist": {
    "url": "https://www.youtube.com/playlist?list=PL6B3937A5D230E335",
    "id": "PL6B3937A5D230E335",
    "title": "Official Blender Open Movies",
    "videoIds": ["u9lj-c29dxI", "UXqq0ZvbOnk"],
    "mixedUrl": "https://www.youtube.com/watch?v=u9lj-c29dxI&list=PL6B3937A5D230E335"
  },
  "archiveAudio": {
    "url": "https://archive.org/details/PureDataSoundEffects",
    "id": "PureDataSoundEffects",
    "license": "creativecommons.org/licenses/by/3.0/",
    "creator": "Andy Farnell",
    "entries": ["effect-acid.mp3", "effect-alarm-siren.mp3", "effect-alarmclock.mp3"],
    "thumbnailExt": "png"
  },
  "archiveVideo": {
    "url": "https://archive.org/details/Justin_Cone_-_Building_On_The_Past_-_640x480",
    "id": "Justin_Cone_-_Building_On_The_Past_-_640x480",
    "license": "creativecommons.org/licenses/by/3.0/",
    "creator": "Justin Cone",
    "files": ["Justin_Cone_-_Building_On_The_Past_-_640x480.ogv", "Justin_Cone_-_Building_On_The_Past_-_640x480_512kb.mp4"]
  },
  "archiveShortVideo": {
    "url": "https://archive.org/details/2026-02-16-public-short-video",
    "id": "2026-02-16-public-short-video",
    "license": "creativecommons.org/publicdomain/zero/1.0/",
    "files": ["test.mp4", "2026-02-16-public-short-video.thumbs/test_000005.jpg"]
  },
  "missingArchiveId": "zownload-fixture-intentionally-missing-0b02",
  "restrictedArchive": {
    "url": "https://archive.org/details/lp_the-music-of-russia_various-artists-a-askaryan-alexander-melik",
    "id": "lp_the-music-of-russia_various-artists-a-askaryan-alexander-melik",
    "privateFile": "disc1/01.01. Bells Of Rostov.mp3"
  },
  "invalidInput": "not-a-url"
}
```
