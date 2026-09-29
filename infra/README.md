# infra — OpenTofu

Provisions the whole footprint for **<{{ app_name }}>**: Cognito, ECR, two Lambda functions
on Function URLs, the PWA's S3 + CloudFront + ACM + Route53 stack, IAM, the
`/<{{ app_name }}>/prod/*` SSM tree, and the Neon project the database lives in.

Architecture: [`../docs/adr/0001-domain-and-auth-architecture.md`](../docs/adr/0001-domain-and-auth-architecture.md).

## Shape of this config

There are **no Terraform config variables and no `terraform.tfvars`**. (The one operational
toggle, `allow_destroy` in `variables.tf`, only exists for teardown — see [Teardown](#teardown).) Every value comes from
`bootstrap-project.config.yaml` and is stamped in once by `bootstrap-project.py`, the same way
the rest of the repo is templated — that includes `scripts/*.sh`, not just the `.tf` files.
After bootstrap, `locals.tf` holds the concrete config for this one project and `scripts/lib.sh`
holds it for the shell scripts; edit either directly if something needs to change.

Only `prod` exists. Multi-environment is explicitly out of scope.

## Prerequisites

`scripts/bootstrap-infra.sh preflight` (or `pre`) checks all of these except the first two —
run it before anything else.

- **OpenTofu ≥ 1.10** (`use_lockfile` — native S3 state locking, no DynamoDB table).
- Admin-ish AWS credentials. **The GitHub Actions deploy role cannot apply this** — it has no
  IAM or create rights by design. Apply as a human/admin principal.
- `aws`, `docker` (daemon running), `psql`, `jq`, `uv`, `pnpm`, `gh` (logged in).
- A Neon account and a personal API key (Neon Console → Account Settings → API Keys),
  exported as `NEON_API_KEY`. Never written to config or state — see `providers.tf`.
- The public Route53 hosted zone for `<{{ root_domain }}>` already exists and is delegated.
- The account-wide GitHub OIDC provider exists. If this is a fresh account, create it once:
  ```sh
  aws iam create-open-id-connect-provider \
    --url https://token.actions.githubusercontent.com \
    --client-id-list sts.amazonaws.com
  ```
  It is read as a data source here on purpose — destroying it would break every other repo
  in the account that federates in. `preflight` checks whether it exists and prints this
  command rather than creating it, since it's account-wide.

## Apply

`scripts/bootstrap-infra.sh` drives the whole apply in phases — the first apply and every
apply after it, since the first image is now seeded inside the same `tofu apply` that creates
the ECR repo (`terraform_data.seed_image` in `ecr.tf`), rather than a separate manual push.
Each phase checks reality, does only the work reality is missing, and tees its output to
`infra/.bootstrap-infra-logs/<timestamp>-<phase>.log`. The `/bootstrap` skill drives this for
you; to run it by hand:

```sh
cd infra/scripts
./bootstrap-infra.sh pre     # preflight, state, repo, plan — review the plan, then:
./bootstrap-infra.sh post    # apply, db, deploy, verify
```

| Phase | Does | Skip / verify |
| --- | --- | --- |
| `preflight` | Checks required tools, `NEON_API_KEY`, that your AWS caller account matches config, the `<{{ root_domain }}>` hosted zone, and the GitHub OIDC provider | Read-only |
| `state` | `bootstrap-state.sh` (creates/reconciles the versioned, encrypted, tagged state bucket), then `tofu init` | Bucket exists, is versioned, blocks public access, is tagged |
| `repo` | Creates the empty GitHub repo if it doesn't exist (confirms first; outward-facing). It must exist before `plan`: the deploy role's OIDC trust policy uses the repo's own subject-claim prefix, which GitHub sets per repo (name-based, or the ID-based form new repos get by default) | Repo exists |
| `plan` | `tofu plan`, saved to `infra/.bootstrap-infra-logs/bootstrap.tfplan` | **Stop here and review** — this is the approval point |
| `apply` | `tofu apply` on the saved plan only; refuses if it's missing or stale | `tofu plan -detailed-exitcode` shows no changes afterward |
| `db` | Generates both DB passwords in memory, runs `scripts/neon-init.sql`, writes both SSM SecureStrings. Nothing touches disk or stdout. `db --rotate` forces new passwords. | Skipped if both SSM URLs are already real and `select 1` succeeds against each |
| `deploy` | Confirms with you first (outward-facing). Pushes `main` if the repo has none yet, or triggers both workflows if it does; then watches both runs | Both workflow runs succeed |
| `verify` | Scripted version of "Verify after apply" below | Pass/fail |

`status` runs every phase's check, read-only — use it to see what's left without doing anything.

### Doing it by hand

Every phase is also a normal script you can read and run piece by piece —
`scripts/bootstrap-infra.sh preflight`, `state`, `plan`, `apply`, `db`, `deploy`, `verify` — and
`scripts/lib.sh` has the shared bits (logging, the account/tool checks, `AWS_PROFILE`/
`AWS_REGION`). The first image push itself is normally automatic —
`terraform_data.seed_image` in `ecr.tf` runs it as part of `apply`, once, when the ECR repo is
first created — but if you ever need to push one by hand (a machine without Docker access to
run `tofu apply` from, for example):

```sh
cd back-end/<{{ app_name }}>-api
aws ecr get-login-password --region <{{ aws_region }}> \
  | docker login --username AWS --password-stdin <{{ aws_account_id }}>.dkr.ecr.<{{ aws_region }}>.amazonaws.com
docker buildx build --platform linux/amd64 --provenance=false --sbom=false \
  -t <{{ aws_account_id }}>.dkr.ecr.<{{ aws_region }}>.amazonaws.com/<{{ app_name }}>-api:latest --push .
```

`neon-init.sql` mirrors `../back-end/<{{ app_name }}>-api/db/init.sql` (same roles, schema,
grants) but takes the two passwords as psql variables instead of embedding them, so real
production credentials exist only in your shell — never in a committed file, never in tofu
state. It's idempotent, including password rotation (see the comment at its top).

The two SSM SecureStrings (`RUNTIME_DB_URL`, `MIGRATIONS_DB_URL`) are created as placeholders
and never read by this stack — `ignore_changes = [value]` on both means whatever you put there
stays out of tofu state. `RUNTIME_DB_URL` is the one value the running app pulls from SSM
itself, on cold start (`app/db.py: resolve_runtime_db_url`); it is **not** in the Lambda
environment, so rotating it is an SSM update plus a cold start — no `tofu apply`, no redeploy.
`MIGRATIONS_DB_URL` is read only by the backend workflow, to run Alembic.

## What owns what

| Concern | Owner |
| --- | --- |
| Function *code* (image tag) | GitHub Actions (`lambda:UpdateFunctionCode`) — `image_uri` is under `ignore_changes` here |
| Function *config* (env, memory, timeout) | This stack. The deploy role has no `UpdateFunctionConfiguration`. |
| CORS for the api component | The api Function URL (`lambda.tf`) — **not** the app. `CORSMiddleware` is added only when `APP_ENV=local`. |
| Neon project/branch/database | This stack (`neon.tf`). |
| `db_owner`/`svc_user` roles | You, via `neon-init.sql` (one-time). Never in tofu state. |
| Database credentials (SSM) | You, via SSM. Never in state, never in an env var. |
| Database schema | Alembic, from the backend workflow. |

## Two things worth knowing

**Refresh-token validity is the real session ceiling.** `access_token_validity` is 15 minutes
(ADR 0001's mitigation for the access token reaching the browser), but the session lives as
long as the Cognito *refresh* token, which is stored server-side in the `sessions` table.
`refresh_token_validity` is set to **30 days to match `SESSION_RESUME_COOKIE_TTL`**. The IaC
plan sketched 5 days; that would have expired sessions at day 5 while the cookie and session
row still looked valid, so `/auth/resume/` would fail for three and a half weeks of apparently
live sessions. If you change one of these, change both.

**The auth Function URL is not public.** It is `AWS_IAM`-authorized and only the PWA's
CloudFront distribution can invoke it, via OAC/SigV4. The `/auth/*` behavior forwards
everything except the `Host` header (`Managed-AllViewerExceptHostHeader`) — forwarding the
viewer's Host would break the signature.

## Verify after apply

`scripts/bootstrap-infra.sh verify` runs this. By hand:

```sh
API=$(tofu output -raw api_function_url)
PWA=$(tofu output -raw pwa_url)
AUTH=$(tofu output -raw auth_function_url)

curl -s "$API/healthz"                       # {"status":"ok"}
curl -I "$PWA"                               # 200, from CloudFront

# For POST/PUT, the viewer must send the real SHA-256 of the body in x-amz-content-sha256;
# Lambda rejects UNSIGNED-PAYLOAD with a 403, which the SPA fallback turns into a 200 index.html.
# This body is empty, so it's the empty-string hash.
curl -s -o /dev/null -w '%{http_code}\n' \
  -X POST "$PWA/auth/login/" \
  -H "x-amz-content-sha256: $(printf '' | sha256sum | cut -d' ' -f1)"   # routes through to the auth Lambda (422, not 404)

# The auth Function URL must NOT be directly invocable:
curl -s -o /dev/null -w '%{http_code}\n' \
  -X POST "${AUTH}auth/login/" \
  -H 'x-amz-content-sha256: UNSIGNED-PAYLOAD'          # expect 403
```

Then the browser end-to-end: signup → confirm → login → reload (resume) → logout.

## Teardown

`scripts/teardown-infra.sh` removes everything `bootstrap-infra.sh` provisioned. Run it only when
you mean to; it isn't a bootstrap phase. It reads `tofu state list` as the ledger of what exists,
flips the three guards that block a plain destroy (Cognito deletion protection, ECR `force_delete`,
S3 `force_destroy`) through the `allow_destroy` variable, runs `tofu destroy`, then empties and
deletes the state bucket. Only this script sets `allow_destroy`; a normal `plan`/`apply` leaves
the guards on.

```sh
infra/scripts/teardown-infra.sh --check-only   # read-only: what still exists, by name
infra/scripts/teardown-infra.sh --plan-only    # show what would be destroyed, change nothing
infra/scripts/teardown-infra.sh [--backup]     # destroy; you type the app name to confirm
```

- `--backup` first writes a `pg_dump -Fc` of the database to `infra/backups/` (git-ignored) and
  checks it with `pg_restore -l`. The Neon project has `history_retention_seconds = 0`, so
  without a dump the data cannot be recovered.
- **Drift guard:** the unlock plan may only flip those three guards. If it wants to change
  anything else (say, a resource left in state after its `.tf` was deleted), the script aborts
  and lists it; reconcile config and state, then rerun.
- **The GitHub repo must still exist**, because `data.external.github_oidc_sub` calls the GitHub
  API on every plan, including a destroy plan. If it is already gone, recreate it empty with
  `bootstrap-infra.sh repo`, tear down, then delete it.
- **Never deleted:** the GitHub repo (the script only prints the `gh repo delete` command for you
  to run yourself), the account-wide GitHub OIDC provider, the Route53 hosted zone, local files.
- A rerun after a mid-way failure is safe; each step checks reality first.
- It ends with a name-based leftover check (also `--check-only`) and exits non-zero if anything
  remains.

## Out of scope

WAF and rate limiting, a custom domain or API Gateway for the API, multiple environments, and
DynamoDB. Neon's project/branch/database are created by this stack (`neon.tf`); its
`db_owner`/`svc_user` roles are not — see "Doing it by hand" above.
