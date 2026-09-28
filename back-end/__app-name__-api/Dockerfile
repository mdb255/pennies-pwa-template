FROM python:<{{ python_version }}>-slim

WORKDIR /app

# Install uv
COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv

# Install the AWS Lambda Web Adapter as a Lambda extension.
# It proxies Lambda Runtime API events to the local uvicorn server, so the same
# image runs unchanged on Lambda (Function URL) and locally / in any container host.
COPY --from=public.ecr.aws/awsguru/aws-lambda-adapter:0.9.1 /lambda-adapter /opt/extensions/lambda-adapter

# Tell the adapter which port uvicorn listens on, and when the app is ready to serve.
ENV AWS_LWA_PORT=<{{ api_port }}>
ENV AWS_LWA_READINESS_CHECK_PATH=/healthz

# Copy dependency files
COPY pyproject.toml uv.lock alembic.ini ./
COPY alembic ./alembic

# Copy application source
COPY src ./src

# Install dependencies
RUN uv sync --frozen --no-dev

# Expose port
EXPOSE <{{ api_port }}>

# Run the application. Calls the venv's uvicorn directly rather than going through
# `uv run`: uv wants a writable cache under $HOME at startup, and Lambda's filesystem is
# read-only outside /tmp, so `uv run` exits 2 before uvicorn ever binds a port (the adapter
# then reports Ready with nothing to proxy to, and every request 502s). The `uv sync` above
# already installed everything into /app/.venv, so uv has no work to do at runtime anyway.
CMD ["/app/.venv/bin/uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "<{{ api_port }}>", "--app-dir", "src"]





