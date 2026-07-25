# ADR 0001 — Domain & Auth Architecture: Token-Mediating Backend on Lambda

- **Status:** Accepted
- **Date:** 2026-06-30
- **Deciders:** Mike B

## Context

The backend was migrated from AWS App Runner to AWS Lambda (via the Lambda Web
Adapter). A **bare Lambda Function URL cannot carry a custom domain** — putting
`api.<domain>` in front of it would require CloudFront or API Gateway as an extra
indirection layer.

The reference app this template is based on (`cat-slideshow`) ran the API on a custom
subdomain (`cat-slideshow-api.mikeindevelopment.com`) and set the session-resume
**refresh token as an HttpOnly cookie on the shared parent domain**
(`.mikeindevelopment.com`), so the browser sent it to both the PWA and the API. That
model depends on the API and PWA sharing a registrable parent domain, and on
cross-site cookies — which Safari and Firefox block by default and Chrome now lets users
disable. It also keeps a long-lived refresh token in the browser.

We want a session-resume flow (`/auth/resume`) that does **not** depend on a custom API
domain or on cross-site cookies, and that keeps the refresh token out of the browser.

## Decision

Adopt the **Token-Mediating Backend (TMB)** pattern. The API stays on its **raw Lambda
Function URL**; a same-origin auth surface fronts the session.

```
Browser (https://app.<domain>)
  │  same-origin  /auth/*  ─► CloudFront (PWA distribution)
  │                            └─ behavior /auth/*  (no cache; POST; forward cookie+Authz)
  │                                 └─ OAC / SigV4 ─► Auth Lambda (Function URL, AWS_IAM)
  │                                      • Cognito broker: login / signup / confirm / resume / logout
  │                                      • refresh token stored SERVER-SIDE (Neon `sessions` table)
  │                                      • sets opaque HttpOnly; Secure session cookie @ app.<domain>
  │                                      • /auth/resume → short-lived access token in RESPONSE BODY
  │
  └─ cross-origin  Authorization: Bearer <access>  ─► Main API Lambda (raw Function URL, public)
                                                      CORS: allow-origin https://app.<domain>,
                                                      allow Authorization header, no credentials mode
```

Specific choices:

1. **IaC tool: OpenTofu** (`tofu`), not Terraform. HCL is compatible; docs/CLI target `tofu`.
2. **Session store: a `sessions` table in Neon.** No new managed service. Maps
   `session_id → { cognito_refresh_token, sub, expires_at, … }`. The browser holds only
   the opaque `session_id`; the refresh token never reaches the client. Enables true
   server-side revocation (logout, kill-session) — see [ADR rationale on the store below].
3. **Auth Lambda = the same FastAPI image as the API**, deployed as a **second function**.
   An `APP_COMPONENT` env var (`api` | `auth`) selects which routers `create_app()` mounts.
   One ECR repo, one codebase, two functions, per-function IAM roles. (Rejected: a separate
   auth microservice — its isolation benefit doesn't justify duplicated Cognito/DB code and
   a second build pipeline in a template, given we already accept the tradeoff in §Consequences.)
4. **PWA keeps a custom domain** (`app.<domain>`) via CloudFront + S3 (OAC) + ACM + Route53.
   The **API does not** — no custom domain, no ACM cert for it, no Route53 record, no
   CloudFront/API Gateway in front of it.
5. **Cognito is API-brokered.** The pool uses email sign-in, `ADMIN_USER_PASSWORD_AUTH` +
   `REFRESH_TOKEN_AUTH`, self-signup with email code verification, MFA off, token revocation
   on, **no client secret**. The vestigial hosted-UI/OAuth fields on the reference client
   (Cognito domain, callback URL, OAuth flows/scopes) are **omitted** — they are unused.

## Consequences

**Positive**

- No dependency on cross-site / third-party cookies — the session cookie is first-party to
  `app.<domain>` because `/auth/*` is served same-origin through the PWA's CloudFront distro.
- The refresh token never touches the browser; a stolen session cookie is an opaque,
  server-revocable handle rather than a usable Cognito credential.
- Reuses infrastructure the template needs anyway (the PWA CloudFront distribution) instead
  of a second domain + ACM cert + distribution just for the API.
- The API's public identity (raw Function URL) is an internal detail — cheap to swap later
  (different region, API Gateway, custom domain) without touching DNS/CORS/frontend config.
- Aligns with the IETF OAuth WG's *OAuth 2.0 for Browser-Based Applications* draft, which
  names TMB as a legitimate architecture (one rung below full BFF, above browser-side token
  handling) for sensitive apps.

**Negative / accepted tradeoffs**

- The **access token does reach the browser** and is XSS-stealable for its lifetime — TMB's
  known weaker point vs. full BFF. Mitigate with **short access-token TTLs** (tune Cognito
  `AccessTokenValidity` down from the reference's 60 min).
- The **raw Function URL as the public API** means no stable custom-domain indirection (the
  URL can change if the Lambda resource is replaced), no built-in WAF/rate-limiting/DDoS
  protection, and the AWS region/service is visible in the frontend bundle. These are
  operational conveniences deliberately deferred, not security-critical gaps.

## Why a server-side session store (vs. an encrypted "sealed" cookie)

A stateless variant could store the refresh token **encrypted with a server-only key inside
the cookie**, avoiding a table — but then the refresh token is back in the browser (as
ciphertext), and real revocation still needs a denylist. The Neon `sessions` table is what
makes this a genuine server-side session: instant logout / kill-session, refresh rotation,
and device/expiry metadata, all as a row we own.

## References

- IETF OAuth WG — *OAuth 2.0 for Browser-Based Applications* (Token-Mediating Backend).
- Implementation plans: [`docs/plans/tmb-refactor-plan.md`](../plans/tmb-refactor-plan.md)
  (app-side, done first), [`docs/plans/iac-plan.md`](../plans/iac-plan.md) (OpenTofu infra).
