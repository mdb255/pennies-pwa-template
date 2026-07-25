from functools import lru_cache

from boto3 import client
from sqlalchemy import event
from sqlmodel import Session, create_engine

from .settings import settings

def resolve_runtime_db_url() -> str:
    """Return the runtime connection string, fetching from SSM when not set directly.

    Local dev sets RUNTIME_DB_URL in .env and never touches AWS. Deployed environments
    set RUNTIME_DB_URL_SSM_PATH instead, which keeps the credential out of the Lambda's
    environment and out of tofu state; rotating it means updating the SSM parameter and
    forcing a cold start, with no infrastructure apply. Called once per process via the
    lru_cache on get_engine().
    """
    if settings.runtime_db_url:
        return settings.runtime_db_url

    if not settings.runtime_db_url_ssm_path:
        raise RuntimeError(
            "No database URL configured: set RUNTIME_DB_URL (local) or "
            "RUNTIME_DB_URL_SSM_PATH (deployed)."
        )

    response = client("ssm", region_name=settings.aws_region).get_parameter(
        Name=settings.runtime_db_url_ssm_path,
        WithDecryption=True,
    )
    return response["Parameter"]["Value"]

@lru_cache
def get_engine():
    """Get database engine."""
    engine = create_engine(resolve_runtime_db_url(), pool_pre_ping=True)
    
    # Set search_path to 'app' schema for all connections
    @event.listens_for(engine, "connect")
    def set_search_path(dbapi_conn, connection_record):
        """Set the search_path to 'app' schema on each connection."""
        with dbapi_conn.cursor() as cursor:
            cursor.execute("SET search_path TO app")
    
    return engine

# With Alembic in place, we do not create tables on startup.
def init_db() -> None:
    """Initialize database."""
    # Placeholder for future startup logic (e.g., seed data).
    return None

def get_session() -> Session:
    """Get database session."""
    engine = get_engine()
    return Session(engine)
