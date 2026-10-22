#!/bin/bash
# scripts/lib/uv.sh - uv itself and the Pythons it manages: how uv was
# installed, whether it is behind, and which managed Pythons are.
#
# Source after ui.sh. Idempotent; safe to source multiple times.
#
#   . "$(dirname "${BASH_SOURCE[0]}")/ui.sh"
#   . "$(dirname "${BASH_SOURCE[0]}")/uv.sh"
#
# Exposes:
#   uv_install_kind          brew | standalone | other | none
#   uv_self_check            "CURRENT LATEST" when the standalone uv is behind,
#                            nothing when current; returns 1 when the check fails
#   uv_python_stale          "HAVE LATEST" per managed Python whose minor has a
#                            newer patch; returns 1 when uv can't list them
#   uv_python_managed        the managed Pythons installed (keys), one per line
#
# Homebrew's uv is upgraded with the extras pack's formulae. The standalone
# installer's uv (it leaves a uv-receipt.json) updates itself with
# `uv self update`, checked against the release's sha256. uv knows the Python
# builds of its own release only, so update uv before its Pythons:
# `uv python upgrade` then moves each installed minor to its latest patch and
# repoints the minor's directory, so venvs built on it follow.

if [[ -n "${_TUIDEV_UV_LOADED:-}" ]]; then
    return 0
fi
_TUIDEV_UV_LOADED=1

uv_install_kind() {
    local bin prefix
    bin="$(command -v uv 2>/dev/null)" || { echo none; return 0; }
    prefix="$(brew --prefix 2>/dev/null || true)"
    if [[ -n "$prefix" && "$bin" == "$prefix/"* ]]; then
        echo brew
    elif [[ -f "${XDG_CONFIG_HOME:-$HOME/.config}/uv/uv-receipt.json" ]]; then
        echo standalone
    else
        echo other
    fi
}

uv_self_check() {
    local out
    out="$(uv self update --dry-run 2>&1)" || return 1
    printf '%s\n' "$out" | awk '/Would update uv from/ { print $(NF-2), $NF }'
}

# `uv python list --managed-python` prints the installed builds with their
# paths and, for each minor, the newest build uv knows as <download available>.
_uv_python_list() { uv python list --managed-python 2>/dev/null; }

uv_python_managed() {
    { _uv_python_list || true; } | awk '$2 != "<download" { print $1 }' | sort -u
}

# A build's series is its key without the patch (cpython-3.14-macos-aarch64-none,
# variants such as +freethreaded kept): one download per series is listed.
uv_python_stale() {
    local list
    list="$(_uv_python_list)" || return 1
    [[ -n "$list" ]] || return 1
    printf '%s\n' "$list" | awk '
        function series(key,   n, p, v, m, s, i) {
            n = split(key, p, "-"); v = p[2]
            sub(/^[0-9]+\.[0-9]+\.[0-9a-z]+/, "", v)
            split(p[2], m, ".")
            s = p[1] "-" m[1] "." m[2] v
            for (i = 3; i <= n; i++) s = s "-" p[i]
            return s
        }
        $2 == "<download" { latest[series($1)] = $1; next }
        !seen[$1]++ { have[++k] = $1 }
        END {
            for (j = 1; j <= k; j++) {
                s = series(have[j])
                if ((s in latest) && latest[s] != have[j]) print have[j], latest[s]
            }
        }'
}
