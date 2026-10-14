#!/bin/bash
# Add the "modern shell" demo to a demo home that demo-setup.sh already built
# (docs/assets/tapes/README.md): demo-shell-setup.sh HOME. Idempotent. It makes
# a small repo at ~/api with a staged change, an unstaged one and an
# untracked file, installs the shipped Starship config with the Tokyo Night
# palette (through scripts/theme.sh, as an install would), and sets the
# defaults tuidev ships for the VCS (delta as the pager). Everything is made up.
set -eo pipefail

home="${1:?usage: demo-shell-setup.sh HOME}"
tapes="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$tapes/../../.." && pwd)"

export HOME="$home"
unset XDG_CONFIG_HOME TUIDEV_STATE_DIR
mkdir -p "$home/.config/tuidev"

api="$home/api"
if [[ ! -d "$api/.git" ]]; then
    mkdir -p "$api/src" "$api/tests"
    cat > "$api/README.md" <<'EOT'
# api

A made-up service for the tuidev screenshots.

    make test    # run the tests
    make run     # serve on :8080
EOT
    cat > "$api/pyproject.toml" <<'EOT'
[project]
name = "api"
version = "1.4.0"
requires-python = ">=3.12"
dependencies = ["httpx>=0.27", "uvicorn>=0.30"]

[tool.pytest.ini_options]
testpaths = ["tests"]
EOT
    printf 'test:\n\tpytest\n\nrun:\n\tuvicorn src.app:app --port 8080\n' > "$api/Makefile"
    cat > "$api/src/app.py" <<'EOT'
"""Entry point for the made-up api."""
from routes import handle, status


def app(path):
    if path == "/status":
        return status()
    return handle(path)
EOT
    cat > "$api/src/routes.py" <<'EOT'
"""HTTP routes."""
from db import connect

ROUTES = {"/health": "ok", "/version": "1.4.0"}


def handle(path):
    """Return the body for a path."""
    # TODO: return a 404 for unknown paths
    return ROUTES.get(path, "")


def status():
    conn = connect("sqlite://demo")
    return {"routes": len(ROUTES), "db": conn["url"]}
EOT
    cat > "$api/src/db.py" <<'EOT'
"""Database access."""


def connect(url):
    # TODO: pool connections
    return {"url": url}
EOT
    cat > "$api/tests/test_routes.py" <<'EOT'
from routes import handle


def test_health():
    assert handle("/health") == "ok"


def test_version():
    assert handle("/version") == "1.4.0"
EOT
    (
        cd "$api"
        command git init -q -b main
        command git add -A
        GIT_AUTHOR_NAME=Demo GIT_AUTHOR_EMAIL=demo@example.com GIT_AUTHOR_DATE="2026-01-05T10:00:00Z" \
        GIT_COMMITTER_NAME=Demo GIT_COMMITTER_EMAIL=demo@example.com GIT_COMMITTER_DATE="2026-01-05T10:00:00Z" \
            command git commit -q -m "feat: health and version routes"
    )
    # An unstaged edit, a staged edit and a new file.
    cat > "$api/src/routes.py" <<'EOT'
"""HTTP routes."""
from db import connect

ROUTES = {"/health": "ok", "/version": "1.4.0"}


def handle(path):
    """Return the body for a path."""
    # TODO: return a 404 for unknown paths
    body = ROUTES.get(path)
    return body if body is not None else "not found"


def status():
    conn = connect("sqlite://demo")
    return {"routes": len(ROUTES), "db": conn["url"]}
EOT
    cat > "$api/src/db.py" <<'EOT'
"""Database access."""


def connect(url, timeout=5):
    # TODO: pool connections
    return {"url": url, "timeout": timeout}
EOT
    command git -C "$api" add src/db.py
    printf '"""A tiny cache."""\nCACHE = {}\n\n\ndef get(key):\n    # TODO: expire entries\n    return CACHE.get(key)\n' > "$api/src/cache.py"
    # Fixed times, so ll never shows when the shot was rendered.
    find "$api" -path "$api/.git" -prune -o -exec env TZ=UTC touch -t 202601051000 {} +
fi

# The shipped prompt config, as install.sh places it, then the palette.
if [[ ! -f "$home/.config/starship.toml" ]]; then
    # shellcheck source=../../../scripts/lib/ui.sh disable=SC1091
    . "$repo/scripts/lib/ui.sh"
    # shellcheck source=../../../scripts/lib/config_write.sh disable=SC1091
    . "$repo/scripts/lib/config_write.sh"
    write_managed_block "$home/.config/starship.toml" tuidev-starship "$(cat "$repo/configs/starship/starship.toml")" >/dev/null
    bash "$repo/scripts/theme.sh" apply tokyo-night >/dev/null 2>&1 || echo "demo-shell-setup: theme.sh apply failed" >&2
fi

# The defaults tuidev ships for the VCS (delta, histogram diffs, ...), for this home only.
if [[ ! -f "$home/.gitconfig" ]]; then
    # shellcheck source=../../../scripts/lib/ui.sh disable=SC1091
    . "$repo/scripts/lib/ui.sh"
    # shellcheck source=../../../scripts/lib/manifest.sh disable=SC1091
    . "$repo/scripts/lib/manifest.sh"
    # shellcheck source=../../../scripts/lib/gitconfig.sh disable=SC1091
    . "$repo/scripts/lib/gitconfig.sh"
    tuidev_git_defaults >/dev/null 2>&1 || true
fi
