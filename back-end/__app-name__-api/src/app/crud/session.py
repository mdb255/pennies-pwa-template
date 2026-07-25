"""Session CRUD (server-side refresh-token store for TMB).

`sqlmodel.Session` (the DB session) is aliased to `DBSession` here so it doesn't collide
with our `Session` table model.
"""

import secrets
from datetime import datetime, timedelta
from typing import Optional

from sqlmodel import Session as DBSession
from sqlmodel import select

from ..models.session import Session


class SessionCRUD:
    """Operations on the server-side `sessions` table."""

    def create(self, db: DBSession, *, cognito_sub: str, refresh_token: str, ttl: int) -> Session:
        """Create a session, returning it (its `id` is the opaque cookie value)."""
        db_obj = Session(
            id=secrets.token_urlsafe(32),
            cognito_sub=cognito_sub,
            refresh_token=refresh_token,
            expires_at=datetime.utcnow() + timedelta(seconds=ttl),
        )
        db.add(db_obj)
        db.commit()
        db.refresh(db_obj)
        return db_obj

    def get(self, db: DBSession, session_id: str) -> Optional[Session]:
        """Get a live session by id. Returns None if missing or expired."""
        session = db.get(Session, session_id)
        if session is None or session.expires_at <= datetime.utcnow():
            return None
        return session

    def rotate(
        self, db: DBSession, *, session_id: str, new_refresh_token: str
    ) -> Optional[Session]:
        """Replace the stored refresh token after Cognito rotates it."""
        session = db.get(Session, session_id)
        if session is None:
            return None
        session.refresh_token = new_refresh_token
        session.rotated_at = datetime.utcnow()
        db.add(session)
        db.commit()
        db.refresh(session)
        return session

    def delete(self, db: DBSession, session_id: str) -> None:
        """Delete a session by id (idempotent)."""
        session = db.get(Session, session_id)
        if session is not None:
            db.delete(session)
            db.commit()

    def delete_expired(self, db: DBSession) -> int:
        """Sweep expired sessions. Returns the number removed."""
        statement = select(Session).where(Session.expires_at <= datetime.utcnow())
        expired = db.exec(statement).all()
        for session in expired:
            db.delete(session)
        db.commit()
        return len(expired)


session = SessionCRUD()
