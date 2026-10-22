# tuidev shell fragment — minimum release age for uvx and `uv tool`
# (installed by `--pack release-age`; @DAYS@ is filled in at install).
#
# uv writes a user-level exclude-newer into every project's uv.lock, and
# `uv sync --locked` then fails for whoever doesn't share it, so the age
# applies only where no lockfile is written: uvx and uv tool (`uv pip` reads
# it from uv.toml's [pip] table). An exported UV_EXCLUDE_NEWER wins; set it to
# false to take a release younger than the age.

if (( $+commands[uv] )); then
  uvx() { UV_EXCLUDE_NEWER="${UV_EXCLUDE_NEWER:-@DAYS@ days}" command uvx "$@"; }
  uv() {
    if [[ "$1" == tool ]]; then
      UV_EXCLUDE_NEWER="${UV_EXCLUDE_NEWER:-@DAYS@ days}" command uv "$@"
    else
      command uv "$@"
    fi
  }
fi
