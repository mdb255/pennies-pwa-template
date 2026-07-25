"""Server-side session model (TMB).

Holds the Cognito refresh token server-side. The browser only ever sees the opaque
primary key (`id`) via a host-only HttpOnly cookie. Named `Session` per the design; note
the clash with `sqlmodel.Session` (the DB session) — importers alias one of them.
"""

from datetime import datetime
from typing import Optional

from sqlmodel import Field, SQLModel


class Session(SQLModel, table=True):
    """A server-side auth session. One row per active login."""

    __tablename__ = "sessions"

    # Opaque, unguessable session id handed to the browser (secrets.token_urlsafe(32)).
    id: str = Field(primary_key=True)
    cognito_sub: str = Field(index=True)
    # Cognito refresh token, stored server-side. Plaintext at rest for v1 (see
    # settings.session_token_encryption_key for the deferred encryption hook).
    refresh_token: str
    created_at: datetime = Field(default_factory=datetime.utcnow)
    # now + session TTL; indexed so delete_expired() can sweep cheaply.
    expires_at: datetime = Field(index=True)
    # Set whenever Cognito rotates the refresh token on resume.
    rotated_at: Optional[datetime] = Field(default=None)
