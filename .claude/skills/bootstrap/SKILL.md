---
name: bootstrap
description: "Bootstrap a new project from the pennies-pwa-template, or resume bootstrapping one already in progress — from filling in your AWS/Neon/GitHub defaults, through copying the template and rendering it, through the phased infra apply and first deploy. Use when the user asks to bootstrap, scaffold, or start a new project from this template, or invokes /bootstrap."
---

# /bootstrap

Drives the whole path from "empty template repo" to "deployed app" in a handful of approvals:
you answer two prompts, approve one `tofu plan`, and this skill runs everything else, phase by
phase, logging each one. Run it from the pennies-pwa-template repo.

Read this whole file before doing anything. The steps below are ordered; do not skip ahead.

## 1. Mode detection

Check whether `infra/locals.tf` still contains the literal string `<{{`.

- **Contains `<{{`** → this is the template itself. Go to step 2, **new project** path.
- **Doesn't** → this project is already rendered. **Resume**: read `bootstrap-project.config.yaml`
  and show its values to the user, then run `infra/scripts/bootstrap-infra.sh status` and
  report which phase to continue from. Skip to step 6 (Infra), starting at that phase.

## 2. Defaults (`~/.config/pennies-pwa-template/export-vars.sh`)

This file holds values that don't change between projects, plus `NEON_API_KEY`. It is never
read with `Read`/`cat` — only sourced in a subshell — because it holds that key.

1. If `~/.config/pennies-pwa-template/export-vars.sh` doesn't exist, copy
   `.claude/skills/bootstrap/export-vars.template.sh` into place and `chmod 600` it.
2. List which variables are still empty, by name only:
   ```sh
   bash -c 'source ~/.config/pennies-pwa-template/export-vars.sh && for v in PENNIES_PROJECTS_DIR PENNIES_AWS_ACCOUNT_ID PENNIES_AWS_REGION PENNIES_AWS_PROFILE PENNIES_ROOT_DOMAIN PENNIES_NEON_REGION_ID PENNIES_GITHUB_VISIBILITY PENNIES_LAMBDA_MEMORY PENNIES_API_PORT PENNIES_PYTHON_VERSION PENNIES_NODE_VERSION PENNIES_PNPM_VERSION; do [ -z "${!v}" ] && echo "$v"; done'
   ```
3. For each empty non-secret variable, ask with AskUserQuestion. Offer a detected value as the
   recommended option where you can:
   - `PENNIES_AWS_ACCOUNT_ID` / `PENNIES_AWS_REGION` / `PENNIES_AWS_PROFILE` ← `aws sts
     get-caller-identity`, `aws configure get region`, `aws configure list-profiles`.
   - `PENNIES_ROOT_DOMAIN` ← `aws route53 list-hosted-zones --query
     "HostedZones[].Name"` (public zones you own).
   - Others: use the template's own defaults (see `export-vars.template.sh`) as the
     recommended option.
4. Write answers back into `~/.config/pennies-pwa-template/export-vars.sh` with targeted `sed`
   edits (one variable per edit) — never rewrite the whole file, and never print its contents.
5. Check `NEON_API_KEY` without ever echoing it:
   ```sh
   bash -c 'source ~/.config/pennies-pwa-template/export-vars.sh && [ -n "$NEON_API_KEY" ]'
   ```
   If empty, tell the user to open the file and add it by hand (Neon Console → Account
   Settings → API Keys), then wait for them to confirm before continuing.

## 3. Prompts (new project only)

Every run, regardless of defaults, ask with AskUserQuestion:
- `app.name` — hyphens, matches `^[a-z][a-z0-9-]*$`.
- `infra.github_repo` — `owner/repo`.

Then check `$PENNIES_PROJECTS_DIR/<app.name>`. If it exists and is non-empty, stop and tell the
user — don't overwrite in-progress work.

## 4. Copy

1. Warn the user if `git status --porcelain` on the template repo is non-empty — `git archive`
   only copies committed content, so uncommitted template changes won't carry over.
2. Note the template's current commit SHA (`git rev-parse HEAD`) for the first commit message.
3. `git archive HEAD | tar -x -C "$PENNIES_PROJECTS_DIR/<app.name>"`, then `git init -b main` in
   the new directory.

## 5. Config

1. Write `<project>/bootstrap-project.config.yaml` from the export-vars defaults plus the
   prompted `app.name`/`infra.github_repo`. Match the shape in the shipped
   `bootstrap-project.config.yaml` — same keys, same structure.
2. Show the filled-in config to the user (it has no secrets in it — safe to print).
3. Run `uv run bootstrap-project.py` in the new project directory.
4. First commit, authorized by this skill run:
   `git commit -m "Initialize from pennies-pwa-template@<sha>"` (the SHA from step 4.2).

## 6. Infra

From here on, every Bash call must `source ~/.config/pennies-pwa-template/export-vars.sh`
before the actual command — shell state (env vars, cwd) does not persist between separate Bash
tool calls, so each one needs the export again. Run everything from
`<project>/infra/scripts/`.

1. Run `./bootstrap-infra.sh pre` (preflight → state → plan).
   - If `preflight` fails, report the specific check that failed and stop — most failures here
     (missing hosted zone, missing OIDC provider, account mismatch) need the user to fix
     something outside this repo.
2. Show the user the plan summary from `pre`'s output (add/change/destroy counts, and point to
   the full log under `infra/.bootstrap-infra-logs/`).
3. AskUserQuestion: approve applying this plan? If no, stop here — the user can rerun `/bootstrap`
   later to pick up from `pre` again.
4. On approval, run `./bootstrap-infra.sh post` (apply → db → deploy → verify) — **except**
   `deploy`: before it runs, AskUserQuestion to confirm creating the GitHub repo (or, if it
   already exists, triggering the workflows) and pushing. This is outward-facing and
   irreversible-ish, so it gets its own explicit confirmation even though it's inside `post`.
   Once confirmed, export `BOOTSTRAP_CONFIRM_DEPLOY=yes` before invoking `post` (or `deploy` on
   its own, if resuming) so the script doesn't also block on its own interactive prompt.
5. If a phase fails: read that phase's log under `infra/.bootstrap-infra-logs/`, report what
   went wrong in plain terms, and re-run only that phase (`./bootstrap-infra.sh <phase>`) once
   the user has addressed it. Never edit `.tf` files or IAM policies to push past an error
   without asking the user first — treat any such error as a stop, not a puzzle to route around.
6. Never print, read, or ask the user for secrets (`NEON_API_KEY`, DB passwords, SSM values).
   The scripts already keep these out of stdout and disk; don't undo that by echoing command
   output that might contain them.

## Done

When `verify` passes, tell the user the app is live at the `pwa_url` tofu output, and mention
`infra/scripts/bootstrap-infra.sh status` as the way to check on it later, and `db --rotate` as
the way to rotate DB passwords.
