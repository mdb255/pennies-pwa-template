from sqlmodel import create_engine, Session
from sqlalchemy import event
from functools import lru_cache
from .settings import settings

@lru_cache()
def get_engine():
    """Get database engine."""
    engine = create_engine(settings.runtime_db_url, pool_pre_ping=True)
    
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
