# Next Up

## Summary of last work session

**Python 3.11 → 3.12 upgrade**
- `bootstrap.config.yaml` — `python_version: "3.11"` → `"3.12"` (covers `apprunner.yaml`, GHA, `requires-python`, `pyright.pythonVersion`)
- `Dockerfile` — hardcoded `FROM python:3.11-slim` templatized to `FROM python:<{{ python_version }}>-slim`
- `pyproject.toml` — `[tool.ruff] target-version` bumped from `"py311"` → `"py312"`

**Template cleanup**
- `.env` — replaced real Cognito resource IDs (`us-east-1_i89Yb81tF` / `5cltqq6k2cspvbhrn4071f5kh`) with `your-user-pool-id` / `your-app-client-id`
- `src/app/main.py` — `title="Todo API"` and hardcoded description templatized to `<{{ app_name }}>`
- `pyproject.toml` — `name = "fastapi-sqlmodel-starter"` and description templatized; version reset to `0.1.0`
- `Dockerfile` — `EXPOSE 8000` and `--port 8000` templatized with `<{{ api_port }}>`
- `README.md` (root) — written from scratch: stack overview, bootstrap instructions, template variable table, directory structure, pre-bootstrap checklist
- `front-end/__app-name__/README.md` — replaced stock Vite boilerplate with project-specific dev setup, `.env.local` requirement, and scripts table
- `back-end/__app-name__-api/README.md` — title still says "Todo API" (not yet templatized)

**bootstrap.py — uv conversion**
- Added PEP 723 inline script metadata (`# /// script` block with `pyyaml` + `jinja2` deps)
- Replaced venv setup instructions with `uv run bootstrap.py`; updated root README to match
- No Python installation required — uv handles it (uv is already required by the backend)

**DB connection string cleanup**
- `.env` and `env.example` — passwords in `RUNTIME_DB_URL` and `MIGRATIONS_DB_URL` renamed from `peanut-*` literals to `<{{ app_name_snake }}>_svc_user_pw` / `<{{ app_name_snake }}>_db_owner_pw`

**docker-compose renamed + Postgres init script**
- `docker-compose.yml` → `docker-compose.local.yml` (local dev only; not referenced by CI/CD or App Runner)
- README updated to use `docker compose -f docker-compose.local.yml up -d`
- `db/init.sql` created — runs once on container first start; creates `db_owner` (DDL, owns schema) and `svc_user` (DML only) roles, the `app` schema, and default privileges so Alembic-created tables are auto-granted to `svc_user`
- `docker-compose.local.yml` — mounts `./db/init.sql` into `/docker-entrypoint-initdb.d/`

## TODO

- Currently deploys to AWS App Runner — migrate to AWS Lambda with Lambda Web Adapter

- **Add Terraform infra** — provision AWS resources (Cognito User Pool + App Client, ECR repo, Lambda Web Adapter, S3 bucket + CloudFront distribution, IAM roles, SSM parameters)
