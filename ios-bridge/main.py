import asyncio
import hashlib
import json
import logging
import os
import pathlib
import shutil
import tempfile
import time
import uuid
from collections import defaultdict
from contextlib import asynccontextmanager
from datetime import datetime, timedelta, timezone
from typing import Optional

from fastapi import Depends, FastAPI, HTTPException, Query, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from pydantic import BaseModel

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
API_KEY: str = os.getenv("IOS_BRIDGE_API_KEY", "")
SERVER_MUSIC_DIR: str = os.getenv("SERVER_MUSIC_DIR", "")
# Per-user music directory. Each user gets {USER_MUSIC_DIR}/{user_id}/.
# Falls back to {SERVER_MUSIC_DIR}/users/ if SERVER_MUSIC_DIR is set.
USER_MUSIC_DIR: str = os.getenv("USER_MUSIC_DIR", "")
SUPPORTED_AUDIO_EXTS: frozenset[str] = frozenset({
    ".mp3", ".m4a", ".aac", ".wav", ".aif", ".aiff",
    ".flac", ".opus", ".ogg", ".caf", ".mp4", ".m4v",
})
VERSION = "1.0.0"

# ---------------------------------------------------------------------------
# yt-dlp concurrency limit (Fix 3)
# ---------------------------------------------------------------------------

_YTDLP_SEMAPHORE = asyncio.Semaphore(4)  # max 4 concurrent yt-dlp processes

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
    forwarded = request.headers.get("X-Forwarded-For")
    if forwarded:
        return forwarded.split(",")[0].strip()
    return request.client.host if request.client else "unknown"


# ---------------------------------------------------------------------------
# Startup temp-dir cleanup (Fix 6)
# ---------------------------------------------------------------------------


async def cleanup_old_temp_dirs() -> None:
    """Remove download temp dirs (prefix 'dl_') older than 10 minutes."""
    tmp = pathlib.Path(tempfile.gettempdir())
    cutoff = time.time() - 600
    cleaned = 0
    for item in tmp.iterdir():
        try:
            if item.is_dir() and item.name.startswith("dl_") and item.stat().st_mtime < cutoff:
                shutil.rmtree(item, ignore_errors=True)
                cleaned += 1
        except Exception:
            pass
    if cleaned:
        logger.info("Startup cleanup: removed %d stale temp download dirs", cleaned)


# ---------------------------------------------------------------------------
# Lifespan
# ---------------------------------------------------------------------------


@asynccontextmanager
async def lifespan(app: FastAPI):
    await init_db()
    await cleanup_old_temp_dirs()
    yield
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
_CACHE_TTL = 300  # seconds


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
    return payload


# ---------------------------------------------------------------------------
# yt-dlp subprocess helper
# ---------------------------------------------------------------------------


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


class UpdatePlaylistRequest(BaseModel):
    name: Optional[str] = None
    description: Optional[str] = None


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
    theme_color: Optional[str] = None


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
    theme_color: Optional[str] = None


# ---------------------------------------------------------------------------
# Helper: build user dict from DB row
# ---------------------------------------------------------------------------


def _user_dict(row: tuple) -> dict:
    """Map a (id, username, email, display_name, avatar_url, created_at, last_login, date_of_birth) row."""
    return {
        "id": row[0],
        "username": row[1],
        "email": row[2],
        "display_name": row[3],
        "avatar_url": row[4],
        "created_at": row[5].isoformat() if row[5] else None,
        "last_login": row[6].isoformat() if row[6] else None,
        "date_of_birth": row[7].isoformat() if len(row) > 7 and row[7] else None,
    }


# ---------------------------------------------------------------------------
# Existing Endpoints
# ---------------------------------------------------------------------------


@app.get("/health")
async def health():
    return {"status": "ok", "version": VERSION}


@app.get("/api/search")
async def search(
    request: Request,
    q: str = Query(..., description="Search query"),
    limit: int = Query(20, ge=1, le=50, description="Max results"),
    source: str = Query("youtube", description="youtube or soundcloud"),
):
    await check_auth(request)

    source = source.lower()
    if source not in ("youtube", "soundcloud"):
        raise HTTPException(status_code=400, detail="source must be 'youtube' or 'soundcloud'")

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
    """Runs yt-dlp --get-url and returns the first HTTP(S) line from stdout."""
    cmd = [
        "yt-dlp",
        "-f", format_flag,
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
            stdout_bytes, _ = await asyncio.wait_for(proc.communicate(), timeout=15.0)
        except asyncio.TimeoutError:
            proc.kill()
            await proc.communicate()  # reap the zombie (Fix 7)
            raise HTTPException(status_code=408, detail="Stream URL fetch timed out")

    for raw_line in stdout_bytes.splitlines():
        line = raw_line.strip().decode(errors="replace")
        if line.startswith("http"):
            return line
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
            _, stderr_bytes = await asyncio.wait_for(proc.communicate(), timeout=120.0)
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

    asyncio.ensure_future(_cleanup_later(tmp_dir))

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
):
    await check_auth(request)

    try:
        entries = await _run_ytdlp(
            "--dump-json",
            "--flat-playlist",
            url,
            timeout=60.0,
        )
    except asyncio.TimeoutError:
        raise HTTPException(status_code=408, detail="Playlist resolve timed out")
    except Exception as exc:
        logger.error("yt-dlp resolve error: %s", exc)
        raise HTTPException(status_code=404, detail="Could not resolve playlist")

    source = "soundcloud" if "soundcloud.com" in url else "youtube"
    tracks = [_parse_track(e, source) for e in entries[:50]]
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
                "SELECT id, username, email, display_name, avatar_url, created_at, last_login, date_of_birth "
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
                "SELECT id, username, email, display_name, avatar_url, created_at, last_login, date_of_birth "
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


@app.get("/auth/me")
async def me(payload: dict = Depends(get_current_user)):
    user_id = payload["sub"]
    pool = await get_pool()
    async with pool.acquire() as conn:
        async with conn.cursor() as cur:
            await cur.execute(
                "SELECT id, username, email, display_name, avatar_url, created_at, last_login, date_of_birth "
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
                "SELECT id, username, email, display_name, avatar_url, created_at, last_login, date_of_birth "
                "FROM ios_users WHERE id = %s AND is_active = TRUE",
                (user_id,),
            )
            row = await cur.fetchone()

    if not row:
        raise HTTPException(status_code=401, detail="User not found")
    return _user_dict(row)


# ---------------------------------------------------------------------------
# Avatar Endpoints
# ---------------------------------------------------------------------------


@app.post("/user/avatar")
async def upload_avatar(request: Request, user: dict = Depends(get_current_user)):
    """Upload profile picture as JPEG bytes (max 1MB)."""
    body = await request.body()
    if len(body) > 1_048_576:  # 1MB limit
        raise HTTPException(status_code=413, detail="Avatar must be under 1MB")
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
    body = await request.json()
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
            await cur.execute(
                """
                SELECT id, name, description, created_at, updated_at
                FROM ios_user_playlists
                WHERE user_id = %s
                ORDER BY updated_at DESC
                """,
                (user_id,),
            )
            playlist_rows = await cur.fetchall()

            playlists = []
            for pl_row in playlist_rows:
                pl_id, name, description, created_at, updated_at = pl_row
                await cur.execute(
                    """
                    SELECT id, track_url, local_song_id, title, artist, album,
                           duration_seconds, position
                    FROM ios_playlist_tracks
                    WHERE playlist_id = %s
                    ORDER BY position ASC
                    """,
                    (pl_id,),
                )
                track_rows = await cur.fetchall()
                tracks = [
                    {
                        "id": t[0],
                        "track_url": t[1],
                        "local_song_id": t[2],
                        "title": t[3],
                        "artist": t[4],
                        "album": t[5],
                        "duration_seconds": t[6],
                        "position": t[7],
                    }
                    for t in track_rows
                ]
                playlists.append(
                    {
                        "id": pl_id,
                        "name": name,
                        "description": description,
                        "created_at": created_at.isoformat() if created_at else None,
                        "updated_at": updated_at.isoformat() if updated_at else None,
                        "tracks": tracks,
                    }
                )

    return playlists


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
                INSERT INTO ios_user_playlists (id, user_id, name, description)
                VALUES (%s, %s, %s, %s)
                """,
                (pl_id, user_id, body.name, body.description),
            )
            await cur.execute(
                """
                SELECT id, name, description, created_at, updated_at
                FROM ios_user_playlists WHERE id = %s
                """,
                (pl_id,),
            )
            row = await cur.fetchone()

    pl_id, name, description, created_at, updated_at = row
    return {
        "id": pl_id,
        "name": name,
        "description": description,
        "created_at": created_at.isoformat() if created_at else None,
        "updated_at": updated_at.isoformat() if updated_at else None,
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

            if updates:
                values.append(playlist_id)
                await cur.execute(
                    f"UPDATE ios_user_playlists SET {', '.join(updates)} WHERE id = %s",
                    values,
                )

            await cur.execute(
                "SELECT id, name, description, created_at, updated_at "
                "FROM ios_user_playlists WHERE id = %s",
                (playlist_id,),
            )
            row = await cur.fetchone()

    pl_id, name, description, created_at, updated_at = row
    return {
        "id": pl_id,
        "name": name,
        "description": description,
        "created_at": created_at.isoformat() if created_at else None,
        "updated_at": updated_at.isoformat() if updated_at else None,
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
            await cur.execute(
                "SELECT id FROM ios_user_playlists WHERE id = %s AND user_id = %s",
                (playlist_id, user_id),
            )
            if not await cur.fetchone():
                raise HTTPException(status_code=404, detail="Playlist not found")
            await cur.execute(
                "DELETE FROM ios_user_playlists WHERE id = %s", (playlist_id,)
            )


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
                "SELECT audio_settings_json, theme_color, updated_at "
                "FROM ios_user_settings WHERE user_id = %s",
                (user_id,),
            )
            row = await cur.fetchone()

    if not row:
        return {"audio_settings_json": None, "theme_color": "#EC4079", "updated_at": None}

    return {
        "audio_settings_json": row[0],
        "theme_color": row[1],
        "updated_at": row[2].isoformat() if row[2] else None,
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
                INSERT INTO ios_user_settings (user_id, audio_settings_json, theme_color)
                VALUES (%s, %s, %s)
                ON DUPLICATE KEY UPDATE
                    audio_settings_json = IF(%s IS NULL, audio_settings_json, %s),
                    theme_color = IF(%s IS NULL, theme_color, %s)
                """,
                (
                    user_id,
                    body.audio_settings_json,
                    body.theme_color or "#EC4079",
                    body.audio_settings_json,
                    body.audio_settings_json,
                    body.theme_color,
                    body.theme_color,
                ),
            )
            await cur.execute(
                "SELECT audio_settings_json, theme_color, updated_at "
                "FROM ios_user_settings WHERE user_id = %s",
                (user_id,),
            )
            row = await cur.fetchone()

    return {
        "audio_settings_json": row[0],
        "theme_color": row[1],
        "updated_at": row[2].isoformat() if row[2] else None,
    }


# ---------------------------------------------------------------------------
# Sync Endpoints
# ---------------------------------------------------------------------------


@app.get("/user/sync")
async def sync_pull(payload: dict = Depends(get_current_user)):
    user_id = payload["sub"]
    pool = await get_pool()
    async with pool.acquire() as conn:
        async with conn.cursor() as cur:
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

            # Playlists with tracks
            await cur.execute(
                "SELECT id, name, description FROM ios_user_playlists WHERE user_id = %s ORDER BY updated_at DESC",
                (user_id,),
            )
            pl_rows = await cur.fetchall()
            playlists = []
            for pl_id, name, description in pl_rows:
                await cur.execute(
                    """
                    SELECT track_url, local_song_id, title, artist, album,
                           duration_seconds, position
                    FROM ios_playlist_tracks
                    WHERE playlist_id = %s ORDER BY position ASC
                    """,
                    (pl_id,),
                )
                track_rows = await cur.fetchall()
                tracks = [
                    {
                        "track_url": t[0],
                        "local_song_id": t[1],
                        "title": t[2],
                        "artist": t[3],
                        "album": t[4],
                        "duration_seconds": t[5],
                        "position": t[6],
                    }
                    for t in track_rows
                ]
                playlists.append(
                    {"id": pl_id, "name": name, "description": description, "tracks": tracks}
                )

            # Settings
            await cur.execute(
                "SELECT audio_settings_json, theme_color FROM ios_user_settings WHERE user_id = %s",
                (user_id,),
            )
            settings_row = await cur.fetchone()
            audio_settings_json = settings_row[0] if settings_row else None
            theme_color = settings_row[1] if settings_row else "#EC4079"

    return {
        "favorites": favorites,
        "playlists": playlists,
        "audio_settings_json": audio_settings_json,
        "theme_color": theme_color,
    }


@app.post("/user/sync")
async def sync_push(
    body: SyncPushRequest,
    payload: dict = Depends(get_current_user),
):
    user_id = payload["sub"]
    pool = await get_pool()
    async with pool.acquire() as conn:
        async with conn.cursor() as cur:
            # Replace favorites
            await cur.execute(
                "DELETE FROM ios_user_favorites WHERE user_id = %s", (user_id,)
            )
            for fav in body.favorites:
                await cur.execute(
                    """
                    INSERT INTO ios_user_favorites (user_id, song_id, title, artist, album)
                    VALUES (%s, %s, %s, %s, %s)
                    """,
                    (user_id, fav.song_id, fav.title, fav.artist, fav.album),
                )

            # Replace playlists
            await cur.execute(
                "DELETE FROM ios_user_playlists WHERE user_id = %s", (user_id,)
            )
            for pl in body.playlists:
                pl_id = pl.id or str(uuid.uuid4())
                await cur.execute(
                    """
                    INSERT INTO ios_user_playlists (id, user_id, name, description)
                    VALUES (%s, %s, %s, %s)
                    """,
                    (pl_id, user_id, pl.name, pl.description),
                )
                for idx, track in enumerate(pl.tracks):
                    track_id = str(uuid.uuid4())
                    await cur.execute(
                        """
                        INSERT INTO ios_playlist_tracks
                            (id, playlist_id, track_url, local_song_id, title, artist, album,
                             duration_seconds, position)
                        VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
                        """,
                        (
                            track_id,
                            pl_id,
                            track.track_url,
                            track.local_song_id,
                            track.title,
                            track.artist,
                            track.album,
                            track.duration_seconds or 0,
                            track.position if track.position is not None else idx,
                        ),
                    )

            # Update settings
            await cur.execute(
                """
                INSERT INTO ios_user_settings (user_id, audio_settings_json, theme_color)
                VALUES (%s, %s, %s)
                ON DUPLICATE KEY UPDATE
                    audio_settings_json = IF(%s IS NULL, audio_settings_json, %s),
                    theme_color = IF(%s IS NULL, theme_color, %s)
                """,
                (
                    user_id,
                    body.audio_settings_json,
                    body.theme_color or "#EC4079",
                    body.audio_settings_json,
                    body.audio_settings_json,
                    body.theme_color,
                    body.theme_color,
                ),
            )

    return {"status": "synced"}




# ---------------------------------------------------------------------------
# Server Music Library helpers
# ---------------------------------------------------------------------------

_FFPROBE_SEMAPHORE = asyncio.Semaphore(8)  # max 8 concurrent ffprobe processes


async def _ffprobe_tags(path: str) -> dict:
    """
    Run ffprobe on *path* and return a normalised track metadata dict.
    Returns a dict with all fields set to sensible defaults on any failure.
    """
    cmd = [
        "ffprobe",
        "-v", "quiet",
        "-print_format", "json",
        "-show_streams",
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

    tags: dict = audio_stream.get("tags") or {}
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

    return {
        "title": tags_lower.get("title") or tags_lower.get("name") or "",
        "artist": tags_lower.get("artist") or tags_lower.get("album_artist") or "",
        "album": tags_lower.get("album") or "",
        "genre": tags_lower.get("genre") or "",
        "track_number": tags_lower.get("track") or tags_lower.get("tracknumber") or "",
        "duration": duration,
        "has_artwork": has_artwork,
    }


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
    music_root = pathlib.Path(SERVER_MUSIC_DIR).resolve()
    full_path = (music_root / path).resolve()

    # Path traversal guard
    if not str(full_path).startswith(str(music_root)):
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
    music_root = pathlib.Path(SERVER_MUSIC_DIR).resolve()
    full_path = (music_root / path).resolve()

    # Path traversal guard
    if not str(full_path).startswith(str(music_root)):
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
    user: dict = Depends(get_current_user),
):
    """
    Uploads raw audio bytes to the authenticated user's personal music directory.
    Max 100 MB. The Content-Type header should match the audio format.
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

    dest_dir = music_dir / folder.strip("/") if folder.strip("/") else music_dir
    dest_dir.mkdir(parents=True, exist_ok=True)
    dest_path = dest_dir / safe_name

    body = await request.body()
    if not body:
        raise HTTPException(status_code=400, detail="Empty file body")
    if len(body) > 100 * 1024 * 1024:  # 100 MB
        raise HTTPException(status_code=413, detail="File too large (max 100 MB)")

    try:
        dest_path.write_bytes(body)
    except Exception as exc:
        logger.error("upload_user_music: write failed for user %s: %s", user_id, exc)
        raise HTTPException(status_code=500, detail="Failed to save file")

    logger.info("upload_user_music: saved %s for user %s (%d bytes)", safe_name, user_id, len(body))
    abs_path = str(dest_path.resolve())
    try:
        rel = str(dest_path.relative_to(music_dir))
    except ValueError:
        rel = safe_name
    return {"filename": safe_name, "path": rel, "id": _stable_id(abs_path), "size": len(body)}


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
    if not str(full_path).startswith(str(music_dir)):
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
    if not str(full_path).startswith(str(music_dir)):
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
    if not str(full_path).startswith(str(music_dir)):
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
# Internal Telemetry Endpoints
# ---------------------------------------------------------------------------


@app.post("/internal/logs", status_code=204)
async def ingest_logs(request: Request):
    """Receives batched log entries from iOS clients. No auth required for
    internal telemetry. Inserts into ios_app_logs table."""
    try:
        entries = await request.json()
        if not isinstance(entries, list):
            return
        pool = await get_pool()
        async with pool.acquire() as conn:
            async with conn.cursor() as cur:
                for e in entries[:100]:  # cap at 100 entries per batch
                    if not isinstance(e, dict):
                        continue
                    await cur.execute(
                        "INSERT IGNORE INTO ios_app_logs "
                        "(level, category, message, file, line, timestamp, extra) "
                        "VALUES (%s, %s, %s, %s, %s, %s, %s)",
                        (
                            str(e.get("level", "info"))[:10],
                            str(e.get("category", "general"))[:30],
                            str(e.get("message", ""))[:500],
                            str(e.get("file", ""))[:100],
                            int(e.get("line", 0)),
                            e.get("timestamp"),
                            json.dumps(e.get("extra", {})),
                        ),
                    )
    except Exception:
        pass  # Logging must never fail the app

# ---------------------------------------------------------------------------
# Entry point (for local dev without Docker)
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    import uvicorn

    uvicorn.run("main:app", host="0.0.0.0", port=8002, reload=True)
