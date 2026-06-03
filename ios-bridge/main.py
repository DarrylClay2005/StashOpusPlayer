import asyncio
import json
import logging
import os
import time
import uuid
from contextlib import asynccontextmanager
from datetime import datetime, timedelta, timezone
from typing import Optional

from fastapi import Depends, FastAPI, HTTPException, Query, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from pydantic import BaseModel

from auth import create_token, decode_token, hash_password, verify_password
from db import get_pool, init_db

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
VERSION = "1.0.0"

# ---------------------------------------------------------------------------
# Lifespan
# ---------------------------------------------------------------------------


@asynccontextmanager
async def lifespan(app: FastAPI):
    await init_db()
    yield


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
    """
    cmd = ["yt-dlp", *args]
    logger.info("Running: %s", " ".join(cmd))
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
        await proc.communicate()
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

    # Artist: uploader / channel / artist tag, in priority order
    artist = (
        entry.get("artist")
        or entry.get("uploader")
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
    """Map a (id, username, email, display_name, avatar_url, created_at, last_login) row."""
    return {
        "id": row[0],
        "username": row[1],
        "email": row[2],
        "display_name": row[3],
        "avatar_url": row[4],
        "created_at": row[5].isoformat() if row[5] else None,
        "last_login": row[6].isoformat() if row[6] else None,
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

    base_args = [
        search_url,
        "--dump-json",
        "--flat-playlist",
        "--no-playlist",
    ]
    if source == "youtube":
        base_args += ["--cache-dir", YTDLP_CACHE_DIR]

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
):
    await check_auth(request)

    source = source.lower()

    if source == "soundcloud":
        if not url:
            raise HTTPException(
                status_code=400, detail="url parameter required for soundcloud source"
            )
        target_url = url
    else:
        target_url = f"https://youtube.com/watch?v={id}"

    try:
        lines = await _run_ytdlp(
            "-f", "bestaudio[ext=m4a]/bestaudio/best",
            "--get-url",
            "--no-playlist",
            target_url,
            timeout=15.0,
        )
    except asyncio.TimeoutError:
        raise HTTPException(status_code=408, detail="Stream URL fetch timed out")
    except Exception as exc:
        logger.error("yt-dlp stream error: %s", exc)
        raise HTTPException(status_code=404, detail="Could not resolve stream URL")

    # --get-url outputs plain text lines (not JSON); _run_ytdlp only keeps valid JSON,
    # so we need to handle this separately.  Re-run with raw stdout capture.
    stream_url = await _get_raw_url(target_url)
    if not stream_url:
        raise HTTPException(status_code=404, detail="No stream URL found")

    return {"url": stream_url, "expires_in": 21600}


async def _get_raw_url(target_url: str) -> Optional[str]:
    """Like _run_ytdlp but captures the first non-empty line as plain text."""
    cmd = [
        "yt-dlp",
        "-f", "bestaudio[ext=m4a]/bestaudio/best",
        "--get-url",
        "--no-playlist",
        target_url,
    ]
    logger.info("Running (raw): %s", " ".join(cmd))
    proc = await asyncio.create_subprocess_exec(
        *cmd,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
    )
    try:
        stdout_bytes, _ = await asyncio.wait_for(proc.communicate(), timeout=15.0)
    except asyncio.TimeoutError:
        proc.kill()
        await proc.communicate()
        raise HTTPException(status_code=408, detail="Stream URL fetch timed out")

    for raw_line in stdout_bytes.splitlines():
        line = raw_line.strip().decode(errors="replace")
        if line.startswith("http"):
            return line
    return None


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
async def register(body: RegisterRequest):
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
            password_hash = hash_password(body.password)

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
                "SELECT id, username, email, display_name, avatar_url, created_at, last_login "
                "FROM ios_users WHERE id = %s",
                (user_id,),
            )
            row = await cur.fetchone()

    return {"user": _user_dict(row), "token": token}


@app.post("/auth/login")
async def login(body: LoginRequest):
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
        raise HTTPException(status_code=401, detail="Invalid username or password")

    (user_id, username, email, display_name, avatar_url,
     created_at, last_login, password_hash, is_active) = row

    if not is_active:
        raise HTTPException(status_code=403, detail="Account is disabled")

    if not verify_password(body.password, password_hash):
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
    user = {
        "id": user_id,
        "username": username,
        "email": email,
        "display_name": display_name,
        "avatar_url": avatar_url,
        "created_at": created_at.isoformat() if created_at else None,
        "last_login": datetime.now(timezone.utc).isoformat(),
    }
    return {"user": user, "token": token}


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
                "SELECT id, username, email, display_name, avatar_url, created_at, last_login "
                "FROM ios_users WHERE id = %s AND is_active = TRUE",
                (user_id,),
            )
            row = await cur.fetchone()

    if not row:
        raise HTTPException(status_code=401, detail="User not found")
    return _user_dict(row)


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
# Entry point (for local dev without Docker)
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    import uvicorn

    uvicorn.run("main:app", host="0.0.0.0", port=7333, reload=True)
