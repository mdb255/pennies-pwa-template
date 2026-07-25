# Todo API

A FastAPI + SQLModel starter with AWS Cognito authentication and a Todo resource as the baseline CRUD example.

## Features

- **FastAPI**: Modern, fast web framework for building APIs
- **SQLModel**: SQL databases in Python, designed for simplicity, compatibility, and robustness
- **Alembic**: Database migration tool for SQLAlchemy
- **uv**: Fast Python package installer and resolver
- **Pytest**: Testing framework with async support
- **Ruff**: Linting
- **Pyright**: Static type checking
- **AWS Cognito Authentication**: JWT-based authentication with Cognito integration, using the Token-Mediating Backend (TMB) pattern — the refresh token is held server-side in a `sessions` table and the browser gets only an opaque session cookie
- **User-scoped CRUD**: Todos are owned by and scoped to the authenticated user

## Project Structure

```
src/
├── app/
│   ├── __init__.py
│   ├── main.py              # FastAPI application
│   ├── db.py                # Database configuration
│   ├── settings.py          # Application settings
│   ├── auth.py               # Cognito integration (signup/login/refresh/revoke, JWT decoding)
│   ├── models/               # SQLModel models
│   │   ├── __init__.py
│   │   ├── base.py           # Base model classes
│   │   ├── user.py           # User model
│   │   ├── session.py        # Server-side session (holds the refresh token)
│   │   └── todo.py           # Todo model
│   ├── crud/                 # CRUD operations
│   │   ├── __init__.py
│   │   ├── base.py           # Base CRUD class
│   │   ├── user.py           # User CRUD operations
│   │   ├── session.py        # Session store (create/get/rotate/delete/expired)
│   │   └── todo.py           # Todo CRUD operations (user-scoped)
│   └── api/                  # API routes
│       ├── __init__.py
│       ├── auth.py            # Auth endpoints
│       └── todos.py           # Todo endpoints
├── alembic/                  # Database migrations
│   ├── versions/
│   ├── env.py
│   └── script.py.mako
└── tests/                    # Test files
    ├── test_todos.py
    ├── test_auth.py          # TMB auth routes (Cognito mocked)
    └── test_session_crud.py  # Session store
```

## Quick Start

1. **Start Postgres**:
   ```bash
   docker compose -f docker-compose.local.yml up -d
   ```

2. **Install dependencies**:
   ```bash
   uv sync --all-extras --dev
   ```

3. **Set up the database**:
   ```bash
   uv run alembic upgrade head
   ```

4. **Run the application**:
   ```bash
   uv run uvicorn app.main:app --reload --app-dir src
   ```

5. **View the API documentation**:
   - OpenAPI docs: http://localhost:8000/docs
   - ReDoc: http://localhost:8000/redoc

6. **Run tests**:
   ```bash
   uv run pytest -q
   ```

## API Endpoints

### Auth
- `POST /auth/signup/` - Register a new user with Cognito
- `POST /auth/confirm-signup/` - Confirm signup with the emailed verification code
- `POST /auth/login/` - Authenticate; store the refresh token server-side, return an access token, and set the opaque session cookie
- `POST /auth/resume/` - Look up the server-side session by cookie and mint a fresh access token
- `POST /auth/logout/` - Delete the server-side session, revoke the refresh token at Cognito, and clear the cookie

### Todos
All todo endpoints require a valid access token and are scoped to the authenticated user.
- `POST /todos/` - Create a new todo
- `GET /todos/` - List todos (`?is_completed=`, `?skip=`, `?limit=`)
- `GET /todos/{todo_id}/` - Get a specific todo
- `PATCH /todos/{todo_id}/` - Update a todo (title, description, is_completed)
- `DELETE /todos/{todo_id}/` - Delete a todo

### System
- `GET /` - Root endpoint with API info
- `GET /healthz` - Application health status

## Models

### User
- `id`: Primary key
- `email`: User email
- `cognito_sub`: Cognito subject identifier
- `name`: Display name
- `created_at` / `updated_at`: Timestamps

### Todo
- `id`: Primary key
- `title`: Todo title
- `description`: Optional description
- `is_completed`: Completion flag (default `false`)
- `user_id`: Foreign key to the owning User
- `created_at` / `updated_at`: Timestamps

## Development

### Running Tests
```bash
uv run pytest
```

### Linting
```bash
uv run ruff check .
```

### Type Checking
```bash
uv run pyright
```

## Database Migrations

### Create a new migration
```bash
uv run alembic revision --autogenerate -m "Description of changes"
```

### Apply migrations
```bash
uv run alembic upgrade head
```

### Rollback migration
```bash
uv run alembic downgrade -1
```

## Adding New Models

1. **Create the model** in `src/app/models/your_model.py`
2. **Create CRUD operations** in `src/app/crud/your_model.py`
3. **Create API endpoints** in `src/app/api/your_model.py`
4. **Update imports** in the respective `__init__.py` files
5. **Add router** to `src/app/main.py`
6. **Create migration** with Alembic
7. **Add tests** in `tests/test_your_model.py`

## Configuration

The application uses environment variables for configuration. Create a `.env` file in the project root (see `env.example` for a template).

## Authentication

The API uses AWS Cognito for JWT-based authentication via the **Token-Mediating Backend (TMB)** pattern. The refresh token never reaches the browser: `POST /auth/login/` stores it in the server-side `sessions` table and hands the browser an opaque session id in a host-only `HttpOnly` cookie. Data endpoints are Bearer-validated with the short-lived access token.

### Two components, one image

`create_app()` mounts routers based on `APP_COMPONENT`:

- `APP_COMPONENT=auth` — mounts `/auth/*` only. Served **same-origin** with the PWA (via CloudFront in prod), so no CORS.
- `APP_COMPONENT=api` (default) — mounts `/todos/*` only, on a public Function URL, Bearer-validated. CORS is configured on the Function URL itself (`infra/lambda.tf`), not in the app, so there is a single source of truth for the allowed origin.
- `APP_ENV=local` — mounts **both** so a single `uvicorn` serves everything; the frontend Vite dev proxy forwards `/auth/*` to this process to mimic the same-origin split.

### Required Environment Variables

- `USER_POOL_ID`: Your AWS Cognito User Pool ID
- `APP_CLIENT_ID`: Your Cognito App Client ID
- `AWS_REGION`: AWS region where your Cognito User Pool is located
- `APP_COMPONENT`: `auth` or `api` (ignored when `APP_ENV=local`, which mounts both)
- `JWKS_CACHE_TTL`: Cache TTL for JWKs (optional, defaults to 3600 seconds)
- `SESSION_RESUME_COOKIE_NAME` / `SESSION_RESUME_COOKIE_TTL`: Opaque session cookie name and TTL (also the session-row TTL; default 30 days)
- `SESSION_TOKEN_ENCRYPTION_KEY`: Optional; encrypt the stored refresh token at rest (off by default)

Database connection string — set **one** of:

- `RUNTIME_DB_URL`: the connection string itself. Used for local dev.
- `RUNTIME_DB_URL_SSM_PATH`: an SSM SecureString path to fetch it from on cold start. Used in
  deployed environments, so the credential stays out of the Lambda environment and out of
  tofu state. Rotating it is then an SSM update plus a cold start — no infrastructure apply.

### Auth Flow

1. `POST /auth/signup/` registers the user with Cognito, then `POST /auth/confirm-signup/` confirms with the emailed code.
2. `POST /auth/login/` authenticates against Cognito, upserts the local `User` row, stores the refresh token in the `sessions` table, returns an access token, and sets the opaque session cookie (session id — **not** the refresh token).
3. `POST /auth/resume/` reads the session cookie, looks up the stored refresh token server-side, and mints a new access token (e.g. on page reload), rotating the stored token if Cognito returns a new one.
4. `POST /auth/logout/` deletes the session row, best-effort revokes the refresh token at Cognito, and clears the cookie.
5. Authenticated data requests send the access token as `Authorization: Bearer <token>` to the API component.

## Notes
- We avoid `create_all()` at runtime; schema is owned by Alembic.
- Tests create tables directly against an in-memory SQLite engine.
- Adminer is available at http://localhost:8080 for quick DB inspection (when using docker-compose.local.yml).

## License

MIT
