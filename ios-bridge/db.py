import aiopg
import json
import logging
import os
import pathlib

from lupa import LuaRuntime

logger = logging.getLogger("ios-bridge.db")

# Embedded Lua runtime for business logic that's been ported to Lua (starting
# with the schema SQL-splitting helpers below) — mirrors how the iOS client
# already embeds Lua (LuaSwift) for its own scripting layer, moving pieces of
# server logic onto the same language over time rather than in one large
# rewrite. sql_split.lua ends with `return M`, so executing its source
# directly yields that module table, exposing strip_sql_comments /
# split_sql_statements as regular callables from Python.
_lua = LuaRuntime(unpack_returned_tuples=True)
_sql_split = _lua.execute(
    pathlib.Path(__file__).parent.joinpath("lua", "sql_split.lua").read_text()
)

# aiopg wraps psycopg2 and keeps the same %s-placeholder /
# cursor.execute()/fetchone()/fetchall() API aiomysql used, which is why this
# migration (MariaDB/MySQL -> PostgreSQL) swaps the driver here instead of
# rewriting every one of main.py's ~1150 SQL call sites for asyncpg's
# incompatible $1/$2 placeholders and row-object API. Postgres uses `dbname`
# (not `db`) and has no per-connection `charset` param (encoding is UTF-8 by
# default / set server-side), and the default port is 5432.
DB_CONFIG = {
    "host": os.getenv("DB_HOST", "127.0.0.1"),
    "port": int(os.getenv("DB_PORT", "5432")),
    "user": os.getenv("DB_USER", "botuser"),
    "password": os.getenv("DB_PASSWORD", "bot_logins"),
    "dbname": os.getenv("DB_NAME", "discord_music_gws"),
}

_pool: aiopg.Pool | None = None


async def get_pool() -> aiopg.Pool:
    global _pool
    if _pool is None:
        # aiopg connections default to autocommit=True (verified against the
        # real driver), matching aiomysql's explicit autocommit=True this
        # pool used to pass — every plain cur.execute() below still commits
        # immediately with no code changes needed at the ~1150 call sites
        # elsewhere in the app. init_db() below is the one place that needs
        # a real multi-statement transaction, which it gets via explicit
        # BEGIN/COMMIT/ROLLBACK statements rather than driver-level
        # conn.begin()/commit()/rollback() — psycopg2/aiopg connections
        # raise "commit cannot be used in asynchronous mode" if you call
        # conn.commit()/rollback() directly instead of issuing the SQL.
        _pool = await aiopg.create_pool(**DB_CONFIG, minsize=1, maxsize=10)
    return _pool


def _strip_sql_comments(sql: str) -> str:
    """Removes `--` line comments before the statements are split on `;`.
    Implemented in Lua — see lua/sql_split.lua for the full rationale."""
    return _sql_split.strip_sql_comments(sql)


def _split_sql_statements(sql: str) -> list[str]:
    """Splits *sql* on `;`, except for semicolons inside a `$$ ... $$`
    dollar-quoted block. Implemented in Lua — see lua/sql_split.lua for the
    full rationale. Lua tables are 1-indexed and come back from lupa as a
    table object, not a Python list, so callers get a proper list here."""
    lua_statements = _sql_split.split_sql_statements(sql)
    return list(lua_statements.values())


async def init_db():
    """Create iOS-specific tables if they don't exist, wrapped in a transaction."""
    pool = await get_pool()
    raw = pathlib.Path(__file__).parent.joinpath("schema.sql").read_text()
    sql = _strip_sql_comments(raw)
    async with pool.acquire() as conn:
        async with conn.cursor() as cur:
            await cur.execute("BEGIN")
            try:
                for stmt in _split_sql_statements(sql):
                    stmt = stmt.strip()
                    if stmt:
                        await cur.execute(stmt)
                await cur.execute("COMMIT")
            except Exception:
                await cur.execute("ROLLBACK")
                logger.exception("init_db failed; rolled back schema migration")
                raise


# ---------------------------------------------------------------------------
# General-purpose structured event logging (ios_app_event_log)
# ---------------------------------------------------------------------------
#
# A single reusable sink for "something happened" events across systems that
# previously had no DB-side audit trail at all (auth, sync, backups,
# metadata/intelligence operations, etc.). Deliberately distinct from:
#   - ios_app_logs: raw client debug-log lines (file/line/level), ingested in
#     bulk from the iOS app's local AppLogger buffer via POST /internal/logs.
#   - ios_sync_log / ios_search_log: narrow, single-purpose logs that predate
#     this table and are left as-is.
# ios_app_event_log instead models a *structured business event*: a
# source (which side produced it), an optional user, a category, a short
# event name, a severity level, a human-readable message, and an optional
# JSON detail blob for anything structured (counts, durations, ids). Both the
# bridge itself and the iOS client (via POST /api/log-event, see main.py) can
# write to it, so the same table can answer "what happened for this user
# across the whole app" instead of being split per-feature.
async def log_event(
    category: str,
    event: str,
    *,
    source: str = "bridge",
    user_id: str | None = None,
    level: str = "info",
    message: str = "",
    detail: dict | None = None,
) -> None:
    """Best-effort structured event log. Never raises — logging must never
    break the request/operation that produced the event, so any failure here
    (DB unreachable, bad JSON, etc.) is caught and reported only via the
    ordinary Python logger."""
    try:
        pool = await get_pool()
        async with pool.acquire() as conn:
            async with conn.cursor() as cur:
                await cur.execute(
                    "INSERT INTO ios_app_event_log "
                    "(source, user_id, category, event, level, message, detail) "
                    "VALUES (%s, %s, %s, %s, %s, %s, %s)",
                    (
                        (source or "bridge")[:20],
                        user_id[:36] if user_id else None,
                        category[:30],
                        event[:60],
                        (level or "info")[:10],
                        (message or "")[:2000],
                        json.dumps(detail) if detail is not None else None,
                    ),
                )
    except Exception:
        logger.exception("log_event failed (category=%s event=%s)", category, event)
