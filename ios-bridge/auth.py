import asyncio
import pathlib
import secrets

import bcrypt
import jwt
import os
from datetime import datetime, timedelta, timezone

JWT_ALGORITHM = "HS256"
TOKEN_EXPIRE_DAYS = 30


def _get_jwt_secret() -> str:
    env = os.getenv("IOS_JWT_SECRET", "").strip()
    if env:
        return env
    secret_file = pathlib.Path("/app/.bridge_jwt_secret")
    try:
        if secret_file.exists():
            return secret_file.read_text().strip()
        s = secrets.token_hex(32)
        secret_file.write_text(s)
        return s
    except Exception:
        # Non-persistent fallback if /app is not writable (e.g. local dev)
        return secrets.token_hex(32)


JWT_SECRET = _get_jwt_secret()


def hash_password(password: str) -> str:
    return bcrypt.hashpw(password.encode(), bcrypt.gensalt()).decode()


def verify_password(password: str, hashed: str) -> bool:
    return bcrypt.checkpw(password.encode(), hashed.encode())


async def hash_password_async(password: str) -> str:
    """Run bcrypt hashing in a thread pool to avoid blocking the event loop."""
    loop = asyncio.get_event_loop()
    return await loop.run_in_executor(None, hash_password, password)


async def verify_password_async(password: str, hashed: str) -> bool:
    """Run bcrypt verification in a thread pool to avoid blocking the event loop."""
    loop = asyncio.get_event_loop()
    return await loop.run_in_executor(None, verify_password, password, hashed)


def create_token(user_id: str, token_id: str, expire_days: int = TOKEN_EXPIRE_DAYS) -> str:
    payload = {
        "sub": user_id,
        "jti": token_id,
        "exp": datetime.now(timezone.utc) + timedelta(days=expire_days),
        "iat": datetime.now(timezone.utc),
    }
    return jwt.encode(payload, JWT_SECRET, algorithm=JWT_ALGORITHM)


def decode_token(token: str) -> dict | None:
    try:
        return jwt.decode(token, JWT_SECRET, algorithms=[JWT_ALGORITHM])
    except Exception:
        return None


# ---------------------------------------------------------------------------
# TOTP two-factor auth — pending-login token
# ---------------------------------------------------------------------------
#
# Deliberately a separate token type from create_token/decode_token's session
# tokens, rather than reusing them with a short expire_days: a session token's
# "jti" is expected by get_current_user to reference a live row in
# ios_user_sessions, and giving one out before the user has actually completed
# 2FA would let the password-only step act as a fully authenticated session if
# any endpoint ever forgot to check the extra claim. A pending token instead
# carries its own "purpose" claim and is verified by a completely separate
# function that no authenticated endpoint calls.

TOTP_PENDING_EXPIRE_SECONDS = 300  # 5 minutes to enter the code


def create_totp_pending_token(user_id: str) -> str:
    payload = {
        "sub": user_id,
        "purpose": "totp_pending",
        "exp": datetime.now(timezone.utc) + timedelta(seconds=TOTP_PENDING_EXPIRE_SECONDS),
        "iat": datetime.now(timezone.utc),
    }
    return jwt.encode(payload, JWT_SECRET, algorithm=JWT_ALGORITHM)


def decode_totp_pending_token(token: str) -> str | None:
    """Returns the pending user_id if *token* is a valid, unexpired
    totp_pending token, else None."""
    try:
        payload = jwt.decode(token, JWT_SECRET, algorithms=[JWT_ALGORITHM])
    except Exception:
        return None
    if payload.get("purpose") != "totp_pending":
        return None
    return payload.get("sub")


# ---------------------------------------------------------------------------
# Discord OAuth2 account-verification state token
# ---------------------------------------------------------------------------
#
# Same shape as the totp_pending token above (a separate "purpose"-scoped JWT,
# never accepted by get_current_user's session lookup) — used as the OAuth2
# "state" parameter for /api/discord/oauth/start -> /api/discord/oauth/callback.
# Discord's callback is an unauthenticated browser redirect (no Authorization
# header this server issued), so this signed, short-lived, tamper-proof token
# is both the CSRF-protection "state" value the OAuth2 spec requires AND the
# only way the callback recovers *which account* started the flow — without
# needing an in-memory state store that wouldn't survive a bridge restart or
# work across multiple worker processes.

DISCORD_OAUTH_STATE_EXPIRE_SECONDS = 600  # 10 minutes to complete the Discord consent screen


def create_discord_oauth_state_token(user_id: str) -> str:
    payload = {
        "sub": user_id,
        "purpose": "discord_oauth_state",
        "exp": datetime.now(timezone.utc) + timedelta(seconds=DISCORD_OAUTH_STATE_EXPIRE_SECONDS),
        "iat": datetime.now(timezone.utc),
    }
    return jwt.encode(payload, JWT_SECRET, algorithm=JWT_ALGORITHM)


def decode_discord_oauth_state_token(token: str) -> str | None:
    """Returns the initiating user_id if *token* is a valid, unexpired
    discord_oauth_state token, else None."""
    try:
        payload = jwt.decode(token, JWT_SECRET, algorithms=[JWT_ALGORITHM])
    except Exception:
        return None
    if payload.get("purpose") != "discord_oauth_state":
        return None
    return payload.get("sub")


# ---------------------------------------------------------------------------
# Discord OAuth2 sign-in/sign-up state token
# ---------------------------------------------------------------------------
#
# Separate "purpose" from discord_oauth_state above, even though both are
# used as the OAuth2 "state" param on the SAME Discord-registered redirect
# URI (see /auth/discord/start's doc comment on the bridge for why this
# doesn't need its own redirect URI) — this one has no `sub` at all, since
# it's minted from the logged-OUT login screen, before there's any account
# to attribute it to. Keeping the purposes distinct means a token minted for
# one flow can never be replayed as the other: this one decodes to a plain
# bool (valid-and-unexpired or not), never to a user_id a link-flow token
# would trust.

DISCORD_OAUTH_LOGIN_STATE_EXPIRE_SECONDS = 600  # 10 minutes to complete the Discord consent screen


def create_discord_oauth_login_state_token() -> str:
    payload = {
        "purpose": "discord_oauth_login_state",
        "exp": datetime.now(timezone.utc) + timedelta(seconds=DISCORD_OAUTH_LOGIN_STATE_EXPIRE_SECONDS),
        "iat": datetime.now(timezone.utc),
    }
    return jwt.encode(payload, JWT_SECRET, algorithm=JWT_ALGORITHM)


def decode_discord_oauth_login_state_token(token: str) -> bool:
    """True if *token* is a valid, unexpired discord_oauth_login_state token."""
    try:
        payload = jwt.decode(token, JWT_SECRET, algorithms=[JWT_ALGORITHM])
    except Exception:
        return False
    return payload.get("purpose") == "discord_oauth_login_state"
