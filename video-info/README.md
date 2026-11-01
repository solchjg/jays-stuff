# video-info

`codecs.sh` prints a short summary of a video file. It uses
[mediainfo](https://mediaarea.net/en/MediaInfo) to read the file.

## Install

```sh
sudo apt install mediainfo        # Debian/Ubuntu
sudo dnf install mediainfo        # Fedora
chmod +x codecs.sh
```

## Usage

```sh
./codecs.sh movie.mkv        # labelled output
./codecs.sh -p movie.mkv     # values only, one per line
```

Example:

```
Video codec:   H.264
Audio codec:   AAC
Resolution:    1080p (1920x1080)
Video bitrate: 4.0 Mb/s
Audio bitrate: 130 kb/s
Duration:      0:00:05
File size:     2.5 MiB
```

The lines always appear in this order: video codec, audio codec, resolution,
video bitrate, audio bitrate, duration, and file size.

## Output

| Line | Shows | Example |
| ---- | ----- | ------- |
| 1 | Video codec | `H.264`, `H.265 (HEVC)`, `MPEG-4 Part 2 (DivX)` |
| 2 | Audio codec (default track) | `AAC`, `Dolby Digital (AC-3)`, `MP3` |
| 3 | Resolution | `4K (3840x2160)`, `1080p (1920x1080)`, `576i (720x576)` |
| 4 | Video bitrate | `4.0 Mb/s` |
| 5 | Audio bitrate (default track) | `192 kb/s` |
| 6 | Duration (H:MM:SS) | `1:42:07` |
| 7 | File size | `1.4 GiB` |

## How it works

The script runs `mediainfo --Inform` with a template that asks only for the
fields it needs, one line per track with fields separated by `|`. It then
converts those raw values into common names using small helper functions:

- `video_name` and `audio_name` map mediainfo format names to common names.
- `mpeg4_flavour` finds a DivX or Xvid hint for MPEG-4 Part 2 video.
- `resolution_name` turns a width and height into 4K, 1080p, 720p, and so on.
- `bitrate`, `duration` and `filesize` format numbers for people to read.

To add an output line, add a label and a value to the two arrays at the end
of the script. Add new lines at the end so scripts that read `-p` output by
line number keep working.

## Notes

- Codec names are converted to the names people usually use. For example,
  `AVC` becomes `H.264`, `HEVC` becomes `H.265 (HEVC)`, and MPEG Audio Layer 3
  becomes `MP3`.
- MPEG-4 Part 2 video includes a DivX or Xvid hint when the file shows one,
  for example `MPEG-4 Part 2 (DivX)`. The hint comes from the encoder library
  recorded in the stream, or from the AVI FourCC (`DIVX`, `DX50`, `DIV3`, and
  so on, or `XVID`).
- The file size is shown in binary units (KiB, MiB, GiB), like `ls -lh`.
- The resolution is named from both the width and the height, so cropped
  widescreen video (such as 1920x800) is still reported as 1080p. Interlaced
  video is shown as `1080i` or `576i`.
- The audio lines describe the audio track marked as default. If no track is
  marked, they describe the first audio track.
- `none` means the file has no track of that kind. `unknown` means mediainfo
  could not find the value. This happens with bitrates in MKV files that
  were not made with mkvmerge.
- Exit codes: `0` means success, `1` means the file is unreadable or has no
  media tracks, `2` means bad usage, and `3` means mediainfo is missing.
