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
import pathlib

from db import _lua, get_pool

logger = logging.getLogger("ios-bridge.aria_apis")

# Row-shaping logic ported to Lua — see lua/aria_shaping.lua. Reuses db.py's
# already-initialized Lua runtime rather than starting a second one.
_aria_shaping = _lua.execute(
    pathlib.Path(__file__).parent.joinpath("lua", "aria_shaping.lua").read_text()
)


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
                rows = await cur.fetchall()
                lua_rows = _lua.table_from([_lua.table_from(row) for row in rows])
                return list(_aria_shaping.genre_snapshot(lua_rows).values())
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
                rows = await cur.fetchall()
                lua_rows = _lua.table_from([_lua.table_from(row) for row in rows])
                lua_result = _aria_shaping.playlist_context(lua_rows)
                return [dict(entry.items()) for entry in lua_result.values()]
    except Exception:
        logger.exception("get_playlist_context failed for user %s", user_id)
        return []


async def get_recent_housekeeping(user_id: str, days: int = 14, limit: int = 20) -> list[dict]:
    """Aria's own memory of the autonomous cleanup she's actually done for
    this user recently (duplicate copies trashed, corrupt files trashed —
    see `ios_aria_actions`, written by `POST /user/intelligence/actions`
    right after each on-device action). Distinct from `ios_aria_memory`
    (her suggestion history): this is what she DID, not what she merely
    proposed. Feeds her taste-profile context so she can reference her own
    housekeeping conversationally ("cleaned up 3 corrupt files this week")
    instead of only ever talking about the user's music."""
    try:
        pool = await get_pool()
        async with pool.acquire() as conn:
            async with conn.cursor() as cur:
                await cur.execute(
                    "SELECT action_type, title, artist, created_at, reverted_at "
                    "FROM ios_aria_actions "
                    "WHERE user_id = %s AND created_at > NOW() - (%s || ' days')::interval "
                    "ORDER BY created_at DESC LIMIT %s",
                    (user_id, days, limit),
                )
                rows = await cur.fetchall()
                return [
                    {
                        "action_type": row[0],
                        "title": row[1],
                        "artist": row[2],
                        "created_at": row[3].isoformat() if row[3] else None,
                        "reverted": row[4] is not None,
                    }
                    for row in rows
                ]
    except Exception:
        logger.exception("get_recent_housekeeping failed for user %s", user_id)
        return []
