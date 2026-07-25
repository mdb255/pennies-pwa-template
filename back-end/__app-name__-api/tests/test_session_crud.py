"""Tests for the server-side session store (crud/session.py)."""

from datetime import datetime, timedelta

from sqlmodel import Session as DBSession
from sqlmodel import select

from app.crud.session import session as session_store
from app.models.session import Session

SUB = "test-session-crud-sub"


def _cleanup(db: DBSession, sub: str = SUB):
    for row in db.exec(select(Session).where(Session.cognito_sub == sub)).all():
        db.delete(row)
    db.commit()


def test_create_returns_opaque_id_and_persists(db: DBSession):
    created = session_store.create(db, cognito_sub=SUB, refresh_token="rt-1", ttl=3600)
    try:
        assert created.id and len(created.id) >= 32  # opaque, unguessable
        assert created.refresh_token == "rt-1"
        assert created.rotated_at is None
        # expires_at ≈ now + ttl
        window = created.expires_at - created.created_at
        assert timedelta(seconds=3595) < window < timedelta(seconds=3605)

        fetched = session_store.get(db, created.id)
        assert fetched is not None and fetched.id == created.id
    finally:
        _cleanup(db)


def test_get_returns_none_for_expired(db: DBSession):
    created = session_store.create(db, cognito_sub=SUB, refresh_token="rt-2", ttl=3600)
    try:
        created.expires_at = datetime.utcnow() - timedelta(seconds=1)
        db.add(created)
        db.commit()
        assert session_store.get(db, created.id) is None
    finally:
        _cleanup(db)


def test_get_returns_none_for_missing(db: DBSession):
    assert session_store.get(db, "does-not-exist") is None


def test_rotate_updates_token_and_stamps(db: DBSession):
    created = session_store.create(db, cognito_sub=SUB, refresh_token="rt-old", ttl=3600)
    try:
        rotated = session_store.rotate(db, session_id=created.id, new_refresh_token="rt-new")
        assert rotated is not None
        assert rotated.refresh_token == "rt-new"
        assert rotated.rotated_at is not None
    finally:
        _cleanup(db)


def test_delete_removes_row(db: DBSession):
    created = session_store.create(db, cognito_sub=SUB, refresh_token="rt-3", ttl=3600)
    session_store.delete(db, created.id)
    assert session_store.get(db, created.id) is None
    # idempotent
    session_store.delete(db, created.id)


def test_delete_expired_sweeps_only_expired(db: DBSession):
    live = session_store.create(db, cognito_sub=SUB, refresh_token="live", ttl=3600)
    dead = session_store.create(db, cognito_sub=SUB, refresh_token="dead", ttl=3600)
    try:
        dead.expires_at = datetime.utcnow() - timedelta(seconds=1)
        db.add(dead)
        db.commit()

        removed = session_store.delete_expired(db)
        assert removed >= 1
        assert session_store.get(db, dead.id) is None
        assert session_store.get(db, live.id) is not None
    finally:
        _cleanup(db)
