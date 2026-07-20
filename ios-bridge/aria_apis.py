"""Aria Lumi's own data APIs.

Dedicated, read-only data-access functions that belong to Aria specifically —
kept separate from intelligence.py's generic call_intelligence/memory
plumbing so it's clear which surface is "hers": each function here gathers
one slice of a user's real library/listening context that the plain
get_user_taste_profile (artist plays + favorites) doesn't cover. Everything
here follows the same contract as the rest of the intelligence module: never
raises past its own boundary, returns an empty/default result on any DB
failure so a missing signal degrades gracefully rather than breaking the
request that wanted it.
"""

import logging

from db import get_pool

logger = logging.getLogger("ios-bridge.aria_apis")


async def get_library_genre_snapshot(user_id: str, limit: int = 10) -> list[str]:
    """Aria's view into what genres actually make up this user's own cloud
    library (ios_user_music_metadata — files they've uploaded, tagged with
    genre at upload/scan time), most-represented first. Distinct from taste
    inferred from play history: this is about library COMPOSITION, not
    listening behavior — a user's library can be genre-diverse even if they
    mostly replay a handful of tracks, and that diversity is itself useful
    context for a metadata pick (a candidate whose genre is completely
    foreign to everything else this user owns is weaker evidence than one
    that fits right in)."""
    try:
        pool = await get_pool()
        async with pool.acquire() as conn:
            async with conn.cursor() as cur:
                await cur.execute(
                    "SELECT genre, COUNT(*) AS n FROM ios_user_music_metadata "
                    "WHERE user_id = %s AND genre IS NOT NULL AND genre != '' "
                    "GROUP BY genre ORDER BY n DESC LIMIT %s",
                    (user_id, limit),
                )
                return [row[0] for row in await cur.fetchall()]
    except Exception:
        logger.exception("get_library_genre_snapshot failed for user %s", user_id)
        return []


async def get_playlist_context(user_id: str, limit: int = 10) -> list[dict]:
    """Aria's view into how this user organizes their own music: their most
    recently updated playlists' names and how many tracks each has. Playlist
    names are often a genuine taste/mood signal on their own ("Late Night
    Coding", "90s Hip Hop") that neither play counts nor favorites capture —
    used as soft context only, same as everything else this module returns."""
    try:
        pool = await get_pool()
        async with pool.acquire() as conn:
            async with conn.cursor() as cur:
                await cur.execute(
                    "SELECT p.name, COUNT(t.id) AS track_count "
                    "FROM ios_user_playlists p "
                    "LEFT JOIN ios_playlist_tracks t ON t.playlist_id = p.id "
                    "WHERE p.user_id = %s "
                    "GROUP BY p.id, p.name ORDER BY p.updated_at DESC LIMIT %s",
                    (user_id, limit),
                )
                return [{"name": row[0], "track_count": row[1]} for row in await cur.fetchall()]
    except Exception:
        logger.exception("get_playlist_context failed for user %s", user_id)
        return []
