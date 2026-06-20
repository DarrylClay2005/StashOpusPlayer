import aiomysql
import logging
import os
import pathlib

logger = logging.getLogger("ios-bridge.db")

DB_CONFIG = {
    "host": os.getenv("DB_HOST", "127.0.0.1"),
    "port": int(os.getenv("DB_PORT", "3306")),
    "user": os.getenv("DB_USER", "botuser"),
    "password": os.getenv("DB_PASSWORD", "bot_logins"),
    "db": os.getenv("DB_NAME", "discord_music_gws"),
    "charset": "utf8mb4",
    "autocommit": True,
}

_pool: aiomysql.Pool | None = None


async def get_pool() -> aiomysql.Pool:
    global _pool
    if _pool is None:
        _pool = await aiomysql.create_pool(**DB_CONFIG, minsize=1, maxsize=10)
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


async def init_db():
    """Create iOS-specific tables if they don't exist, wrapped in a transaction."""
    pool = await get_pool()
    raw = pathlib.Path(__file__).parent.joinpath("schema.sql").read_text()
    sql = _strip_sql_comments(raw)
    async with pool.acquire() as conn:
        async with conn.cursor() as cur:
            await conn.begin()
            try:
                for stmt in sql.split(";"):
                    stmt = stmt.strip()
                    if stmt:
                        await cur.execute(stmt)
                await conn.commit()
            except Exception:
                await conn.rollback()
                logger.exception("init_db failed; rolled back schema migration")
                raise
