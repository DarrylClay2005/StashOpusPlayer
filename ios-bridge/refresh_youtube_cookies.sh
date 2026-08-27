#!/usr/bin/env bash
#
# Host-only YouTube cookie refresh.
#
# This script intentionally does not run in the ios-bridge container. Browser
# cookie databases and their keyrings must stay on the host, and the generated
# file is written atomically so a failed refresh never replaces a previously
# working file with an empty/partial one.
set -Eeuo pipefail

umask 077

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
COOKIE_FILE="${YTDLP_COOKIES_FILE:-$SCRIPT_DIR/cookies.txt}"
CACHE_DIR="${YTDLP_CACHE_DIR:-$SCRIPT_DIR/cache/yt-dlp}"
REFRESH_URL="${YTDLP_COOKIE_REFRESH_URL:-https://www.youtube.com/watch?v=BaW_jenozKc}"
YTDLP_BROWSER="${YTDLP_BROWSER:-}"
YTDLP_BIN="${YTDLP_BIN:-$(command -v yt-dlp || true)}"

if [[ -z "$YTDLP_BROWSER" ]]; then
    printf '%s\n' "YTDLP_BROWSER is not configured; refusing to read a browser profile." >&2
    exit 2
fi
if [[ -z "$YTDLP_BIN" || ! -x "$YTDLP_BIN" ]]; then
    printf '%s\n' "yt-dlp is required on the host (set YTDLP_BIN if it is not on PATH)." >&2
    exit 2
fi

COOKIE_DIR="$(dirname -- "$COOKIE_FILE")"
mkdir -p -- "$COOKIE_DIR" "$CACHE_DIR"

# A lock prevents a timer run and a sentinel-triggered run from reading the
# browser database concurrently. The lock contains no cookie data.
exec 9>"$CACHE_DIR/.cookies_refresh.lock"
if ! flock -n 9; then
    exit 0
fi

STAGING_DIR="$COOKIE_DIR/.cookies-refresh.$$"
cleanup() {
    rm -rf -- "$STAGING_DIR"
}
trap cleanup EXIT
if ! mkdir -- "$STAGING_DIR"; then
    printf '%s\n' "Another cookie refresh is already staging a file." >&2
    exit 0
fi

STAGED_COOKIE_FILE="$STAGING_DIR/cookies.txt"
ERROR_FILE="$STAGING_DIR/yt-dlp.stderr"

# yt-dlp performs the browser extraction locally and writes a Netscape cookie
# jar to --cookies. Suppress its output: diagnostics must never include cookie
# values in service logs.
if ! "$YTDLP_BIN" \
    --cookies-from-browser "$YTDLP_BROWSER" \
    --cookies "$STAGED_COOKIE_FILE" \
    --skip-download \
    --no-playlist \
    --no-warnings \
    "$REFRESH_URL" \
    >/dev/null 2>"$ERROR_FILE"; then
    printf '%s\n' "Browser cookie refresh failed; keeping the existing cookie file." >&2
    exit 1
fi

if [[ ! -s "$STAGED_COOKIE_FILE" ]]; then
    printf '%s\n' "Browser cookie refresh produced no cookie file; keeping the existing file." >&2
    exit 1
fi

# Refuse to install an arbitrary or anonymous export. This is deliberately a
# structural check only; cookie contents are never printed or returned.
if ! grep -Eqi '(^|[[:space:]])(#HttpOnly_)?\.?(youtube\.com|www\.youtube\.com)([[:space:]]|$)' "$STAGED_COOKIE_FILE"; then
    printf '%s\n' "Refusing to install a cookie file without YouTube cookies." >&2
    exit 1
fi
if ! grep -Eqi '([[:space:]])(__Secure-)?(SID|HSID|SSID|APISID|SAPISID|LOGIN_INFO)([[:space:]]|$)' "$STAGED_COOKIE_FILE"; then
    printf '%s\n' "Refusing to install a cookie file without a YouTube session cookie." >&2
    exit 1
fi

chmod 600 -- "$STAGED_COOKIE_FILE"
mv -f -- "$STAGED_COOKIE_FILE" "$COOKIE_FILE"
# The bridge only needs the sentinel while a refresh is pending. Remove it
# after the atomic replacement, never before a validated file is installed.
rm -f -- "$CACHE_DIR/.cookies_stale"
printf '%s\n' "YouTube cookies refreshed successfully."
