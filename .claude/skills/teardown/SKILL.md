---
name: teardown
description: Destroy all AWS and Neon infrastructure that /bootstrap provisioned for this project. Use ONLY when the user explicitly asks to tear down, destroy, or delete the infra for a project. Never use for bootstrap, scaffold, redo, or start-over requests.
---

# Teardown

Destroys everything `infra/scripts/bootstrap-infra.sh` created, via `infra/scripts/teardown-infra.sh`
(see "Teardown" in `infra/README.md`). It runs inside a rendered project, not the template repo.
All paths below are relative to the project root.

## Hard rules

- **Never delete the GitHub repo.** Neither the script nor this skill does. Only relay the
  script's closing message that the user *can* run `gh repo delete <repo>` themselves (needs
  `gh auth refresh -s delete_repo`). Don't offer to run it or automate it.
- Never print secrets (`NEON_API_KEY`, SSM values, DB URLs). Never read or `cat` the export-vars file.
- Never edit `.tf` files or work around a guard without asking the user.

## Flow

1. Confirm this is a rendered project: `infra/locals.tf` must not contain `<{{`. If it does, stop.
   Show the user the app name, AWS account, region and profile (from `infra/scripts/lib.sh`).
2. Every Bash call from here sources the defaults in a subshell for `NEON_API_KEY`, like `/bootstrap`
   step 2: `bash -c 'source ~/.config/pennies-pwa-template/export-vars.sh && infra/scripts/teardown-infra.sh ...'`.
3. Run `teardown-infra.sh --check-only`, then `teardown-infra.sh --plan-only`. Ask the user whether
   they want a database dump; if so add `--backup` to the plan-only run and later the real run.
   Show them the results.
4. Ask with AskUserQuestion whether to proceed. Only on an explicit yes, run the real teardown with
   `TEARDOWN_CONFIRM_APP=<app-name>` exported (must equal the app name, not "yes"). CloudFront
   deletion takes 5-15 minutes.
5. If it fails or the drift guard aborts, read the newest log under `infra/.bootstrap-infra-logs/`,
   report what happened, and stop.
6. When it finishes, report the leftover check result and relay the GitHub-repo note above.
