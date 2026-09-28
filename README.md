# pennies-pwa-template

A full-stack PWA starter with auth, CI/CD, and AWS deployment wired up out of the box. Bootstrap it once and get a working app skeleton ready for your features.

## Stack

See [docs/tech-stack.md](docs/tech-stack.md) for the full list.

- **Frontend**: React + TypeScript + Ionic 8 + Tailwind v4 + Redux Toolkit + RTK Query + Vite
- **Backend**: FastAPI + SQLModel + Postgres + AWS Cognito + uv
- **Infra**: AWS (Lambda via Web Adapter, ECR, S3/CloudFront, Cognito), GitHub Actions, OpenTofu

## Getting started

The fastest path is the `/bootstrap` skill (see `.claude/skills/bootstrap/`) — it interviews
you for the values below, copies the template into a fresh project, and drives the infra apply.
Run it from the template repo with Claude Code.

The manual path:

1. Edit `bootstrap-project.config.yaml` with your app name and AWS details
2. Run `uv run bootstrap-project.py` — renames directories and substitutes all template placeholders in place
3. Follow the READMEs inside the generated `back-end/` and `front-end/` directories for local dev setup
4. Follow `infra/README.md` to provision AWS/Neon and deploy

## Template variables

| Variable | Set in | Used for |
|---|---|---|
| `app_name` | `bootstrap-project.config.yaml → app.name` | directory names, ECR repo, SSM paths |
| `app_name_snake` | derived from `app_name` | Python package name, DB names, cookie names |
| `aws_account_id` | `bootstrap-project.config.yaml → aws.account_id` | IAM policies, ECR URIs |
| `aws_region` | `bootstrap-project.config.yaml → aws.region` | all AWS resource references |
| `aws_profile` | `bootstrap-project.config.yaml → aws.profile` | deploy-time AWS CLI profile, exported by `bootstrap-infra.sh` |
| `api_port` | `bootstrap-project.config.yaml → app.api_port` | Dockerfile (uvicorn + `AWS_LWA_PORT`) |
| `python_version` | `bootstrap-project.config.yaml → python_version` | Dockerfile, pyproject.toml, GHA |
| `node_version` | `bootstrap-project.config.yaml → node_version` | GHA workflows |
| `pnpm_version` | `bootstrap-project.config.yaml → pnpm_version` | GHA workflows |
| `root_domain` | `bootstrap-project.config.yaml → infra.root_domain` | ACM cert, CloudFront alias, Route53, CORS origin |
| `github_repo` | `bootstrap-project.config.yaml → infra.github_repo` | OIDC deploy-role trust policy |
| `github_visibility` | `bootstrap-project.config.yaml → infra.github_visibility` | `gh repo create` visibility |
| `lambda_memory` | `bootstrap-project.config.yaml → infra.lambda_memory` | both Lambda functions |
| `neon_region_id` | `bootstrap-project.config.yaml → infra.neon_region_id` | Neon project region |

## Directory structure

```
.
├── bootstrap-project.py           # Renders the template — run this to set up your project
├── bootstrap-project.config.yaml  # Your config — edit this first
├── back-end/
│   └── __app-name__-api/    # FastAPI backend (directory renamed on bootstrap)
├── front-end/
│   └── __app-name__/        # React/Ionic frontend (directory renamed on bootstrap)
├── infra/                    # OpenTofu — the whole AWS footprint (see infra/README.md)
├── docs/                     # Tech decisions and conventions
├── .claude/skills/bootstrap/ # The /bootstrap skill — not rendered by bootstrap-project.py
└── .github/workflows/        # CI/CD pipelines
```

## Pre-bootstrap checklist

- [ ] A Neon account and a personal API key (template assumes [Neon](https://neon.tech)),
      exported as `NEON_API_KEY`
- [ ] Own a domain with a public Route53 hosted zone — the PWA is served at `<app_name>.<root_domain>`
- [ ] Configure AWS credentials with admin-level access (`infra/` creates IAM roles)
- [ ] Fill in `bootstrap-project.config.yaml`
- [ ] Run `uv run bootstrap-project.py`
- [ ] Add DB credentials to the generated `.env` files (never committed) — for local dev,
      pointed at the `docker-compose.local.yml` Postgres, not Neon

Neither Cognito nor the Neon project/database are prerequisites — `infra/` creates both: the
user pool and app client (writing their IDs into the SSM tree and Lambda environments), and
the Neon project itself (`neon.tf`). Deploying is then:

- [ ] `infra/README.md` — the phased `bootstrap-infra.sh` apply, then fill the two
      SecureString DB URLs
- [ ] Push to `main` to trigger the backend and frontend workflows
