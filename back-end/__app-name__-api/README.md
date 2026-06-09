# Cat Slideshow API

A scalable FastAPI application for managing cats and slideshows with a clean, modular architecture.

## Features

- **FastAPI**: Modern, fast web framework for building APIs
- **SQLModel**: SQL databases in Python, designed for simplicity, compatibility, and robustness
- **Alembic**: Database migration tool for SQLAlchemy
- **uv**: Fast Python package installer and resolver
- **Pytest**: Testing framework with async support
- **Type hints**: Full type safety throughout the application
- **Modular Architecture**: Scalable structure for adding new models and features
- **CRUD Operations**: Base classes for consistent database operations
- **Relationship Support**: Proper model relationships with foreign keys
- **AWS Cognito Authentication**: JWT-based authentication with Cognito integration

## Project Structure

```
src/
├── app/
│   ├── __init__.py
│   ├── main.py              # FastAPI application
│   ├── db.py                # Database configuration
│   ├── settings.py          # Application settings
│   ├── models/              # SQLModel models
│   │   ├── __init__.py
│   │   ├── base.py          # Base model classes
│   │   ├── cat.py           # Cat model
│   │   └── slideshow.py     # Slideshow model
│   ├── crud/                # CRUD operations
│   │   ├── __init__.py
│   │   ├── base.py          # Base CRUD class
│   │   ├── cat.py           # Cat CRUD operations
│   │   └── slideshow.py     # Slideshow CRUD operations
│   └── api/                 # API routes
│       ├── __init__.py
│       ├── cats.py          # Cat endpoints
│       └── slideshows.py    # Slideshow endpoints
├── alembic/                 # Database migrations
│   ├── versions/
│   ├── env.py
│   └── script.py.mako
├── tests/                   # Test files
│   ├── test_cats.py
│   └── test_slideshows.py
└── pyproject.toml           # Project configuration
```

## Quick Start

1. **Start Postgres** (optional, can use SQLite):
   ```bash
   docker compose up -d
   ```

2. **Install dependencies**:
   ```bash
   uv sync --all-extras --dev
   ```

3. **Set up the database**:
   ```bash
   # Create and run migrations
   uv run alembic revision --autogenerate -m "Initial migration"
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

### Query Parameter Examples

**Cats API with filtering:**
- `GET /cats/` - Get all cats
- `GET /cats/?breed=Persian` - Get Persian cats
- `GET /cats/?min_age=2&max_age=5` - Get cats between 2-5 years old
- `GET /cats/?search=fluffy` - Search for cats with "fluffy" in description
- `GET /cats/?breed=Siamese&skip=10&limit=5` - Get 5 Siamese cats, skipping first 10

### Cats
- `POST /cats/` - Create a new cat
- `GET /cats/` - List all cats (with optional query parameters)
  - `?breed={breed}` - Filter by cat breed
  - `?min_age={age}&max_age={age}` - Filter by age range
  - `?search={term}` - Search cats by description
  - `?skip={number}&limit={number}` - Pagination
- `GET /cats/{id}` - Get a specific cat
- `PATCH /cats/{id}` - Update a cat
- `DELETE /cats/{id}` - Delete a cat

### Slideshows
- `POST /slideshows/` - Create a new slideshow
- `GET /slideshows/` - List all slideshows
- `GET /slideshows/{id}` - Get a specific slideshow
- `PATCH /slideshows/{id}` - Update a slideshow
- `DELETE /slideshows/{id}` - Delete a slideshow
- `GET /slideshows/cat/{cat_id}` - Get slideshows by cat
- `GET /slideshows/search/{search_term}` - Search slideshows by title

### System
- `GET /` - Root endpoint with API information
- `GET /healthz` - Application health status

## Models

### Cat
- `id`: Primary key
- `name`: Cat name
- `breed`: Cat breed (optional)
- `age`: Cat age (optional)
- `color`: Cat color (optional)
- `description`: Cat description (optional)
- `image_urls`: List of image URLs
- `created_at`: Creation timestamp
- `updated_at`: Last update timestamp

### Slideshow
- `id`: Primary key
- `title`: Slideshow title
- `description`: Slideshow description (optional)
- `image_urls`: List of image URLs
- `cat_id`: Foreign key to Cat (optional)
- `created_at`: Creation timestamp
- `updated_at`: Last update timestamp

## Development

### Running Tests
```bash
uv run pytest
```

### Code Formatting
```bash
uv run black .
uv run isort .
```

### Type Checking
```bash
uv run mypy .
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

The project is designed to be easily extensible. To add a new model:

1. **Create the model** in `src/app/models/your_model.py`
2. **Create CRUD operations** in `src/app/crud/your_model.py`
3. **Create API endpoints** in `src/app/api/your_model.py`
4. **Update imports** in the respective `__init__.py` files
5. **Add router** to `src/app/main.py`
6. **Create migration** with Alembic
7. **Add tests** in `tests/test_your_model.py`

## Configuration

The application uses environment variables for configuration. Create a `.env` file in the project root (see `env.example` for a template):


## Authentication

The API uses AWS Cognito for JWT-based authentication. Some endpoints require a valid access token in the Authorization header.

### Required Environment Variables

- `USER_POOL_ID`: Your AWS Cognito User Pool ID
- `APP_CLIENT_ID`: Your Cognito App Client ID
- `AWS_REGION`: AWS region where your Cognito User Pool is located
- `JWKS_CACHE_TTL`: Cache TTL for JWKs (optional, defaults to 3600 seconds)

### Obtaining an Access Token

1. **Set up AWS Cognito User Pool**:
   - Create a User Pool in AWS Console
   - Create an App Client
   - Configure the authentication flow (e.g., USER_PASSWORD_AUTH)

2. **Get access token** using AWS CLI or SDK:

```bash
aws cognito-idp initiate-auth \
  --auth-flow USER_PASSWORD_AUTH \
  --client-id YOUR_APP_CLIENT_ID \
  --auth-parameters USERNAME=your_username,PASSWORD=your_password
```

3. **Use the token** in API requests:

```bash
curl -H "Authorization: Bearer YOUR_ACCESS_TOKEN" \
  http://localhost:8000/cat-images/
```

## Notes
- We avoid `create_all()` at runtime; schema is owned by Alembic.
- Tests still create tables directly against an in-memory SQLite engine.
- Adminer is available at http://localhost:8080 for quick DB inspection (when using docker-compose).

## License

MIT