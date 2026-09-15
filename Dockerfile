# syntax=docker/dockerfile:1
# ============================================================================
# Linux parity test image for tuidev — Alpine, one package layer, no compiling
# ============================================================================
# Built by `make container-test` (Apple container → podman → docker) and by
# the CI `docker-core` job. Runs `scripts/test_suite.sh --tag core` as an
# unprivileged user.
#
# Why Alpine: every tool the suite probes is an apk package, so the toolchain
# is a single cached layer measured in seconds, and the image is a fraction of
# the Ubuntu one. The Debian/Ubuntu apt path in scripts/install/core.sh is
# exercised on a real Debian box (see docs/remote.md), not here — this image
# tests the scripts, configs, and tool contract on Linux, not the installer.
# ============================================================================

FROM alpine:3.22

# Distro packages only. `yq-go` is the Go yq the configs expect (Alpine's
# plain `yq` name is not packaged; Debian's is the incompatible Python one).
RUN apk add --no-cache \
      bash zsh sudo git github-cli curl ca-certificates ncurses tmux \
      neovim ripgrep fd bat fzf zoxide delta eza starship bottom lazygit \
      jq yq-go lua5.4 shellcheck httpie \
    # Fail the build, not the test run, if a package stops providing its binary.
    && for t in nvim rg fd bat fzf zoxide delta eza starship btm lazygit jq yq gh shellcheck http tmux zsh; do \
         command -v "$t" >/dev/null || { echo "missing: $t" >&2; exit 1; }; done

# Unprivileged test user (passwordless sudo: the apt/apk fallback path uses it).
RUN adduser -D -s /bin/zsh testuser \
    && echo "testuser ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/testuser \
    && chmod 0440 /etc/sudoers.d/testuser

# Repo last: it changes most often.
COPY --chown=testuser:testuser . /home/testuser/tuidev/
USER testuser
WORKDIR /home/testuser/tuidev
ENV TERM=xterm-256color

# Minimal installed-config shape the core tests expect.
RUN mkdir -p ~/.config/nvim ~/.config/tmux ~/.local/bin \
    && cp configs/zsh/.zshrc ~/.zshrc \
    && cp configs/starship/starship.toml ~/.config/starship.toml \
    && cp configs/tmux/tmux.conf ~/.config/tmux/tmux.conf \
    && cp -r configs/nvim/. ~/.config/nvim/ \
    && git config --global core.pager delta \
    && chmod +x scripts/*.sh

CMD ["./scripts/test_suite.sh", "--tag", "core"]
