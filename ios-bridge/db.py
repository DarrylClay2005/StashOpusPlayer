import aiopg
import json
import logging
import os
import pathlib

logger = logging.getLogger("ios-bridge.db")

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

    The schema is split naively on `;`, so a semicolon *inside* a comment
    (e.g. "Never echoed back to clients; see ...") used to slice a comment in
    half and feed the trailing fragment to the DB as bogus SQL — crashing
    startup. Stripping everything from `--` to end-of-line first makes the
    splitter immune to punctuation in comments. (`--` only ever introduces a
    comment in this DDL-only schema; it never appears inside a string literal.)
    """
    lines: list[str] = []
    for line in sql.splitlines():
        idx = line.find("--")
        lines.append(line[:idx] if idx != -1 else line)
    return "\n".join(lines)


def _split_sql_statements(sql: str) -> list[str]:
    """Splits *sql* on `;`, except for semicolons inside a `$$ ... $$`
    dollar-quoted block.

    Postgres trigger functions (see the `ios_touch_*` functions/triggers at
    the end of schema.sql) are plpgsql bodies quoted with `$$ ... $$` and are
    themselves full of statement-terminating semicolons (`NEW.x := ...;`,
    `RETURN NEW;`) — a plain `sql.split(";")` chops a function body into
    fragments and feeds Postgres invalid partial statements (or, worse, an
    "unterminated dollar-quoted string" error) instead of the one
    CREATE FUNCTION statement it actually is. This mirrors
    `_strip_sql_comments`'s exact rationale (a schema this simple stays
    splittable by a punctuation character, as long as that one character's
    occurrences *inside* something else are excluded first) but for `$$`
    blocks instead of `--` comments.
    """
    statements: list[str] = []
    buf: list[str] = []
    in_dollar_quote = False
    i = 0
    n = len(sql)
    while i < n:
        if sql[i : i + 2] == "$$":
            in_dollar_quote = not in_dollar_quote
            buf.append("$$")
            i += 2
            continue
        ch = sql[i]
        if ch == ";" and not in_dollar_quote:
            statements.append("".join(buf))
            buf = []
        else:
            buf.append(ch)
        i += 1
    if buf:
        statements.append("".join(buf))
    return statements


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
