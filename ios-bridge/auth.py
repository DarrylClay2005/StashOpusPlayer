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


def create_token(user_id: str, token_id: str) -> str:
    payload = {
        "sub": user_id,
        "jti": token_id,
        "exp": datetime.now(timezone.utc) + timedelta(days=TOKEN_EXPIRE_DAYS),
        "iat": datetime.now(timezone.utc),
    }
    return jwt.encode(payload, JWT_SECRET, algorithm=JWT_ALGORITHM)


def decode_token(token: str) -> dict | None:
    try:
        return jwt.decode(token, JWT_SECRET, algorithms=[JWT_ALGORITHM])
    except Exception:
        return None
