from pydantic_settings import BaseSettings, SettingsConfigDict
from typing import Optional

class Settings(BaseSettings):
    # Database URLs
    # - runtime_db_url: used by the FastAPI app at runtime (required)
    # - migrations_db_url: used only by Alembic migrations (optional for app boot, required for migrations)
    runtime_db_url: str
    migrations_db_url: Optional[str] = None

    # AWS Cognito settings
    user_pool_id: str
    app_client_id: str
    aws_region: str = "us-east-1"
    jwks_cache_ttl: int = 3600  # 1 hour in seconds
    
    # Application settings
    app_env: str = "local"  # local vs production
    app_domain: Optional[str] = None  # for cookie domain
    session_resume_cookie_name: str = "app.session-resume"
    session_resume_cookie_ttl: int = 2592000  # 30 days in seconds
    cors_origins: str = "http://127.0.0.1:5173"  # comma-separated list of allowed origins
    
    @property
    def cors_origins_list(self) -> list[str]:
        """Parse comma-separated CORS origins into a list."""
        return [origin.strip() for origin in self.cors_origins.split(",") if origin.strip()]

    model_config = SettingsConfigDict(
        env_file=".env",
        env_prefix="",
        case_sensitive=False,
    )

settings = Settings()
