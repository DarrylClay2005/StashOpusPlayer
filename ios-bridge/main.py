import array
import asyncio
import hashlib
import io
import ipaddress
import json
import logging
import os
import pathlib
import re
import secrets
import shutil
import string
import tempfile
import time
import urllib.request
import uuid
import zipfile
from collections import defaultdict
from contextlib import asynccontextmanager
from datetime import datetime, timedelta, timezone
from typing import Optional
from urllib.parse import urlsplit

from fastapi import Depends, FastAPI, File, HTTPException, Query, Request, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, StreamingResponse
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from pydantic import BaseModel

import yt_dlp

from auth import (
    create_token,
    decode_token,
    hash_password_async,
    verify_password_async,
)
from db import _pool as _db_pool_ref, get_pool, init_db

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s  %(levelname)-8s  %(name)s  %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
logger = logging.getLogger("ios-bridge")

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

YTDLP_CACHE_DIR: str = os.getenv("YTDLP_CACHE_DIR", "/app/.cache/yt-dlp")
YTDLP_COOKIES_FILE: str = os.getenv("YTDLP_COOKIES_FILE", "/app/cookies.txt")
API_KEY: str = os.getenv("IOS_BRIDGE_API_KEY", "")
SERVER_MUSIC_DIR: str = os.getenv("SERVER_MUSIC_DIR", "")
# Per-user music directory. Each user gets {USER_MUSIC_DIR}/{user_id}/.
# Falls back to {SERVER_MUSIC_DIR}/users/ if SERVER_MUSIC_DIR is set.
USER_MUSIC_DIR: str = os.getenv("USER_MUSIC_DIR", "")
SUPPORTED_AUDIO_EXTS: frozenset[str] = frozenset({
    ".mp3", ".m4a", ".aac", ".wav", ".aif", ".aiff",
    ".flac", ".opus", ".ogg", ".caf", ".mp4", ".m4v",
})
# Optional: a YouTube Data API v3 key (https://console.cloud.google.com, enable
# "YouTube Data API v3"). When set, /api/resolve uses playlistItems.list to
# enumerate YouTube playlists, which paginates via nextPageToken with no
# practical limit — unlike yt-dlp's flat-playlist scrape of the playlist page,
# which YouTube caps at ~205 entries regardless of cookies/session (the
# richGridRenderer/lockupViewModel grid UI's continuation simply stops being
# returned by YouTube's browse API after ~2 pages).
YOUTUBE_API_KEY: str = os.getenv("YOUTUBE_API_KEY", "")
VERSION = "1.0.0"

# ---------------------------------------------------------------------------
# ffprobe result cache
# ---------------------------------------------------------------------------

class _FfprobeCache:
    """
    Disk-backed cache for ffprobe results, keyed by ``path|mtime|size``.
    Thread-safe for concurrent async callers via an asyncio Lock on flush.
    """

    def __init__(self, cache_path: str) -> None:
        self._path = cache_path
        self._flush_lock = asyncio.Lock()
        self._data: dict = {}
        self._dirty: bool = False
        self._load()

    def _load(self) -> None:
        try:
            with open(self._path) as fh:
                self._data = json.load(fh)
            logger.info("ffprobe cache loaded: %d entries from %s", len(self._data), self._path)
        except (FileNotFoundError, json.JSONDecodeError, OSError):
            self._data = {}

    def _file_key(self, abs_path: str) -> str | None:
        try:
            st = os.stat(abs_path)
            return f"{abs_path}|{st.st_mtime}|{st.st_size}"
        except OSError:
            return None

    def get(self, abs_path: str) -> dict | None:
        key = self._file_key(abs_path)
        return self._data.get(key) if key else None

    def put(self, abs_path: str, tags: dict) -> None:
        key = self._file_key(abs_path)
        if key:
            self._data[key] = tags
            self._dirty = True

    async def flush(self) -> None:
        """Persist to disk if dirty. Safe to call after every scan batch."""
        if not self._dirty:
            return
        async with self._flush_lock:
            if not self._dirty:
                return
            try:
                tmp = self._path + ".tmp"
                with open(tmp, "w") as fh:
                    json.dump(self._data, fh)
                os.replace(tmp, self._path)
                self._dirty = False
            except OSError as exc:
                logger.warning("ffprobe cache flush failed: %s", exc)

    def evict_missing(self) -> None:
        """Prune entries whose source file no longer exists."""
        before = len(self._data)
        self._data = {
            k: v for k, v in self._data.items()
            if os.path.exists(k.split("|")[0])
        }
        removed = before - len(self._data)
        if removed:
            self._dirty = True
            logger.info("ffprobe cache: evicted %d stale entries", removed)


_ffprobe_cache_path: str = (
    os.path.join(SERVER_MUSIC_DIR, ".lumisound_ffprobe_cache.json")
    if SERVER_MUSIC_DIR
    else os.path.join(tempfile.gettempdir(), "lumisound_ffprobe_cache.json")
)
_FFPROBE_CACHE = _FfprobeCache(_ffprobe_cache_path)


# ---------------------------------------------------------------------------
# yt-dlp concurrency limit (Fix 3)
# ---------------------------------------------------------------------------

_YTDLP_SEMAPHORE = asyncio.Semaphore(10)  # max 10 concurrent yt-dlp processes — matches the iOS client's "Download All" pipeline width

# ---------------------------------------------------------------------------
# Rate limiter for auth endpoints (Fix 2)
# ---------------------------------------------------------------------------

_auth_attempts: dict[str, list[float]] = defaultdict(list)
_AUTH_RATE_LIMIT = 10   # max attempts per window
_AUTH_WINDOW = 60       # seconds


def _check_auth_rate(client_ip: str) -> None:
    """Raises HTTPException(429) if the IP has exceeded the auth rate limit."""
    now = time.time()
    attempts = _auth_attempts[client_ip]
    _auth_attempts[client_ip] = [t for t in attempts if now - t < _AUTH_WINDOW]
    if len(_auth_attempts[client_ip]) >= _AUTH_RATE_LIMIT:
        raise HTTPException(
            status_code=429,
            detail=f"Too many authentication attempts. Try again in {_AUTH_WINDOW} seconds.",
        )
    _auth_attempts[client_ip].append(now)


def _get_client_ip(request: Request) -> str:
    # The leftmost entry in X-Forwarded-For is attacker-controlled (the client
    # sets it directly); only the entry our own reverse proxy appended — the
    # rightmost one — can be trusted. Trusting the leftmost lets a client spoof
    # an arbitrary IP and bypass per-IP auth rate limiting.
    forwarded = request.headers.get("X-Forwarded-For")
    if forwarded:
        parts = [p.strip() for p in forwarded.split(",") if p.strip()]
        if parts:
            return parts[-1]
    return request.client.host if request.client else "unknown"


# ---------------------------------------------------------------------------
# Startup temp-dir cleanup (Fix 6)
# ---------------------------------------------------------------------------


async def cleanup_orphan_temp_dirs() -> None:
    """Remove download temp dirs (prefix 'dl_') older than 1 hour."""
    tmp_dir = pathlib.Path(tempfile.gettempdir())
    cutoff = time.time() - 3600
    for dl_dir in tmp_dir.glob("dl_*"):
        if dl_dir.is_dir() and dl_dir.stat().st_mtime < cutoff:
            try:
                shutil.rmtree(dl_dir, ignore_errors=True)
                logger.info(f"Cleaned orphan temp dir: {dl_dir}")
            except Exception as e:
                logger.warning(f"Failed to clean {dl_dir}: {e}")


# ---------------------------------------------------------------------------
# Lifespan
# ---------------------------------------------------------------------------


async def _auth_attempts_janitor() -> None:
    """Periodically evict stale IP entries from _auth_attempts so it never grows unbounded."""
    while True:
        await asyncio.sleep(300)  # every 5 minutes
        now = time.time()
        stale = [
            ip for ip, times in list(_auth_attempts.items())
            if not any(now - t < _AUTH_WINDOW for t in times)
        ]
        for ip in stale:
            _auth_attempts.pop(ip, None)
        if stale:
            logger.debug("auth janitor: evicted %d stale IP entries", len(stale))


_APP_LOGS_RETENTION_DAYS = 14


async def _app_logs_janitor() -> None:
    """Periodically prune old rows from ios_app_logs so client telemetry never grows unbounded."""
    while True:
        await asyncio.sleep(86400)  # once a day
        try:
            pool = await get_pool()
            async with pool.acquire() as conn:
                async with conn.cursor() as cur:
                    deleted = await cur.execute(
                        "DELETE FROM ios_app_logs WHERE created_at < NOW() - INTERVAL %s DAY",
                        (_APP_LOGS_RETENTION_DAYS,),
                    )
            if deleted:
                logger.info("app logs janitor: pruned %d rows older than %d days", deleted, _APP_LOGS_RETENTION_DAYS)
        except Exception:
            logger.exception("app logs janitor: prune failed")


@asynccontextmanager
async def lifespan(app: FastAPI):
    await init_db()
    await cleanup_orphan_temp_dirs()
    janitor = asyncio.create_task(_auth_attempts_janitor())
    app_logs_janitor = asyncio.create_task(_app_logs_janitor())
    yield
    janitor.cancel()
    app_logs_janitor.cancel()
    # Shutdown: close the DB connection pool (Fix 8)
    import db as _db_module
    pool = _db_module._pool
    if pool is not None:
        pool.close()
        await pool.wait_closed()
        logger.info("DB connection pool closed")


# ---------------------------------------------------------------------------
# App
# ---------------------------------------------------------------------------

app = FastAPI(title="StashOpusPlayer iOS Bridge", version=VERSION, lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# ---------------------------------------------------------------------------
# Simple in-memory search cache  (TTL = 5 minutes)
# ---------------------------------------------------------------------------

_search_cache: dict[str, tuple[float, list[dict]]] = {}
_CACHE_TTL = 300       # seconds
_CACHE_MAX  = 500      # max entries before eviction


def _cache_get(key: str) -> Optional[list[dict]]:
    entry = _search_cache.get(key)
    if entry is None:
        return None
    ts, data = entry
    if time.monotonic() - ts > _CACHE_TTL:
        del _search_cache[key]
        return None
    return data


def _cache_set(key: str, data: list[dict]) -> None:
    if len(_search_cache) >= _CACHE_MAX:
        # Evict oldest 25%
        oldest = sorted(_search_cache.items(), key=lambda x: x[1][0])
        for k, _ in oldest[: _CACHE_MAX // 4]:
            _search_cache.pop(k, None)
    _search_cache[key] = (time.monotonic(), data)


# ---------------------------------------------------------------------------
# API key auth (for existing yt-dlp endpoints)
# ---------------------------------------------------------------------------


async def check_auth(request: Request) -> None:
    """If IOS_BRIDGE_API_KEY is set, require a matching Bearer token."""
    if not API_KEY:
        return
    auth_header = request.headers.get("Authorization", "")
    if not auth_header.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Missing Authorization header")
    token = auth_header[len("Bearer "):]
    if token != API_KEY:
        raise HTTPException(status_code=403, detail="Invalid API key")


# ---------------------------------------------------------------------------
# JWT auth dependency (for account endpoints)
# ---------------------------------------------------------------------------

_security = HTTPBearer(auto_error=False)


async def get_current_user(
    credentials: HTTPAuthorizationCredentials | None = Depends(_security),
) -> dict:
    if not credentials:
        raise HTTPException(status_code=401, detail="Authentication required")
    payload = decode_token(credentials.credentials)
    if not payload:
        logger.warning("JWT decode failed for token (invalid or expired)")
        raise HTTPException(status_code=401, detail="Invalid or expired token")

    # A valid JWT signature isn't enough on its own — logout (and future
    # "sign out other devices" features) only delete the matching row in
    # ios_user_sessions, so without this lookup a revoked or stolen token
    # would keep working for its full lifetime. token_id is the table's
    # primary key, so this is a single indexed point lookup per request.
    token_id = payload.get("jti")
    if token_id:
        pool = await get_pool()
        async with pool.acquire() as conn:
            async with conn.cursor() as cur:
                await cur.execute(
                    "SELECT 1 FROM ios_user_sessions WHERE token_id = %s AND expires_at > NOW()",
                    (token_id,),
                )
                if not await cur.fetchone():
                    raise HTTPException(status_code=401, detail="Session has been revoked")

    return payload


# ---------------------------------------------------------------------------
# SSRF guard for client-supplied URLs handed to yt-dlp
# ---------------------------------------------------------------------------

# /api/stream, /api/download (soundcloud), /api/track, and /api/resolve all take
# a client-supplied `url` and pass it straight to a `yt-dlp <url>` subprocess.
# yt-dlp's generic extractor will happily fetch arbitrary http(s) URLs, which
# would let this bridge be abused as an internal-network probe / SSRF proxy
# (e.g. http://169.254.169.254/... cloud metadata, or http://localhost:<port>/...
# internal services). Resolve the host and reject anything that lands on a
# non-public address rather than restricting to a fixed site allowlist — that
# preserves yt-dlp's broad site support for legitimate playlist/track URLs.
async def _reject_ssrf_targets(url: str) -> None:
    parsed = urlsplit(url)
    if parsed.scheme not in ("http", "https"):
        raise HTTPException(status_code=400, detail="URL must be http or https")

    hostname = parsed.hostname
    if not hostname:
        raise HTTPException(status_code=400, detail="URL is missing a host")

    try:
        infos = await asyncio.get_running_loop().getaddrinfo(hostname, None)
    except OSError:
        raise HTTPException(status_code=400, detail="Could not resolve URL host")

    for info in infos:
        try:
            ip = ipaddress.ip_address(info[4][0])
        except ValueError:
            continue
        if (
            ip.is_private
            or ip.is_loopback
            or ip.is_link_local
            or ip.is_multicast
            or ip.is_reserved
            or ip.is_unspecified
        ):
            raise HTTPException(status_code=400, detail="URL host resolves to a disallowed address")


# ---------------------------------------------------------------------------
# yt-dlp subprocess helper
# ---------------------------------------------------------------------------


def _ytdlp_cookie_args() -> list[str]:
    """YouTube only paginates flat-playlist results past the first ~100 entries
    for authenticated requests. If a session cookie export is bind-mounted at
    YTDLP_COOKIES_FILE, use it — the file can be swapped out at any time
    (no rebuild/restart needed) to refresh the session.

    Also skip yt-dlp's initial webpage fetch for the playlist tab and go
    straight to the API JSON — for large playlists that contain unavailable
    (deleted/private) videos this roughly doubles the number of entries
    yt-dlp is able to paginate through (e.g. 105/307 -> 205/307)."""
    args = ["--extractor-args", "youtubetab:skip=webpage"]
    if os.path.isfile(YTDLP_COOKIES_FILE) and os.path.getsize(YTDLP_COOKIES_FILE) > 0:
        args += ["--cookies", YTDLP_COOKIES_FILE]
    return args


async def _run_ytdlp(*args: str, timeout: float = 30.0) -> list[dict]:
    """
    Run yt-dlp with the given arguments.
    Returns a list of parsed JSON objects (one per stdout line).
    Raises asyncio.TimeoutError if the process exceeds *timeout* seconds.
    Max 4 concurrent yt-dlp processes are allowed (semaphore).
    """
    cmd = ["yt-dlp", *args]
    logger.info("Running: %s", " ".join(cmd))
    async with _YTDLP_SEMAPHORE:
        proc = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        try:
            stdout_bytes, stderr_bytes = await asyncio.wait_for(
                proc.communicate(), timeout=timeout
            )
        except asyncio.TimeoutError:
            proc.kill()
            await proc.communicate()  # reap the zombie (Fix 7)
            raise

    if stderr_bytes:
        logger.debug("yt-dlp stderr: %s", stderr_bytes.decode(errors="replace")[:500])

    results: list[dict] = []
    for raw_line in stdout_bytes.splitlines():
        line = raw_line.strip()
        if not line:
            continue
        try:
            results.append(json.loads(line))
        except json.JSONDecodeError:
            logger.debug("Skipping non-JSON line: %s", line[:120])
    return results


def _parse_track(entry: dict, source: str) -> dict:
    """Normalise a yt-dlp flat-playlist or full dump into a StreamTrack dict."""
    track_id = entry.get("id") or entry.get("webpage_url_basename") or ""
    title = entry.get("title") or entry.get("fulltitle") or "Unknown Title"

    # Artist: uploader / channel / artist tag, in priority order.
    # SoundCloud flat-playlist entries often use uploader_id rather than uploader.
    artist = (
        entry.get("artist")
        or entry.get("uploader")
        or entry.get("uploader_id")
        or entry.get("channel")
        or entry.get("creator")
        or "Unknown Artist"
    )

    duration_raw = entry.get("duration") or 0
    try:
        duration_seconds = int(float(duration_raw))
    except (ValueError, TypeError):
        duration_seconds = 0

    # Thumbnail: prefer 'thumbnail', fall back to first item in 'thumbnails' list
    thumbnail_url = entry.get("thumbnail") or ""
    if not thumbnail_url:
        thumbnails = entry.get("thumbnails") or []
        if thumbnails:
            thumbnail_url = thumbnails[-1].get("url", "")

    # Canonical URL
    youtube_url = (
        entry.get("webpage_url")
        or entry.get("original_url")
        or (f"https://youtube.com/watch?v={track_id}" if source == "youtube" else "")
    )

    return {
        "id": track_id,
        "title": title,
        "artist": artist,
        "duration_seconds": duration_seconds,
        "thumbnail_url": thumbnail_url,
        "source": source,
        "youtube_url": youtube_url,
    }


_YOUTUBE_PLAYLIST_ID_RE = re.compile(r"[?&]list=([A-Za-z0-9_-]+)")

# ISO 8601 durations as returned by YouTube Data API's contentDetails.duration,
# e.g. "PT1H2M3S", "PT45S".
_ISO8601_DURATION_RE = re.compile(
    r"^PT(?:(?P<hours>\d+)H)?(?:(?P<minutes>\d+)M)?(?:(?P<seconds>\d+)S)?$"
)


def _extract_youtube_playlist_id(url: str) -> Optional[str]:
    match = _YOUTUBE_PLAYLIST_ID_RE.search(url)
    return match.group(1) if match else None


def _parse_iso8601_duration(duration: str) -> int:
    match = _ISO8601_DURATION_RE.match(duration or "")
    if not match:
        return 0
    parts = match.groupdict()
    hours = int(parts["hours"] or 0)
    minutes = int(parts["minutes"] or 0)
    seconds = int(parts["seconds"] or 0)
    return hours * 3600 + minutes * 60 + seconds


def _youtube_data_api_get(path: str, params: dict) -> dict:
    """Synchronous GET against the YouTube Data API v3 — call via asyncio.to_thread.

    The target host is a hardcoded Google domain (not derived from user input),
    so this does not need the SSRF guard used for user-supplied playlist URLs.
    """
    from urllib.parse import urlencode

    query = urlencode({**params, "key": YOUTUBE_API_KEY})
    req = urllib.request.Request(f"https://www.googleapis.com/youtube/v3/{path}?{query}")
    with urllib.request.urlopen(req, timeout=15) as resp:
        return json.loads(resp.read())


async def _resolve_youtube_playlist_via_api(playlist_id: str, limit: int) -> list[dict]:
    """Enumerate a YouTube playlist via playlistItems.list (paginated via
    nextPageToken — no ~205-entry cap, unlike yt-dlp's flat-playlist scrape).

    Raises on any API error so the caller can fall back to yt-dlp.
    """
    items: list[dict] = []
    page_token: Optional[str] = None
    while len(items) < limit:
        params = {
            "part": "snippet",
            "playlistId": playlist_id,
            "maxResults": min(50, limit - len(items)),
        }
        if page_token:
            params["pageToken"] = page_token
        data = await asyncio.to_thread(_youtube_data_api_get, "playlistItems", params)
        for item in data.get("items", []):
            snippet = item.get("snippet") or {}
            video_id = (snippet.get("resourceId") or {}).get("videoId")
            title = snippet.get("title") or ""
            if not video_id or title in ("Deleted video", "Private video"):
                continue
            thumbnails = snippet.get("thumbnails") or {}
            thumbnail_url = ""
            for size in ("maxres", "standard", "high", "medium", "default"):
                if size in thumbnails:
                    thumbnail_url = thumbnails[size].get("url", "")
                    break
            items.append({
                "id": video_id,
                "title": title,
                "channel": snippet.get("videoOwnerChannelTitle") or snippet.get("channelTitle"),
                "thumbnail": thumbnail_url,
            })

        page_token = data.get("nextPageToken")
        if not page_token:
            break

    # Batch-fetch durations (videos.list accepts up to 50 IDs per call).
    for batch_start in range(0, len(items), 50):
        batch = items[batch_start:batch_start + 50]
        data = await asyncio.to_thread(
            _youtube_data_api_get,
            "videos",
            {"part": "contentDetails", "id": ",".join(i["id"] for i in batch)},
        )
        durations = {
            v["id"]: _parse_iso8601_duration((v.get("contentDetails") or {}).get("duration", ""))
            for v in data.get("items", [])
        }
        for item in batch:
            item["duration"] = durations.get(item["id"], 0)

    return items


# ---------------------------------------------------------------------------
# Pydantic models
# ---------------------------------------------------------------------------


class RegisterRequest(BaseModel):
    username: str
    password: str
    email: Optional[str] = None
    display_name: Optional[str] = None


class LoginRequest(BaseModel):
    username: str
    password: str
    device_name: Optional[str] = None


class CreatePlaylistRequest(BaseModel):
    name: str
    description: Optional[str] = None
    folder: Optional[str] = None
    tags: list[str] = []


class UpdatePlaylistRequest(BaseModel):
    name: Optional[str] = None
    description: Optional[str] = None
    folder: Optional[str] = None
    tags: Optional[list[str]] = None


class AddFavoriteRequest(BaseModel):
    song_id: str
    title: Optional[str] = None
    artist: Optional[str] = None
    album: Optional[str] = None


class LogPlayRequest(BaseModel):
    title: str
    artist: Optional[str] = None
    track_url: Optional[str] = None
    local_song_id: Optional[str] = None
    listen_seconds: Optional[int] = 0


class UpdateSettingsRequest(BaseModel):
    audio_settings_json: Optional[str] = None
    track_audio_settings_json: Optional[str] = None
    theme_color: Optional[str] = None


class BugReportRequest(BaseModel):
    category: str = "other"
    description: str
    contact_email: Optional[str] = None
    app_version: Optional[str] = None
    device_info: Optional[str] = None
    recent_logs: Optional[str] = None


class SyncTrack(BaseModel):
    local_song_id: Optional[str] = None
    track_url: Optional[str] = None
    title: str
    artist: Optional[str] = None
    album: Optional[str] = None
    duration_seconds: Optional[int] = 0
    position: Optional[int] = 0


class SyncPlaylist(BaseModel):
    id: str
    name: str
    description: Optional[str] = None
    folder: Optional[str] = None
    tags: list[str] = []
    tracks: list[SyncTrack] = []


class SyncFavorite(BaseModel):
    song_id: str
    title: Optional[str] = None
    artist: Optional[str] = None
    album: Optional[str] = None


class SyncPushRequest(BaseModel):
    favorites: list[SyncFavorite] = []
    playlists: list[SyncPlaylist] = []
    audio_settings_json: Optional[str] = None
    track_audio_settings_json: Optional[str] = None
    theme_color: Optional[str] = None


class SharePlaylistRequest(BaseModel):
    playlist_id: str = ""
    playlist_name: str
    tracks: list


class PlaybackStateRequest(BaseModel):
    song_id: Optional[str] = None
    title: Optional[str] = None
    artist: Optional[str] = None
    track_url: Optional[str] = None
    source: Optional[str] = None
    position_seconds: float = 0
    duration_seconds: float = 0
    is_playing: bool = True


class PlaylistSourceRequest(BaseModel):
    source_url: str


class CreateRoomRequest(BaseModel):
    track_url: Optional[str] = None
    title: Optional[str] = None
    artist: Optional[str] = None
    position_seconds: float = 0
    is_playing: bool = False


class UpdateRoomRequest(BaseModel):
    track_url: Optional[str] = None
    title: Optional[str] = None
    artist: Optional[str] = None
    position_seconds: Optional[float] = None
    is_playing: Optional[bool] = None


class SubscribeChannelRequest(BaseModel):
    channel_url: str
    channel_name: Optional[str] = None


class AddCollaboratorRequest(BaseModel):
    username: str
    role: str = "editor"  # 'editor' or 'viewer'


class QueueTrackRequest(BaseModel):
    local_song_id: Optional[str] = None
    track_url: Optional[str] = None
    title: str
    artist: Optional[str] = None
    album: Optional[str] = None
    duration_seconds: Optional[int] = 0


class ReplaceQueueRequest(BaseModel):
    tracks: list[QueueTrackRequest] = []


class ScrobbleLinkRequest(BaseModel):
    lastfm_session_key: Optional[str] = None
    lastfm_username: Optional[str] = None
    listenbrainz_token: Optional[str] = None
    enabled: Optional[bool] = None


class PushTokenRequest(BaseModel):
    device_token: str
    platform: str = "ios"


class DiscordWebhookRequest(BaseModel):
    webhook_url: Optional[str] = None
    enabled: bool = True


class DiscordRpcConfigRequest(BaseModel):
    discord_client_id: str
    large_image: Optional[str] = None
    enabled: bool = True


# ---------------------------------------------------------------------------
# Helper: build user dict from DB row
# ---------------------------------------------------------------------------


def _user_dict(row: tuple) -> dict:
    """Map a (id, username, email, display_name, avatar_url, created_at, last_login,
    date_of_birth, share_listening_activity) row."""
    return {
        "id": row[0],
        "username": row[1],
        "email": row[2],
        "display_name": row[3],
        "avatar_url": row[4],
        "created_at": row[5].isoformat() if row[5] else None,
        "last_login": row[6].isoformat() if row[6] else None,
        "date_of_birth": row[7].isoformat() if len(row) > 7 and row[7] else None,
        "share_listening_activity": bool(row[8]) if len(row) > 8 else False,
    }


# ---------------------------------------------------------------------------
# Existing Endpoints
# ---------------------------------------------------------------------------


@app.get("/health")
async def health():
    return {
        "status": "ok",
        "version": VERSION,
        "yt_dlp_version": yt_dlp.version.__version__,
    }


@app.get("/api/search")
async def search(
    request: Request,
    q: str = Query(..., min_length=1, max_length=200, description="Search query"),
    limit: int = Query(20, ge=1, le=50, description="Max results"),
    source: str = Query("youtube", description="youtube or soundcloud"),
):
    await check_auth(request)

    source = source.lower()
    if source not in ("youtube", "soundcloud"):
        raise HTTPException(status_code=400, detail="source must be 'youtube' or 'soundcloud'")

    asyncio.create_task(_log_search(q, source))

    cache_key = f"{source}:{limit}:{q}"
    cached = _cache_get(cache_key)
    if cached is not None:
        logger.info("Cache hit for query %r", q)
        return cached

    prefix = "ytsearch" if source == "youtube" else "scsearch"
    search_url = f"{prefix}{limit}:{q}"

    # SoundCloud flat-playlist entries are sparse (often missing thumbnails and artist).
    # Use full --dump-json (no --flat-playlist) for SoundCloud so we get complete metadata.
    if source == "soundcloud":
        base_args = [
            search_url,
            "--dump-json",
            "--no-playlist",
        ]
    else:
        base_args = [
            search_url,
            "--dump-json",
            "--flat-playlist",
            "--no-playlist",
            "--cache-dir", YTDLP_CACHE_DIR,
            *_ytdlp_cookie_args(),
        ]

    try:
        entries = await _run_ytdlp(*base_args, timeout=30.0)
    except asyncio.TimeoutError:
        logger.warning("yt-dlp search timed out for query %r", q)
        return []
    except Exception as exc:
        logger.error("yt-dlp search error: %s", exc)
        return []

    tracks = [_parse_track(e, source) for e in entries]
    _cache_set(cache_key, tracks)
    return tracks


@app.get("/api/stream")
async def stream(
    request: Request,
    id: str = Query(..., description="Video/track ID"),
    source: str = Query("youtube", description="youtube or soundcloud"),
    url: Optional[str] = Query(None, description="Full URL (required for soundcloud)"),
    format: str = Query("m4a", description="Audio format: mp3, m4a, flac, opus, best"),
):
    await check_auth(request)

    source = source.lower()
    format = format.lower()

    if source == "soundcloud":
        if not url:
            raise HTTPException(
                status_code=400, detail="url parameter required for soundcloud source"
            )
        await _reject_ssrf_targets(url)
        target_url = url
    else:
        target_url = f"https://youtube.com/watch?v={id}"

    format_flag = _format_flag(format)
    stream_url = await _get_raw_url(target_url, format_flag=format_flag)
    if not stream_url:
        raise HTTPException(status_code=404, detail="No stream URL found")

    return {"url": stream_url, "expires_in": 21600}


def _format_flag(format: str) -> str:
    """Map a format name to a yt-dlp -f flag value for direct URL extraction."""
    mapping = {
        "mp3":  "bestaudio/best",
        "m4a":  "bestaudio[ext=m4a]/bestaudio/best",
        "flac": "bestaudio/best",
        "opus": "bestaudio[ext=webm]/bestaudio/best",
        "wav":  "bestaudio/best",
        "best": "bestaudio/best",
    }
    return mapping.get(format, "bestaudio[ext=m4a]/bestaudio/best")


async def _get_raw_url(
    target_url: str,
    format_flag: str = "bestaudio[ext=m4a]/bestaudio/best",
) -> Optional[str]:
    """
    Runs yt-dlp --get-url and returns the first HTTP(S) line from stdout.

    Some videos don't expose the requested container/codec combination (the
    preferred format simply isn't in the available formats list), which makes
    yt-dlp print nothing and surfaces to users as "Unable to find stream URL".
    Rather than failing outright, retry with progressively more permissive
    format selectors before giving up.
    """
    attempts: list[str] = []
    for flag in (format_flag, "bestaudio/best", "best"):
        if flag not in attempts:
            attempts.append(flag)

    last_stderr = b""
    for attempt_flag in attempts:
        cmd = [
            "yt-dlp",
            "-f", attempt_flag,
            "--get-url",
            "--no-playlist",
            target_url,
        ]
        logger.info("Running (raw): %s", " ".join(cmd))
        async with _YTDLP_SEMAPHORE:
            proc = await asyncio.create_subprocess_exec(
                *cmd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
            )
            try:
                stdout_bytes, stderr_bytes = await asyncio.wait_for(proc.communicate(), timeout=15.0)
            except asyncio.TimeoutError:
                proc.kill()
                await proc.communicate()  # reap the zombie (Fix 7)
                raise HTTPException(status_code=408, detail="Stream URL fetch timed out")

        last_stderr = stderr_bytes
        for raw_line in stdout_bytes.splitlines():
            line = raw_line.strip().decode(errors="replace")
            if line.startswith("http"):
                if attempt_flag != format_flag:
                    logger.info(
                        "Stream URL resolved via fallback format %r (preferred %r unavailable) for %s",
                        attempt_flag, format_flag, target_url,
                    )
                return line

        logger.warning(
            "yt-dlp returned no stream URL for %s with format %r — trying next fallback",
            target_url, attempt_flag,
        )

    logger.error(
        "yt-dlp exhausted all format fallbacks for %s — stderr: %s",
        target_url, last_stderr.decode(errors="replace")[-500:],
    )
    return None


@app.get("/api/download")
async def download_track(
    request: Request,
    id: str = Query(..., description="Video/track ID"),
    source: str = Query("youtube", description="youtube or soundcloud"),
    url: Optional[str] = Query(None, description="Full URL (required for soundcloud)"),
    format: str = Query("m4a", description="Audio format: mp3, m4a, flac, opus, best"),
    title: Optional[str] = Query(None, description="Safe filename hint (no extension)"),
):
    """
    Download audio with embedded metadata and thumbnail, stream the file bytes back,
    then clean up the temporary file.
    """
    await check_auth(request)

    source = source.lower()
    format = format.lower()

    if source == "soundcloud":
        if not url:
            raise HTTPException(
                status_code=400, detail="url parameter required for soundcloud source"
            )
        await _reject_ssrf_targets(url)
        target_url = url
    else:
        target_url = f"https://youtube.com/watch?v={id}"

    extra_args, expected_ext = _download_format_args(format)

    safe_title = (title or id).replace("/", "-").replace(":", "-")[:100]
    # Use UUID-based temp dir to prevent collisions (Fix 6)
    tmp_dir = pathlib.Path(tempfile.gettempdir()) / f"dl_{uuid.uuid4().hex}"
    tmp_dir.mkdir(parents=True, exist_ok=True)
    output_template = str(tmp_dir / f"{safe_title}.%(ext)s")

    cmd = [
        "yt-dlp",
        "--no-playlist",
        "--embed-metadata",
        # --embed-thumbnail intentionally omitted: requires AtomicParsley for M4A
        # which is not in the Docker image. The iOS ArtworkService handles artwork
        # display separately via the thumbnailURL field from search results.
        "-o", output_template,
        *extra_args,
        target_url,
    ]
    logger.info("Download cmd: %s", " ".join(cmd))

    async with _YTDLP_SEMAPHORE:
        proc = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        try:
            _, stderr_bytes = await asyncio.wait_for(proc.communicate(), timeout=300.0)
        except asyncio.TimeoutError:
            proc.kill()
            await proc.communicate()  # reap the zombie (Fix 7)
            shutil.rmtree(tmp_dir, ignore_errors=True)
            raise HTTPException(status_code=408, detail="Download timed out")

    if proc.returncode != 0:
        err_text = stderr_bytes.decode(errors="replace")[-500:]
        logger.error("yt-dlp download failed: %s", err_text)
        shutil.rmtree(tmp_dir, ignore_errors=True)
        raise HTTPException(status_code=404, detail="Could not download track")

    # yt-dlp may choose a slightly different extension than requested — scan the dir.
    output_file: Optional[pathlib.Path] = None
    actual_ext = expected_ext
    for fname in tmp_dir.iterdir():
        output_file = fname
        actual_ext = fname.suffix.lstrip(".") or expected_ext
        break

    if not output_file or not output_file.exists():
        shutil.rmtree(tmp_dir, ignore_errors=True)
        raise HTTPException(status_code=404, detail="Downloaded file not found")

    content_type_map = {
        "mp3":  "audio/mpeg",
        "m4a":  "audio/mp4",
        "flac": "audio/flac",
        "opus": "audio/ogg",
        "ogg":  "audio/ogg",
        "wav":  "audio/wav",
        "webm": "audio/webm",
    }
    media_type = content_type_map.get(actual_ext, "application/octet-stream")

    # Schedule cleanup after the file has been streamed (5-second grace period).
    async def _cleanup_later(path: pathlib.Path) -> None:
        await asyncio.sleep(5)
        shutil.rmtree(path, ignore_errors=True)

    asyncio.create_task(_cleanup_later(tmp_dir))

    return FileResponse(
        path=str(output_file),
        media_type=media_type,
        filename=f"{safe_title}.{actual_ext}",
    )


def _download_format_args(format: str) -> tuple[list[str], str]:
    """
    Returns (extra_yt_dlp_args, expected_ext) for a given format name.
    Formats requiring transcoding use -x --audio-format so yt-dlp converts and
    embeds metadata in a single pass.
    """
    if format == "mp3":
        return ["-f", "bestaudio", "-x", "--audio-format", "mp3", "--audio-quality", "0"], "mp3"
    elif format == "flac":
        return ["-f", "bestaudio", "-x", "--audio-format", "flac"], "flac"
    elif format == "opus":
        return ["-f", "bestaudio[ext=webm]/bestaudio", "-x", "--audio-format", "opus"], "opus"
    elif format == "wav":
        return ["-f", "bestaudio", "-x", "--audio-format", "wav"], "wav"
    elif format == "best":
        return ["-f", "bestaudio/best"], "m4a"
    else:
        # m4a — native m4a from YouTube, no transcoding needed.
        return ["-f", "bestaudio[ext=m4a]/bestaudio/best"], "m4a"


@app.get("/api/track")
async def track_metadata(
    request: Request,
    url: str = Query(..., description="Full track URL"),
):
    await check_auth(request)
    await _reject_ssrf_targets(url)

    try:
        entries = await _run_ytdlp(
            "--dump-json",
            "--no-playlist",
            url,
            timeout=20.0,
        )
    except asyncio.TimeoutError:
        raise HTTPException(status_code=408, detail="Metadata fetch timed out")
    except Exception as exc:
        logger.error("yt-dlp track error: %s", exc)
        raise HTTPException(status_code=404, detail="Could not fetch track metadata")

    if not entries:
        raise HTTPException(status_code=404, detail="Track not found")

    entry = entries[0]
    source = "soundcloud" if "soundcloud.com" in url else "youtube"
    base = _parse_track(entry, source)
    base["description"] = entry.get("description") or ""
    return base


@app.get("/api/resolve")
async def resolve_playlist(
    request: Request,
    url: str = Query(..., description="Playlist or album URL"),
    limit: int = Query(100, ge=1, le=1000, description="Max tracks to return"),
):
    await check_auth(request)
    await _reject_ssrf_targets(url)

    source = "soundcloud" if "soundcloud.com" in url else "youtube"

    if source == "youtube" and YOUTUBE_API_KEY:
        playlist_id = _extract_youtube_playlist_id(url)
        if playlist_id:
            try:
                items = await _resolve_youtube_playlist_via_api(playlist_id, limit)
                return [_parse_track(item, source) for item in items]
            except Exception as exc:
                logger.warning("YouTube Data API resolve failed, falling back to yt-dlp: %s", exc)

    # SoundCloud flat-playlist entries are sparse (often missing artist/duration/
    # thumbnails) — use full --dump-json for complete metadata, same as /api/search.
    if source == "soundcloud":
        args = ["--dump-json", url]
    else:
        args = ["--dump-json", "--flat-playlist", *_ytdlp_cookie_args(), url]

    try:
        entries = await _run_ytdlp(*args, timeout=120.0)
    except asyncio.TimeoutError:
        raise HTTPException(status_code=408, detail="Playlist resolve timed out")
    except Exception as exc:
        logger.error("yt-dlp resolve error: %s", exc)
        raise HTTPException(status_code=404, detail="Could not resolve playlist")

    tracks = [_parse_track(e, source) for e in entries[:limit]]
    return tracks


# ---------------------------------------------------------------------------
# Auth Endpoints
# ---------------------------------------------------------------------------


@app.post("/auth/register", status_code=201)
async def register(body: RegisterRequest, request: Request):
    # Rate limit check (Fix 2)
    _check_auth_rate(_get_client_ip(request))

    username = body.username.strip()
    if len(username) < 3:
        raise HTTPException(status_code=400, detail="Username must be at least 3 characters")
    if len(body.password) < 6:
        raise HTTPException(status_code=400, detail="Password must be at least 6 characters")

    pool = await get_pool()
    async with pool.acquire() as conn:
        async with conn.cursor() as cur:
            # Check username uniqueness
            await cur.execute(
                "SELECT id FROM ios_users WHERE username = %s", (username,)
            )
            if await cur.fetchone():
                raise HTTPException(status_code=409, detail="Username already taken")

            # Check email uniqueness if provided
            if body.email:
                await cur.execute(
                    "SELECT id FROM ios_users WHERE email = %s", (body.email,)
                )
                if await cur.fetchone():
                    raise HTTPException(status_code=409, detail="Email already registered")

            user_id = str(uuid.uuid4())
            # Fix 1: run bcrypt off the event loop
            password_hash = await hash_password_async(body.password)

            await cur.execute(
                """
                INSERT INTO ios_users (id, username, email, password_hash, display_name)
                VALUES (%s, %s, %s, %s, %s)
                """,
                (user_id, username, body.email, password_hash, body.display_name),
            )

            # Create default settings row
            await cur.execute(
                "INSERT INTO ios_user_settings (user_id) VALUES (%s)",
                (user_id,),
            )

            token_id = str(uuid.uuid4())
            expires_at = datetime.now(timezone.utc) + timedelta(days=30)
            await cur.execute(
                """
                INSERT INTO ios_user_sessions (token_id, user_id, expires_at, device_name)
                VALUES (%s, %s, %s, %s)
                """,
                (token_id, user_id, expires_at, "Unknown device"),
            )

            token = create_token(user_id, token_id)

            await cur.execute(
                "SELECT id, username, email, display_name, avatar_url, created_at, last_login, date_of_birth, "
                "share_listening_activity "
                "FROM ios_users WHERE id = %s",
                (user_id,),
            )
            row = await cur.fetchone()

    return {"user": _user_dict(row), "token": token}


@app.post("/auth/login")
async def login(body: LoginRequest, request: Request):
    # Rate limit check (Fix 2)
    _check_auth_rate(_get_client_ip(request))

    pool = await get_pool()
    async with pool.acquire() as conn:
        async with conn.cursor() as cur:
            await cur.execute(
                "SELECT id, username, email, display_name, avatar_url, created_at, "
                "last_login, password_hash, is_active "
                "FROM ios_users WHERE username = %s",
                (body.username.strip(),),
            )
            row = await cur.fetchone()

    if not row:
        logger.warning("Login attempt for unknown username: %r", body.username.strip())
        raise HTTPException(status_code=401, detail="Invalid username or password")

    (user_id, username, email, display_name, avatar_url,
     created_at, last_login, password_hash, is_active) = row

    if not is_active:
        logger.warning("Login attempt for disabled account: %r (user_id=%s)", username, user_id)
        raise HTTPException(status_code=403, detail="Account is disabled")

    # Fix 1: run bcrypt off the event loop
    if not await verify_password_async(body.password, password_hash):
        logger.warning("Failed password attempt for username: %r (user_id=%s)", username, user_id)
        raise HTTPException(status_code=401, detail="Invalid username or password")

    async with pool.acquire() as conn:
        async with conn.cursor() as cur:
            token_id = str(uuid.uuid4())
            expires_at = datetime.now(timezone.utc) + timedelta(days=30)
            device_name = body.device_name or "Unknown device"
            await cur.execute(
                """
                INSERT INTO ios_user_sessions (token_id, user_id, expires_at, device_name)
                VALUES (%s, %s, %s, %s)
                """,
                (token_id, user_id, expires_at, device_name),
            )
            await cur.execute(
                "UPDATE ios_users SET last_login = NOW() WHERE id = %s",
                (user_id,),
            )

    token = create_token(user_id, token_id)

    # Fetch full user row so we return date_of_birth and all fields consistently.
    async with pool.acquire() as conn:
        async with conn.cursor() as cur:
            await cur.execute(
                "SELECT id, username, email, display_name, avatar_url, created_at, last_login, date_of_birth, "
                "share_listening_activity "
                "FROM ios_users WHERE id = %s",
                (user_id,),
            )
            row = await cur.fetchone()

    return {"user": _user_dict(row), "token": token}


@app.post("/auth/logout", status_code=204)
async def logout(payload: dict = Depends(get_current_user)):
    token_id = payload.get("jti")
    if token_id:
        pool = await get_pool()
        async with pool.acquire() as conn:
            async with conn.cursor() as cur:
                await cur.execute(
                    "DELETE FROM ios_user_sessions WHERE token_id = %s", (token_id,)
                )


@app.get("/auth/sessions")
async def list_sessions(payload: dict = Depends(get_current_user)):
    """Lists this account's active logins (one per device/sign-in), so a user
    can spot and revoke a session they don't recognize."""
    user_id = payload["sub"]
    current_token_id = payload.get("jti")
    pool = await get_pool()
    async with pool.acquire() as conn:
        async with conn.cursor() as cur:
            await cur.execute(
                """
                SELECT token_id, device_name, created_at, expires_at
                FROM ios_user_sessions
                WHERE user_id = %s AND expires_at > NOW()
                ORDER BY created_at DESC
                """,
                (user_id,),
            )
            rows = await cur.fetchall()

    return {
        "sessions": [
            {
                "token_id": r[0],
                "device_name": r[1],
                "created_at": r[2].isoformat() if r[2] else None,
                "expires_at": r[3].isoformat() if r[3] else None,
                "is_current": r[0] == current_token_id,
            }
            for r in rows
        ]
    }


@app.delete("/auth/sessions/{token_id}", status_code=204)
async def revoke_session(token_id: str, payload: dict = Depends(get_current_user)):
    """Signs out a specific device by deleting its session. A user can revoke
    any of their own sessions, including (deliberately) the current one."""
    user_id = payload["sub"]
    pool = await get_pool()
    async with pool.acquire() as conn:
        async with conn.cursor() as cur:
            await cur.execute(
                "DELETE FROM ios_user_sessions WHERE token_id = %s AND user_id = %s",
                (token_id, user_id),
            )


class ChangePasswordRequest(BaseModel):
    current_password: str
    new_password: str


@app.post("/auth/change-password", status_code=204)
async def change_password(body: ChangePasswordRequest, payload: dict = Depends(get_current_user)):
    """Changes the account password, then revokes every other session so a
    stolen/old token can't keep using the previous password's session."""
    user_id = payload["sub"]
    current_token_id = payload.get("jti")

    if len(body.new_password) < 8:
        raise HTTPException(status_code=400, detail="New password must be at least 8 characters")

    pool = await get_pool()
    async with pool.acquire() as conn:
        async with conn.cursor() as cur:
            await cur.execute("SELECT password_hash FROM ios_users WHERE id = %s", (user_id,))
            row = await cur.fetchone()
            if not row:
                raise HTTPException(status_code=401, detail="User not found")

            if not await verify_password_async(body.current_password, row[0]):
                raise HTTPException(status_code=401, detail="Current password is incorrect")

            new_hash = await hash_password_async(body.new_password)
            await cur.execute(
                "UPDATE ios_users SET password_hash = %s WHERE id = %s", (new_hash, user_id)
            )
            # Sign out every other device — keep only the session used to make this request.
            await cur.execute(
                "DELETE FROM ios_user_sessions WHERE user_id = %s AND token_id != %s",
                (user_id, current_token_id),
            )


class DeleteAccountRequest(BaseModel):
    password: str


@app.post("/auth/delete-account", status_code=204)
async def delete_account(body: DeleteAccountRequest, payload: dict = Depends(get_current_user)):
    """Permanently deletes the account and all associated data. Requires the
    current password as confirmation. Cascading foreign keys on ios_users
    remove playlists, favorites, history, settings, backups, uploads, etc."""
    user_id = payload["sub"]
    pool = await get_pool()
    async with pool.acquire() as conn:
        async with conn.cursor() as cur:
            await cur.execute("SELECT password_hash FROM ios_users WHERE id = %s", (user_id,))
            row = await cur.fetchone()
            if not row:
                raise HTTPException(status_code=401, detail="User not found")

            if not await verify_password_async(body.password, row[0]):
                raise HTTPException(status_code=401, detail="Incorrect password")

            await cur.execute("DELETE FROM ios_users WHERE id = %s", (user_id,))

    # Remove the user's uploaded music/gallery files from disk — the DB rows
    # describing them were just cascade-deleted, but the files themselves
    # live outside the database under USER_MUSIC_DIR/{user_id}/.
    music_dir = _user_music_dir(user_id)
    if music_dir and music_dir.exists():
        shutil.rmtree(music_dir, ignore_errors=True)

    logger.info("delete_account: user %s deleted their account", user_id)


@app.get("/auth/me")
async def me(payload: dict = Depends(get_current_user)):
    user_id = payload["sub"]
    pool = await get_pool()
    async with pool.acquire() as conn:
        async with conn.cursor() as cur:
            await cur.execute(
                "SELECT id, username, email, display_name, avatar_url, created_at, last_login, date_of_birth, "
                "share_listening_activity "
                "FROM ios_users WHERE id = %s AND is_active = TRUE",
                (user_id,),
            )
            row = await cur.fetchone()

    if not row:
        raise HTTPException(status_code=401, detail="User not found")
    return _user_dict(row)


class UpdateMeRequest(BaseModel):
    display_name: Optional[str] = None
    date_of_birth: Optional[str] = None  # ISO format YYYY-MM-DD


@app.put("/auth/me")
async def update_me(body: UpdateMeRequest, payload: dict = Depends(get_current_user)):
    user_id = payload["sub"]
    display_name = (body.display_name or "").strip()[:100]
    pool = await get_pool()
    async with pool.acquire() as conn:
        async with conn.cursor() as cur:
            await cur.execute(
                "UPDATE ios_users SET display_name = %s WHERE id = %s AND is_active = TRUE",
                (display_name if display_name else None, user_id),
            )

            # DOB: immutable once set
            if body.date_of_birth:
                try:
                    datetime.strptime(body.date_of_birth, "%Y-%m-%d")
                except ValueError:
                    raise HTTPException(status_code=400, detail="date_of_birth must be in YYYY-MM-DD format")
                await cur.execute(
                    "SELECT date_of_birth FROM ios_users WHERE id = %s",
                    (user_id,),
                )
                dob_row = await cur.fetchone()
                if dob_row and dob_row[0]:
                    raise HTTPException(
                        status_code=400, detail="Date of birth cannot be changed once set"
                    )
                await cur.execute(
                    "UPDATE ios_users SET date_of_birth = %s WHERE id = %s",
                    (body.date_of_birth, user_id),
                )

            await cur.execute(
                "SELECT id, username, email, display_name, avatar_url, created_at, last_login, date_of_birth, "
                "share_listening_activity "
                "FROM ios_users WHERE id = %s AND is_active = TRUE",
                (user_id,),
            )
            row = await cur.fetchone()

    if not row:
        raise HTTPException(status_code=401, detail="User not found")
    return _user_dict(row)


class PrivacyRequest(BaseModel):
    share_listening_activity: bool


@app.put("/user/privacy")
async def update_privacy(body: PrivacyRequest, payload: dict = Depends(get_current_user)):
    """Toggles whether this user's recent plays (title/artist only) are
    visible to other signed-in users via GET /social/activity and
    /social/discover."""
    user_id = payload["sub"]
    pool = await get_pool()
    async with pool.acquire() as conn:
        async with conn.cursor() as cur:
            await cur.execute(
                "UPDATE ios_users SET share_listening_activity = %s WHERE id = %s AND is_active = TRUE",
                (body.share_listening_activity, user_id),
            )

    return {"share_listening_activity": body.share_listening_activity}


# ---------------------------------------------------------------------------
# Avatar Endpoints
# ---------------------------------------------------------------------------


@app.post("/user/avatar")
async def upload_avatar(request: Request, user: dict = Depends(get_current_user)):
    """Upload profile picture as JPEG bytes (max 1MB)."""
    body = await request.body()
    if len(body) > 1_048_576:  # 1MB limit
        raise HTTPException(status_code=413, detail="Avatar must be under 1MB")
    if not body.startswith(b"\xff\xd8\xff"):  # JPEG magic bytes (SOI + APPn/marker)
        raise HTTPException(status_code=400, detail="Avatar must be a JPEG image")
    pool = await get_pool()
    async with pool.acquire() as conn:
        async with conn.cursor() as cur:
            await cur.execute(
                "UPDATE ios_users SET avatar_data = %s WHERE id = %s",
                (body, user["sub"]),
            )
    return {"ok": True}


@app.get("/user/avatar/{user_id}")
async def get_avatar(user_id: str):
    """Returns raw JPEG bytes or 404."""
    pool = await get_pool()
    async with pool.acquire() as conn:
        async with conn.cursor() as cur:
            await cur.execute(
                "SELECT avatar_data FROM ios_users WHERE id = %s", (user_id,)
            )
            row = await cur.fetchone()
    if not row or not row[0]:
        raise HTTPException(status_code=404, detail="No avatar set")
    from fastapi.responses import Response
    return Response(content=bytes(row[0]), media_type="image/jpeg")


# ---------------------------------------------------------------------------
# Expanded Settings Endpoints
# ---------------------------------------------------------------------------

_EXPANDED_SETTINGS_COLS = [
    "user_id", "audio_settings_json", "theme_color", "vinyl_disc_enabled",
    "show_queue_preview", "songs_per_row", "albums_per_row", "bg_animation",
    "bg_opacity", "preferred_audio_format", "download_path", "updated_at",
]

_EXPANDED_SETTINGS_ALLOWED = [
    "audio_settings_json", "theme_color", "vinyl_disc_enabled",
    "show_queue_preview", "songs_per_row", "albums_per_row", "bg_animation",
    "bg_opacity", "preferred_audio_format", "download_path",
]


@app.get("/user/settings/expanded")
async def get_expanded_settings(user: dict = Depends(get_current_user)):
    pool = await get_pool()
    async with pool.acquire() as conn:
        async with conn.cursor() as cur:
            await cur.execute(
                "SELECT * FROM ios_user_settings_expanded WHERE user_id = %s",
                (user["sub"],),
            )
            row = await cur.fetchone()
    if not row:
        return {}  # Return empty dict — client uses defaults
    return dict(zip(_EXPANDED_SETTINGS_COLS, row))


@app.put("/user/settings/expanded")
async def put_expanded_settings(request: Request, user: dict = Depends(get_current_user)):
    raw = await request.body()
    if len(raw) > 262_144:  # 256KB — generous for a settings blob
        raise HTTPException(status_code=413, detail="Settings payload too large")
    try:
        body = json.loads(raw)
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid JSON body")
    if not isinstance(body, dict):
        raise HTTPException(status_code=400, detail="Body must be a JSON object")
    updates = {k: v for k, v in body.items() if k in _EXPANDED_SETTINGS_ALLOWED}
    if not updates:
        return {"ok": True}
    set_clause = ", ".join(f"{k} = %s" for k in updates)
    pool = await get_pool()
    async with pool.acquire() as conn:
        async with conn.cursor() as cur:
            await cur.execute(
                f"INSERT INTO ios_user_settings_expanded (user_id, {', '.join(updates)}) "
                f"VALUES (%s, {', '.join(['%s'] * len(updates))}) "
                f"ON DUPLICATE KEY UPDATE {set_clause}",
                [user["sub"]] + list(updates.values()) + list(updates.values()),
            )
    return {"ok": True}


# ---------------------------------------------------------------------------
# Playlist Endpoints
# ---------------------------------------------------------------------------


@app.get("/user/playlists")
async def get_playlists(payload: dict = Depends(get_current_user)):
    user_id = payload["sub"]
    pool = await get_pool()
    async with pool.acquire() as conn:
        async with conn.cursor() as cur:
            # Single JOIN fetches all playlists + tracks in one round-trip (no N+1).
            await cur.execute(
                """
                SELECT p.id, p.name, p.description, p.created_at, p.updated_at,
                       p.folder, p.tags_json,
                       t.id, t.track_url, t.local_song_id, t.title, t.artist, t.album,
                       t.duration_seconds, t.position
                FROM ios_user_playlists p
                LEFT JOIN ios_playlist_tracks t ON t.playlist_id = p.id
                WHERE p.user_id = %s
                ORDER BY p.updated_at DESC, t.position ASC
                """,
                (user_id,),
            )
            rows = await cur.fetchall()

    playlists: dict[str, dict] = {}
    order: list[str] = []
    for row in rows:
        (pl_id, name, description, created_at, updated_at, folder, tags_json,
         t_id, t_url, t_local, t_title, t_artist, t_album, t_dur, t_pos) = row
        if pl_id not in playlists:
            playlists[pl_id] = {
                "id": pl_id,
                "name": name,
                "description": description,
                "created_at": created_at.isoformat() if created_at else None,
                "updated_at": updated_at.isoformat() if updated_at else None,
                "folder": folder,
                "tags": json.loads(tags_json) if tags_json else [],
                "tracks": [],
            }
            order.append(pl_id)
        if t_id is not None:
            playlists[pl_id]["tracks"].append({
                "id": t_id,
                "track_url": t_url,
                "local_song_id": t_local,
                "title": t_title,
                "artist": t_artist,
                "album": t_album,
                "duration_seconds": t_dur,
                "position": t_pos,
            })

    return [playlists[pid] for pid in order]


@app.post("/user/playlists", status_code=201)
async def create_playlist(
    body: CreatePlaylistRequest,
    payload: dict = Depends(get_current_user),
):
    user_id = payload["sub"]
    pl_id = str(uuid.uuid4())
    pool = await get_pool()
    async with pool.acquire() as conn:
        async with conn.cursor() as cur:
            await cur.execute(
                """
                INSERT INTO ios_user_playlists (id, user_id, name, description, folder, tags_json)
                VALUES (%s, %s, %s, %s, %s, %s)
                """,
                (pl_id, user_id, body.name, body.description, body.folder, json.dumps(body.tags)),
            )
            await cur.execute(
                """
                SELECT id, name, description, created_at, updated_at, folder, tags_json
                FROM ios_user_playlists WHERE id = %s
                """,
                (pl_id,),
            )
            row = await cur.fetchone()

    pl_id, name, description, created_at, updated_at, folder, tags_json = row
    return {
        "id": pl_id,
        "name": name,
        "description": description,
        "created_at": created_at.isoformat() if created_at else None,
        "updated_at": updated_at.isoformat() if updated_at else None,
        "folder": folder,
        "tags": json.loads(tags_json) if tags_json else [],
        "tracks": [],
    }


@app.put("/user/playlists/{playlist_id}")
async def update_playlist(
    playlist_id: str,
    body: UpdatePlaylistRequest,
    payload: dict = Depends(get_current_user),
):
    user_id = payload["sub"]
    pool = await get_pool()
    async with pool.acquire() as conn:
        async with conn.cursor() as cur:
            await cur.execute(
                "SELECT id FROM ios_user_playlists WHERE id = %s AND user_id = %s",
                (playlist_id, user_id),
            )
            if not await cur.fetchone():
                raise HTTPException(status_code=404, detail="Playlist not found")

            updates = []
            values = []
            if body.name is not None:
                updates.append("name = %s")
                values.append(body.name)
            if body.description is not None:
                updates.append("description = %s")
                values.append(body.description)
            if body.folder is not None:
                updates.append("folder = %s")
                values.append(body.folder or None)
            if body.tags is not None:
                updates.append("tags_json = %s")
                values.append(json.dumps(body.tags))

            if updates:
                values.append(playlist_id)
                await cur.execute(
                    f"UPDATE ios_user_playlists SET {', '.join(updates)} WHERE id = %s",
                    values,
                )

            await cur.execute(
                "SELECT id, name, description, created_at, updated_at, folder, tags_json "
                "FROM ios_user_playlists WHERE id = %s",
                (playlist_id,),
            )
            row = await cur.fetchone()

    pl_id, name, description, created_at, updated_at, folder, tags_json = row
    return {
        "id": pl_id,
        "name": name,
        "description": description,
        "created_at": created_at.isoformat() if created_at else None,
        "updated_at": updated_at.isoformat() if updated_at else None,
        "folder": folder,
        "tags": json.loads(tags_json) if tags_json else [],
    }


@app.delete("/user/playlists/{playlist_id}", status_code=204)
async def delete_playlist(
    playlist_id: str,
    payload: dict = Depends(get_current_user),
):
    user_id = payload["sub"]
    pool = await get_pool()
    async with pool.acquire() as conn:
        async with conn.cursor() as cur:
            # Ownership check folded into the DELETE's WHERE clause (rather than a
            # separate SELECT-then-DELETE) so the two can't race or diverge — the
            # statement only ever removes a row this user actually owns.
            await cur.execute(
                "DELETE FROM ios_user_playlists WHERE id = %s AND user_id = %s",
                (playlist_id, user_id),
            )
            if cur.rowcount == 0:
                raise HTTPException(status_code=404, detail="Playlist not found")


@app.get("/user/playlists/{playlist_id}")
async def get_playlist(playlist_id: str, payload: dict = Depends(get_current_user)):
    """Returns one playlist (with tracks), for the owner or any collaborator
    (editor/viewer) — used to open playlists shared via "Shared with Me"."""
    user_id = payload["sub"]
    pool = await get_pool()
    async with pool.acquire() as conn:
        async with conn.cursor() as cur:
            role = await _playlist_role(cur, playlist_id, user_id)
            if role is None:
                raise HTTPException(status_code=404, detail="Playlist not found")

            await cur.execute(
                """
                SELECT p.id, p.name, p.description, p.created_at, p.updated_at,
                       p.folder, p.tags_json,
                       t.id, t.track_url, t.local_song_id, t.title, t.artist, t.album,
                       t.duration_seconds, t.position
                FROM ios_user_playlists p
                LEFT JOIN ios_playlist_tracks t ON t.playlist_id = p.id
                WHERE p.id = %s
                ORDER BY t.position ASC
                """,
                (playlist_id,),
            )
            rows = await cur.fetchall()

    if not rows:
        raise HTTPException(status_code=404, detail="Playlist not found")

    first = rows[0]
    pl_id, name, description, created_at, updated_at, folder, tags_json = first[:7]
    tracks = []
    for row in rows:
        t_id, t_url, t_local, t_title, t_artist, t_album, t_dur, t_pos = row[7:]
        if t_id is not None:
            tracks.append({
                "id": t_id, "track_url": t_url, "local_song_id": t_local, "title": t_title,
                "artist": t_artist, "album": t_album, "duration_seconds": t_dur, "position": t_pos,
            })

    return {
        "id": pl_id,
        "name": name,
        "description": description,
        "created_at": created_at.isoformat() if created_at else None,
        "updated_at": updated_at.isoformat() if updated_at else None,
        "folder": folder,
        "tags": json.loads(tags_json) if tags_json else [],
        "role": role,
        "tracks": tracks,
    }


# ---------------------------------------------------------------------------
# Favorites Endpoints
# ---------------------------------------------------------------------------


@app.get("/user/favorites")
async def get_favorites(payload: dict = Depends(get_current_user)):
    user_id = payload["sub"]
    pool = await get_pool()
    async with pool.acquire() as conn:
        async with conn.cursor() as cur:
            await cur.execute(
                """
                SELECT song_id, title, artist, album, added_at
                FROM ios_user_favorites
                WHERE user_id = %s
                ORDER BY added_at DESC
                """,
                (user_id,),
            )
            rows = await cur.fetchall()

    return [
        {
            "song_id": r[0],
            "title": r[1],
            "artist": r[2],
            "album": r[3],
            "added_at": r[4].isoformat() if r[4] else None,
        }
        for r in rows
    ]


@app.post("/user/favorites", status_code=201)
async def add_favorite(
    body: AddFavoriteRequest,
    payload: dict = Depends(get_current_user),
):
    user_id = payload["sub"]
    pool = await get_pool()
    async with pool.acquire() as conn:
        async with conn.cursor() as cur:
            await cur.execute(
                """
                INSERT INTO ios_user_favorites (user_id, song_id, title, artist, album)
                VALUES (%s, %s, %s, %s, %s)
                ON DUPLICATE KEY UPDATE title = VALUES(title), artist = VALUES(artist),
                    album = VALUES(album)
                """,
                (user_id, body.song_id, body.title, body.artist, body.album),
            )

    return {"song_id": body.song_id, "status": "added"}


@app.delete("/user/favorites/{song_id}", status_code=204)
async def remove_favorite(
    song_id: str,
    payload: dict = Depends(get_current_user),
):
    user_id = payload["sub"]
    pool = await get_pool()
    async with pool.acquire() as conn:
        async with conn.cursor() as cur:
            await cur.execute(
                "DELETE FROM ios_user_favorites WHERE user_id = %s AND song_id = %s",
                (user_id, song_id),
            )


# ---------------------------------------------------------------------------
# Play History Endpoints
# ---------------------------------------------------------------------------


@app.post("/user/history", status_code=201)
async def log_history(
    body: LogPlayRequest,
    payload: dict = Depends(get_current_user),
):
    user_id = payload["sub"]
    history_id = str(uuid.uuid4())
    pool = await get_pool()
    async with pool.acquire() as conn:
        async with conn.cursor() as cur:
            await cur.execute(
                """
                INSERT INTO ios_play_history
                    (id, user_id, track_url, local_song_id, title, artist, listen_seconds)
                VALUES (%s, %s, %s, %s, %s, %s, %s)
                """,
                (
                    history_id,
                    user_id,
                    body.track_url,
                    body.local_song_id,
                    body.title,
                    body.artist,
                    body.listen_seconds or 0,
                ),
            )

    # Fire-and-forget integrations: scrobble to linked Last.fm/ListenBrainz
    # accounts and post a "Now Playing" embed to a linked Discord webhook.
    # Neither should ever block or fail the history write itself.
    asyncio.create_task(_scrobble_track(user_id, body.title, body.artist, body.listen_seconds or 0))
    asyncio.create_task(_notify_now_playing_discord(user_id, body.title, body.artist))

    return {"id": history_id, "status": "logged"}


@app.get("/user/history")
async def get_history(
    limit: int = Query(50, ge=1, le=200),
    payload: dict = Depends(get_current_user),
):
    user_id = payload["sub"]
    pool = await get_pool()
    async with pool.acquire() as conn:
        async with conn.cursor() as cur:
            await cur.execute(
                """
                SELECT id, track_url, local_song_id, title, artist, played_at, listen_seconds
                FROM ios_play_history
                WHERE user_id = %s
                ORDER BY played_at DESC
                LIMIT %s
                """,
                (user_id, limit),
            )
            rows = await cur.fetchall()

    return [
        {
            "id": r[0],
            "track_url": r[1],
            "local_song_id": r[2],
            "title": r[3],
            "artist": r[4],
            "played_at": r[5].isoformat() if r[5] else None,
            "listen_seconds": r[6],
        }
        for r in rows
    ]


@app.get("/user/stats")
async def get_stats(payload: dict = Depends(get_current_user)):
    """Lifetime listening stats derived from ios_play_history: total plays,
    total listening time, and top artists/tracks. Powers an "Stats" summary
    on the Account screen."""
    user_id = payload["sub"]
    pool = await get_pool()
    async with pool.acquire() as conn:
        async with conn.cursor() as cur:
            await cur.execute(
                "SELECT COUNT(*), COALESCE(SUM(listen_seconds), 0) FROM ios_play_history WHERE user_id = %s",
                (user_id,),
            )
            total_plays, total_seconds = await cur.fetchone()

            await cur.execute(
                """
                SELECT artist, COUNT(*) AS plays
                FROM ios_play_history
                WHERE user_id = %s AND artist IS NOT NULL AND artist != ''
                GROUP BY artist
                ORDER BY plays DESC
                LIMIT 5
                """,
                (user_id,),
            )
            top_artists = await cur.fetchall()

            await cur.execute(
                """
                SELECT title, artist, COUNT(*) AS plays
                FROM ios_play_history
                WHERE user_id = %s AND title IS NOT NULL AND title != ''
                GROUP BY title, artist
                ORDER BY plays DESC
                LIMIT 5
                """,
                (user_id,),
            )
            top_tracks = await cur.fetchall()

    return {
        "total_plays": total_plays,
        "total_listen_seconds": int(total_seconds),
        "top_artists": [{"artist": r[0], "play_count": r[1]} for r in top_artists],
        "top_tracks": [{"title": r[0], "artist": r[1], "play_count": r[2]} for r in top_tracks],
    }


# ---------------------------------------------------------------------------
# User Settings Endpoints
# ---------------------------------------------------------------------------


@app.get("/user/settings")
async def get_settings(payload: dict = Depends(get_current_user)):
    user_id = payload["sub"]
    pool = await get_pool()
    async with pool.acquire() as conn:
        async with conn.cursor() as cur:
            await cur.execute(
                "SELECT audio_settings_json, track_audio_settings_json, theme_color, updated_at "
                "FROM ios_user_settings WHERE user_id = %s",
                (user_id,),
            )
            row = await cur.fetchone()

    if not row:
        return {
            "audio_settings_json": None,
            "track_audio_settings_json": None,
            "theme_color": "#EC4079",
            "updated_at": None,
        }

    return {
        "audio_settings_json": row[0],
        "track_audio_settings_json": row[1],
        "theme_color": row[2],
        "updated_at": row[3].isoformat() if row[3] else None,
    }


@app.put("/user/settings")
async def update_settings(
    body: UpdateSettingsRequest,
    payload: dict = Depends(get_current_user),
):
    user_id = payload["sub"]
    pool = await get_pool()
    async with pool.acquire() as conn:
        async with conn.cursor() as cur:
            # Upsert settings row
            await cur.execute(
                """
                INSERT INTO ios_user_settings
                    (user_id, audio_settings_json, track_audio_settings_json, theme_color)
                VALUES (%s, %s, %s, %s)
                ON DUPLICATE KEY UPDATE
                    audio_settings_json = IF(%s IS NULL, audio_settings_json, %s),
                    track_audio_settings_json = IF(%s IS NULL, track_audio_settings_json, %s),
                    theme_color = IF(%s IS NULL, theme_color, %s)
                """,
                (
                    user_id,
                    body.audio_settings_json,
                    body.track_audio_settings_json,
                    body.theme_color or "#EC4079",
                    body.audio_settings_json,
                    body.audio_settings_json,
                    body.track_audio_settings_json,
                    body.track_audio_settings_json,
                    body.theme_color,
                    body.theme_color,
                ),
            )
            await cur.execute(
                "SELECT audio_settings_json, track_audio_settings_json, theme_color, updated_at "
                "FROM ios_user_settings WHERE user_id = %s",
                (user_id,),
            )
            row = await cur.fetchone()

    return {
        "audio_settings_json": row[0],
        "track_audio_settings_json": row[1],
        "theme_color": row[2],
        "updated_at": row[3].isoformat() if row[3] else None,
    }


# ---------------------------------------------------------------------------
# Sync Endpoints
# ---------------------------------------------------------------------------


# ---------------------------------------------------------------------------
# Sync snapshots, backups, and audit log
# ---------------------------------------------------------------------------

# How many automatic backups to retain per user (oldest pruned beyond this).
_MAX_BACKUPS_PER_USER = 20


async def _build_sync_snapshot(cur, user_id: str) -> dict:
    """Gathers a user's favorites, playlists, and settings into the same
    shape returned by GET /user/sync. Used both to answer pull requests and
    to take backup snapshots before destructive writes."""
    # Favorites
    await cur.execute(
        "SELECT song_id, title, artist, album FROM ios_user_favorites WHERE user_id = %s",
        (user_id,),
    )
    fav_rows = await cur.fetchall()
    favorites = [
        {"song_id": r[0], "title": r[1], "artist": r[2], "album": r[3]}
        for r in fav_rows
    ]

    # Playlists with tracks — single JOIN, no N+1
    await cur.execute(
        """
        SELECT p.id, p.name, p.description, p.folder, p.tags_json,
               t.track_url, t.local_song_id, t.title, t.artist, t.album,
               t.duration_seconds, t.position
        FROM ios_user_playlists p
        LEFT JOIN ios_playlist_tracks t ON t.playlist_id = p.id
        WHERE p.user_id = %s
        ORDER BY p.updated_at DESC, t.position ASC
        """,
        (user_id,),
    )
    pl_join_rows = await cur.fetchall()
    pl_dict: dict[str, dict] = {}
    pl_order: list[str] = []
    for row in pl_join_rows:
        (pl_id, name, description, folder, tags_json,
         t_url, t_local, t_title, t_artist, t_album, t_dur, t_pos) = row
        if pl_id not in pl_dict:
            pl_dict[pl_id] = {
                "id": pl_id, "name": name, "description": description,
                "folder": folder, "tags": json.loads(tags_json) if tags_json else [],
                "tracks": [],
            }
            pl_order.append(pl_id)
        if t_url is not None or t_title is not None:
            pl_dict[pl_id]["tracks"].append({
                "track_url": t_url,
                "local_song_id": t_local,
                "title": t_title,
                "artist": t_artist,
                "album": t_album,
                "duration_seconds": t_dur,
                "position": t_pos,
            })
    playlists = [pl_dict[pid] for pid in pl_order]

    # Settings
    await cur.execute(
        "SELECT audio_settings_json, track_audio_settings_json, theme_color "
        "FROM ios_user_settings WHERE user_id = %s",
        (user_id,),
    )
    settings_row = await cur.fetchone()
    audio_settings_json = settings_row[0] if settings_row else None
    track_audio_settings_json = settings_row[1] if settings_row else None
    theme_color = settings_row[2] if settings_row else "#EC4079"

    return {
        "favorites": favorites,
        "playlists": playlists,
        "audio_settings_json": audio_settings_json,
        "track_audio_settings_json": track_audio_settings_json,
        "theme_color": theme_color,
    }


async def _apply_sync_snapshot(cur, user_id: str, snapshot: dict) -> None:
    """Replaces a user's favorites/playlists/settings with the contents of a
    snapshot dict (same shape as _build_sync_snapshot's return). Used to
    restore a backup, with the same replace-everything semantics as a normal
    sync push."""
    favorites = snapshot.get("favorites") or []
    playlists = snapshot.get("playlists") or []

    await cur.execute("DELETE FROM ios_user_favorites WHERE user_id = %s", (user_id,))
    if favorites:
        await cur.executemany(
            """
            INSERT INTO ios_user_favorites (user_id, song_id, title, artist, album)
            VALUES (%s, %s, %s, %s, %s)
            """,
            [
                (user_id, fav.get("song_id"), fav.get("title"), fav.get("artist"), fav.get("album"))
                for fav in favorites
            ],
        )

    await cur.execute("DELETE FROM ios_user_playlists WHERE user_id = %s", (user_id,))
    if playlists:
        await cur.executemany(
            """
            INSERT INTO ios_user_playlists (id, user_id, name, description)
            VALUES (%s, %s, %s, %s)
            """,
            [
                (pl.get("id") or str(uuid.uuid4()), user_id, pl.get("name"), pl.get("description"))
                for pl in playlists
            ],
        )
        all_track_rows = []
        for pl in playlists:
            pl_id = pl.get("id") or str(uuid.uuid4())
            for idx, track in enumerate(pl.get("tracks") or []):
                all_track_rows.append((
                    str(uuid.uuid4()),
                    pl_id,
                    track.get("track_url"),
                    track.get("local_song_id"),
                    track.get("title"),
                    track.get("artist"),
                    track.get("album"),
                    track.get("duration_seconds") or 0,
                    track.get("position") if track.get("position") is not None else idx,
                ))
        if all_track_rows:
            await cur.executemany(
                """
                INSERT INTO ios_playlist_tracks
                    (id, playlist_id, track_url, local_song_id, title, artist, album,
                     duration_seconds, position)
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
                """,
                all_track_rows,
            )

    await cur.execute(
        """
        INSERT INTO ios_user_settings
            (user_id, audio_settings_json, track_audio_settings_json, theme_color)
        VALUES (%s, %s, %s, %s)
        ON DUPLICATE KEY UPDATE
            audio_settings_json = %s,
            track_audio_settings_json = %s,
            theme_color = %s
        """,
        (
            user_id,
            snapshot.get("audio_settings_json"),
            snapshot.get("track_audio_settings_json"),
            snapshot.get("theme_color") or "#EC4079",
            snapshot.get("audio_settings_json"),
            snapshot.get("track_audio_settings_json"),
            snapshot.get("theme_color") or "#EC4079",
        ),
    )


async def _create_backup(cur, user_id: str, reason: str) -> None:
    """Snapshots the user's current sync data into ios_user_backups, then
    prunes old backups beyond _MAX_BACKUPS_PER_USER."""
    snapshot = await _build_sync_snapshot(cur, user_id)
    await cur.execute(
        "INSERT INTO ios_user_backups (id, user_id, reason, snapshot_json) VALUES (%s, %s, %s, %s)",
        (str(uuid.uuid4()), user_id, reason[:30], json.dumps(snapshot)),
    )
    await cur.execute(
        """
        DELETE FROM ios_user_backups
        WHERE user_id = %s
          AND id NOT IN (
              SELECT id FROM (
                  SELECT id FROM ios_user_backups
                  WHERE user_id = %s
                  ORDER BY created_at DESC
                  LIMIT %s
              ) AS keep
          )
        """,
        (user_id, user_id, _MAX_BACKUPS_PER_USER),
    )


async def _log_sync(cur, user_id: str, action: str, details: str = "") -> None:
    await cur.execute(
        "INSERT INTO ios_sync_log (user_id, action, details) VALUES (%s, %s, %s)",
        (user_id, action[:20], details[:255]),
    )


@app.get("/user/sync")
async def sync_pull(payload: dict = Depends(get_current_user)):
    user_id = payload["sub"]
    pool = await get_pool()
    async with pool.acquire() as conn:
        async with conn.cursor() as cur:
            snapshot = await _build_sync_snapshot(cur, user_id)
            await _log_sync(cur, user_id, "pull")

    return snapshot


@app.post("/user/sync")
async def sync_push(
    body: SyncPushRequest,
    payload: dict = Depends(get_current_user),
):
    user_id = payload["sub"]
    pool = await get_pool()
    async with pool.acquire() as conn:
        async with conn.cursor() as cur:
            # Snapshot current state before it's overwritten, so a bad push
            # (empty/corrupted client data) is always recoverable.
            await _create_backup(cur, user_id, "pre_push")
            await _log_sync(
                cur, user_id, "push",
                f"{len(body.favorites)} favorites, {len(body.playlists)} playlists",
            )

            # Replace favorites — batch upsert
            await cur.execute(
                "DELETE FROM ios_user_favorites WHERE user_id = %s", (user_id,)
            )
            if body.favorites:
                await cur.executemany(
                    """
                    INSERT INTO ios_user_favorites (user_id, song_id, title, artist, album)
                    VALUES (%s, %s, %s, %s, %s)
                    """,
                    [
                        (user_id, fav.song_id, fav.title, fav.artist, fav.album)
                        for fav in body.favorites
                    ],
                )

            # Replace playlists — batch insert playlists then all tracks in one shot
            await cur.execute(
                "DELETE FROM ios_user_playlists WHERE user_id = %s", (user_id,)
            )
            if body.playlists:
                await cur.executemany(
                    """
                    INSERT INTO ios_user_playlists (id, user_id, name, description, folder, tags_json)
                    VALUES (%s, %s, %s, %s, %s, %s)
                    """,
                    [
                        (pl.id or str(uuid.uuid4()), user_id, pl.name, pl.description,
                         pl.folder, json.dumps(pl.tags))
                        for pl in body.playlists
                    ],
                )
                # Collect all track rows across all playlists for a single executemany
                all_track_rows = []
                for pl in body.playlists:
                    pl_id = pl.id or str(uuid.uuid4())
                    for idx, track in enumerate(pl.tracks):
                        all_track_rows.append((
                            str(uuid.uuid4()),
                            pl_id,
                            track.track_url,
                            track.local_song_id,
                            track.title,
                            track.artist,
                            track.album,
                            track.duration_seconds or 0,
                            track.position if track.position is not None else idx,
                        ))
                if all_track_rows:
                    await cur.executemany(
                        """
                        INSERT INTO ios_playlist_tracks
                            (id, playlist_id, track_url, local_song_id, title, artist, album,
                             duration_seconds, position)
                        VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
                        """,
                        all_track_rows,
                    )

            # Update settings
            await cur.execute(
                """
                INSERT INTO ios_user_settings
                    (user_id, audio_settings_json, track_audio_settings_json, theme_color)
                VALUES (%s, %s, %s, %s)
                ON DUPLICATE KEY UPDATE
                    audio_settings_json = IF(%s IS NULL, audio_settings_json, %s),
                    track_audio_settings_json = IF(%s IS NULL, track_audio_settings_json, %s),
                    theme_color = IF(%s IS NULL, theme_color, %s)
                """,
                (
                    user_id,
                    body.audio_settings_json,
                    body.track_audio_settings_json,
                    body.theme_color or "#EC4079",
                    body.audio_settings_json,
                    body.audio_settings_json,
                    body.track_audio_settings_json,
                    body.track_audio_settings_json,
                    body.theme_color,
                    body.theme_color,
                ),
            )

    return {"status": "synced"}


@app.get("/user/backups")
async def list_backups(payload: dict = Depends(get_current_user)):
    """Lists this user's automatic sync backups (most recent first), without
    their full snapshot payloads — used to populate a restore picker."""
    user_id = payload["sub"]
    pool = await get_pool()
    async with pool.acquire() as conn:
        async with conn.cursor() as cur:
            await cur.execute(
                """
                SELECT id, reason, created_at,
                       JSON_LENGTH(JSON_EXTRACT(snapshot_json, '$.favorites')) AS favorite_count,
                       JSON_LENGTH(JSON_EXTRACT(snapshot_json, '$.playlists')) AS playlist_count
                FROM ios_user_backups
                WHERE user_id = %s
                ORDER BY created_at DESC
                """,
                (user_id,),
            )
            rows = await cur.fetchall()

    return {
        "backups": [
            {
                "id": r[0],
                "reason": r[1],
                "created_at": r[2].isoformat() if r[2] else None,
                "favorite_count": r[3] or 0,
                "playlist_count": r[4] or 0,
            }
            for r in rows
        ]
    }


@app.post("/user/backups/{backup_id}/restore")
async def restore_backup(backup_id: str, payload: dict = Depends(get_current_user)):
    """Restores a previous sync snapshot, replacing the user's current
    favorites/playlists/settings. The current state is itself backed up first
    (reason 'pre_restore'), so a restore can always be undone."""
    user_id = payload["sub"]
    pool = await get_pool()
    async with pool.acquire() as conn:
        async with conn.cursor() as cur:
            await cur.execute(
                "SELECT snapshot_json, created_at FROM ios_user_backups WHERE id = %s AND user_id = %s",
                (backup_id, user_id),
            )
            row = await cur.fetchone()
            if not row:
                raise HTTPException(status_code=404, detail="Backup not found")

            snapshot = json.loads(row[0])

            await _create_backup(cur, user_id, "pre_restore")
            await _apply_sync_snapshot(cur, user_id, snapshot)
            await _log_sync(cur, user_id, "restore", f"restored backup from {row[1].isoformat() if row[1] else backup_id}")

    return await sync_pull(payload)


# ---------------------------------------------------------------------------
# Social: listening activity & discovery
#
# Opt-in (ios_users.share_listening_activity, toggled via PUT /user/privacy).
# Only title/artist/played_at from ios_play_history is exposed — never file
# contents, URLs, or anything else from the account.
# ---------------------------------------------------------------------------


@app.get("/social/activity")
async def social_activity(
    limit: int = Query(30, ge=1, le=100),
    payload: dict = Depends(get_current_user),
):
    """Recent plays from users who've opted in to sharing listening activity,
    newest first. Powers a simple 'what others are listening to' feed."""
    pool = await get_pool()
    async with pool.acquire() as conn:
        async with conn.cursor() as cur:
            await cur.execute(
                """
                SELECT u.username, u.display_name, u.avatar_url,
                       h.title, h.artist, h.played_at
                FROM ios_play_history h
                JOIN ios_users u ON u.id = h.user_id
                WHERE u.share_listening_activity = TRUE AND u.is_active = TRUE
                ORDER BY h.played_at DESC
                LIMIT %s
                """,
                (limit,),
            )
            rows = await cur.fetchall()

    return {
        "activity": [
            {
                "username": r[0],
                "display_name": r[1],
                "avatar_url": r[2],
                "title": r[3],
                "artist": r[4],
                "played_at": r[5].isoformat() if r[5] else None,
            }
            for r in rows
        ]
    }


@app.get("/social/discover")
async def social_discover(
    days: int = Query(7, ge=1, le=90),
    limit: int = Query(20, ge=1, le=100),
    payload: dict = Depends(get_current_user),
):
    """Trending tracks — most-played title/artist pairs over the last `days`
    days, among users who've opted in to sharing listening activity."""
    pool = await get_pool()
    async with pool.acquire() as conn:
        async with conn.cursor() as cur:
            await cur.execute(
                """
                SELECT h.title, h.artist,
                       COUNT(*) AS play_count,
                       COUNT(DISTINCT h.user_id) AS listener_count
                FROM ios_play_history h
                JOIN ios_users u ON u.id = h.user_id
                WHERE u.share_listening_activity = TRUE AND u.is_active = TRUE
                  AND h.played_at >= NOW() - INTERVAL %s DAY
                  AND h.title IS NOT NULL AND h.title != ''
                GROUP BY h.title, h.artist
                ORDER BY play_count DESC, listener_count DESC
                LIMIT %s
                """,
                (days, limit),
            )
            rows = await cur.fetchall()

    return {
        "tracks": [
            {
                "title": r[0],
                "artist": r[1],
                "play_count": r[2],
                "listener_count": r[3],
            }
            for r in rows
        ]
    }


# ---------------------------------------------------------------------------
# Collaborative Playlist Endpoints
# ---------------------------------------------------------------------------

# Excludes visually ambiguous characters (0/O, 1/I/L) so codes are easy to
# read aloud, type, or transcribe by hand.
_SHARE_CODE_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
_SHARE_CODE_LENGTH = 8


def _generate_share_code() -> str:
    return "".join(secrets.choice(_SHARE_CODE_ALPHABET) for _ in range(_SHARE_CODE_LENGTH))


async def _unique_share_code(cur) -> str:
    """Generates a short share code, retrying on the rare collision."""
    for _ in range(10):
        code = _generate_share_code()
        await cur.execute(
            "SELECT 1 FROM ios_shared_playlists WHERE share_token = %s",
            (code,),
        )
        if not await cur.fetchone():
            return code
    raise HTTPException(status_code=500, detail="Could not generate a unique share code")


@app.post("/user/playlists/share", status_code=201)
async def share_playlist(
    body: SharePlaylistRequest,
    payload: dict = Depends(get_current_user),
):
    """Create a shareable snapshot of a playlist. Returns a short share code and deep-link URL."""
    user_id = payload["sub"]
    share_id = str(uuid.uuid4())

    playlist_data = json.dumps({
        "name": body.playlist_name,
        "tracks": body.tracks,
    })

    pool = await get_pool()
    async with pool.acquire() as conn:
        async with conn.cursor() as cur:
            # Fetch display name for the owner
            await cur.execute(
                "SELECT display_name, username FROM ios_users WHERE id = %s",
                (user_id,),
            )
            user_row = await cur.fetchone()
            if not user_row:
                raise HTTPException(status_code=401, detail="User not found")

            share_token = await _unique_share_code(cur)

            await cur.execute(
                """
                INSERT INTO ios_shared_playlists
                    (id, playlist_id, owner_user_id, share_token, playlist_data)
                VALUES (%s, %s, %s, %s, %s)
                """,
                (share_id, body.playlist_id, user_id, share_token, playlist_data),
            )

    share_url = f"lumisound://shared/{share_token}"
    logger.info("share_playlist: user %s shared playlist %s as code %s", user_id, body.playlist_id, share_token)
    return {"share_token": share_token, "share_url": share_url}


@app.get("/shared/{share_token}")
async def get_shared_playlist(share_token: str):
    """Public endpoint — returns a shared playlist snapshot by its token."""
    pool = await get_pool()
    async with pool.acquire() as conn:
        async with conn.cursor() as cur:
            await cur.execute(
                """
                SELECT sp.playlist_data, sp.created_at, sp.is_active,
                       u.display_name, u.username
                FROM ios_shared_playlists sp
                JOIN ios_users u ON u.id = sp.owner_user_id
                WHERE sp.share_token = %s
                """,
                (share_token,),
            )
            row = await cur.fetchone()

    if not row:
        raise HTTPException(status_code=404, detail="Shared playlist not found")

    playlist_data_raw, created_at, is_active, display_name, username = row

    if not is_active:
        raise HTTPException(status_code=404, detail="Shared playlist has been revoked")

    try:
        data = json.loads(playlist_data_raw) if isinstance(playlist_data_raw, str) else playlist_data_raw
    except (json.JSONDecodeError, TypeError):
        data = {}

    tracks = data.get("tracks", [])
    name = data.get("name", "Shared Playlist")
    owner = display_name or username

    return {
        "share_token": share_token,
        "name": name,
        "owner": owner,
        "tracks": tracks,
        "track_count": len(tracks),
        "created_at": created_at.isoformat() if created_at else None,
    }


@app.delete("/user/playlists/share/{share_token}", status_code=204)
async def revoke_shared_playlist(
    share_token: str,
    payload: dict = Depends(get_current_user),
):
    """Revoke a share token — only the owner can revoke."""
    user_id = payload["sub"]
    pool = await get_pool()
    async with pool.acquire() as conn:
        async with conn.cursor() as cur:
            await cur.execute(
                "SELECT owner_user_id, is_active FROM ios_shared_playlists WHERE share_token = %s",
                (share_token,),
            )
            row = await cur.fetchone()

    if not row:
        raise HTTPException(status_code=404, detail="Shared playlist not found")

    owner_user_id, is_active = row
    if owner_user_id != user_id:
        raise HTTPException(status_code=403, detail="You are not the owner of this shared playlist")

    async with pool.acquire() as conn:
        async with conn.cursor() as cur:
            # Re-check ownership in the UPDATE's WHERE clause itself — closes the
            # window between the SELECT above and this statement during which the
            # token could (in theory) have been re-assigned to another owner.
            await cur.execute(
                "UPDATE ios_shared_playlists SET is_active = FALSE WHERE share_token = %s AND owner_user_id = %s",
                (share_token, user_id),
            )

    logger.info("revoke_shared_playlist: user %s revoked share token %s", user_id, share_token)


# ---------------------------------------------------------------------------
# Server Music Library helpers
# ---------------------------------------------------------------------------

_FFPROBE_SEMAPHORE = asyncio.Semaphore(8)  # max 8 concurrent ffprobe processes

# Bounds concurrent ffmpeg analysis (_measure_loudness + _estimate_bpm) spawned
# per uploaded track. Without this, "Download All" with auto-cloud-backup enabled
# can fire dozens of uploads at once, each spawning two ffmpeg subprocesses with
# no limit — this previously exhausted host memory/CPU and crashed the bridge
# process outright (connection reset / 502 for every in-flight request).
_UPLOAD_ANALYSIS_SEMAPHORE = asyncio.Semaphore(3)


async def _ffprobe_tags(path: str) -> dict:
    """
    Run ffprobe on *path* and return a normalised track metadata dict.
    Results are cached by (path, mtime, size) to avoid redundant subprocess calls.
    Returns a dict with all fields set to sensible defaults on any failure.
    """
    abs_path = os.path.abspath(path)
    cached = _FFPROBE_CACHE.get(abs_path)
    if cached is not None:
        return cached

    cmd = [
        "ffprobe",
        "-v", "quiet",
        "-print_format", "json",
        "-show_streams",
        "-show_format",
        path,
    ]
    async with _FFPROBE_SEMAPHORE:
        try:
            proc = await asyncio.create_subprocess_exec(
                *cmd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
            )
            stdout_bytes, _ = await asyncio.wait_for(proc.communicate(), timeout=10.0)
        except asyncio.TimeoutError:
            logger.warning("ffprobe timed out for %s", path)
            return {}
        except Exception as exc:
            logger.warning("ffprobe error for %s: %s", path, exc)
            return {}

    try:
        data = json.loads(stdout_bytes)
    except json.JSONDecodeError:
        return {}

    streams = data.get("streams") or []

    # Find the primary audio stream for tags + duration
    audio_stream: dict = {}
    has_artwork = False
    for s in streams:
        codec_type = s.get("codec_type", "")
        codec_name = s.get("codec_name", "")
        if codec_type == "audio" and not audio_stream:
            audio_stream = s
        if codec_name in ("png", "mjpeg"):
            has_artwork = True

    # For MP4/M4A containers, ffprobe reports title/artist/album/etc. under
    # format.tags (the moov/udta/meta atom), not streams[].tags — stream tags
    # there are just language/handler_name. Other containers (FLAC, Opus/OGG
    # Vorbis comments) may put them on the stream instead, so merge both,
    # preferring format-level tags.
    tags: dict = {**(audio_stream.get("tags") or {}), **(data.get("format", {}).get("tags") or {})}
    # ffprobe stores tags in varying case depending on container
    tags_lower = {k.lower(): v for k, v in tags.items()}

    # Duration: prefer stream duration, fall back to format duration
    duration = 0.0
    raw_dur = audio_stream.get("duration") or data.get("format", {}).get("duration")
    if raw_dur:
        try:
            duration = float(raw_dur)
        except (ValueError, TypeError):
            duration = 0.0

    result = {
        "title": tags_lower.get("title") or tags_lower.get("name") or "",
        "artist": tags_lower.get("artist") or tags_lower.get("album_artist") or "",
        "album": tags_lower.get("album") or "",
        "genre": tags_lower.get("genre") or "",
        "track_number": tags_lower.get("track") or tags_lower.get("tracknumber") or "",
        "duration": duration,
        "has_artwork": has_artwork,
    }
    _FFPROBE_CACHE.put(abs_path, result)
    return result


def _stable_id(abs_path: str) -> str:
    """Return a stable 16-char hex ID based on the SHA-256 of the absolute path."""
    return hashlib.sha256(abs_path.encode()).hexdigest()[:16]


def _audio_media_type(ext: str) -> str:
    """Map a file extension (without dot, lower-case) to a MIME type."""
    mapping = {
        "opus": "audio/ogg",
        "ogg": "audio/ogg",
        "mp3": "audio/mpeg",
        "m4a": "audio/mp4",
        "m4v": "audio/mp4",
        "mp4": "audio/mp4",
        "aac": "audio/aac",
        "flac": "audio/flac",
        "wav": "audio/wav",
        "aif": "audio/aiff",
        "aiff": "audio/aiff",
        "caf": "audio/x-caf",
    }
    return mapping.get(ext, "application/octet-stream")


async def _measure_loudness(path: pathlib.Path) -> Optional[float]:
    """Runs ffmpeg's loudnorm filter in analysis mode and returns the
    integrated loudness (LUFS) of the file at `path`, or None on failure.
    Used for server-side ReplayGain-style normalization (Feature: loudness)."""
    cmd = [
        "ffmpeg", "-hide_banner", "-nostats",
        "-i", str(path),
        "-af", "loudnorm=print_format=json",
        "-f", "null", "-",
    ]
    try:
        proc = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.DEVNULL,
            stderr=asyncio.subprocess.PIPE,
        )
        _, stderr_bytes = await asyncio.wait_for(proc.communicate(), timeout=60.0)
    except Exception as exc:
        logger.warning("_measure_loudness: ffmpeg failed for %s: %s", path.name, exc)
        return None

    stderr_text = stderr_bytes.decode(errors="replace")
    # loudnorm prints a JSON block at the end of stderr output
    start = stderr_text.rfind("{")
    end = stderr_text.rfind("}")
    if start == -1 or end == -1 or end < start:
        return None
    try:
        stats = json.loads(stderr_text[start:end + 1])
        return float(stats["input_i"])
    except (ValueError, KeyError, TypeError) as exc:
        logger.warning("_measure_loudness: could not parse loudnorm output for %s: %s", path.name, exc)
        return None


# ---------------------------------------------------------------------------
# Server Music Library Endpoints
# ---------------------------------------------------------------------------


@app.get("/api/library/server")
async def server_library(
    search: str = Query("", description="Filter by title/artist"),
    limit: int = Query(200, ge=1, le=500),
):
    """Lists all music files in the server's music directory with metadata.
    Configure via SERVER_MUSIC_DIR environment variable."""
    if not SERVER_MUSIC_DIR:
        return {"tracks": [], "total": 0, "dir": None, "configured": False}

    music_root = pathlib.Path(SERVER_MUSIC_DIR).resolve()

    # Collect all matching audio files
    audio_files: list[pathlib.Path] = []
    try:
        for entry in music_root.rglob("*"):
            if entry.is_file() and entry.suffix.lower() in SUPPORTED_AUDIO_EXTS:
                audio_files.append(entry)
    except Exception as exc:
        logger.error("Error scanning SERVER_MUSIC_DIR %s: %s", music_root, exc)
        raise HTTPException(status_code=500, detail="Failed to scan music directory")

    # Run all ffprobe calls concurrently (bounded by _FFPROBE_SEMAPHORE)
    abs_paths = [str(f.resolve()) for f in audio_files]
    tag_results = await asyncio.gather(*(_ffprobe_tags(p) for p in abs_paths))
    await _FFPROBE_CACHE.flush()

    tracks: list[dict] = []
    for fpath, meta in zip(audio_files, tag_results):
        abs_path = str(fpath.resolve())
        try:
            rel_path = str(fpath.relative_to(music_root))
        except ValueError:
            rel_path = fpath.name

        ext = fpath.suffix.lstrip(".").lower()
        filename = fpath.name
        title = meta.get("title") or fpath.stem
        artist = meta.get("artist") or "Unknown Artist"

        # Apply search filter
        if search:
            search_lower = search.lower()
            if search_lower not in title.lower() and search_lower not in artist.lower():
                continue

        # Use embedded album tag; if absent, fall back to parent folder name so
        # tracks organised in subdirectories (e.g. Music/AlbumName/track.mp3)
        # are grouped correctly in the album view without requiring tags.
        album_name = meta.get("album") or ""
        if not album_name:
            parent = fpath.parent
            if parent.resolve() != music_root.resolve():
                album_name = parent.name

        tracks.append({
            "id": _stable_id(abs_path),
            "title": title,
            "artist": artist,
            "album": album_name,
            "duration": meta.get("duration") or 0.0,
            "genre": meta.get("genre") or "",
            "track_number": meta.get("track_number") or "",
            "has_artwork": meta.get("has_artwork") or False,
            "server_path": rel_path,
            "filename": filename,
            "ext": ext,
        })

    tracks.sort(key=lambda t: (t["artist"].lower(), t["album"].lower(), t["title"].lower()))
    total = len(tracks)
    tracks = tracks[:limit]

    return {
        "tracks": tracks,
        "total": total,
        "dir": str(music_root),
    }


@app.get("/api/library/server/stream")
async def server_stream(
    path: str = Query(..., description="Relative path within SERVER_MUSIC_DIR"),
):
    """Streams an audio file from the server music directory."""
    if not SERVER_MUSIC_DIR:
        raise HTTPException(status_code=404, detail="Server music library not configured")
    music_root = pathlib.Path(SERVER_MUSIC_DIR).resolve()
    full_path = (music_root / path).resolve()

    # Path traversal guard
    if not full_path.is_relative_to(music_root):
        raise HTTPException(status_code=403, detail="Access denied")

    if not full_path.exists() or not full_path.is_file():
        raise HTTPException(status_code=404, detail="File not found")

    ext = full_path.suffix.lstrip(".").lower()
    media_type = _audio_media_type(ext)

    return FileResponse(
        path=str(full_path),
        media_type=media_type,
        filename=full_path.name,
    )


@app.get("/api/library/server/artwork")
async def server_artwork(
    path: str = Query(..., description="Relative path within SERVER_MUSIC_DIR"),
):
    """Extracts embedded album art from a server file and returns it as JPEG."""
    if not SERVER_MUSIC_DIR:
        raise HTTPException(status_code=404, detail="Server music library not configured")
    music_root = pathlib.Path(SERVER_MUSIC_DIR).resolve()
    full_path = (music_root / path).resolve()

    # Path traversal guard
    if not full_path.is_relative_to(music_root):
        raise HTTPException(status_code=403, detail="Access denied")

    if not full_path.exists() or not full_path.is_file():
        raise HTTPException(status_code=404, detail="File not found")

    cmd = [
        "ffmpeg",
        "-i", str(full_path),
        "-map", "0:v",
        "-frames:v", "1",
        "-f", "image2",
        "-vcodec", "copy",
        "-",
    ]
    try:
        proc = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        stdout_bytes, _ = await asyncio.wait_for(proc.communicate(), timeout=10.0)
    except asyncio.TimeoutError:
        raise HTTPException(status_code=408, detail="Artwork extraction timed out")
    except Exception as exc:
        logger.error("ffmpeg artwork error for %s: %s", full_path, exc)
        raise HTTPException(status_code=500, detail="Artwork extraction failed")

    if not stdout_bytes:
        raise HTTPException(status_code=404, detail="No embedded artwork found")

    from fastapi.responses import Response
    return Response(content=stdout_bytes, media_type="image/jpeg")


# ---------------------------------------------------------------------------
# Per-user Music Library Endpoints
# ---------------------------------------------------------------------------

def _resolve_user_music_root() -> Optional[pathlib.Path]:
    """Returns the base directory for per-user music, or None if unconfigured."""
    if USER_MUSIC_DIR:
        return pathlib.Path(USER_MUSIC_DIR).resolve()
    if SERVER_MUSIC_DIR:
        return (pathlib.Path(SERVER_MUSIC_DIR) / "users").resolve()
    return None


def _user_music_dir(user_id: str) -> Optional[pathlib.Path]:
    root = _resolve_user_music_root()
    if root is None:
        return None
    return root / user_id


@app.get("/user/music")
async def get_user_music(
    search: str = Query("", description="Filter by title/artist/album"),
    limit: int = Query(200, ge=1, le=500),
    user: dict = Depends(get_current_user),
):
    """Lists all music files in the authenticated user's personal server directory."""
    user_id = user["sub"]
    music_dir = _user_music_dir(user_id)
    if music_dir is None:
        return {"tracks": [], "total": 0, "configured": False}

    music_dir.mkdir(parents=True, exist_ok=True)

    audio_files: list[pathlib.Path] = []
    try:
        for entry in music_dir.rglob("*"):
            if entry.is_file() and entry.suffix.lower() in SUPPORTED_AUDIO_EXTS:
                audio_files.append(entry)
    except Exception as exc:
        logger.error("Error scanning user music dir for %s: %s", user_id, exc)
        raise HTTPException(status_code=500, detail="Failed to scan music directory")

    abs_paths = [str(f.resolve()) for f in audio_files]
    tag_results = await asyncio.gather(*(_ffprobe_tags(p) for p in abs_paths))
    await _FFPROBE_CACHE.flush()

    tracks: list[dict] = []
    for fpath, meta in zip(audio_files, tag_results):
        abs_path = str(fpath.resolve())
        try:
            rel_path = str(fpath.relative_to(music_dir))
        except ValueError:
            rel_path = fpath.name

        ext = fpath.suffix.lstrip(".").lower()
        title = meta.get("title") or fpath.stem
        artist = meta.get("artist") or "Unknown Artist"
        album_name = meta.get("album") or ""
        if not album_name:
            parent = fpath.parent
            if parent.resolve() != music_dir.resolve():
                album_name = parent.name

        if search:
            q = search.lower()
            if q not in title.lower() and q not in artist.lower() and q not in album_name.lower():
                continue

        tracks.append({
            "id": _stable_id(abs_path),
            "title": title,
            "artist": artist,
            "album": album_name,
            "duration": meta.get("duration") or 0.0,
            "genre": meta.get("genre") or "",
            "track_number": meta.get("track_number") or "",
            "has_artwork": meta.get("has_artwork") or False,
            "server_path": rel_path,
            "filename": fpath.name,
            "ext": ext,
        })

    tracks.sort(key=lambda t: (t["album"].lower(), t["title"].lower()))
    total = len(tracks)
    return {"tracks": tracks[:limit], "total": total, "configured": True}


@app.post("/user/music/upload", status_code=201)
async def upload_user_music(
    request: Request,
    filename: str = Query(..., description="Destination filename (e.g. song.mp3)"),
    folder: str = Query("", description="Optional subfolder inside user's music dir"),
    title: Optional[str] = Query(None, description="Track title metadata"),
    artist: Optional[str] = Query(None, description="Track artist metadata"),
    album: Optional[str] = Query(None, description="Track album metadata"),
    genre: Optional[str] = Query(None, description="Track genre metadata"),
    year: Optional[str] = Query(None, description="Track year metadata"),
    duration: Optional[float] = Query(None, description="Duration in seconds"),
    bitrate: Optional[int] = Query(None, description="Bitrate in kbps"),
    sample_rate: Optional[int] = Query(None, description="Sample rate in Hz"),
    user: dict = Depends(get_current_user),
):
    """
    Uploads raw audio bytes to the authenticated user's personal music directory.
    Max 100 MB. The Content-Type header should match the audio format.
    Optionally populates ios_user_music_metadata when metadata query params are provided.
    """
    user_id = user["sub"]
    music_dir = _user_music_dir(user_id)
    if music_dir is None:
        raise HTTPException(status_code=503, detail="User music storage not configured on server")

    # Sanitise the destination filename
    safe_name = pathlib.Path(filename).name.replace("..", "").strip()
    if not safe_name or pathlib.Path(safe_name).suffix.lower().lstrip(".") not in {
        e.lstrip(".") for e in SUPPORTED_AUDIO_EXTS
    }:
        raise HTTPException(status_code=400, detail="Unsupported or invalid filename")

    folder_clean = folder.strip("/")
    dest_dir = (music_dir / folder_clean) if folder_clean else music_dir
    # Reject `folder` values containing ".." (or absolute paths re-rooted by
    # pathlib) that would resolve outside the user's music directory — without
    # this check a client could write arbitrary files anywhere on disk that the
    # bridge process can reach (e.g. folder="../../../etc/cron.d").
    music_root = music_dir.resolve()
    try:
        resolved_dest_dir = dest_dir.resolve()
        resolved_dest_dir.relative_to(music_root)
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid folder path")
    dest_dir = resolved_dest_dir
    dest_dir.mkdir(parents=True, exist_ok=True)
    dest_path = dest_dir / safe_name

    body = await request.body()
    if not body:
        raise HTTPException(status_code=400, detail="Empty file body")
    if len(body) > 100 * 1024 * 1024:  # 100 MB
        raise HTTPException(status_code=413, detail="File too large (max 100 MB)")

    # Compute content SHA-256 as the metadata row ID. Offloaded to a thread —
    # hashing a 100 MB body synchronously on the event loop would stall every
    # other request for the duration, compounding under concurrent uploads.
    content_hash = await asyncio.to_thread(lambda: hashlib.sha256(body).hexdigest())

    # Duplicate detection: if this exact content was already uploaded by this
    # user (under any filename) and the file is still on disk, skip the write
    # entirely and point the client at the existing copy.
    pool = await get_pool()
    async with pool.acquire() as conn:
        async with conn.cursor() as cur:
            await cur.execute(
                "SELECT filename FROM ios_user_music_metadata WHERE id = %s AND user_id = %s",
                (content_hash, user_id),
            )
            existing = await cur.fetchone()
    if existing:
        existing_path = music_dir / existing[0]
        if existing_path.exists():
            logger.info("upload_user_music: duplicate of %s for user %s, skipping write", existing[0], user_id)
            try:
                existing_rel = str(existing_path.relative_to(music_dir))
            except ValueError:
                existing_rel = existing[0]
            return {
                "filename": existing[0],
                "path": existing_rel,
                "id": _stable_id(str(existing_path.resolve())),
                "metadata_id": content_hash,
                "size": existing_path.stat().st_size,
                "duplicate": True,
            }

    try:
        await asyncio.to_thread(dest_path.write_bytes, body)
    except Exception as exc:
        logger.error("upload_user_music: write failed for user %s: %s", user_id, exc)
        raise HTTPException(status_code=500, detail="Failed to save file")

    logger.info("upload_user_music: saved %s for user %s (%d bytes)", safe_name, user_id, len(body))
    abs_path = str(dest_path.resolve())
    try:
        rel = str(dest_path.relative_to(music_dir))
    except ValueError:
        rel = safe_name

    # Determine MIME type from extension
    ext_lower = pathlib.Path(safe_name).suffix.lstrip(".").lower()
    mime_type = _audio_media_type(ext_lower)

    # Server-side loudness analysis (ReplayGain-style) via ffmpeg's loudnorm
    # filter, and tempo (BPM) estimate for crossfade/gapless tuning. Bounded by
    # _UPLOAD_ANALYSIS_SEMAPHORE so a burst of uploads (e.g. "Download All" with
    # auto-cloud-backup) can't spawn unlimited concurrent ffmpeg processes.
    async with _UPLOAD_ANALYSIS_SEMAPHORE:
        loudness_lufs = await _measure_loudness(dest_path)
        bpm = await _estimate_bpm(dest_path)

    # Populate ios_user_music_metadata when metadata is provided
    try:
        async with pool.acquire() as conn:
            async with conn.cursor() as cur:
                await cur.execute(
                    """
                    INSERT INTO ios_user_music_metadata
                        (id, user_id, filename, original_filename, title, artist, album,
                         genre, year, duration_seconds, file_size_bytes, bitrate,
                         sample_rate, mime_type, has_artwork, loudness_lufs, bpm)
                    VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
                    ON DUPLICATE KEY UPDATE
                        filename = VALUES(filename),
                        title = IF(VALUES(title) IS NULL, title, VALUES(title)),
                        artist = IF(VALUES(artist) IS NULL, artist, VALUES(artist)),
                        album = IF(VALUES(album) IS NULL, album, VALUES(album)),
                        genre = IF(VALUES(genre) IS NULL, genre, VALUES(genre)),
                        year = IF(VALUES(year) IS NULL, year, VALUES(year)),
                        duration_seconds = IF(VALUES(duration_seconds) IS NULL, duration_seconds, VALUES(duration_seconds)),
                        file_size_bytes = VALUES(file_size_bytes),
                        bitrate = IF(VALUES(bitrate) IS NULL, bitrate, VALUES(bitrate)),
                        sample_rate = IF(VALUES(sample_rate) IS NULL, sample_rate, VALUES(sample_rate)),
                        mime_type = VALUES(mime_type),
                        loudness_lufs = IF(VALUES(loudness_lufs) IS NULL, loudness_lufs, VALUES(loudness_lufs)),
                        bpm = IF(VALUES(bpm) IS NULL, bpm, VALUES(bpm))
                    """,
                    (
                        content_hash,
                        user_id,
                        safe_name,
                        filename,
                        title,
                        artist,
                        album,
                        genre,
                        year,
                        duration,
                        len(body),
                        bitrate,
                        sample_rate,
                        mime_type,
                        False,
                        loudness_lufs,
                        bpm,
                    ),
                )
    except Exception as exc:
        logger.warning("upload_user_music: metadata insert failed for %s: %s", safe_name, exc)
        # Non-fatal — file was already saved successfully

    return {
        "filename": safe_name,
        "path": rel,
        "id": _stable_id(abs_path),
        "loudness_lufs": loudness_lufs,
        "bpm": bpm,
        "metadata_id": content_hash,
        "size": len(body),
    }


@app.get("/user/music/stream")
async def stream_user_music(
    path: str = Query(..., description="Relative path within user's music dir"),
    user: dict = Depends(get_current_user),
):
    """Streams an audio file from the authenticated user's personal music directory."""
    user_id = user["sub"]
    music_dir = _user_music_dir(user_id)
    if music_dir is None:
        raise HTTPException(status_code=503, detail="User music storage not configured")

    full_path = (music_dir / path).resolve()
    if not full_path.is_relative_to(music_dir):
        raise HTTPException(status_code=403, detail="Access denied")
    if not full_path.exists() or not full_path.is_file():
        raise HTTPException(status_code=404, detail="File not found")

    ext = full_path.suffix.lstrip(".").lower()
    return FileResponse(path=str(full_path), media_type=_audio_media_type(ext), filename=full_path.name)


@app.get("/user/music/artwork")
async def user_music_artwork(
    path: str = Query(..., description="Relative path within user's music dir"),
    user: dict = Depends(get_current_user),
):
    """Extracts embedded album art from a user music file and returns it as JPEG."""
    user_id = user["sub"]
    music_dir = _user_music_dir(user_id)
    if music_dir is None:
        raise HTTPException(status_code=503, detail="User music storage not configured")

    full_path = (music_dir / path).resolve()
    if not full_path.is_relative_to(music_dir):
        raise HTTPException(status_code=403, detail="Access denied")
    if not full_path.exists() or not full_path.is_file():
        raise HTTPException(status_code=404, detail="File not found")

    cmd = ["ffmpeg", "-i", str(full_path), "-map", "0:v", "-frames:v", "1", "-f", "image2", "-vcodec", "copy", "-"]
    try:
        proc = await asyncio.create_subprocess_exec(*cmd, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE)
        stdout_bytes, _ = await asyncio.wait_for(proc.communicate(), timeout=10.0)
    except asyncio.TimeoutError:
        raise HTTPException(status_code=408, detail="Artwork extraction timed out")
    except Exception as exc:
        raise HTTPException(status_code=500, detail="Artwork extraction failed")

    if not stdout_bytes:
        raise HTTPException(status_code=404, detail="No embedded artwork found")

    from fastapi.responses import Response
    return Response(content=stdout_bytes, media_type="image/jpeg")


@app.delete("/user/music/{filepath:path}", status_code=204)
async def delete_user_music(
    filepath: str,
    user: dict = Depends(get_current_user),
):
    """Deletes a file from the authenticated user's personal music directory."""
    user_id = user["sub"]
    music_dir = _user_music_dir(user_id)
    if music_dir is None:
        raise HTTPException(status_code=503, detail="User music storage not configured")

    full_path = (music_dir / filepath).resolve()
    if not full_path.is_relative_to(music_dir):
        raise HTTPException(status_code=403, detail="Access denied")
    if not full_path.exists():
        raise HTTPException(status_code=404, detail="File not found")

    try:
        full_path.unlink()
        # Remove empty parent directories up to the user root
        parent = full_path.parent
        while parent != music_dir and parent.exists():
            try:
                parent.rmdir()  # only removes if empty
                parent = parent.parent
            except OSError:
                break
    except Exception as exc:
        logger.error("delete_user_music: failed for user %s path %s: %s", user_id, filepath, exc)
        raise HTTPException(status_code=500, detail="Failed to delete file")


# ---------------------------------------------------------------------------
# User Music Metadata Endpoint
# ---------------------------------------------------------------------------

_USER_MUSIC_METADATA_COLS = [
    "id", "user_id", "filename", "original_filename", "title", "artist", "album",
    "genre", "year", "duration_seconds", "file_size_bytes", "bitrate", "sample_rate",
    "mime_type", "has_artwork", "uploaded_at", "loudness_lufs", "bpm",
]


@app.get("/user/music/metadata")
async def list_user_music_metadata(
    limit: int = Query(200, ge=1, le=500),
    user: dict = Depends(get_current_user),
):
    """Returns rich metadata rows for all uploaded tracks belonging to this user."""
    user_id = user["sub"]
    pool = await get_pool()
    async with pool.acquire() as conn:
        async with conn.cursor() as cur:
            await cur.execute(
                """
                SELECT id, user_id, filename, original_filename, title, artist, album,
                       genre, year, duration_seconds, file_size_bytes, bitrate, sample_rate,
                       mime_type, has_artwork, uploaded_at, loudness_lufs, bpm
                FROM ios_user_music_metadata
                WHERE user_id = %s
                ORDER BY uploaded_at DESC
                LIMIT %s
                """,
                (user_id, limit),
            )
            rows = await cur.fetchall()

    base_url = ""
    music_dir = _user_music_dir(user_id)

    result = []
    for row in rows:
        d = dict(zip(_USER_MUSIC_METADATA_COLS, row))
        d["uploaded_at"] = d["uploaded_at"].isoformat() if d["uploaded_at"] else None
        d["has_artwork"] = bool(d["has_artwork"])
        # Add artwork URL if has_artwork and file exists on disk
        if d["has_artwork"] and music_dir:
            encoded = d["filename"].replace(" ", "%20")
            d["artwork_url"] = f"/user/music/artwork?path={encoded}"
        else:
            d["artwork_url"] = None
        # Remove server-internal field from public response
        d.pop("user_id", None)
        result.append(d)

    return {"tracks": result, "total": len(result)}


# ---------------------------------------------------------------------------
# User Gallery Image Endpoints
# ---------------------------------------------------------------------------

_GALLERY_DIR_NAME = "gallery"
_MAX_GALLERY_IMAGE_BYTES = 10 * 1024 * 1024  # 10 MB


def _user_gallery_dir(user_id: str) -> Optional[pathlib.Path]:
    base = _user_music_dir(user_id)
    if base is None:
        return None
    return base / _GALLERY_DIR_NAME


@app.get("/user/gallery/images")
async def list_gallery_images(
    user: dict = Depends(get_current_user),
):
    """Returns cloud-synced gallery images for the authenticated user."""
    user_id = user["sub"]
    pool = await get_pool()
    async with pool.acquire() as conn:
        async with conn.cursor() as cur:
            await cur.execute(
                """
                SELECT id, filename, display_order, uploaded_at
                FROM ios_user_gallery_images
                WHERE user_id = %s
                ORDER BY display_order ASC, uploaded_at DESC
                """,
                (user_id,),
            )
            rows = await cur.fetchall()

    return [
        {
            "id": r[0],
            "filename": r[1],
            "display_order": r[2],
            "uploaded_at": r[3].isoformat() if r[3] else None,
            "url": f"/user/gallery/images/{r[0]}",
        }
        for r in rows
    ]


@app.post("/user/gallery/images", status_code=201)
async def upload_gallery_image(
    file: UploadFile = File(...),
    display_order: int = Query(0, description="Sort order for display"),
    user: dict = Depends(get_current_user),
):
    """Upload a JPEG gallery image (max 10 MB) for the authenticated user."""
    user_id = user["sub"]
    gallery_dir = _user_gallery_dir(user_id)
    if gallery_dir is None:
        raise HTTPException(status_code=503, detail="User storage not configured on server")

    gallery_dir.mkdir(parents=True, exist_ok=True)

    # Validate content type
    content_type = file.content_type or ""
    if content_type not in ("image/jpeg", "image/jpg", "image/png", "image/webp"):
        raise HTTPException(
            status_code=400,
            detail="Unsupported image type. Use JPEG, PNG, or WebP."
        )

    body = await file.read()
    if not body:
        raise HTTPException(status_code=400, detail="Empty file body")
    if len(body) > _MAX_GALLERY_IMAGE_BYTES:
        raise HTTPException(status_code=413, detail="Image too large (max 10 MB)")

    image_id = str(uuid.uuid4())
    # Always store as .jpg filename regardless of source type
    ext = "jpg"
    stored_filename = f"{image_id}.{ext}"
    dest_path = gallery_dir / stored_filename

    try:
        dest_path.write_bytes(body)
    except Exception as exc:
        logger.error("upload_gallery_image: write failed for user %s: %s", user_id, exc)
        raise HTTPException(status_code=500, detail="Failed to save image")

    pool = await get_pool()
    async with pool.acquire() as conn:
        async with conn.cursor() as cur:
            await cur.execute(
                """
                INSERT INTO ios_user_gallery_images (id, user_id, filename, display_order)
                VALUES (%s, %s, %s, %s)
                """,
                (image_id, user_id, stored_filename, display_order),
            )
            await cur.execute(
                "SELECT id, filename, display_order, uploaded_at FROM ios_user_gallery_images WHERE id = %s",
                (image_id,),
            )
            row = await cur.fetchone()

    logger.info("upload_gallery_image: saved %s for user %s (%d bytes)", stored_filename, user_id, len(body))
    return {
        "id": row[0],
        "filename": row[1],
        "display_order": row[2],
        "uploaded_at": row[3].isoformat() if row[3] else None,
        "url": f"/user/gallery/images/{row[0]}",
    }


@app.get("/user/gallery/images/{image_id}")
async def get_gallery_image(
    image_id: str,
    user: dict = Depends(get_current_user),
):
    """Serves a gallery image file (authenticated)."""
    user_id = user["sub"]
    pool = await get_pool()
    async with pool.acquire() as conn:
        async with conn.cursor() as cur:
            await cur.execute(
                "SELECT filename FROM ios_user_gallery_images WHERE id = %s AND user_id = %s",
                (image_id, user_id),
            )
            row = await cur.fetchone()

    if not row:
        raise HTTPException(status_code=404, detail="Image not found")

    gallery_dir = _user_gallery_dir(user_id)
    if gallery_dir is None:
        raise HTTPException(status_code=503, detail="User storage not configured")

    image_path = (gallery_dir / row[0]).resolve()
    if not image_path.is_relative_to(gallery_dir.resolve()):
        raise HTTPException(status_code=403, detail="Access denied")

    if not image_path.exists() or not image_path.is_file():
        raise HTTPException(status_code=404, detail="Image file not found on disk")

    return FileResponse(path=str(image_path), media_type="image/jpeg", filename=row[0])


@app.delete("/user/gallery/images/{image_id}", status_code=204)
async def delete_gallery_image(
    image_id: str,
    user: dict = Depends(get_current_user),
):
    """Deletes a gallery image (DB row + file on disk)."""
    user_id = user["sub"]
    pool = await get_pool()
    async with pool.acquire() as conn:
        async with conn.cursor() as cur:
            await cur.execute(
                "SELECT filename FROM ios_user_gallery_images WHERE id = %s AND user_id = %s",
                (image_id, user_id),
            )
            row = await cur.fetchone()
            if not row:
                raise HTTPException(status_code=404, detail="Image not found")

            await cur.execute(
                "DELETE FROM ios_user_gallery_images WHERE id = %s AND user_id = %s",
                (image_id, user_id),
            )

    gallery_dir = _user_gallery_dir(user_id)
    if gallery_dir is not None:
        image_path = (gallery_dir / row[0]).resolve()
        if image_path.is_relative_to(gallery_dir.resolve()) and image_path.exists():
            try:
                image_path.unlink()
            except Exception as exc:
                logger.warning("delete_gallery_image: could not remove file %s: %s", image_path, exc)


# ---------------------------------------------------------------------------
# Lyrics (Feature: lyrics sync)
# ---------------------------------------------------------------------------


@app.get("/api/lyrics")
async def get_lyrics(
    request: Request,
    title: str = Query(..., min_length=1, max_length=200),
    artist: str = Query("", max_length=200),
    duration: Optional[int] = Query(None, description="Track duration in seconds, improves matching"),
):
    """Fetches synced (LRC) or plain lyrics for a track from the public
    lrclib.net API. Returns 404 if no match is found."""
    await check_auth(request)

    params = {"track_name": title, "artist_name": artist}
    if duration:
        params["duration"] = str(duration)
    query = "&".join(f"{k}={urllib.parse.quote(v)}" for k, v in params.items())
    url = f"https://lrclib.net/api/get?{query}"

    def _fetch() -> Optional[dict]:
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "Lumisound-iOS-Bridge/1.0"})
            with urllib.request.urlopen(req, timeout=10) as resp:
                return json.loads(resp.read().decode("utf-8"))
        except Exception:
            return None

    data = await asyncio.to_thread(_fetch)
    if not data or (not data.get("syncedLyrics") and not data.get("plainLyrics")):
        raise HTTPException(status_code=404, detail="No lyrics found")

    return {
        "title": data.get("trackName") or title,
        "artist": data.get("artistName") or artist,
        "synced_lyrics": data.get("syncedLyrics") or None,
        "plain_lyrics": data.get("plainLyrics") or None,
        "instrumental": bool(data.get("instrumental", False)),
    }


# ---------------------------------------------------------------------------
# Radio / Playlist Auto-Continuation (Feature: radio)
# ---------------------------------------------------------------------------


@app.get("/api/radio")
async def get_radio(
    request: Request,
    id: str = Query(..., description="Seed video/track ID"),
    source: str = Query("youtube", description="youtube or soundcloud"),
    limit: int = Query(20, ge=1, le=50, description="Max tracks to return"),
):
    """Returns a list of related tracks that continue from the seed track,
    using YouTube's auto-generated "Mix" playlist (RD<id>). SoundCloud has no
    equivalent mix concept, so this is youtube-only for now."""
    await check_auth(request)

    if source.lower() != "youtube":
        raise HTTPException(status_code=400, detail="Radio is only supported for source=youtube")

    mix_url = f"https://www.youtube.com/watch?v={id}&list=RD{id}"
    try:
        entries = await _run_ytdlp(
            "--dump-json",
            "--flat-playlist",
            "--no-warnings",
            *_ytdlp_cookie_args(),
            mix_url,
            timeout=30.0,
        )
    except asyncio.TimeoutError:
        raise HTTPException(status_code=408, detail="Radio resolve timed out")
    except Exception as exc:
        logger.error("yt-dlp radio error: %s", exc)
        raise HTTPException(status_code=404, detail="Could not build radio")

    # Drop the seed track itself and cap to `limit`.
    tracks = [_parse_track(e, "youtube") for e in entries if e.get("id") != id]
    return tracks[:limit]


# ---------------------------------------------------------------------------
# Cross-Device Continue Listening (Feature: playback-state)
# ---------------------------------------------------------------------------


@app.get("/user/playback-state")
async def get_playback_state(payload: dict = Depends(get_current_user)):
    """Returns the most recently saved playback position for this user, so
    another device can resume where the last one left off."""
    user_id = payload["sub"]
    pool = await get_pool()
    async with pool.acquire() as conn:
        async with conn.cursor() as cur:
            await cur.execute(
                """
                SELECT song_id, title, artist, track_url, source,
                       position_seconds, duration_seconds, updated_at, is_playing
                FROM ios_playback_state WHERE user_id = %s
                """,
                (user_id,),
            )
            row = await cur.fetchone()

    if not row:
        return None

    return {
        "song_id": row[0],
        "title": row[1],
        "artist": row[2],
        "track_url": row[3],
        "source": row[4],
        "position_seconds": row[5],
        "duration_seconds": row[6],
        "updated_at": row[7].isoformat() if row[7] else None,
        "is_playing": bool(row[8]),
    }


@app.put("/user/playback-state", status_code=204)
async def update_playback_state(
    body: PlaybackStateRequest,
    payload: dict = Depends(get_current_user),
):
    user_id = payload["sub"]
    pool = await get_pool()
    async with pool.acquire() as conn:
        async with conn.cursor() as cur:
            await cur.execute(
                """
                INSERT INTO ios_playback_state
                    (user_id, song_id, title, artist, track_url, source, position_seconds, duration_seconds, is_playing)
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
                ON DUPLICATE KEY UPDATE
                    song_id = VALUES(song_id), title = VALUES(title), artist = VALUES(artist),
                    track_url = VALUES(track_url), source = VALUES(source),
                    position_seconds = VALUES(position_seconds), duration_seconds = VALUES(duration_seconds),
                    is_playing = VALUES(is_playing)
                """,
                (
                    user_id, body.song_id, body.title, body.artist, body.track_url,
                    body.source, body.position_seconds, body.duration_seconds, body.is_playing,
                ),
            )


# ---------------------------------------------------------------------------
# Shared Listening Rooms (Feature: listen-rooms)
# ---------------------------------------------------------------------------


def _generate_room_code() -> str:
    alphabet = string.ascii_uppercase + string.digits
    return "".join(secrets.choice(alphabet) for _ in range(6))


@app.post("/rooms", status_code=201)
async def create_room(
    body: CreateRoomRequest,
    payload: dict = Depends(get_current_user),
):
    """Creates a shared listening room. The host's currently-playing track and
    position are broadcast via room_code; other users can poll GET /rooms/{code}
    to follow along ("listen together")."""
    user_id = payload["sub"]
    room_id = str(uuid.uuid4())
    pool = await get_pool()
    async with pool.acquire() as conn:
        async with conn.cursor() as cur:
            for _ in range(5):
                room_code = _generate_room_code()
                try:
                    await cur.execute(
                        """
                        INSERT INTO ios_listen_rooms
                            (id, host_user_id, room_code, track_url, title, artist, position_seconds, is_playing)
                        VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
                        """,
                        (room_id, user_id, room_code, body.track_url, body.title, body.artist,
                         body.position_seconds, body.is_playing),
                    )
                    break
                except Exception:
                    continue
            else:
                raise HTTPException(status_code=500, detail="Could not allocate room code")

    return {"id": room_id, "room_code": room_code}


@app.get("/rooms/{room_code}")
async def get_room(room_code: str):
    """Returns the current shared-room state. No auth required so guests
    without an account can follow a shared listening session."""
    pool = await get_pool()
    async with pool.acquire() as conn:
        async with conn.cursor() as cur:
            await cur.execute(
                """
                SELECT id, host_user_id, room_code, track_url, title, artist,
                       position_seconds, is_playing, updated_at
                FROM ios_listen_rooms WHERE room_code = %s
                """,
                (room_code.upper(),),
            )
            row = await cur.fetchone()

    if not row:
        raise HTTPException(status_code=404, detail="Room not found")

    return {
        "id": row[0],
        "room_code": row[2],
        "track_url": row[3],
        "title": row[4],
        "artist": row[5],
        "position_seconds": row[6],
        "is_playing": bool(row[7]),
        "updated_at": row[8].isoformat() if row[8] else None,
    }


@app.put("/rooms/{room_code}")
async def update_room(
    room_code: str,
    body: UpdateRoomRequest,
    payload: dict = Depends(get_current_user),
):
    """Updates a shared room's playback state. Only the host can update it."""
    user_id = payload["sub"]
    pool = await get_pool()
    async with pool.acquire() as conn:
        async with conn.cursor() as cur:
            await cur.execute(
                "SELECT host_user_id FROM ios_listen_rooms WHERE room_code = %s",
                (room_code.upper(),),
            )
            row = await cur.fetchone()
            if not row:
                raise HTTPException(status_code=404, detail="Room not found")
            if row[0] != user_id:
                raise HTTPException(status_code=403, detail="Only the host can update this room")

            updates: list[str] = []
            params: list = []
            for field, col in (
                ("track_url", "track_url"), ("title", "title"), ("artist", "artist"),
                ("position_seconds", "position_seconds"), ("is_playing", "is_playing"),
            ):
                value = getattr(body, field)
                if value is not None:
                    updates.append(f"{col} = %s")
                    params.append(value)
            if updates:
                params.append(room_code.upper())
                await cur.execute(
                    f"UPDATE ios_listen_rooms SET {', '.join(updates)} WHERE room_code = %s",
                    params,
                )

    return {"status": "updated"}


# ---------------------------------------------------------------------------
# Scheduled Playlist Refresh (Feature: playlist-refresh)
# ---------------------------------------------------------------------------


@app.post("/user/playlists/{playlist_id}/source")
async def set_playlist_source(
    playlist_id: str,
    body: PlaylistSourceRequest,
    payload: dict = Depends(get_current_user),
):
    """Attaches a source URL (e.g. a YouTube/SoundCloud playlist) to a playlist
    so the bridge can periodically check it for newly-added tracks."""
    user_id = payload["sub"]
    await _reject_ssrf_targets(body.source_url)
    pool = await get_pool()
    async with pool.acquire() as conn:
        async with conn.cursor() as cur:
            await cur.execute(
                "UPDATE ios_user_playlists SET source_url = %s, source_new_count = 0 "
                "WHERE id = %s AND user_id = %s",
                (body.source_url, playlist_id, user_id),
            )
            if cur.rowcount == 0:
                raise HTTPException(status_code=404, detail="Playlist not found")

    return {"status": "ok"}


@app.post("/user/playlists/{playlist_id}/refresh")
async def refresh_playlist_source(
    playlist_id: str,
    payload: dict = Depends(get_current_user),
):
    """Re-resolves a playlist's source URL and reports how many tracks it
    currently has versus how many are saved locally, so the client can offer
    to import the difference."""
    user_id = payload["sub"]
    pool = await get_pool()
    async with pool.acquire() as conn:
        async with conn.cursor() as cur:
            await cur.execute(
                "SELECT source_url FROM ios_user_playlists WHERE id = %s AND user_id = %s",
                (playlist_id, user_id),
            )
            row = await cur.fetchone()
            if not row:
                raise HTTPException(status_code=404, detail="Playlist not found")
            source_url = row[0]
            if not source_url:
                raise HTTPException(status_code=400, detail="Playlist has no source URL set")

            await cur.execute(
                "SELECT COUNT(*) FROM ios_playlist_tracks WHERE playlist_id = %s",
                (playlist_id,),
            )
            (local_count,) = await cur.fetchone()

    try:
        entries = await _run_ytdlp("--dump-json", "--flat-playlist", "--no-warnings", *_ytdlp_cookie_args(), source_url, timeout=60.0)
    except asyncio.TimeoutError:
        raise HTTPException(status_code=408, detail="Playlist refresh timed out")
    except Exception as exc:
        logger.error("refresh_playlist_source: yt-dlp error: %s", exc)
        raise HTTPException(status_code=404, detail="Could not resolve playlist source")

    remote_count = len(entries)
    new_count = max(0, remote_count - local_count)

    async with pool.acquire() as conn:
        async with conn.cursor() as cur:
            await cur.execute(
                "UPDATE ios_user_playlists SET source_checked_at = NOW(), source_new_count = %s "
                "WHERE id = %s AND user_id = %s",
                (new_count, playlist_id, user_id),
            )

    return {"remote_count": remote_count, "local_count": local_count, "new_count": new_count}


# ---------------------------------------------------------------------------
# Weekly Listening Stats (Feature: weekly-stats)
# ---------------------------------------------------------------------------


@app.get("/user/stats/weekly")
async def get_weekly_stats(payload: dict = Depends(get_current_user)):
    """Returns per-day play counts and listen time for the last 7 days,
    powering a weekly activity chart on the Account screen."""
    user_id = payload["sub"]
    pool = await get_pool()
    async with pool.acquire() as conn:
        async with conn.cursor() as cur:
            await cur.execute(
                """
                SELECT DATE(played_at) AS day, COUNT(*) AS plays, COALESCE(SUM(listen_seconds), 0) AS seconds
                FROM ios_play_history
                WHERE user_id = %s AND played_at >= DATE_SUB(CURDATE(), INTERVAL 6 DAY)
                GROUP BY DATE(played_at)
                ORDER BY day ASC
                """,
                (user_id,),
            )
            rows = await cur.fetchall()

    return [
        {"date": r[0].isoformat(), "plays": r[1], "listen_seconds": int(r[2])}
        for r in rows
    ]


# ---------------------------------------------------------------------------
# Duplicate Track Detection (Feature: library-duplicates)
# ---------------------------------------------------------------------------


@app.get("/user/library/duplicates")
async def get_library_duplicates(payload: dict = Depends(get_current_user)):
    """Scans the user's saved playlist tracks for likely duplicates — tracks
    with the same (normalized) title and artist appearing more than once,
    possibly across different playlists."""
    user_id = payload["sub"]
    pool = await get_pool()
    async with pool.acquire() as conn:
        async with conn.cursor() as cur:
            await cur.execute(
                """
                SELECT LOWER(TRIM(t.title)) AS norm_title, LOWER(TRIM(COALESCE(t.artist, ''))) AS norm_artist,
                       COUNT(*) AS occurrences,
                       GROUP_CONCAT(DISTINCT p.name SEPARATOR ', ') AS playlists,
                       MIN(t.title) AS title, MIN(t.artist) AS artist
                FROM ios_playlist_tracks t
                JOIN ios_user_playlists p ON p.id = t.playlist_id
                WHERE p.user_id = %s AND t.title IS NOT NULL AND t.title != ''
                GROUP BY norm_title, norm_artist
                HAVING occurrences > 1
                ORDER BY occurrences DESC
                LIMIT 100
                """,
                (user_id,),
            )
            rows = await cur.fetchall()

    return [
        {
            "title": r[4],
            "artist": r[5],
            "occurrences": r[2],
            "playlists": r[3].split(", ") if r[3] else [],
        }
        for r in rows
    ]


# ---------------------------------------------------------------------------
# Bulk Export (Feature: bulk-export)
# ---------------------------------------------------------------------------


@app.get("/user/export")
async def export_user_data(payload: dict = Depends(get_current_user)):
    """Returns a ZIP archive containing the user's playlists, favorites,
    settings, and play history as JSON files — for backup or migration."""
    user_id = payload["sub"]
    pool = await get_pool()
    data: dict[str, object] = {}

    async with pool.acquire() as conn:
        async with conn.cursor() as cur:
            await cur.execute(
                """
                SELECT p.id, p.name, p.description, p.source_url,
                       t.track_url, t.local_song_id, t.title, t.artist, t.album,
                       t.duration_seconds, t.position
                FROM ios_user_playlists p
                LEFT JOIN ios_playlist_tracks t ON t.playlist_id = p.id
                WHERE p.user_id = %s
                ORDER BY p.id, t.position
                """,
                (user_id,),
            )
            playlist_rows = await cur.fetchall()

            await cur.execute(
                "SELECT song_id, title, artist, album, added_at FROM ios_user_favorites WHERE user_id = %s",
                (user_id,),
            )
            favorite_rows = await cur.fetchall()

            await cur.execute(
                "SELECT audio_settings_json, track_audio_settings_json, theme_color FROM ios_user_settings WHERE user_id = %s",
                (user_id,),
            )
            settings_row = await cur.fetchone()

            await cur.execute(
                "SELECT track_url, local_song_id, title, artist, played_at, listen_seconds "
                "FROM ios_play_history WHERE user_id = %s ORDER BY played_at DESC LIMIT 1000",
                (user_id,),
            )
            history_rows = await cur.fetchall()

    playlists: dict[str, dict] = {}
    for r in playlist_rows:
        pid = r[0]
        if pid not in playlists:
            playlists[pid] = {"id": pid, "name": r[1], "description": r[2], "source_url": r[3], "tracks": []}
        if r[4] is not None or r[6] is not None:
            playlists[pid]["tracks"].append({
                "track_url": r[4], "local_song_id": r[5], "title": r[6],
                "artist": r[7], "album": r[8], "duration_seconds": r[9], "position": r[10],
            })

    data["playlists"] = list(playlists.values())
    data["favorites"] = [
        {"song_id": r[0], "title": r[1], "artist": r[2], "album": r[3],
         "added_at": r[4].isoformat() if r[4] else None}
        for r in favorite_rows
    ]
    data["settings"] = {
        "audio_settings_json": settings_row[0] if settings_row else None,
        "track_audio_settings_json": settings_row[1] if settings_row else None,
        "theme_color": settings_row[2] if settings_row else None,
    } if settings_row else {}
    data["history"] = [
        {"track_url": r[0], "local_song_id": r[1], "title": r[2], "artist": r[3],
         "played_at": r[4].isoformat() if r[4] else None, "listen_seconds": r[5]}
        for r in history_rows
    ]
    data["exported_at"] = datetime.now(timezone.utc).isoformat()

    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as zf:
        zf.writestr("playlists.json", json.dumps(data["playlists"], indent=2, default=str))
        zf.writestr("favorites.json", json.dumps(data["favorites"], indent=2, default=str))
        zf.writestr("settings.json", json.dumps(data["settings"], indent=2, default=str))
        zf.writestr("history.json", json.dumps(data["history"], indent=2, default=str))
        zf.writestr("export_info.json", json.dumps({"exported_at": data["exported_at"], "user_id": user_id}, indent=2))
    buf.seek(0)

    return StreamingResponse(
        buf,
        media_type="application/zip",
        headers={"Content-Disposition": "attachment; filename=lumisound_export.zip"},
    )


# ---------------------------------------------------------------------------
# Internal Telemetry Endpoints
# ---------------------------------------------------------------------------


def _parse_log_timestamp(value) -> Optional[str]:
    """Normalizes the iOS client's ISO-8601 timestamp (e.g. "2026-06-07T00:43:24Z",
    from Swift's `Date().formatted(.iso8601)`) into MySQL's native
    "YYYY-MM-DD HH:MM:SS" format. Passing the raw string through made MySQL log a
    "Data truncated for column 'timestamp'" warning on every single insert, since
    its TIMESTAMP parser doesn't understand the "T" separator / "Z" UTC suffix."""
    if not isinstance(value, str):
        return None
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00")).strftime("%Y-%m-%d %H:%M:%S")
    except ValueError:
        return None


@app.post("/bug-report", status_code=201)
async def submit_bug_report(
    body: BugReportRequest,
    credentials: HTTPAuthorizationCredentials | None = Depends(_security),
):
    """Receives in-app bug reports from Settings → Help & Feature Guide.
    Auth is optional — the app is usable without an account, so a logged-out
    user can still file a report (just without a user_id to follow up via)."""
    if not body.description.strip():
        raise HTTPException(status_code=400, detail="Description is required")

    user_id = None
    if credentials:
        payload = decode_token(credentials.credentials)
        if payload:
            user_id = payload.get("sub")

    report_id = str(uuid.uuid4())
    pool = await get_pool()
    async with pool.acquire() as conn:
        async with conn.cursor() as cur:
            await cur.execute(
                """
                INSERT INTO ios_bug_reports
                    (id, user_id, category, description, contact_email, app_version, device_info, recent_logs)
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
                """,
                (
                    report_id,
                    user_id,
                    body.category[:30],
                    body.description[:5000],
                    body.contact_email,
                    body.app_version,
                    body.device_info,
                    body.recent_logs[:50_000] if body.recent_logs else None,
                ),
            )

    return {"id": report_id, "status": "received"}


@app.post("/internal/logs", status_code=204)
async def ingest_logs(request: Request):
    """Receives batched log entries from iOS clients. No auth required for
    internal telemetry. Inserts into ios_app_logs table."""
    # Unauthenticated endpoint — cap body size before parsing so a client
    # (malicious or buggy) can't force us to buffer/parse a multi-GB payload
    # just to keep the first 100 entries. Outside the broad except below so
    # the 413 actually reaches the client instead of being swallowed.
    raw = await request.body()
    if len(raw) > 1_048_576:  # 1MB — generous for a 100-entry log batch
        raise HTTPException(status_code=413, detail="Log payload too large")
    try:
        entries = json.loads(raw)
        if not isinstance(entries, list):
            return
        rows = [
            (
                str(e.get("level", "info"))[:10],
                str(e.get("category", "general"))[:30],
                str(e.get("message", ""))[:500],
                str(e.get("file", ""))[:100],
                int(e.get("line", 0)),
                _parse_log_timestamp(e.get("timestamp")),
                json.dumps(e.get("extra", {})),
            )
            for e in entries[:100]
            if isinstance(e, dict)
        ]
        if rows:
            pool = await get_pool()
            async with pool.acquire() as conn:
                async with conn.cursor() as cur:
                    await cur.executemany(
                        "INSERT IGNORE INTO ios_app_logs "
                        "(level, category, message, file, line, timestamp, extra) "
                        "VALUES (%s, %s, %s, %s, %s, %s, %s)",
                        rows,
                    )
    except Exception:
        pass  # Logging must never fail the app


# ---------------------------------------------------------------------------
# Shared helpers for the features below
# ---------------------------------------------------------------------------


async def _create_notification(
    cur, user_id: str, type_: str, title: str, body: str = "", data: Optional[dict] = None
) -> str:
    """Inserts a row into ios_notifications. Caller owns the cursor/transaction."""
    notif_id = str(uuid.uuid4())
    await cur.execute(
        "INSERT INTO ios_notifications (id, user_id, type, title, body, data_json) "
        "VALUES (%s, %s, %s, %s, %s, %s)",
        (notif_id, user_id, type_, title, body, json.dumps(data or {})),
    )
    return notif_id


async def _playlist_role(cur, playlist_id: str, user_id: str) -> Optional[str]:
    """Returns 'owner', 'editor', 'viewer', or None for *user_id*'s relationship
    to *playlist_id*. Caller owns the cursor."""
    await cur.execute(
        "SELECT user_id FROM ios_user_playlists WHERE id = %s",
        (playlist_id,),
    )
    row = await cur.fetchone()
    if not row:
        return None
    if row[0] == user_id:
        return "owner"
    await cur.execute(
        "SELECT role FROM ios_playlist_collaborators WHERE playlist_id = %s AND user_id = %s",
        (playlist_id, user_id),
    )
    role_row = await cur.fetchone()
    return role_row[0] if role_row else None


async def _log_search(query: str, source: str) -> None:
    """Fire-and-forget logging of a search query for trending/suggestions.
    Never raises — search must work even if this fails."""
    try:
        pool = await get_pool()
        async with pool.acquire() as conn:
            async with conn.cursor() as cur:
                await cur.execute(
                    "INSERT INTO ios_search_log (query, source) VALUES (%s, %s)",
                    (query.strip()[:255], source),
                )
    except Exception as exc:
        logger.debug("_log_search failed: %s", exc)


# ---------------------------------------------------------------------------
# BPM estimation via lightweight energy-autocorrelation (Feature: audio-bpm)
# ---------------------------------------------------------------------------


async def _estimate_bpm(path: pathlib.Path) -> Optional[float]:
    """Best-effort tempo estimate (BPM) for an audio file.

    Decodes the first 60s to mono 11025Hz PCM via ffmpeg, builds a coarse
    energy-onset envelope (~50 frames/sec), and autocorrelates it to find the
    dominant beat period in the 60-200 BPM range. This avoids depending on
    extra analysis libraries (e.g. aubio/essentia) that aren't installed in
    the bridge's runtime image. Returns None on any failure."""
    cmd = [
        "ffmpeg", "-hide_banner", "-nostats", "-v", "quiet",
        "-i", str(path),
        "-t", "60",
        "-ac", "1", "-ar", "11025",
        "-f", "s16le", "-",
    ]
    try:
        proc = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.DEVNULL,
        )
        raw, _ = await asyncio.wait_for(proc.communicate(), timeout=30.0)
    except Exception as exc:
        logger.warning("_estimate_bpm: ffmpeg decode failed for %s: %s", path.name, exc)
        return None

    # Need at least a few seconds of audio to get a meaningful estimate.
    if len(raw) < 11025 * 2 * 4:
        return None

    samples = array.array("h")
    samples.frombytes(raw[: len(raw) - (len(raw) % 2)])

    sample_rate = 11025
    window = sample_rate // 50  # ~20ms windows -> ~50 frames/sec
    energies = [
        sum(s * s for s in samples[i:i + window]) / window
        for i in range(0, len(samples) - window, window)
    ]
    if len(energies) < 20:
        return None

    # Onset envelope: positive jumps in energy between consecutive windows.
    onsets = [max(0.0, energies[i] - energies[i - 1]) for i in range(1, len(energies))]

    frame_rate = sample_rate / window  # frames per second
    min_bpm, max_bpm = 60, 200
    min_lag = max(1, int(frame_rate * 60 / max_bpm))
    max_lag = min(int(frame_rate * 60 / min_bpm), len(onsets) - 1)
    if min_lag >= max_lag:
        return None

    best_lag, best_score = None, -1.0
    for lag in range(min_lag, max_lag + 1):
        score = sum(onsets[i] * onsets[i - lag] for i in range(lag, len(onsets)))
        if score > best_score:
            best_score, best_lag = score, lag

    if not best_lag:
        return None

    return round(60.0 * frame_rate / best_lag, 1)


# ---------------------------------------------------------------------------
# Scrobbling: Last.fm / ListenBrainz (Feature: scrobbling)
# ---------------------------------------------------------------------------

LASTFM_API_KEY: str = os.getenv("LASTFM_API_KEY", "")
LASTFM_API_SECRET: str = os.getenv("LASTFM_API_SECRET", "")


def _lastfm_sign(params: dict) -> str:
    sig_string = "".join(f"{k}{params[k]}" for k in sorted(params)) + LASTFM_API_SECRET
    return hashlib.md5(sig_string.encode("utf-8")).hexdigest()


async def _lastfm_scrobble(session_key: str, artist: str, title: str, timestamp: int) -> None:
    if not LASTFM_API_KEY or not LASTFM_API_SECRET:
        logger.debug("_lastfm_scrobble: LASTFM_API_KEY/SECRET not configured, skipping")
        return
    params = {
        "method": "track.scrobble",
        "api_key": LASTFM_API_KEY,
        "sk": session_key,
        "artist": artist,
        "track": title,
        "timestamp": str(timestamp),
    }
    params["api_sig"] = _lastfm_sign(params)
    params["format"] = "json"

    def _post() -> None:
        try:
            data = urllib.parse.urlencode(params).encode("utf-8")
            req = urllib.request.Request(
                "https://ws.audioscrobbler.com/2.0/",
                data=data,
                headers={"User-Agent": "Lumisound-iOS-Bridge/1.0"},
                method="POST",
            )
            urllib.request.urlopen(req, timeout=10)
        except Exception as exc:
            logger.debug("_lastfm_scrobble request failed: %s", exc)

    await asyncio.to_thread(_post)


async def _listenbrainz_scrobble(token: str, artist: str, title: str, duration_seconds: int) -> None:
    payload = {
        "listen_type": "single",
        "payload": [{
            "listened_at": int(time.time()),
            "track_metadata": {
                "artist_name": artist or "Unknown Artist",
                "track_name": title,
                "additional_info": ({"duration": duration_seconds} if duration_seconds else {}),
            },
        }],
    }

    def _post() -> None:
        try:
            req = urllib.request.Request(
                "https://api.listenbrainz.org/1/submit-listens",
                data=json.dumps(payload).encode("utf-8"),
                headers={
                    "Content-Type": "application/json",
                    "Authorization": f"Token {token}",
                    "User-Agent": "Lumisound-iOS-Bridge/1.0",
                },
                method="POST",
            )
            urllib.request.urlopen(req, timeout=10)
        except Exception as exc:
            logger.debug("_listenbrainz_scrobble request failed: %s", exc)

    await asyncio.to_thread(_post)


async def _scrobble_track(user_id: str, title: str, artist: Optional[str], listen_seconds: int) -> None:
    """Fire-and-forget scrobble to any linked services. Mirrors Last.fm's own
    ~30-second minimum listen duration before counting a play."""
    if listen_seconds < 30:
        return
    try:
        pool = await get_pool()
        async with pool.acquire() as conn:
            async with conn.cursor() as cur:
                await cur.execute(
                    "SELECT lastfm_session_key, listenbrainz_token, enabled "
                    "FROM ios_scrobble_links WHERE user_id = %s",
                    (user_id,),
                )
                row = await cur.fetchone()
    except Exception as exc:
        logger.debug("_scrobble_track: lookup failed: %s", exc)
        return

    if not row or not row[2]:
        return
    lastfm_key, listenbrainz_token, _enabled = row
    artist_name = artist or "Unknown Artist"
    if lastfm_key:
        await _lastfm_scrobble(lastfm_key, artist_name, title, int(time.time()))
    if listenbrainz_token:
        await _listenbrainz_scrobble(listenbrainz_token, artist_name, title, listen_seconds)


# ---------------------------------------------------------------------------
# Discord "Now Playing" webhook (Feature: discord-webhook)
#
# True per-user Discord Rich Presence (the "Listening to ..." status shown on
# a user's profile) is set via the Game SDK over a local IPC socket to the
# Discord desktop client — there is no API for a third-party server to set it
# on a user's behalf, and no such channel exists from an iOS app. The
# realistic equivalent is a Discord webhook: each user can point this at a
# channel in their own server, and the bridge posts a "Now Playing" embed
# there whenever they log a played track.
# ---------------------------------------------------------------------------

_DISCORD_WEBHOOK_HOSTS = frozenset({"discord.com", "discordapp.com", "canary.discord.com", "ptb.discord.com"})


def _validate_discord_webhook(url: str) -> None:
    parsed = urlsplit(url)
    if parsed.scheme != "https" or parsed.hostname not in _DISCORD_WEBHOOK_HOSTS:
        raise HTTPException(
            status_code=400,
            detail="webhook_url must be an https://discord.com/api/webhooks/... URL",
        )
    if "/api/webhooks/" not in parsed.path:
        raise HTTPException(status_code=400, detail="webhook_url does not look like a webhook URL")


async def _post_discord_webhook(webhook_url: str, payload: dict) -> None:
    def _post() -> None:
        try:
            req = urllib.request.Request(
                webhook_url,
                data=json.dumps(payload).encode("utf-8"),
                headers={"Content-Type": "application/json", "User-Agent": "Lumisound-iOS-Bridge/1.0"},
                method="POST",
            )
            urllib.request.urlopen(req, timeout=10)
        except Exception as exc:
            logger.debug("_post_discord_webhook failed: %s", exc)

    await asyncio.to_thread(_post)


async def _notify_now_playing_discord(user_id: str, title: str, artist: Optional[str]) -> None:
    try:
        pool = await get_pool()
        async with pool.acquire() as conn:
            async with conn.cursor() as cur:
                await cur.execute(
                    "SELECT webhook_url, enabled FROM ios_discord_webhooks WHERE user_id = %s",
                    (user_id,),
                )
                row = await cur.fetchone()
    except Exception as exc:
        logger.debug("_notify_now_playing_discord: lookup failed: %s", exc)
        return

    if not row or not row[1]:
        return

    embed = {
        "embeds": [{
            "title": "Now Playing",
            "description": f"**{title}**" + (f"\nby {artist}" if artist else ""),
            "color": 0xEC4079,
        }],
    }
    await _post_discord_webhook(row[0], embed)


# ---------------------------------------------------------------------------
# Smart Auto-Generated Playlists (Feature: discover-mix)
# ---------------------------------------------------------------------------


@app.get("/user/discover-mix")
async def get_discover_mix(
    limit: int = Query(20, ge=1, le=50),
    payload: dict = Depends(get_current_user),
):
    """Builds a 'Discover Mix' of suggested tracks via yt-dlp searches seeded
    by the user's most-played artists, excluding tracks already in their
    library or favorites."""
    user_id = payload["sub"]
    pool = await get_pool()
    async with pool.acquire() as conn:
        async with conn.cursor() as cur:
            await cur.execute(
                """
                SELECT artist, COUNT(*) AS plays
                FROM ios_play_history
                WHERE user_id = %s AND artist IS NOT NULL AND artist != ''
                GROUP BY artist
                ORDER BY plays DESC
                LIMIT 3
                """,
                (user_id,),
            )
            top_artists = [r[0] for r in await cur.fetchall()]

            await cur.execute(
                "SELECT song_id FROM ios_user_favorites WHERE user_id = %s "
                "UNION SELECT song_id FROM ios_user_library WHERE user_id = %s",
                (user_id, user_id),
            )
            known_ids = {r[0] for r in await cur.fetchall()}

    if not top_artists:
        return []

    per_artist = max(1, limit // len(top_artists) + 1)
    tracks: list[dict] = []
    seen_ids: set[str] = set()
    for artist in top_artists:
        try:
            entries = await _run_ytdlp(
                f"ytsearch{per_artist}:{artist}",
                "--dump-json", "--flat-playlist", "--no-playlist",
                "--cache-dir", YTDLP_CACHE_DIR,
                *_ytdlp_cookie_args(),
                timeout=20.0,
            )
        except Exception as exc:
            logger.warning("discover_mix: yt-dlp search failed for %r: %s", artist, exc)
            continue
        for entry in entries:
            track = _parse_track(entry, "youtube")
            if track["id"] in known_ids or track["id"] in seen_ids:
                continue
            seen_ids.add(track["id"])
            tracks.append(track)
            if len(tracks) >= limit:
                break
        if len(tracks) >= limit:
            break

    return tracks


# ---------------------------------------------------------------------------
# Artist/Channel Subscriptions (Feature: subscriptions)
# ---------------------------------------------------------------------------


@app.post("/user/subscriptions", status_code=201)
async def create_subscription(
    body: SubscribeChannelRequest,
    payload: dict = Depends(get_current_user),
):
    user_id = payload["sub"]
    await _reject_ssrf_targets(body.channel_url)
    sub_id = str(uuid.uuid4())
    pool = await get_pool()
    async with pool.acquire() as conn:
        async with conn.cursor() as cur:
            await cur.execute(
                "INSERT INTO ios_artist_subscriptions (id, user_id, channel_url, channel_name) "
                "VALUES (%s, %s, %s, %s)",
                (sub_id, user_id, body.channel_url, body.channel_name),
            )
    return {"id": sub_id, "channel_url": body.channel_url, "channel_name": body.channel_name}


@app.get("/user/subscriptions")
async def list_subscriptions(payload: dict = Depends(get_current_user)):
    user_id = payload["sub"]
    pool = await get_pool()
    async with pool.acquire() as conn:
        async with conn.cursor() as cur:
            await cur.execute(
                "SELECT id, channel_url, channel_name, last_video_id, last_checked_at, created_at "
                "FROM ios_artist_subscriptions WHERE user_id = %s ORDER BY created_at DESC",
                (user_id,),
            )
            rows = await cur.fetchall()

    return [
        {
            "id": r[0],
            "channel_url": r[1],
            "channel_name": r[2],
            "last_video_id": r[3],
            "last_checked_at": r[4].isoformat() if r[4] else None,
            "created_at": r[5].isoformat() if r[5] else None,
        }
        for r in rows
    ]


@app.delete("/user/subscriptions/{sub_id}", status_code=204)
async def delete_subscription(sub_id: str, payload: dict = Depends(get_current_user)):
    user_id = payload["sub"]
    pool = await get_pool()
    async with pool.acquire() as conn:
        async with conn.cursor() as cur:
            await cur.execute(
                "DELETE FROM ios_artist_subscriptions WHERE id = %s AND user_id = %s",
                (sub_id, user_id),
            )
            if cur.rowcount == 0:
                raise HTTPException(status_code=404, detail="Subscription not found")


@app.post("/user/subscriptions/{sub_id}/check")
async def check_subscription(sub_id: str, payload: dict = Depends(get_current_user)):
    """Re-resolves a channel's latest uploads and reports any new videos since
    the last check, creating an in-app notification for each."""
    user_id = payload["sub"]
    pool = await get_pool()
    async with pool.acquire() as conn:
        async with conn.cursor() as cur:
            await cur.execute(
                "SELECT channel_url, channel_name, last_video_id FROM ios_artist_subscriptions "
                "WHERE id = %s AND user_id = %s",
                (sub_id, user_id),
            )
            row = await cur.fetchone()
            if not row:
                raise HTTPException(status_code=404, detail="Subscription not found")
            channel_url, channel_name, last_video_id = row

    try:
        entries = await _run_ytdlp(
            channel_url,
            "--dump-json", "--flat-playlist", "--playlist-end", "5",
            "--cache-dir", YTDLP_CACHE_DIR,
            *_ytdlp_cookie_args(),
            timeout=30.0,
        )
    except Exception as exc:
        logger.warning("check_subscription: yt-dlp failed for %r: %s", channel_url, exc)
        raise HTTPException(status_code=502, detail="Could not resolve channel")

    tracks = [_parse_track(e, "youtube") for e in entries]

    new_tracks: list[dict] = []
    if last_video_id is not None:
        for track in tracks:
            if track["id"] == last_video_id:
                break
            new_tracks.append(track)
    # On the very first check there's no baseline to diff against — record
    # the current top video without flooding the user with their back catalog.

    latest_id = tracks[0]["id"] if tracks else last_video_id

    pool = await get_pool()
    async with pool.acquire() as conn:
        async with conn.cursor() as cur:
            await cur.execute(
                "UPDATE ios_artist_subscriptions SET last_video_id = %s, last_checked_at = NOW() "
                "WHERE id = %s",
                (latest_id, sub_id),
            )
            for track in new_tracks:
                await _create_notification(
                    cur, user_id, "new_upload",
                    f"New from {channel_name or 'a channel you follow'}",
                    track["title"],
                    {"track": track, "subscription_id": sub_id},
                )

    return {"new_tracks": new_tracks}


# ---------------------------------------------------------------------------
# Collaborative Playlists (Feature: playlist-collaborators)
# ---------------------------------------------------------------------------


@app.post("/user/playlists/{playlist_id}/collaborators", status_code=201)
async def add_collaborator(
    playlist_id: str,
    body: AddCollaboratorRequest,
    payload: dict = Depends(get_current_user),
):
    if body.role not in ("editor", "viewer"):
        raise HTTPException(status_code=400, detail="role must be 'editor' or 'viewer'")
    user_id = payload["sub"]
    pool = await get_pool()
    async with pool.acquire() as conn:
        async with conn.cursor() as cur:
            await cur.execute(
                "SELECT user_id, name FROM ios_user_playlists WHERE id = %s",
                (playlist_id,),
            )
            row = await cur.fetchone()
            if not row:
                raise HTTPException(status_code=404, detail="Playlist not found")
            if row[0] != user_id:
                raise HTTPException(status_code=403, detail="Only the owner can add collaborators")
            playlist_name = row[1]

            await cur.execute(
                "SELECT id, username FROM ios_users WHERE username = %s",
                (body.username,),
            )
            target = await cur.fetchone()
            if not target:
                raise HTTPException(status_code=404, detail="User not found")
            target_id, target_username = target
            if target_id == user_id:
                raise HTTPException(status_code=400, detail="You already own this playlist")

            await cur.execute(
                "INSERT INTO ios_playlist_collaborators (playlist_id, user_id, role) "
                "VALUES (%s, %s, %s) ON DUPLICATE KEY UPDATE role = VALUES(role)",
                (playlist_id, target_id, body.role),
            )
            await _create_notification(
                cur, target_id, "playlist_collaborator",
                "Added to a playlist",
                f"You can now {'edit' if body.role == 'editor' else 'view'} \"{playlist_name}\"",
                {"playlist_id": playlist_id, "role": body.role},
            )

    return {"playlist_id": playlist_id, "username": target_username, "role": body.role}


@app.get("/user/playlists/{playlist_id}/collaborators")
async def list_collaborators(playlist_id: str, payload: dict = Depends(get_current_user)):
    user_id = payload["sub"]
    pool = await get_pool()
    async with pool.acquire() as conn:
        async with conn.cursor() as cur:
            role = await _playlist_role(cur, playlist_id, user_id)
            if role is None:
                raise HTTPException(status_code=404, detail="Playlist not found")
            await cur.execute(
                """
                SELECT u.id, u.username, c.role, c.added_at
                FROM ios_playlist_collaborators c
                JOIN ios_users u ON u.id = c.user_id
                WHERE c.playlist_id = %s
                ORDER BY c.added_at ASC
                """,
                (playlist_id,),
            )
            rows = await cur.fetchall()

    return [
        {"user_id": r[0], "username": r[1], "role": r[2], "added_at": r[3].isoformat() if r[3] else None}
        for r in rows
    ]


@app.delete("/user/playlists/{playlist_id}/collaborators/{collab_user_id}", status_code=204)
async def remove_collaborator(
    playlist_id: str,
    collab_user_id: str,
    payload: dict = Depends(get_current_user),
):
    """Removes a collaborator. The owner can remove anyone; a collaborator can
    remove themselves."""
    user_id = payload["sub"]
    pool = await get_pool()
    async with pool.acquire() as conn:
        async with conn.cursor() as cur:
            await cur.execute(
                "SELECT user_id FROM ios_user_playlists WHERE id = %s",
                (playlist_id,),
            )
            row = await cur.fetchone()
            if not row:
                raise HTTPException(status_code=404, detail="Playlist not found")
            if row[0] != user_id and collab_user_id != user_id:
                raise HTTPException(status_code=403, detail="Not allowed")

            await cur.execute(
                "DELETE FROM ios_playlist_collaborators WHERE playlist_id = %s AND user_id = %s",
                (playlist_id, collab_user_id),
            )
            if cur.rowcount == 0:
                raise HTTPException(status_code=404, detail="Collaborator not found")


@app.get("/user/playlists/shared-with-me")
async def shared_with_me(payload: dict = Depends(get_current_user)):
    user_id = payload["sub"]
    pool = await get_pool()
    async with pool.acquire() as conn:
        async with conn.cursor() as cur:
            await cur.execute(
                """
                SELECT p.id, p.name, p.description, c.role, u.username, p.updated_at
                FROM ios_playlist_collaborators c
                JOIN ios_user_playlists p ON p.id = c.playlist_id
                JOIN ios_users u ON u.id = p.user_id
                WHERE c.user_id = %s
                ORDER BY p.updated_at DESC
                """,
                (user_id,),
            )
            rows = await cur.fetchall()

    return [
        {
            "id": r[0], "name": r[1], "description": r[2], "role": r[3],
            "owner_username": r[4], "updated_at": r[5].isoformat() if r[5] else None,
        }
        for r in rows
    ]


@app.post("/user/playlists/{playlist_id}/tracks", status_code=201)
async def add_playlist_track(
    playlist_id: str,
    body: SyncTrack,
    payload: dict = Depends(get_current_user),
):
    """Adds a track to a playlist. Allowed for the owner or any collaborator
    with the 'editor' role."""
    user_id = payload["sub"]
    track_id = str(uuid.uuid4())
    pool = await get_pool()
    async with pool.acquire() as conn:
        async with conn.cursor() as cur:
            role = await _playlist_role(cur, playlist_id, user_id)
            if role is None:
                raise HTTPException(status_code=404, detail="Playlist not found")
            if role == "viewer":
                raise HTTPException(status_code=403, detail="You only have view access to this playlist")

            await cur.execute(
                "SELECT COALESCE(MAX(position), -1) + 1 FROM ios_playlist_tracks WHERE playlist_id = %s",
                (playlist_id,),
            )
            next_position = (await cur.fetchone())[0]

            await cur.execute(
                """
                INSERT INTO ios_playlist_tracks
                    (id, playlist_id, track_url, local_song_id, title, artist, album, duration_seconds, position)
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
                """,
                (track_id, playlist_id, body.track_url, body.local_song_id, body.title,
                 body.artist, body.album, body.duration_seconds or 0, next_position),
            )
            await cur.execute(
                "UPDATE ios_user_playlists SET updated_at = NOW() WHERE id = %s",
                (playlist_id,),
            )

    return {"id": track_id, "position": next_position}


# ---------------------------------------------------------------------------
# Persistent Play Queue (Feature: user-queue)
# ---------------------------------------------------------------------------


@app.get("/user/queue")
async def get_queue(payload: dict = Depends(get_current_user)):
    user_id = payload["sub"]
    pool = await get_pool()
    async with pool.acquire() as conn:
        async with conn.cursor() as cur:
            await cur.execute(
                """
                SELECT id, local_song_id, track_url, title, artist, album, duration_seconds, position
                FROM ios_user_queue WHERE user_id = %s ORDER BY position ASC
                """,
                (user_id,),
            )
            rows = await cur.fetchall()

    return [
        {
            "id": r[0], "local_song_id": r[1], "track_url": r[2], "title": r[3],
            "artist": r[4], "album": r[5], "duration_seconds": r[6], "position": r[7],
        }
        for r in rows
    ]


@app.put("/user/queue")
async def replace_queue(body: ReplaceQueueRequest, payload: dict = Depends(get_current_user)):
    """Replaces the user's entire 'up next' queue, in order, so it survives
    app restarts and syncs across devices."""
    user_id = payload["sub"]
    pool = await get_pool()
    async with pool.acquire() as conn:
        async with conn.cursor() as cur:
            await cur.execute("DELETE FROM ios_user_queue WHERE user_id = %s", (user_id,))
            if body.tracks:
                rows = [
                    (str(uuid.uuid4()), user_id, idx, t.local_song_id, t.track_url, t.title,
                     t.artist, t.album, t.duration_seconds or 0)
                    for idx, t in enumerate(body.tracks)
                ]
                await cur.executemany(
                    """
                    INSERT INTO ios_user_queue
                        (id, user_id, position, local_song_id, track_url, title, artist, album, duration_seconds)
                    VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
                    """,
                    rows,
                )

    return {"status": "ok", "count": len(body.tracks)}


@app.delete("/user/queue", status_code=204)
async def clear_queue(payload: dict = Depends(get_current_user)):
    user_id = payload["sub"]
    pool = await get_pool()
    async with pool.acquire() as conn:
        async with conn.cursor() as cur:
            await cur.execute("DELETE FROM ios_user_queue WHERE user_id = %s", (user_id,))


# ---------------------------------------------------------------------------
# Scrobbling Account Links (Feature: scrobbling)
# ---------------------------------------------------------------------------


@app.get("/user/scrobble")
async def get_scrobble_links(payload: dict = Depends(get_current_user)):
    user_id = payload["sub"]
    pool = await get_pool()
    async with pool.acquire() as conn:
        async with conn.cursor() as cur:
            await cur.execute(
                "SELECT lastfm_username, listenbrainz_token, enabled FROM ios_scrobble_links WHERE user_id = %s",
                (user_id,),
            )
            row = await cur.fetchone()

    if not row:
        return {"lastfm_linked": False, "lastfm_username": None, "listenbrainz_linked": False, "enabled": True}

    return {
        "lastfm_linked": bool(row[0]),
        "lastfm_username": row[0],
        "listenbrainz_linked": bool(row[1]),
        "enabled": bool(row[2]),
    }


@app.put("/user/scrobble")
async def update_scrobble_links(body: ScrobbleLinkRequest, payload: dict = Depends(get_current_user)):
    user_id = payload["sub"]
    enabled = body.enabled if body.enabled is not None else True
    pool = await get_pool()
    async with pool.acquire() as conn:
        async with conn.cursor() as cur:
            await cur.execute(
                """
                INSERT INTO ios_scrobble_links
                    (user_id, lastfm_session_key, lastfm_username, listenbrainz_token, enabled)
                VALUES (%s, %s, %s, %s, %s)
                ON DUPLICATE KEY UPDATE
                    lastfm_session_key = IF(VALUES(lastfm_session_key) IS NULL, lastfm_session_key, VALUES(lastfm_session_key)),
                    lastfm_username = IF(VALUES(lastfm_username) IS NULL, lastfm_username, VALUES(lastfm_username)),
                    listenbrainz_token = IF(VALUES(listenbrainz_token) IS NULL, listenbrainz_token, VALUES(listenbrainz_token)),
                    enabled = VALUES(enabled)
                """,
                (user_id, body.lastfm_session_key, body.lastfm_username, body.listenbrainz_token, enabled),
            )

    return {"status": "ok"}


@app.delete("/user/scrobble", status_code=204)
async def delete_scrobble_links(payload: dict = Depends(get_current_user)):
    user_id = payload["sub"]
    pool = await get_pool()
    async with pool.acquire() as conn:
        async with conn.cursor() as cur:
            await cur.execute("DELETE FROM ios_scrobble_links WHERE user_id = %s", (user_id,))


def _lastfm_api_get(params: dict) -> dict:
    """Synchronous helper for signed Last.fm API GET requests."""
    signed = dict(params)
    signed["api_sig"] = _lastfm_sign(signed)
    signed["format"] = "json"
    url = "https://ws.audioscrobbler.com/2.0/?" + urllib.parse.urlencode(signed)
    req = urllib.request.Request(url, headers={"User-Agent": "Lumisound-iOS-Bridge/1.0"})
    with urllib.request.urlopen(req, timeout=10) as resp:
        return json.loads(resp.read().decode("utf-8"))


@app.post("/user/scrobble/lastfm/request-token")
async def lastfm_request_token(payload: dict = Depends(get_current_user)):
    """Step 1 of the Last.fm desktop auth flow: fetch an unauthorized token
    and the URL the user must open to approve it."""
    if not LASTFM_API_KEY or not LASTFM_API_SECRET:
        raise HTTPException(status_code=503, detail="Last.fm integration is not configured")

    try:
        data = await asyncio.to_thread(
            _lastfm_api_get, {"method": "auth.gettoken", "api_key": LASTFM_API_KEY}
        )
    except Exception as exc:
        raise HTTPException(status_code=502, detail=f"Last.fm request failed: {exc}")

    token = data.get("token")
    if not token:
        raise HTTPException(status_code=502, detail="Last.fm did not return a token")

    auth_url = f"https://www.last.fm/api/auth/?api_key={LASTFM_API_KEY}&token={token}"
    return {"token": token, "auth_url": auth_url}


class LastfmLinkRequest(BaseModel):
    token: str


@app.post("/user/scrobble/lastfm/link")
async def lastfm_link_session(body: LastfmLinkRequest, payload: dict = Depends(get_current_user)):
    """Step 2: exchange an approved token for a session key and store it."""
    if not LASTFM_API_KEY or not LASTFM_API_SECRET:
        raise HTTPException(status_code=503, detail="Last.fm integration is not configured")

    try:
        data = await asyncio.to_thread(
            _lastfm_api_get,
            {"method": "auth.getsession", "api_key": LASTFM_API_KEY, "token": body.token},
        )
    except Exception as exc:
        raise HTTPException(status_code=502, detail=f"Last.fm request failed: {exc}")

    session = data.get("session")
    if not session or not session.get("key"):
        raise HTTPException(status_code=400, detail="Last.fm did not approve this token")

    session_key = session["key"]
    username = session.get("name")

    user_id = payload["sub"]
    pool = await get_pool()
    async with pool.acquire() as conn:
        async with conn.cursor() as cur:
            await cur.execute(
                """
                INSERT INTO ios_scrobble_links (user_id, lastfm_session_key, lastfm_username, enabled)
                VALUES (%s, %s, %s, TRUE)
                ON DUPLICATE KEY UPDATE
                    lastfm_session_key = VALUES(lastfm_session_key),
                    lastfm_username = VALUES(lastfm_username)
                """,
                (user_id, session_key, username),
            )

    return {"lastfm_username": username}


# ---------------------------------------------------------------------------
# Listening Achievements & Streaks (Feature: achievements)
# ---------------------------------------------------------------------------


@app.get("/user/achievements")
async def get_achievements(payload: dict = Depends(get_current_user)):
    """Derives streaks and badge unlocks from ios_play_history. Computed on
    the fly — no separate achievements table to keep in sync."""
    user_id = payload["sub"]
    pool = await get_pool()
    async with pool.acquire() as conn:
        async with conn.cursor() as cur:
            await cur.execute(
                "SELECT COUNT(*), COALESCE(SUM(listen_seconds), 0) FROM ios_play_history WHERE user_id = %s",
                (user_id,),
            )
            total_plays, total_seconds = await cur.fetchone()

            await cur.execute(
                "SELECT DISTINCT DATE(played_at) AS d FROM ios_play_history WHERE user_id = %s ORDER BY d DESC",
                (user_id,),
            )
            play_dates = [r[0] for r in await cur.fetchall()]

            await cur.execute(
                "SELECT HOUR(played_at), COUNT(*) FROM ios_play_history WHERE user_id = %s GROUP BY HOUR(played_at)",
                (user_id,),
            )
            hour_counts = dict(await cur.fetchall())

    # Streaks: consecutive calendar days with at least one play.
    current_streak = 0
    longest_streak = 0
    if play_dates:
        run = 1
        longest_streak = 1
        for i in range(1, len(play_dates)):
            if (play_dates[i - 1] - play_dates[i]).days == 1:
                run += 1
            else:
                longest_streak = max(longest_streak, run)
                run = 1
        longest_streak = max(longest_streak, run)

        today = datetime.now(timezone.utc).date()
        if play_dates[0] in (today, today - timedelta(days=1)):
            current_streak = 1
            for i in range(1, len(play_dates)):
                if (play_dates[i - 1] - play_dates[i]).days == 1:
                    current_streak += 1
                else:
                    break

    total_hours = total_seconds / 3600
    badges = []
    badges += [f"plays_{n}" for n in (10, 50, 100, 500, 1000) if total_plays >= n]
    badges += [f"hours_{n}" for n in (1, 10, 24, 100) if total_hours >= n]
    badges += [f"streak_{n}" for n in (3, 7, 30, 100) if longest_streak >= n]
    if any(hour_counts.get(h, 0) for h in range(0, 5)):
        badges.append("night_owl")
    if any(hour_counts.get(h, 0) for h in range(5, 9)):
        badges.append("early_bird")

    return {
        "total_plays": total_plays,
        "total_listen_seconds": int(total_seconds),
        "current_streak_days": current_streak,
        "longest_streak_days": longest_streak,
        "badges": badges,
    }


# ---------------------------------------------------------------------------
# Search Autocomplete & Trending (Feature: search-trending)
# ---------------------------------------------------------------------------


@app.get("/api/search/trending")
async def search_trending(
    request: Request,
    limit: int = Query(10, ge=1, le=25),
    days: int = Query(7, ge=1, le=30),
):
    """Most popular search queries across all users in the last *days* days."""
    await check_auth(request)
    pool = await get_pool()
    async with pool.acquire() as conn:
        async with conn.cursor() as cur:
            await cur.execute(
                """
                SELECT query, COUNT(*) AS hits
                FROM ios_search_log
                WHERE searched_at >= NOW() - INTERVAL %s DAY
                GROUP BY query
                ORDER BY hits DESC, MAX(searched_at) DESC
                LIMIT %s
                """,
                (days, limit),
            )
            rows = await cur.fetchall()

    return [{"query": r[0], "count": r[1]} for r in rows]


@app.get("/api/search/suggestions")
async def search_suggestions(
    request: Request,
    q: str = Query(..., min_length=1, max_length=200),
    limit: int = Query(8, ge=1, le=20),
):
    """Autocomplete suggestions: past queries starting with *q*, most popular first."""
    await check_auth(request)
    pool = await get_pool()
    async with pool.acquire() as conn:
        async with conn.cursor() as cur:
            await cur.execute(
                """
                SELECT query, COUNT(*) AS hits
                FROM ios_search_log
                WHERE query LIKE %s
                GROUP BY query
                ORDER BY hits DESC
                LIMIT %s
                """,
                (f"{q}%", limit),
            )
            rows = await cur.fetchall()

    return [{"query": r[0], "count": r[1]} for r in rows]


# ---------------------------------------------------------------------------
# Playlist Folders (Feature: playlist-folders)
# ---------------------------------------------------------------------------


@app.get("/user/playlists/folders")
async def list_playlist_folders(payload: dict = Depends(get_current_user)):
    user_id = payload["sub"]
    pool = await get_pool()
    async with pool.acquire() as conn:
        async with conn.cursor() as cur:
            await cur.execute(
                """
                SELECT COALESCE(folder, ''), COUNT(*)
                FROM ios_user_playlists
                WHERE user_id = %s
                GROUP BY folder
                ORDER BY folder ASC
                """,
                (user_id,),
            )
            rows = await cur.fetchall()

    return [{"folder": r[0] or None, "count": r[1]} for r in rows]


# ---------------------------------------------------------------------------
# Push Notifications (Feature: push-notifications)
# ---------------------------------------------------------------------------


@app.post("/user/push-token", status_code=201)
async def register_push_token(body: PushTokenRequest, payload: dict = Depends(get_current_user)):
    user_id = payload["sub"]
    pool = await get_pool()
    async with pool.acquire() as conn:
        async with conn.cursor() as cur:
            await cur.execute(
                "INSERT INTO ios_push_tokens (user_id, device_token, platform) VALUES (%s, %s, %s) "
                "ON DUPLICATE KEY UPDATE platform = VALUES(platform)",
                (user_id, body.device_token, body.platform),
            )
    return {"status": "ok"}


@app.delete("/user/push-token/{device_token}", status_code=204)
async def unregister_push_token(device_token: str, payload: dict = Depends(get_current_user)):
    user_id = payload["sub"]
    pool = await get_pool()
    async with pool.acquire() as conn:
        async with conn.cursor() as cur:
            await cur.execute(
                "DELETE FROM ios_push_tokens WHERE user_id = %s AND device_token = %s",
                (user_id, device_token),
            )


@app.get("/user/notifications")
async def get_notifications(
    limit: int = Query(50, ge=1, le=200),
    unread_only: bool = Query(False),
    payload: dict = Depends(get_current_user),
):
    user_id = payload["sub"]
    pool = await get_pool()
    async with pool.acquire() as conn:
        async with conn.cursor() as cur:
            query = (
                "SELECT id, type, title, body, data_json, created_at, read_at "
                "FROM ios_notifications WHERE user_id = %s"
            )
            params: list = [user_id]
            if unread_only:
                query += " AND read_at IS NULL"
            query += " ORDER BY created_at DESC LIMIT %s"
            params.append(limit)
            await cur.execute(query, params)
            rows = await cur.fetchall()

    return [
        {
            "id": r[0], "type": r[1], "title": r[2], "body": r[3],
            "data": json.loads(r[4]) if r[4] else {},
            "created_at": r[5].isoformat() if r[5] else None,
            "read_at": r[6].isoformat() if r[6] else None,
        }
        for r in rows
    ]


@app.post("/user/notifications/{notification_id}/read", status_code=204)
async def mark_notification_read(notification_id: str, payload: dict = Depends(get_current_user)):
    user_id = payload["sub"]
    pool = await get_pool()
    async with pool.acquire() as conn:
        async with conn.cursor() as cur:
            await cur.execute(
                "UPDATE ios_notifications SET read_at = NOW() WHERE id = %s AND user_id = %s AND read_at IS NULL",
                (notification_id, user_id),
            )
            if cur.rowcount == 0:
                await cur.execute(
                    "SELECT 1 FROM ios_notifications WHERE id = %s AND user_id = %s",
                    (notification_id, user_id),
                )
                if not await cur.fetchone():
                    raise HTTPException(status_code=404, detail="Notification not found")


@app.post("/user/notifications/read-all", status_code=204)
async def mark_all_notifications_read(payload: dict = Depends(get_current_user)):
    user_id = payload["sub"]
    pool = await get_pool()
    async with pool.acquire() as conn:
        async with conn.cursor() as cur:
            await cur.execute(
                "UPDATE ios_notifications SET read_at = NOW() WHERE user_id = %s AND read_at IS NULL",
                (user_id,),
            )


# ---------------------------------------------------------------------------
# Discord "Now Playing" Webhook Settings (Feature: discord-webhook)
# ---------------------------------------------------------------------------


@app.get("/user/discord-webhook")
async def get_discord_webhook(payload: dict = Depends(get_current_user)):
    user_id = payload["sub"]
    pool = await get_pool()
    async with pool.acquire() as conn:
        async with conn.cursor() as cur:
            await cur.execute(
                "SELECT webhook_url, enabled FROM ios_discord_webhooks WHERE user_id = %s",
                (user_id,),
            )
            row = await cur.fetchone()

    if not row:
        return {"configured": False, "enabled": False, "webhook_url": None}

    url = row[0]
    masked = url[:48] + "..." if len(url) > 48 else url
    return {"configured": True, "enabled": bool(row[1]), "webhook_url": masked}


@app.put("/user/discord-webhook")
async def set_discord_webhook(body: DiscordWebhookRequest, payload: dict = Depends(get_current_user)):
    user_id = payload["sub"]

    if body.webhook_url is not None:
        _validate_discord_webhook(body.webhook_url)
    else:
        # Allow toggling `enabled` without resending the URL (which the
        # client never sees again after it's masked by GET).
        pool = await get_pool()
        async with pool.acquire() as conn:
            async with conn.cursor() as cur:
                await cur.execute(
                    "SELECT 1 FROM ios_discord_webhooks WHERE user_id = %s", (user_id,)
                )
                if not await cur.fetchone():
                    raise HTTPException(status_code=400, detail="webhook_url is required")

    pool = await get_pool()
    async with pool.acquire() as conn:
        async with conn.cursor() as cur:
            if body.webhook_url is not None:
                await cur.execute(
                    "INSERT INTO ios_discord_webhooks (user_id, webhook_url, enabled) VALUES (%s, %s, %s) "
                    "ON DUPLICATE KEY UPDATE webhook_url = VALUES(webhook_url), enabled = VALUES(enabled)",
                    (user_id, body.webhook_url, body.enabled),
                )
            else:
                await cur.execute(
                    "UPDATE ios_discord_webhooks SET enabled = %s WHERE user_id = %s",
                    (body.enabled, user_id),
                )
    return {"status": "ok"}


@app.delete("/user/discord-webhook", status_code=204)
async def delete_discord_webhook(payload: dict = Depends(get_current_user)):
    user_id = payload["sub"]
    pool = await get_pool()
    async with pool.acquire() as conn:
        async with conn.cursor() as cur:
            await cur.execute("DELETE FROM ios_discord_webhooks WHERE user_id = %s", (user_id,))


# ---------------------------------------------------------------------------
# Long-lived "RPC setup" tokens — for the local Discord Rich Presence daemon
# (and similar local tools) so a user never has to put their account
# password in a desktop config file. Generated from Settings in the app,
# shown once, and managed as a regular session (visible/revocable in
# /auth/sessions like any other device).
# ---------------------------------------------------------------------------

RPC_TOKEN_EXPIRE_DAYS = 365


@app.post("/user/rpc-token")
async def create_rpc_token(payload: dict = Depends(get_current_user)):
    user_id = payload["sub"]
    pool = await get_pool()
    token_id = str(uuid.uuid4())
    expires_at = datetime.now(timezone.utc) + timedelta(days=RPC_TOKEN_EXPIRE_DAYS)
    async with pool.acquire() as conn:
        async with conn.cursor() as cur:
            await cur.execute(
                """
                INSERT INTO ios_user_sessions (token_id, user_id, expires_at, device_name)
                VALUES (%s, %s, %s, %s)
                """,
                (token_id, user_id, expires_at, "Discord RPC Bridge"),
            )

    token = create_token(user_id, token_id, expire_days=RPC_TOKEN_EXPIRE_DAYS)
    return {"token": token, "expires_at": expires_at.isoformat()}


# ---------------------------------------------------------------------------
# Discord Rich Presence config registration (Feature: discord-rpc-config)
#
# Centralizes the per-user settings the local Discord Rich Presence daemon
# needs (Discord Application client ID + optional art asset name) so users
# only have to put their RPC token (see /user/rpc-token) in the daemon's
# local config — everything else is fetched from here.
# ---------------------------------------------------------------------------

_DISCORD_CLIENT_ID_RE = re.compile(r"^\d{15,25}$")


@app.get("/user/discord-rpc-config")
async def get_discord_rpc_config(payload: dict = Depends(get_current_user)):
    user_id = payload["sub"]
    pool = await get_pool()
    async with pool.acquire() as conn:
        async with conn.cursor() as cur:
            await cur.execute(
                "SELECT discord_client_id, large_image, enabled FROM ios_discord_rpc_config WHERE user_id = %s",
                (user_id,),
            )
            row = await cur.fetchone()

    if not row:
        return {"configured": False, "enabled": False, "discord_client_id": None, "large_image": None}

    return {"configured": True, "enabled": bool(row[2]), "discord_client_id": row[0], "large_image": row[1]}


@app.put("/user/discord-rpc-config")
async def set_discord_rpc_config(body: DiscordRpcConfigRequest, payload: dict = Depends(get_current_user)):
    user_id = payload["sub"]

    if not _DISCORD_CLIENT_ID_RE.match(body.discord_client_id):
        raise HTTPException(status_code=400, detail="discord_client_id must be a numeric Discord application ID")

    pool = await get_pool()
    async with pool.acquire() as conn:
        async with conn.cursor() as cur:
            await cur.execute(
                "INSERT INTO ios_discord_rpc_config (user_id, discord_client_id, large_image, enabled) "
                "VALUES (%s, %s, %s, %s) "
                "ON DUPLICATE KEY UPDATE discord_client_id = VALUES(discord_client_id), "
                "large_image = VALUES(large_image), enabled = VALUES(enabled)",
                (user_id, body.discord_client_id, body.large_image, body.enabled),
            )
    return {"status": "ok"}


@app.delete("/user/discord-rpc-config", status_code=204)
async def delete_discord_rpc_config(payload: dict = Depends(get_current_user)):
    user_id = payload["sub"]
    pool = await get_pool()
    async with pool.acquire() as conn:
        async with conn.cursor() as cur:
            await cur.execute("DELETE FROM ios_discord_rpc_config WHERE user_id = %s", (user_id,))


# ---------------------------------------------------------------------------
# Entry point (for local dev without Docker)
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    import uvicorn

    uvicorn.run("main:app", host="0.0.0.0", port=8002, reload=True)
