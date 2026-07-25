# infra — OpenTofu

Provisions the whole AWS footprint for **<{{ app_name }}>**: Cognito, ECR, two Lambda
functions on Function URLs, the PWA's S3 + CloudFront + ACM + Route53 stack, IAM, and the
`/<{{ app_name }}>/prod/*` SSM tree.

Architecture: [`../docs/adr/0001-domain-and-auth-architecture.md`](../docs/adr/0001-domain-and-auth-architecture.md).

## Shape of this config

There are **no variables and no `terraform.tfvars`**. Every value comes from
`bootstrap.config.yaml` and is stamped in once by `bootstrap.py`, the same way the rest of the
repo is templated. After bootstrap, `locals.tf` holds the concrete config for this one
project; edit it directly if something needs to change.

Only `prod` exists. Multi-environment is explicitly out of scope.

## Prerequisites

- **OpenTofu ≥ 1.10** (`use_lockfile` — native S3 state locking, no DynamoDB table).
- Admin-ish AWS credentials. **The GitHub Actions deploy role cannot apply this** — it has no
  IAM or create rights by design. Apply as a human/admin principal.
- The public Route53 hosted zone for `<{{ root_domain }}>` already exists and is delegated.
- The account-wide GitHub OIDC provider exists. If this is a fresh account, create it once:
  ```sh
  aws iam create-open-id-connect-provider \
    --url https://token.actions.githubusercontent.com \
    --client-id-list sts.amazonaws.com
  ```
  It is read as a data source here on purpose — destroying it would break every other repo
  in the account that federates in.

## Apply sequence

A container-image Lambda cannot be created before an image exists in ECR, and the thing that
pushes the image is the CI role this stack creates. So the first apply is split in two.
Afterwards, `tofu apply` on its own is all you need.

```sh
cd infra

# 1. One-time: create the state bucket (versioned, encrypted, private).
./bootstrap-state.sh                # add --profile <name> if not using the default
tofu init

# 2. Everything except the Lambdas and CloudFront.
tofu apply \
  -target=aws_ecr_repository.api \
  -target=aws_ecr_lifecycle_policy.api \
  -target=aws_cognito_user_pool.main \
  -target=aws_cognito_user_pool_client.app \
  -target=aws_iam_role_policy.deploy \
  -target=aws_iam_role_policy.api_ssm \
  -target=aws_iam_role_policy.auth_ssm \
  -target=aws_iam_role_policy.auth_cognito \
  -target=aws_iam_role_policy_attachment.api_logs \
  -target=aws_iam_role_policy_attachment.auth_logs

# 3. Fill the two external secrets (see below), then push an initial image:
#    either run the "Deploy Backend" workflow, or push manually from
#    back-end/<{{ app_name }}>-api (see "Manual first image").

# 4. Everything else — Lambdas, Function URLs, S3, ACM, CloudFront, Route53, SSM.
#    ACM validation blocks until the DNS record resolves; a few minutes is normal, and
#    CloudFront itself takes ~5-10 more to deploy.
tofu apply
```

> Step 2's `-target` list is deliberate: targeting the `aws_iam_role_policy` resources pulls
> in the roles, the ECR repo and the user pool as dependencies, without pulling in the
> Lambdas that don't have an image yet.

### External secrets

Two SSM SecureStrings are created as placeholders and never read by this stack —
`ignore_changes = [value]` means whatever you put in them stays out of tofu state:

```sh
aws ssm put-parameter --type SecureString --overwrite \
  --name /<{{ app_name }}>/prod/RUNTIME_DB_URL \
  --value 'postgresql+psycopg://<{{ app_name_snake }}>_svc_user:...@...neon.tech/...?options=-csearch_path%3Dapp'

aws ssm put-parameter --type SecureString --overwrite \
  --name /<{{ app_name }}>/prod/MIGRATIONS_DB_URL \
  --value 'postgresql+psycopg://<{{ app_name_snake }}>_db_owner:...@...neon.tech/...?options=-csearch_path%3Dapp'
```

`RUNTIME_DB_URL` is the one value the running app pulls from SSM itself, on cold start
(`app/db.py: resolve_runtime_db_url`). It is **not** in the Lambda environment. Rotating it is
therefore an SSM update plus a cold start — no `tofu apply`, no redeploy.

`MIGRATIONS_DB_URL` is read only by the backend workflow, to run Alembic.

### Manual first image

```sh
cd back-end/<{{ app_name }}>-api
aws ecr get-login-password --region <{{ aws_region }}> \
  | docker login --username AWS --password-stdin <{{ aws_account_id }}>.dkr.ecr.<{{ aws_region }}>.amazonaws.com
docker buildx build --platform linux/amd64 \
  -t <{{ aws_account_id }}>.dkr.ecr.<{{ aws_region }}>.amazonaws.com/<{{ app_name }}>-api:latest --push .
```

## What owns what

| Concern | Owner |
| --- | --- |
| Function *code* (image tag) | GitHub Actions (`lambda:UpdateFunctionCode`) — `image_uri` is under `ignore_changes` here |
| Function *config* (env, memory, timeout) | This stack. The deploy role has no `UpdateFunctionConfiguration`. |
| CORS for the api component | The api Function URL (`lambda.tf`) — **not** the app. `CORSMiddleware` is added only when `APP_ENV=local`. |
| Database credentials | You, via SSM. Never in state, never in an env var. |
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

```sh
API=$(tofu output -raw api_function_url)
PWA=$(tofu output -raw pwa_url)

curl -s "$API/healthz"                       # {"status":"ok"}
curl -I "$PWA"                               # 200, from CloudFront
curl -s -o /dev/null -w '%{http_code}\n' \
  -X POST "$PWA/auth/login/"                 # routes through to the auth Lambda (422, not 404)

# The auth Function URL must NOT be directly invocable:
curl -s -o /dev/null -w '%{http_code}\n' \
  -X POST "$(tofu output -raw auth_function_url)auth/login/"   # expect 403
```

Then the browser end-to-end: signup → confirm → login → reload (resume) → logout.

## Out of scope

WAF and rate limiting, a custom domain or API Gateway for the API, multiple environments,
DynamoDB, and Neon itself (created out of band).
