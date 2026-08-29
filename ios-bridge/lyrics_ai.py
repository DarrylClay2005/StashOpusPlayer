"""Aria Lumi's audio-to-lyrics transcription.

The "listen and check" half of the lyrics system: the existing pipeline
(LRCLIB/lyrics.ovh fetch, manual .lrc/.txt import — see
NowPlayingView+Helpers.swift's loadLyrics()) only ever trusts fetched or
imported TEXT, with no way to verify it actually matches a given track, and
no way to produce anything at all for a user's own unreleased/personal
recording that no lyrics database has ever heard of. This module has Aria
actually listen to the audio (Gemini's native audio understanding) and
either transcribes it from scratch or, when candidate text is available,
corrects and re-times it against what's really in the recording.

Same failure contract as intelligence.py's call_intelligence: returns None
on any failure (no API key, rate limit, bad response) — every caller
already has "no AI-generated lyrics for this track" as a safe, pre-existing
fallback, since none of the existing lyrics paths depend on this.
"""

import asyncio
import json
import logging

from google.genai import errors as genai_errors
from google.genai import types as genai_types

import intelligence

logger = logging.getLogger("ios-bridge.lyrics_ai")

_LYRICS_SCHEMA = {
    "type": "object",
    "properties": {
        "instrumental": {"type": "boolean"},
        "confidence": {"type": "string", "enum": ["high", "medium", "low"]},
        "lines": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "time_seconds": {"type": "number"},
                    "text": {"type": "string"},
                },
                "required": ["time_seconds", "text"],
            },
        },
    },
    "required": ["instrumental", "confidence", "lines"],
}

_SYSTEM_PROMPT = """\
You are transcribing lyrics for a music player's synced-lyrics display.
Listen to the attached audio track carefully and produce a line-by-line
transcription of exactly what is sung or rapped, each line tagged with the
timestamp (in seconds from the start of the track) at which that line
actually begins in the audio. Timestamps must reflect the REAL audio, not
guesses from a lyrics database — treat your own ears as the source of
truth.

If existing candidate lyrics text is provided below, use it as a starting
point (it saves you re-transcribing wording you can already reuse), but you
MUST correct any word, line order, or line count where it doesn't match
what you actually hear in the audio, and you must derive every timestamp
from the audio yourself, since candidate text never comes with real timing.
Do not invent lines that aren't actually present in the audio, and do not
omit lines that are present.

If the track is instrumental (no sung/spoken words) or you cannot make out
any lyrics with reasonable confidence, set "instrumental" to true (only if
there are no words at all) and return an empty "lines" array, and set
"confidence" to "low" — never fabricate lyrics you aren't reasonably sure
of; a user's own personal recording deserves an honest "couldn't make this
out" over confidently wrong text.
"""


def _run_transcription(audio_bytes: bytes, mime_type: str, title: str, artist: str, hint_lyrics: str | None) -> str:
    """The actual blocking Gemini call — run via asyncio.to_thread by the
    caller, same pattern intelligence.py's _run_gemini_request uses."""
    user_text = {"title": title, "artist": artist, "candidate_lyrics": hint_lyrics or None}
    parts: list[genai_types.Part] = [
        genai_types.Part.from_text(text=json.dumps(user_text)),
        genai_types.Part.from_bytes(data=audio_bytes, mime_type=mime_type),
    ]
    config = genai_types.GenerateContentConfig(
        system_instruction=intelligence.ARIA_PERSONA + "\n" + _SYSTEM_PROMPT,
        response_mime_type="application/json",
        response_schema=_LYRICS_SCHEMA,
        # Native-audio transcription of a whole track is a much slower call
        # than the text-only Gemini calls elsewhere in this file (audio
        # bytes for a full 3-5 min track, not just a text prompt) and had NO
        # explicit timeout at all before this, relying on the SDK default —
        # a hung/slow request could run indefinitely inside the background
        # job below with nothing to ever mark it failed. 240s comfortably
        # covers a long track while still guaranteeing the job eventually
        # resolves either way. (milliseconds, per google-genai's HttpOptions)
        http_options=genai_types.HttpOptions(timeout=240_000),
    )
    response = intelligence._client.models.generate_content(
        model=intelligence.INTELLIGENCE_MODEL,
        contents=parts,
        config=config,
    )
    text = (response.text or "").strip()
    if not text:
        raise RuntimeError("Gemini returned an empty response")
    return text


async def transcribe_lyrics(
    audio_bytes: bytes, mime_type: str, title: str, artist: str, hint_lyrics: str | None = None
) -> dict | None:
    """Returns {"instrumental": bool, "confidence": str, "lines": [{"time_seconds": float, "text": str}]},
    or None on any failure — no API key configured, a Gemini error, or an
    unparseable response."""
    if intelligence._client is None:
        return None
    try:
        text = await asyncio.to_thread(_run_transcription, audio_bytes, mime_type, title, artist, hint_lyrics)
        parsed = json.loads(text)
        if not isinstance(parsed.get("lines"), list):
            return None
        return parsed
    except genai_errors.APIError as exc:
        logger.warning("transcribe_lyrics: Gemini API error: %s", exc)
        return None
    except Exception:
        logger.exception("transcribe_lyrics: unexpected failure")
        return None
