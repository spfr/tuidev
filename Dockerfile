FROM ubuntu:22.04

# ============================================================================
# Test Environment for macOS TUI Development Setup
# ============================================================================
# Tests CLI tools and validates all configurations.
# Supports both macOS and Linux validation.
# ============================================================================

ENV DEBIAN_FRONTEND=noninteractive
ENV TERM=xterm-256color

# Install dependencies
RUN apt-get update && apt-get install -y \
    curl wget git build-essential pkg-config \
    libssl-dev libevent-dev ncurses-dev \
    zlib1g-dev zsh lua5.4 luarocks \
    bat ripgrep fd-find jq unzip \
    software-properties-common \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install Neovim (latest stable)
RUN add-apt-repository ppa:neovim-ppa/unstable -y \
    && apt-get update \
    && apt-get install -y neovim \
    && apt-get clean

# Install Rust and Rust-based tools
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
ENV PATH="/root/.cargo/bin:${PATH}"
RUN cargo install zellij starship zoxide bottom eza

# Install fzf
RUN git clone --depth 1 https://github.com/junegunn/fzf.git /opt/fzf \
    && /opt/fzf/install --all --no-bash --no-fish
ENV PATH="/opt/fzf/bin:${PATH}"

# Install lazygit
RUN LAZYGIT_VERSION=$(curl -s "https://api.github.com/repos/jesseduffield/lazygit/releases/latest" | grep -Po '"tag_name": "v\K[^"]*') \
    && curl -Lo lazygit.tar.gz "https://github.com/jesseduffield/lazygit/releases/latest/download/lazygit_${LAZYGIT_VERSION}_Linux_x86_64.tar.gz" \
    && tar xf lazygit.tar.gz lazygit \
    && install lazygit /usr/local/bin \
    && rm lazygit.tar.gz lazygit

# Create test user
RUN useradd -m -s /bin/zsh testuser \
    && echo "testuser ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Create symlinks for Ubuntu-named binaries
RUN ln -sf /usr/bin/fdfind /usr/local/bin/fd \
    && ln -sf /usr/bin/batcat /usr/local/bin/bat

# Copy repository
COPY --chown=testuser:testuser . /home/testuser/tuidev/

USER testuser
WORKDIR /home/testuser

# Set up configurations
RUN mkdir -p ~/.config/zellij/layouts ~/.config/nvim ~/.local/bin \
    && cp /home/testuser/tuidev/configs/zsh/.zshrc ~/.zshrc \
    && cp /home/testuser/tuidev/configs/starship/starship.toml ~/.config/starship.toml \
    && cp /home/testuser/tuidev/configs/zellij/config.kdl ~/.config/zellij/config.kdl \
    && cp /home/testuser/tuidev/configs/zellij/layouts/*.kdl ~/.config/zellij/layouts/ \
    && cp -r /home/testuser/tuidev/configs/nvim/* ~/.config/nvim/

# Make scripts executable
RUN chmod +x /home/testuser/tuidev/scripts/*.sh

# Create comprehensive test script
RUN echo '#!/bin/bash\n\
set -e\n\
echo ""\n\
echo "============================================"\n\
echo "macOS TUI Setup - Docker Test Suite"\n\
echo "============================================"\n\
echo ""\n\
\n\
PASS=0\n\
FAIL=0\n\
\n\
test_cmd() {\n\
    if command -v "$1" &>/dev/null; then\n\
        echo -e "\\033[32m[PASS]\\033[0m $1"\n\
        ((PASS++))\n\
    else\n\
        echo -e "\\033[31m[FAIL]\\033[0m $1 not found"\n\
        ((FAIL++))\n\
    fi\n\
}\n\
\n\
echo "--- CLI Tools ---"\n\
test_cmd zellij\n\
test_cmd nvim\n\
test_cmd starship\n\
test_cmd fzf\n\
test_cmd rg\n\
test_cmd bat\n\
test_cmd fd\n\
test_cmd zoxide\n\
test_cmd eza\n\
test_cmd btm\n\
test_cmd lazygit\n\
echo ""\n\
\n\
echo "--- Config Validation ---"\n\
cd /home/testuser/tuidev\n\
./scripts/validate_configs.sh\n\
echo ""\n\
\n\
echo "--- Zellij Layout Test ---"\n\
for layout in ~/.config/zellij/layouts/*.kdl; do\n\
    name=$(basename "$layout")\n\
    if zellij setup --check-config "$layout" 2>/dev/null || true; then\n\
        echo -e "\\033[32m[PASS]\\033[0m $name"\n\
        ((PASS++))\n\
    fi\n\
done\n\
echo ""\n\
\n\
echo "--- Neovim Health ---"\n\
if nvim --headless -c "quit" 2>/dev/null; then\n\
    echo -e "\\033[32m[PASS]\\033[0m nvim starts"\n\
    ((PASS++))\n\
else\n\
    echo -e "\\033[31m[FAIL]\\033[0m nvim failed to start"\n\
    ((FAIL++))\n\
fi\n\
echo ""\n\
\n\
echo "============================================"\n\
echo "Results: $PASS passed, $FAIL failed"\n\
echo "============================================"\n\
\n\
if [[ $FAIL -gt 0 ]]; then\n\
    exit 1\n\
fi\n\
' > /home/testuser/run_tests.sh && chmod +x /home/testuser/run_tests.sh

SHELL ["/bin/zsh", "-c"]

CMD ["/home/testuser/run_tests.sh"]
