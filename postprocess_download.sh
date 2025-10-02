#!/usr/bin/env bash
set -euo pipefail
# postprocess_download.sh — Simple wrapper to embed a thumbnail into audio in-place using app-local ffmpeg
# Usage:
#   postprocess_download.sh --audio /path/to/audio.(mp3|m4a|opus|flac) --thumb /path/to/img.(jpg|png|webp)
#   postprocess_download.sh --audio /path/to/audio.(mp3|m4a|opus|flac) --video /path/to/video.(mp4|mkv|webm) [--at 00:00:01]
#
# Behavior: runs embed_cover.sh with --in-place and prefers bin/ffmpeg next to this script

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
EMBED="$SCRIPT_DIR/embed_cover.sh"
if [ ! -x "$EMBED" ]; then
  echo "embed_cover.sh is missing or not executable at $EMBED" >&2
  exit 1
fi

AUDIO=""; THUMB=""; VIDEO=""; AT="00:00:01"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --audio) AUDIO="$2"; shift 2;;
    --thumb) THUMB="$2"; shift 2;;
    --video) VIDEO="$2"; shift 2;;
    --at) AT="$2"; shift 2;;
    -h|--help) sed -n '1,50p' "$0"; exit 0;;
    *) echo "Unknown arg: $1" >&2; exit 2;;
  esac
done

if [ -z "$AUDIO" ]; then
  echo "--audio is required" >&2; exit 2
fi

if [ -n "$THUMB" ]; then
  FFMPEG_BIN="$SCRIPT_DIR/bin/ffmpeg" "$EMBED" --audio "$AUDIO" --thumb "$THUMB" --in-place
elif [ -n "$VIDEO" ]; then
  FFMPEG_BIN="$SCRIPT_DIR/bin/ffmpeg" "$EMBED" --audio "$AUDIO" --video "$VIDEO" --at "$AT" --in-place
else
  echo "Provide either --thumb or --video" >&2; exit 2
fi

echo "Post-process complete: $AUDIO"
