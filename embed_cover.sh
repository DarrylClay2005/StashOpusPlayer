#!/usr/bin/env bash
set -euo pipefail

# embed_cover.sh - Embed cover art into an audio file using ffmpeg
# Supports: MP3 (ID3v2.3), M4A/MP4, (attempts) Opus/Ogg
# Also supports extracting a frame from a local video if no image is provided.
#
# Usage:
#   embed_cover.sh --audio /path/to/audio.(mp3|m4a|opus) --thumb /path/to/image.(jpg|png|webp) [--in-place]
#   embed_cover.sh --audio /path/to/audio.(mp3|m4a|opus) --video /path/to/video.(mp4|mkv|webm|...) [--at 00:00:01] [--in-place]
#
# Notes:
# - The image will be converted to JPG for best compatibility.
# - For Opus/Ogg, many players have limited cover art support. This script attempts embedding, but results may vary.
# - Requires ffmpeg in PATH or at ~/.local/opt/ffmpeg-yt/bin/ffmpeg

FFMPEG_BIN="${FFMPEG_BIN:-ffmpeg}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_BIN_FFMPEG="$SCRIPT_DIR/bin/ffmpeg"
ALT_BIN="$HOME/.local/opt/ffmpeg-yt/bin/ffmpeg"

# Prefer app-local ffmpeg first, then PATH, then ~/.local copy
if [ -x "$APP_BIN_FFMPEG" ]; then
  FFMPEG_BIN="$APP_BIN_FFMPEG"
elif ! command -v "$FFMPEG_BIN" >/dev/null 2>&1; then
  if [ -x "$ALT_BIN" ]; then
    FFMPEG_BIN="$ALT_BIN"
  else
    echo "Error: ffmpeg not found. Ensure it's installed or set FFMPEG_BIN to its path." >&2
    exit 1
  fi
fi

AUDIO=""
THUMB=""
VIDEO_SRC=""
AT="00:00:01"
IN_PLACE="false"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --audio)
      AUDIO="$2"; shift 2;;
    --thumb)
      THUMB="$2"; shift 2;;
    --video)
      VIDEO_SRC="$2"; shift 2;;
    --at)
      AT="$2"; shift 2;;
    --in-place)
      IN_PLACE="true"; shift;;
    -h|--help)
      sed -n '1,50p' "$0"; exit 0;;
    *)
      echo "Unknown arg: $1" >&2; exit 2;;
  esac
done

if [ -z "$AUDIO" ]; then
  echo "--audio is required" >&2; exit 2
fi
if [ ! -f "$AUDIO" ]; then
  echo "Audio not found: $AUDIO" >&2; exit 2
fi

# If no THUMB and a VIDEO is provided, extract a frame as cover
TMP_DIR=""
CLEANUP() { [ -n "$TMP_DIR" ] && rm -rf "$TMP_DIR" || true; }
trap CLEANUP EXIT

if [ -z "$THUMB" ] && [ -n "$VIDEO_SRC" ]; then
  if [ ! -f "$VIDEO_SRC" ]; then
    echo "Video not found: $VIDEO_SRC" >&2; exit 2
  fi
  TMP_DIR=$(mktemp -d)
  THUMB="$TMP_DIR/cover.jpg"
  "$FFMPEG_BIN" -y -ss "$AT" -i "$VIDEO_SRC" -frames:v 1 -q:v 2 "$THUMB" >/dev/null 2>&1
fi

if [ -z "$THUMB" ]; then
  echo "Provide either --thumb IMAGE or --video VIDEO" >&2; exit 2
fi
if [ ! -f "$THUMB" ]; then
  echo "Thumbnail not found: $THUMB" >&2; exit 2
fi

# Normalize image to JPG for embedding compatibility
IMG_EXT="${THUMB##*.}"; IMG_EXT="${IMG_EXT,,}"
EMBED_IMG="$THUMB"
if [ "$IMG_EXT" != "jpg" ] && [ "$IMG_EXT" != "jpeg" ]; then
  TMP_DIR=${TMP_DIR:-$(mktemp -d)}
  EMBED_IMG="$TMP_DIR/cover.jpg"
  "$FFMPEG_BIN" -y -i "$THUMB" -q:v 2 "$EMBED_IMG" >/dev/null 2>&1
fi

# Prepare output path
ext="${AUDIO##*.}"; ext="${ext,,}"
base="${AUDIO%.*}"
dir="$(dirname "$AUDIO")"
name="$(basename "$base")"
if [ "$IN_PLACE" = "true" ]; then
  OUT="$dir/.${name}.tmp.${ext}"
else
  OUT="$dir/${name}.tagged.${ext}"
fi

# Build ffmpeg args
common=(
  -y -i "$AUDIO" -i "$EMBED_IMG" 
  -map 0:a -map 1:v 
  -c copy 
  -disposition:v attached_pic 
  -metadata:s:v title="Album cover" 
  -metadata:s:v comment="Cover (front)"
)

extra=()
case "$ext" in
  mp3)
    extra=( -id3v2_version 3 )
    ;;
  m4a|mp4)
    # MP4/M4A works with attached pictures
    ;;
  opus|ogg)
    echo "Warning: Embedding cover art in $ext may not be recognized by all players." >&2
    ;;
  flac)
    # FLAC generally fine
    ;;
  *)
    echo "Warning: Unhandled audio type '$ext'. Attempting generic embed." >&2
    ;;
 esac

# Run ffmpeg
set +e
"$FFMPEG_BIN" "${common[@]}" "${extra[@]}" "$OUT"
status=$?
set -e
if [ $status -ne 0 ]; then
  echo "ffmpeg failed to embed cover art. See warnings above." >&2
  exit $status
fi

# If in-place, replace original atomically
if [ "$IN_PLACE" = "true" ]; then
  mv -f "$OUT" "$AUDIO"
  echo "Embedded cover in-place: $AUDIO"
else
  echo "Created: $OUT"
fi
