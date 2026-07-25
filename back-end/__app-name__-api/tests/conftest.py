import pytest
from fastapi.testclient import TestClient
from sqlmodel import Session
from app.main import app
from app.db import get_engine
from app.auth import get_current_user
from app.crud.user import user as user_crud
from app.models.user import UserCreate

# Dedicated test user — never conflicts with real data
TEST_COGNITO_SUB = "test-cognito-sub-00000000-0000-0000-0000-000000000000"
TEST_USER_EMAIL = "test-user@example.com"


@pytest.fixture(scope="session", autouse=True)
def test_user():
    """Ensure a test user exists in the DB for the session."""
    engine = get_engine()
    with Session(engine) as db:
        if not user_crud.get_by_cognito_sub(db, cognito_sub=TEST_COGNITO_SUB):
            user_crud.create(db, obj_in=UserCreate(
                email=TEST_USER_EMAIL,
                cognito_sub=TEST_COGNITO_SUB,
                name="Test User",
            ))


@pytest.fixture
def client():
    """TestClient with auth dependency overridden to the test user."""
    app.dependency_overrides[get_current_user] = lambda: {"sub": TEST_COGNITO_SUB}
    with TestClient(app) as c:
        yield c
    app.dependency_overrides.clear()


@pytest.fixture
def db():
    """A direct DB session for tests that assert on persisted rows."""
    engine = get_engine()
    with Session(engine) as session:
        yield session
