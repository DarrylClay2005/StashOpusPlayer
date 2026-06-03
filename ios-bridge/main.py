import asyncio
import json
import logging
import os
import time
from typing import Optional

from fastapi import FastAPI, HTTPException, Query, Request
from fastapi.middleware.cors import CORSMiddleware

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
# App
# ---------------------------------------------------------------------------

app = FastAPI(title="StashOpusPlayer iOS Bridge", version=VERSION)

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
# Auth dependency
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
# Endpoints
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
# Entry point (for local dev without Docker)
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    import uvicorn

    uvicorn.run("main:app", host="0.0.0.0", port=7333, reload=True)
