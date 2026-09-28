#!/usr/bin/env -S uv run
# /// script
# requires-python = ">=3.12"
# dependencies = ["pyyaml", "jinja2"]
# ///
"""Stamp this template for a new project.

Template files use <{{ variable }}> syntax for Jinja2 expressions.
That delimiter is safe alongside GHA ${{ }}, Python {}, and YAML.

Folder/file name placeholders use __app-name__ (double-underscore, hyphen inside).

Usage:
    uv run bootstrap-project.py           # apply changes in place
    uv run bootstrap-project.py --dry-run # preview without writing
"""
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

try:
    import yaml
except ImportError:
    sys.exit("PyYAML required: pip install pyyaml jinja2")

try:
    from jinja2 import Environment, StrictUndefined
except ImportError:
    sys.exit("Jinja2 required: pip install pyyaml jinja2")

DRY_RUN = '--dry-run' in sys.argv
ROOT = Path(__file__).parent

# Custom delimiters — <{{ and }}> are safe alongside GHA ${{ }}, Python {}, YAML
J2_ENV = Environment(
    variable_start_string='<{{',
    variable_end_string='}}>',
    block_start_string='<{%',
    block_end_string='%}>',
    comment_start_string='<{#',
    comment_end_string='#}>',
    keep_trailing_newline=True,
    undefined=StrictUndefined,
)

SKIP_DIRS = {
    '.git', 'node_modules', '.venv', 'dist', '__pycache__',
    '.pytest_cache', '.mypy_cache', '.ruff_cache', '.terraform',
    '.claude',
}
SKIP_FILES = {
    'bootstrap-project.py', 'bootstrap-project.config.yaml',
    'uv.lock', 'pnpm-lock.yaml', 'LICENSE',
    '.terraform.lock.hcl',
}

# Placeholder used in dir/file names (filesystem names can't use <{{ }}>)
NAME_PLACEHOLDER = '__app-name__'

APP_NAME_RE = re.compile(r'[a-z][a-z0-9-]*')
ACCOUNT_ID_RE = re.compile(r'\d{12}')
GITHUB_REPO_RE = re.compile(r'[^/\s]+/[^/\s]+')


def load_config():
    p = ROOT / 'bootstrap-project.config.yaml'
    if not p.exists():
        sys.exit(f"Config not found: {p}")
    return yaml.safe_load(p.read_text())


def validate_config(c):
    """No silent defaults for project decisions — a wrong value here (wrong region, wrong
    account) is expensive to unwind once real infra exists, so every one of these is required
    and checked rather than quietly defaulted."""
    app = c.get('app') or {}
    aws = c.get('aws') or {}
    infra = c.get('infra') or {}
    errors = []

    name = app.get('name')
    if not name or not APP_NAME_RE.fullmatch(name):
        errors.append("app.name is required and must match ^[a-z][a-z0-9-]*$")

    account_id = aws.get('account_id')
    if not account_id or not ACCOUNT_ID_RE.fullmatch(str(account_id)):
        errors.append("aws.account_id is required and must be exactly 12 digits")

    if not aws.get('region'):
        errors.append("aws.region is required")

    github_repo = infra.get('github_repo')
    if not github_repo or not GITHUB_REPO_RE.fullmatch(github_repo):
        errors.append("infra.github_repo is required and must be 'owner/repo'")

    if not infra.get('root_domain'):
        errors.append("infra.root_domain is required")

    visibility = infra.get('github_visibility', 'private')
    if visibility not in ('private', 'public'):
        errors.append("infra.github_visibility must be 'private' or 'public'")

    if errors:
        sys.exit("Config errors in bootstrap-project.config.yaml:\n" + "\n".join(f"  - {e}" for e in errors))


def build_context(c):
    name = c['app']['name']
    aws = c['aws']
    infra = c.get('infra', {})
    return {
        'app_name':          name,
        'app_name_snake':    name.replace('-', '_'),
        'aws_account_id':    str(aws['account_id']),
        'aws_region':        aws['region'],
        # Deploy-time profile — bootstrap-infra.sh exports this as AWS_PROFILE. Not used by
        # the running app; local dev auth is up to whatever's already active in your shell.
        'aws_profile':       aws.get('profile', 'default'),
        'api_port':          str(c['app'].get('api_port', 8000)),
        'python_version':    str(c.get('python_version', '3.12')),
        'node_version':      str(c.get('node_version', '24')),
        'pnpm_version':      str(c.get('pnpm_version', '11')),
        # infra/ (OpenTofu)
        'root_domain':       infra['root_domain'],
        'github_repo':       infra['github_repo'],
        'github_visibility': infra.get('github_visibility', 'private'),
        'lambda_memory':     str(infra.get('lambda_memory', 512)),
        'neon_region_id':    infra.get('neon_region_id') or f"aws-{aws['region']}",
    }


def is_binary(path: Path) -> bool:
    try:
        path.read_bytes()[:8192].decode('utf-8')
        return False
    except (UnicodeDecodeError, PermissionError):
        return True


def walk_text_files():
    for dirpath, dirnames, filenames in os.walk(ROOT, topdown=True):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for fname in filenames:
            if fname in SKIP_FILES:
                continue
            fpath = Path(dirpath) / fname
            if not is_binary(fpath):
                yield fpath


def render_contents(context):
    modified = []
    for fpath in walk_text_files():
        original = fpath.read_text(encoding='utf-8')
        try:
            updated = J2_ENV.from_string(original).render(context)
        except Exception as e:
            print(f"  WARNING: skipping {fpath.relative_to(ROOT)}: {e}")
            continue
        if updated != original:
            modified.append(fpath.relative_to(ROOT))
            if not DRY_RUN:
                fpath.write_text(updated, encoding='utf-8')
    return modified


def collect_renames(app_name):
    to_rename = []
    for dirpath, dirnames, filenames in os.walk(ROOT, topdown=True):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for name in filenames + dirnames:
            if NAME_PLACEHOLDER in name:
                to_rename.append(Path(dirpath) / name)
    # Deepest paths first so children are renamed before their parent dirs
    to_rename.sort(key=lambda p: len(p.parts), reverse=True)
    return to_rename


def apply_renames(app_name):
    renames = []
    for src in collect_renames(app_name):
        if not src.exists():
            continue
        new_name = src.name.replace(NAME_PLACEHOLDER, app_name)
        dst = src.parent / new_name
        renames.append((src.relative_to(ROOT), dst.relative_to(ROOT)))
        if not DRY_RUN:
            src.rename(dst)
    return renames


def relock_uv():
    """uv.lock is excluded from templating (it's not renderable), so it still
    pins the pre-bootstrap package name. Regenerate it so `uv sync --frozen`
    (used in the Dockerfile) doesn't choke on a stale workspace member name."""
    if shutil.which('uv') is None:
        print("  WARNING: uv not found on PATH — skipping, run `uv lock` manually")
        return []
    relocked = []
    for lockfile in ROOT.rglob('uv.lock'):
        if any(part in SKIP_DIRS for part in lockfile.relative_to(ROOT).parts):
            continue
        project_dir = lockfile.parent
        result = subprocess.run(['uv', 'lock'], cwd=project_dir, capture_output=True, text=True)
        if result.returncode != 0:
            print(f"  WARNING: uv lock failed in {project_dir.relative_to(ROOT)}:\n{result.stderr}")
            continue
        relocked.append(lockfile.relative_to(ROOT))
    return relocked


def main():
    config = load_config()
    validate_config(config)
    context = build_context(config)

    if DRY_RUN:
        print("=== DRY RUN — nothing will be written ===\n")

    print("Rendering file contents...")
    modified = render_contents(context)
    for p in sorted(modified):
        print(f"  modified  {p}")
    print(f"  ({len(modified)} files)\n")

    print("Renaming paths...")
    renames = apply_renames(context['app_name'])
    for src, dst in renames:
        print(f"  {src} → {dst}")
    print(f"  ({len(renames)} paths)\n")

    if DRY_RUN:
        print("Would regenerate uv.lock files (skipped in dry run).\n")
    else:
        print("Regenerating uv.lock (pyproject.toml package name changed)...")
        relocked = relock_uv()
        for p in sorted(relocked):
            print(f"  relocked  {p}")
        print(f"  ({len(relocked)} files)\n")

    if DRY_RUN:
        print("Run without --dry-run to apply.")
    else:
        print("Done. bootstrap-project.config.yaml is kept in place — re-running this script")
        print("reads it again, and it's how a resumed /bootstrap run finds its config.")
        print("Suggested next steps:")
        print("  git add -A")
        print("  git commit -m 'Initialize from template'")


if __name__ == '__main__':
    main()
