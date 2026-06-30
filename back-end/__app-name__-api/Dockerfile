FROM python:<{{ python_version }}>-slim

WORKDIR /app

# Install uv
COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv

# Copy dependency files
COPY pyproject.toml uv.lock alembic.ini ./
COPY alembic ./alembic

# Copy application source
COPY src ./src

# Install dependencies
RUN uv sync --frozen --no-dev

# Expose port
EXPOSE <{{ api_port }}>

# Run the application
CMD ["uv", "run", "uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "<{{ api_port }}>", "--app-dir", "src"]





