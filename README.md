# pennies-pwa-template

A full-stack PWA starter with auth, CI/CD, and AWS deployment wired up out of the box. Bootstrap it once and get a working app skeleton ready for your features.

## Stack

See [docs/tech-stack.md](docs/tech-stack.md) for the full list.

- **Frontend**: React + TypeScript + Ionic 8 + Tailwind v4 + Redux Toolkit + RTK Query + Vite
- **Backend**: FastAPI + SQLModel + Postgres + AWS Cognito + uv
- **Infra**: AWS (App Runner, ECR, S3/CloudFront), GitHub Actions, Terraform

## Getting started

1. Edit `bootstrap.config.yaml` with your app name and AWS details
2. Run `uv run bootstrap.py` — renames directories and substitutes all template placeholders
3. Follow the READMEs inside the generated `back-end/` and `front-end/` directories for local dev setup

## Template variables

| Variable | Set in | Used for |
|---|---|---|
| `app_name` | `bootstrap.config.yaml → app.name` | directory names, ECR repo, SSM paths |
| `app_name_snake` | derived from `app_name` | Python package name, DB names, cookie names |
| `aws_account_id` | `bootstrap.config.yaml → aws.account_id` | IAM policies, ECR URIs |
| `aws_region` | `bootstrap.config.yaml → aws.region` | all AWS resource references |
| `api_port` | `bootstrap.config.yaml → app.api_port` | Dockerfile, App Runner config |
| `python_version` | `bootstrap.config.yaml → python_version` | Dockerfile, pyproject.toml, GHA |
| `node_version` | `bootstrap.config.yaml → node_version` | GHA workflows |
| `pnpm_version` | `bootstrap.config.yaml → pnpm_version` | GHA workflows |

## Directory structure

```
.
├── bootstrap.py              # Renders the template — run this to set up your project
├── bootstrap.config.yaml     # Your config — edit this first
├── back-end/
│   └── __app-name__-api/    # FastAPI backend (directory renamed on bootstrap)
├── front-end/
│   └── __app-name__/        # React/Ionic frontend (directory renamed on bootstrap)
├── docs/                     # Tech decisions and conventions
└── .github/workflows/        # CI/CD pipelines
```

## Pre-bootstrap checklist

- [ ] Create an AWS Cognito User Pool; note the Pool ID and App Client ID
- [ ] Set up a Postgres database (template assumes [Neon](https://neon.tech))
- [ ] Configure AWS credentials with access to ECR, S3, CloudFront, and App Runner
- [ ] Fill in `bootstrap.config.yaml`
- [ ] Run `python3 bootstrap.py`
- [ ] Add Cognito and DB credentials to the generated `.env` files (never committed)
