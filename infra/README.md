# infra — OpenTofu

Provisions the whole footprint for **<{{ app_name }}>**: Cognito, ECR, two Lambda functions
on Function URLs, the PWA's S3 + CloudFront + ACM + Route53 stack, IAM, the
`/<{{ app_name }}>/prod/*` SSM tree, and the Neon project the database lives in.

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
- A Neon account and a personal API key (Neon Console → Account Settings → API Keys),
  exported as `NEON_API_KEY`. Never written to config or state — see `providers.tf`.
- `psql` installed locally — needed once, for the "Neon bootstrap" step below.
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

# 3. Push an initial image manually, from back-end/<{{ app_name }}>-api
#    (see "Manual first image" below). The "Deploy Backend" workflow can't do this one —
#    it reads Lambda function names and MIGRATIONS_DB_URL from SSM, neither of which
#    exist until step 4. Use the workflow for every push after this one.

# 4. Everything else — Lambdas, Function URLs, S3, ACM, CloudFront, Route53, SSM, Neon.
#    ACM validation blocks until the DNS record resolves; a few minutes is normal, and
#    CloudFront itself takes ~5-10 more to deploy.
tofu apply

# 5. One-time: create the app's real DB roles/schema. See "Neon bootstrap" below.

# 6. Fill the two external secrets (see "External secrets" below) with real values —
#    only possible now that step 4 created the SSM parameters and step 5 created the
#    Neon roles.
```

> Step 2's `-target` list is deliberate: targeting the `aws_iam_role_policy` resources pulls
> in the roles, the ECR repo and the user pool as dependencies, without pulling in the
> Lambdas that don't have an image yet.

### Manual first image (step 3)

```sh
cd back-end/<{{ app_name }}>-api
aws ecr get-login-password --region <{{ aws_region }}> \
  | docker login --username AWS --password-stdin <{{ aws_account_id }}>.dkr.ecr.<{{ aws_region }}>.amazonaws.com
docker buildx build --platform linux/amd64 \
  -t <{{ aws_account_id }}>.dkr.ecr.<{{ aws_region }}>.amazonaws.com/<{{ app_name }}>-api:latest --push .
```

### Neon bootstrap (step 5)

`neon.tf` creates the Neon project (step 4, since it doesn't depend on the Lambda image) but
stops there — see the comment at the top of that file for why. Once it exists, run the schema
setup once, connected as the temporary role Neon provisioned with the project:

```sh
cd infra
DB_OWNER_PW=$(openssl rand -base64 24)
SVC_USER_PW=$(openssl rand -base64 24)

psql "$(tofu output -raw neon_bootstrap_connection_uri)" \
  -v db_owner_pw="$DB_OWNER_PW" \
  -v svc_user_pw="$SVC_USER_PW" \
  -f neon-init.sql

echo "db_owner:  $DB_OWNER_PW"
echo "svc_user:  $SVC_USER_PW"
```

`neon-init.sql` mirrors `../back-end/<{{ app_name }}>-api/db/init.sql` (same roles, schema,
grants) but takes the two passwords as psql variables instead of embedding them, so the real
production credentials exist only in your shell — never in a committed file, never in tofu
state. Note the two printed passwords; the next step needs them, and Neon won't show them
again. The bootstrap role itself is never used again and can be left alone or dropped.

### External secrets (step 6)

Two SSM SecureStrings are created as placeholders and never read by this stack —
`ignore_changes = [value]` means whatever you put in them stays out of tofu state. Build the
values from the host in `neon_bootstrap_connection_uri` (same project/branch, just swap in
`<{{ app_name_snake }}>_svc_user`/`_db_owner` and the passwords from the bootstrap step above):

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

WAF and rate limiting, a custom domain or API Gateway for the API, multiple environments, and
DynamoDB. Neon's project/branch/database are created by this stack (`neon.tf`); its
`db_owner`/`svc_user` roles are not — see "Neon bootstrap" above.
