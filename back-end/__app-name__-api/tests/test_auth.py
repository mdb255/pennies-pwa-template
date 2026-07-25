"""Tests for the TMB auth routes (api/auth.py) with Cognito mocked.

Assert the core TMB invariants: login stores the refresh token server-side and hands the
browser only an opaque session id; resume mints a fresh access token and rotates on demand;
logout deletes the row and revokes.
"""

import pytest
from fastapi.testclient import TestClient
from sqlmodel import Session as DBSession
from sqlmodel import select

import app.api.auth as auth_routes
from app.crud.session import session as session_store
from app.models.session import Session
from app.models.user import User

EMAIL = "tmb-test@example.com"
SUB = "tmb-test-cognito-sub"


@pytest.fixture(autouse=True)
def cleanup(db: DBSession):
    """Remove any users/sessions this module creates, before and after each test."""
    def _purge():
        for row in db.exec(select(Session).where(Session.cognito_sub == SUB)).all():
            db.delete(row)
        for row in db.exec(select(User).where(User.email == EMAIL)).all():
            db.delete(row)
        db.commit()
    _purge()
    yield
    _purge()


def _mock_login(monkeypatch, *, refresh_token="refresh-abc", access_token="access-xyz"):
    monkeypatch.setattr(auth_routes, "cognito_login", lambda email, password: {
        "AuthenticationResult": {
            "IdToken": "id-token",
            "AccessToken": access_token,
            "RefreshToken": refresh_token,
            "ExpiresIn": 3600,
        }
    })
    monkeypatch.setattr(auth_routes, "decode_id_token", lambda id_token: {"sub": SUB})


def test_login_stores_session_and_sets_opaque_cookie(
    client: TestClient, db: DBSession, monkeypatch
):
    _mock_login(monkeypatch, refresh_token="refresh-secret", access_token="access-1")

    resp = client.post("/auth/login/", json={"email": EMAIL, "password": "pw"})
    assert resp.status_code == 200
    body = resp.json()
    assert body["access_token"] == "access-1"
    assert body["access_token_expires_in_ms"] == 3600 * 1000

    cookie_val = resp.cookies.get("app.session-resume")
    assert cookie_val  # opaque session id set
    assert cookie_val != "refresh-secret"  # NOT the refresh token

    # The refresh token lives server-side, keyed by the opaque id.
    row = db.get(Session, cookie_val)
    assert row is not None
    assert row.refresh_token == "refresh-secret"
    assert row.cognito_sub == SUB


def test_resume_returns_fresh_access_token(client: TestClient, db: DBSession, monkeypatch):
    created = session_store.create(db, cognito_sub=SUB, refresh_token="rt-live", ttl=3600)
    monkeypatch.setattr(auth_routes, "cognito_refresh_session", lambda rt: {
        "AuthenticationResult": {"AccessToken": "access-refreshed", "ExpiresIn": 900}
    })

    client.cookies.set("app.session-resume", created.id)
    resp = client.post("/auth/resume/")
    assert resp.status_code == 200
    assert resp.json()["access_token"] == "access-refreshed"


def test_resume_rotates_refresh_token_when_cognito_rotates(
    client: TestClient, db: DBSession, monkeypatch
):
    created = session_store.create(db, cognito_sub=SUB, refresh_token="rt-old", ttl=3600)
    monkeypatch.setattr(auth_routes, "cognito_refresh_session", lambda rt: {
        "AuthenticationResult": {
            "AccessToken": "access-2",
            "RefreshToken": "rt-rotated",
            "ExpiresIn": 900,
        }
    })

    client.cookies.set("app.session-resume", created.id)
    resp = client.post("/auth/resume/")
    assert resp.status_code == 200

    db.refresh(created)
    assert created.refresh_token == "rt-rotated"
    assert created.rotated_at is not None


def test_resume_401_without_cookie(client: TestClient):
    client.cookies.clear()
    resp = client.post("/auth/resume/")
    assert resp.status_code == 401


def test_resume_401_for_unknown_session(client: TestClient):
    client.cookies.set("app.session-resume", "not-a-real-session")
    resp = client.post("/auth/resume/")
    assert resp.status_code == 401


def test_logout_deletes_session_and_revokes(client: TestClient, db: DBSession, monkeypatch):
    created = session_store.create(db, cognito_sub=SUB, refresh_token="rt-bye", ttl=3600)
    revoked = {}
    monkeypatch.setattr(auth_routes, "cognito_revoke", lambda rt: revoked.update(token=rt))

    client.cookies.set("app.session-resume", created.id)
    resp = client.post("/auth/logout/")
    assert resp.status_code == 200

    # The endpoint deleted the row in its own DB session; drop our identity-map cache so the
    # assertion reads fresh from the DB.
    db.expunge_all()
    assert db.get(Session, created.id) is None  # row deleted
    assert revoked.get("token") == "rt-bye"  # refresh token revoked at Cognito
