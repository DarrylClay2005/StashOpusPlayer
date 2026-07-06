"""Aria Lumi — Lumisound's on-device music intelligence.

Aria is a persona wrapped around a Claude structured-output call
(call_intelligence). She upgrades a handful of the bridge's existing
rule-based decisions (metadata disambiguation today; EQ suggestion,
duplicate resolution, and Discover Mix curation are planned follow-ups using
the same helper), and — unlike a stateless API call — she remembers: every
correction a user makes after one of her suggestions is logged to
ios_aria_memory (see db/schema.sql) and fed back into her next prompt for
that task as few-shot context, so her judgment concretely improves from real
usage instead of resetting every request.

Every caller MUST treat a ``None`` return as "fall back to the existing
heuristic" — this module never raises past its own boundary, so a missing API
key, an Anthropic outage, or a rate limit never breaks a request path that
worked before this feature existed.
"""

import json
import logging
import os
import time

import anthropic

from db import get_pool

logger = logging.getLogger("ios-bridge.intelligence")

ANTHROPIC_API_KEY: str = os.getenv("ANTHROPIC_API_KEY", "")
INTELLIGENCE_MODEL = "claude-sonnet-5"

_client: anthropic.AsyncAnthropic | None = (
    anthropic.AsyncAnthropic(api_key=ANTHROPIC_API_KEY) if ANTHROPIC_API_KEY else None
)

# Per-task cooldown: once a task hits a rate limit, skip further calls for
# that task until this many seconds have passed, mirroring the YouTube Data
# API quota-cooldown pattern (_youtube_quota_exceeded_until in main.py) so a
# single 429 doesn't turn into a retry storm against Anthropic.
_COOLDOWN_SECONDS = 300
_cooldown_until: dict[str, float] = {}

# ---------------------------------------------------------------------------
# Persona + seeded domain knowledge
# ---------------------------------------------------------------------------
#
# Prepended to every task's system prompt. The "curated knowledge" section
# below is hand-authored reference material (not learned) — the kind of thing
# a domain expert would hand a new hire on day one, so Aria starts informed
# rather than blank. It supplements (never replaces) the model's own
# knowledge and the per-task few-shot corrections pulled from ios_aria_memory.
ARIA_PERSONA = """\
You are Aria Lumi, Lumisound's music intelligence — sharp-eared, confident,
and a little competitive about getting the call right. You carry yourself
like someone who takes music seriously enough to have opinions about it: a
touch of swagger, no patience for sloppy guesses, but genuinely invested in
the library you're curating rather than detached from it. You make small,
focused judgment calls that a rule-based heuristic used to make — picking the
right metadata match, later: the right EQ curve, the right duplicate
verdict, the right mix. You are never shown to the user as a chatbot; your
only output is the structured decision asked of you. Be decisive but
conservative: when a heuristic already has a strong signal (an exact match,
an unambiguous duplicate), defer to it rather than second-guessing. Only
assert a different answer when you have real signal the simple heuristic
lacks — confidence isn't the same as certainty, and a wrong pick made loudly
is still wrong.

Curated reference knowledge:
- Common YouTube/SoundCloud noise tags to ignore when comparing titles:
  "(Official Video)", "(Official Audio)", "(Official Music Video)", "(Lyrics)",
  "(Lyric Video)", "[HQ]", "[HD]", "(4K)", "(Visualizer)", "(Audio)",
  "(Explicit)", "(Clean)", "ft.", "feat.", "prod. by", "(Remastered)",
  bracketed year tags like "(2019)".
- Featured-artist clauses ("feat. X", "ft. X", "(with X)", "X Remix") describe
  collaborators, not the primary artist — do not let them override a strong
  primary-artist match.
- Diacritics and stylized casing are cosmetic, not semantic: "Beyoncé" ==
  "Beyonce", "SZA" == "Sza", "MØ" == "MO" — normalize before comparing.
- A title that is only a numbering/edition difference ("Song (Radio Edit)"
  vs "Song") is the same underlying song for metadata-matching purposes, but
  IS a meaningfully different edit for duplicate-detection purposes — do not
  conflate these two judgments.
"""


async def call_intelligence(
    task: str,
    system_prompt: str,
    user_content: dict,
    schema: dict,
) -> dict | None:
    """Runs one structured-output Claude call for *task*, as Aria Lumi.

    Returns the parsed JSON object on success, or None if intelligence is
    disabled (no API key), the task is cooling down after a rate limit, or
    the call failed for any reason. Callers always have a pre-existing
    heuristic to fall back to, so failures are logged, not raised.
    """
    if _client is None:
        return None
    until = _cooldown_until.get(task)
    if until is not None and time.monotonic() < until:
        return None

    try:
        response = await _client.messages.create(
            model=INTELLIGENCE_MODEL,
            max_tokens=1024,
            system=ARIA_PERSONA + "\n" + system_prompt,
            output_config={"format": {"type": "json_schema", "schema": schema}},
            messages=[{"role": "user", "content": json.dumps(user_content)}],
        )
        text = next(block.text for block in response.content if block.type == "text")
        return json.loads(text)
    except anthropic.RateLimitError:
        _cooldown_until[task] = time.monotonic() + _COOLDOWN_SECONDS
        logger.warning("intelligence task %s rate-limited; cooling down %ds", task, _COOLDOWN_SECONDS)
        return None
    except Exception:
        logger.exception("intelligence task %s failed", task)
        return None


# ---------------------------------------------------------------------------
# Memory: learning from corrections (ios_aria_memory)
# ---------------------------------------------------------------------------

_MAX_FEEDBACK_EXAMPLES = 5


async def get_recent_corrections(task: str, limit: int = _MAX_FEEDBACK_EXAMPLES) -> list[dict]:
    """Returns up to *limit* most recent user corrections for *task*, across
    all users, as few-shot examples: what Aria was shown, what she picked,
    and what the user actually confirmed instead. Empty list if the table
    has no rows yet or the DB is unreachable — never raises, since this is
    an enrichment of the prompt, not something request handling depends on.
    """
    try:
        pool = await get_pool()
        async with pool.acquire() as conn:
            async with conn.cursor() as cur:
                await cur.execute(
                    "SELECT input_json, ai_result_json, correction_json FROM ios_aria_memory "
                    "WHERE task = %s AND correction_json IS NOT NULL "
                    "ORDER BY created_at DESC LIMIT %s",
                    (task, limit),
                )
                rows = await cur.fetchall()
        return [
            {
                "input": json.loads(row[0]),
                "aria_picked": json.loads(row[1]),
                "user_corrected_to": json.loads(row[2]),
            }
            for row in rows
        ]
    except Exception:
        logger.exception("failed to load ios_aria_memory corrections for task %s", task)
        return []


async def record_suggestion(task: str, user_id: str, input_data: dict, ai_result: dict) -> int | None:
    """Logs a suggestion Aria made, so a later correction (record_correction)
    can reference it. Returns the new row's id, or None on failure (logging
    a suggestion is best-effort — never blocks the response that produced
    it)."""
    try:
        pool = await get_pool()
        async with pool.acquire() as conn:
            async with conn.cursor() as cur:
                await cur.execute(
                    "INSERT INTO ios_aria_memory (user_id, task, input_json, ai_result_json) "
                    "VALUES (%s, %s, %s, %s)",
                    (user_id, task, json.dumps(input_data), json.dumps(ai_result)),
                )
                return cur.lastrowid
    except Exception:
        logger.exception("failed to record ios_aria_memory suggestion for task %s", task)
        return None


async def record_correction(memory_id: int, correction: dict) -> None:
    """Attaches a user's correction to a previously-logged suggestion. Silent
    no-op on failure or if *memory_id* doesn't exist."""
    try:
        pool = await get_pool()
        async with pool.acquire() as conn:
            async with conn.cursor() as cur:
                await cur.execute(
                    "UPDATE ios_aria_memory SET correction_json = %s WHERE id = %s",
                    (json.dumps(correction), memory_id),
                )
    except Exception:
        logger.exception("failed to record correction for ios_aria_memory id %s", memory_id)
