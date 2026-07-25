from pydantic_settings import BaseSettings, SettingsConfigDict

class Settings(BaseSettings):
    # Database URLs
    # - runtime_db_url: used by the FastAPI app at runtime. Set directly for local dev (.env).
    #   In deployed environments it is left unset and RUNTIME_DB_URL_SSM_PATH is set instead,
    #   so the connection string is fetched from SSM on cold start rather than living in the
    #   Lambda's environment (and, transitively, in tofu state). See db.resolve_runtime_db_url.
    # - runtime_db_url_ssm_path: SSM SecureString path holding that connection string.
    # - migrations_db_url: used only by Alembic migrations (optional for app boot,
    #   required for migrations)
    runtime_db_url: str | None = None
    runtime_db_url_ssm_path: str | None = None
    migrations_db_url: str | None = None

    # AWS Cognito settings
    user_pool_id: str
    app_client_id: str
    aws_region: str = "us-east-1"
    jwks_cache_ttl: int = 3600  # 1 hour in seconds
    
    # Application settings
    app_env: str = "local"  # local vs production
    # Which router this process serves. "auth" = same-origin /auth/* (via CloudFront);
    # "api" = public Function URL, Bearer-validated. Local dev leaves this unset → both mount.
    app_component: str = "api"  # env APP_COMPONENT; values: api | auth
    # Opaque session cookie: holds a random session_id (NOT the refresh token). The refresh
    # token lives server-side in the sessions table. Host-only, so no parent-domain attribute.
    session_resume_cookie_name: str = "app.session-resume"
    session_resume_cookie_ttl: int = 2592000  # 30 days in seconds; also the session row TTL
    # Optional: symmetric key to encrypt the stored refresh token at rest. Off for v1
    # (plaintext at rest, protected by DB access controls). Left unwired intentionally.
    session_token_encryption_key: str | None = None
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
