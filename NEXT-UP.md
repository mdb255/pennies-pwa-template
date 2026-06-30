# Next Up

## Summary of last work session

**App Runner → AWS Lambda (Web Adapter) migration**
- `Dockerfile` — added the Lambda Web Adapter as an extension (`COPY --from=public.ecr.aws/awsguru/aws-lambda-adapter`), set `AWS_LWA_PORT=<{{ api_port }}>` and `AWS_LWA_READINESS_CHECK_PATH=/healthz`; uvicorn `CMD` unchanged
- `deploy-backend.yml` — renamed to "Deploy Backend to AWS Lambda"; SSM param `APPRUNNER_SERVICE_ARN` → `LAMBDA_FUNCTION_NAME`; replaced the App Runner config/update/start steps with `aws lambda update-function-code` + `aws lambda wait function-updated`; migrations/ECR/OIDC unchanged
- Deleted `apprunner.yaml` and `.github/scripts/build-apprunner-config.sh` (runtime-secret wiring captured in the Terraform TODO below)
- App + CI/CD layer only — provisioning the Lambda, Function URL, IAM, and the function's env vars is deferred to the Terraform TODO
- Decisions: Lambda Function URL (not API Gateway), BUFFERED invoke mode, Neon over public internet (no VPC); `db.py` engine already Lambda-safe (`lru_cache` + `pool_pre_ping`)

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

- **Add Terraform infra** — provision AWS resources (Cognito User Pool + App Client, ECR repo, Lambda Web Adapter, S3 bucket + CloudFront distribution, IAM roles, SSM parameters)
  - **Lambda runtime env/secrets (was `build-apprunner-config.sh` on App Runner)** — App
    Runner injected these SSM SecureStrings into the container at runtime via
    `ImageConfiguration.RuntimeEnvironmentSecrets` (env-var name → SSM parameter ARN),
    pulled from prefix `/<{{ app_name }}>/prod`. Lambda has no native equivalent, so
    Terraform must set the Lambda function's `environment` from these 6 SSM params:
      - `RUNTIME_DB_URL`   (Neon connection string used by the app)
      - `USER_POOL_ID`     (Cognito)
      - `APP_CLIENT_ID`    (Cognito)
      - `CORS_ORIGINS`     (comma-separated allowed origins)
      - `APP_ENV`          (e.g. `production`)
      - `APP_DOMAIN`       (cookie domain)
    These names map 1:1 to fields in `src/app/settings.py` (pydantic-settings reads them
    from the environment). NOT runtime secrets: `MIGRATIONS_DB_URL` is used only by Alembic
    in the GHA deploy step; `LAMBDA_FUNCTION_NAME` is a deploy-time CI param, not app config.
    Decide in TF how to source them: (a) `data.aws_ssm_parameter` → plaintext in the
    function's env config (simplest; matches today's exposure), (b) app fetches from SSM at
    cold start, or (c) an SSM/Secrets Lambda extension. App Runner also set `Port = api_port`
    and `AutoDeploymentsEnabled: false` — Port is now handled by `AWS_LWA_PORT` in the
    Dockerfile; the deploy workflow updates function code explicitly (no auto-deploy).
