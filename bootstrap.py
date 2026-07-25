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
    uv run bootstrap.py           # apply changes in place
    uv run bootstrap.py --dry-run # preview without writing
"""
import os
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
}
SKIP_FILES = {
    'bootstrap.py', 'bootstrap.config.yaml',
    'uv.lock', 'pnpm-lock.yaml', 'LICENSE',
    '.terraform.lock.hcl',
}

# Placeholder used in dir/file names (filesystem names can't use <{{ }}>)
NAME_PLACEHOLDER = '__app-name__'


def load_config():
    p = ROOT / 'bootstrap.config.yaml'
    if not p.exists():
        sys.exit(f"Config not found: {p}")
    return yaml.safe_load(p.read_text())


def build_context(c):
    name = c['app']['name']
    infra = c.get('infra', {})
    return {
        'app_name':       name,
        'app_name_snake': name.replace('-', '_'),
        'aws_account_id': str(c['aws']['account_id']),
        'aws_region':     c['aws']['region'],
        'api_port':       str(c['app'].get('api_port', 8000)),
        'python_version': str(c.get('python_version', '3.11')),
        'node_version':   str(c.get('node_version', '24')),
        'pnpm_version':   str(c.get('pnpm_version', '11')),
        # infra/ (OpenTofu)
        'root_domain':    infra.get('root_domain', 'example.com'),
        'github_repo':    infra.get('github_repo', 'my-org/my-repo'),
        'lambda_memory':  str(infra.get('lambda_memory', 512)),
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


def main():
    config = load_config()
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
        print("Run without --dry-run to apply.")
    else:
        print("Done. Suggested next steps:")
        print("  git add -A")
        print("  git commit -m 'Initialize from template'")
        print("  # Optional: delete bootstrap.py and bootstrap.config.yaml")


if __name__ == '__main__':
    main()
