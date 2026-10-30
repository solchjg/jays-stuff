#!/usr/bin/env bash
#
# codecs.sh - summarise a video file's codecs, resolution, bitrates and length.
#
# Uses mediainfo (https://mediaarea.net/en/MediaInfo) as the backend: the
# script only asks mediainfo for raw fields and turns them into the names
# people normally use ("H.264" rather than "AVC", "1080p" rather than
# "1920x1080", and so on).
#
# Usage:
#   codecs.sh [-p] FILE
#
# Options:
#   -p   Plain output: print only the values, without the "Label:" prefixes.
#        Handy when another script reads the output line by line.
#   -h   Show usage.
#
# Output, one item per line, always in this order:
#   1. Video codec      e.g. H.264, H.265 (HEVC), VP9, AV1, MPEG-2
#   2. Audio codec      e.g. AAC, Dolby Digital (AC-3), MP3, Opus
#   3. Resolution       e.g. 4K (3840x2160), 1080p (1920x1080), 576i (720x576)
#   4. Video bitrate    e.g. 4.0 Mb/s
#   5. Audio bitrate    e.g. 192 kb/s
#   6. Duration         H:MM:SS, e.g. 1:42:07
#
# Only the first video track is reported. For audio, the track flagged as
# "default" is reported, or the first audio track if none is flagged.
#
# A value of "none" means the file has no track of that kind; "unknown" means
# the track exists but mediainfo could not determine the value (common for
# bitrates in MKV files that were not written by mkvmerge).
#
# Exit codes:
#   0  success
#   1  file missing/unreadable, or it has no audio or video tracks
#   2  bad command-line usage
#   3  mediainfo is not installed
#
# Requires: bash 4+, mediainfo, awk.

set -euo pipefail

usage() {
    echo "Usage: ${0##*/} [-p] FILE" >&2
    exit 2
}

# ----------------------------------------------------------------------------
# Command-line parsing
# ----------------------------------------------------------------------------

plain=0
while getopts ":ph" opt; do
    case $opt in
        p) plain=1 ;;
        *) usage ;;     # -h and any unknown option
    esac
done
shift $((OPTIND - 1))
[[ $# -eq 1 ]] || usage
file=$1

command -v mediainfo >/dev/null || { echo "error: mediainfo is not installed" >&2; exit 3; }
[[ -f $file && -r $file ]] || { echo "error: cannot read '$file'" >&2; exit 1; }

# mi TEMPLATE
# Run mediainfo with an --Inform template, which prints only the fields we
# name. A template looks like "Section;%Field1%|%Field2%\n": the section is
# General, Video or Audio, and the template is repeated for every track in
# that section. We separate fields with "|" and end each track with a newline
# so every track becomes one line that `read` can split.
mi() {
    mediainfo --Inform="$1" -- "$file"
}

# ----------------------------------------------------------------------------
# Gather raw fields from mediainfo
# ----------------------------------------------------------------------------

# First video track only (head -n1). Format_Version tells MPEG-1 from MPEG-2;
# ScanType tells progressive from interlaced. BitRate_Nominal is the
# encoder's target bitrate, used when the measured BitRate is missing.
# `|| true` keeps `set -e` from aborting when there is no video track.
IFS='|' read -r v_fmt v_ver v_width v_height v_scan v_br v_br_nom \
    < <(mi 'Video;%Format%|%Format_Version%|%Width%|%Height%|%ScanType%|%BitRate%|%BitRate_Nominal%\n' | head -n1) || true

# Whole-file values: duration in milliseconds and the overall bitrate.
IFS='|' read -r g_dur g_br < <(mi 'General;%Duration%|%OverallBitRate%\n') || true

# Every audio track, one line each, so we can choose the default one later.
# Format_Profile distinguishes MP2 from MP3; Format_Commercial_IfAny gives
# marketing names such as "Dolby TrueHD" or "DTS-HD MA". Default is Yes/No.
mapfile -t audio < <(mi 'Audio;%Format%|%Format_Profile%|%Format_Commercial_IfAny%|%BitRate%|%BitRate_Nominal%|%Default%\n' | sed '/^$/d')

if [[ -z ${v_fmt:-} && ${#audio[@]} -eq 0 ]]; then
    echo "error: '$file' has no audio or video tracks mediainfo recognises" >&2
    exit 1
fi

# ----------------------------------------------------------------------------
# Helpers that turn raw mediainfo values into common names
# ----------------------------------------------------------------------------

# video_name FORMAT FORMAT_VERSION
# Map mediainfo's video format name to the name most people know it by.
video_name() {
    case $1 in
        AVC)             echo "H.264" ;;
        HEVC)            echo "H.265 (HEVC)" ;;
        VVC)             echo "H.266 (VVC)" ;;
        "MPEG Video")    # mediainfo reports both MPEG-1 and MPEG-2 this way
                         case $2 in *1*) echo "MPEG-1" ;; *) echo "MPEG-2" ;; esac ;;
        "MPEG-4 Visual") echo "MPEG-4 Part 2" ;;   # Xvid / DivX
        *)               echo "$1" ;;              # VP8, VP9, AV1, ProRes, ... are already common names
    esac
}

# audio_name FORMAT FORMAT_PROFILE COMMERCIAL_NAME
# Map mediainfo's audio format name to the name most people know it by.
audio_name() {
    case $1 in
        "MPEG Audio")   # MP2 and MP3 share a format name; the profile is the layer
                        case $2 in "Layer 3") echo "MP3" ;; "Layer 2") echo "MP2" ;; *) echo "MPEG Audio" ;; esac ;;
        AC-3)           echo "Dolby Digital (AC-3)" ;;
        E-AC-3)         echo "Dolby Digital Plus (E-AC-3)" ;;
        "MLP FA")       echo "${3:-Dolby TrueHD}" ;;   # TrueHD; the commercial name may add "with Atmos"
        DTS)            echo "${3:-DTS}" ;;            # prefer "DTS-HD Master Audio" etc. when given
        *)              echo "$1" ;;                   # AAC, Opus, FLAC, Vorbis, PCM, ...
    esac
}

# resolution_name WIDTH HEIGHT SCAN_TYPE
# Give the common resolution name plus the exact size, e.g. "1080p (1920x1080)".
# Width is checked as well as height so letterboxed or cropped widescreen
# video (e.g. 1920x800 or 3840x1600) still gets the name people expect.
# Interlaced video gets an "i" instead of "p" (1080i, 576i).
resolution_name() {
    local w=${1:-0} h=${2:-0} label
    if   (( w >= 7000 || h >= 4320 )); then label="8K"
    elif (( w >= 3200 || h >= 2160 )); then label="4K"
    elif (( w >= 2400 || h >= 1440 )); then label="1440p"
    elif (( w >= 1800 || h >= 1080 )); then label="1080p"
    elif (( w >= 1200 || h >= 720  )); then label="720p"
    elif (( h >= 576 ));                then label="576p"    # PAL SD
    elif (( w >= 640 || h >= 480 ));    then label="480p"    # NTSC SD
    elif (( h > 0 ));                   then label="${h}p"   # anything smaller: just use the height
    else echo "unknown"; return
    fi
    if [[ $3 == Interlaced || $3 == MBAFF ]]; then
        label=${label%p}i    # "4K" and "8K" have no trailing p, so they stay as they are
    fi
    echo "$label (${w}x${h})"
}

# bitrate BITS_PER_SECOND
# Format a bitrate as "x.x Mb/s" (1 Mb/s and above) or "x kb/s". mediainfo
# sometimes returns decimals, so anything after a "." is dropped first.
bitrate() {
    local bps=${1%%.*}
    [[ $bps =~ ^[0-9]+$ ]] || { echo "unknown"; return; }
    if (( bps >= 1000000 )); then
        awk -v b="$bps" 'BEGIN { printf "%.1f Mb/s\n", b / 1000000 }'
    else
        echo "$(( (bps + 500) / 1000 )) kb/s"    # +500 rounds to the nearest kb/s
    fi
}

# duration MILLISECONDS
# Format a duration as H:MM:SS, rounded to the nearest second.
duration() {
    local ms=${1%%.*}
    [[ $ms =~ ^[0-9]+$ ]] || { echo "unknown"; return; }
    local s=$(( (ms + 500) / 1000 ))
    printf '%d:%02d:%02d\n' $(( s / 3600 )) $(( s % 3600 / 60 )) $(( s % 60 ))
}

# ----------------------------------------------------------------------------
# Choose the audio track to report
# ----------------------------------------------------------------------------

# Use the first track whose Default field (the last field) is "Yes";
# fall back to the first audio track if no track is flagged.
a_line=""
for t in "${audio[@]}"; do
    if [[ ${t##*|} == Yes ]]; then
        a_line=$t
        break
    fi
done
if [[ -z $a_line && ${#audio[@]} -gt 0 ]]; then
    a_line=${audio[0]}
fi
IFS='|' read -r a_fmt a_prof a_comm a_br a_br_nom a_def <<< "$a_line"

# ----------------------------------------------------------------------------
# Build the output values
# ----------------------------------------------------------------------------

if [[ -n ${v_fmt:-} ]]; then
    out_vcodec=$(video_name "$v_fmt" "$v_ver")
    out_res=$(resolution_name "$v_width" "$v_height" "$v_scan")

    # Prefer the measured bitrate, then the encoder's nominal bitrate.
    vb=${v_br:-$v_br_nom}

    # Some containers (notably MKV made by tools other than mkvmerge) store no
    # per-track bitrate at all. In that case estimate the video bitrate as the
    # file's overall bitrate minus every audio track's bitrate, but only when
    # all of the audio bitrates are known; otherwise the estimate would be
    # misleading and we report "unknown" instead.
    if [[ -z $vb && -n ${g_br:-} ]]; then
        est=$g_br
        ok=1
        for t in "${audio[@]}"; do
            IFS='|' read -r _ _ _ b bn _ <<< "$t"
            b=${b:-$bn}
            if [[ ! $b =~ ^[0-9]+ ]]; then
                ok=0
                break
            fi
            est=$(( ${est%%.*} - ${b%%.*} ))
        done
        if (( ok && est > 0 )); then
            out_vbr="$(bitrate "$est") (estimated)"
        fi
    fi
    out_vbr=${out_vbr:-$(bitrate "$vb")}
else
    out_vcodec=none
    out_res=none
    out_vbr=none
fi

if [[ -n $a_line ]]; then
    out_acodec=$(audio_name "$a_fmt" "$a_prof" "$a_comm")
    out_abr=$(bitrate "${a_br:-$a_br_nom}")
else
    out_acodec=none
    out_abr=none
fi

out_dur=$(duration "${g_dur:-}")

# ----------------------------------------------------------------------------
# Print
# ----------------------------------------------------------------------------

labels=("Video codec" "Audio codec" "Resolution" "Video bitrate" "Audio bitrate" "Duration")
values=("$out_vcodec" "$out_acodec" "$out_res" "$out_vbr" "$out_abr" "$out_dur")
for i in "${!values[@]}"; do
    if (( plain )); then
        echo "${values[i]}"
    else
        printf '%-14s %s\n' "${labels[i]}:" "${values[i]}"
    fi
done
