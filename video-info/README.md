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
```

The lines always appear in this order: video codec, audio codec, resolution,
video bitrate, audio bitrate, and duration.

## Notes

- Codec names are converted to the names people usually use. For example,
  `AVC` becomes `H.264`, `HEVC` becomes `H.265 (HEVC)`, and MPEG Audio Layer 3
  becomes `MP3`.
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
