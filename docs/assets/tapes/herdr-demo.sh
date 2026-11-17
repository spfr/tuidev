#!/bin/bash
# The Herdr screenshot's fleet (docs/assets/tapes/README.md): a Herdr server on
# this Mac and two Linux machines, devbox and workbox, each a container running
# sshd and Herdr, saved in the Mac's Herdr as SSH machines. The runtime is Apple
# `container` or podman (TUIDEV_CONTAINER_RUNTIME; detection is
# scripts/lib/container.sh). Each machine runs a few scripted agent stand-ins
# (herdr/demo-agent.sh) that report their state through Herdr's hook API, in
# workspaces that are git repos, with tuidev as the herdr and monitoring packs
# leave it: this checkout's `agents`, the tuidev.link plugin (its hooks name
# the tabs and fill the sidebar's tokens) and its keys, and on the Mac the
# sidebar rows (configs/herdr/sidebar.toml).
#
#   herdr-demo.sh up HOME     build the image if needed, start everything
#   herdr-demo.sh env HOME    print the environment for a Herdr client (eval it)
#   herdr-demo.sh go HOME     the cue for the stand-ins that finish once a
#                             client is attached (herdr.tape runs it just before)
#   herdr-demo.sh down HOME   stop the servers, remove the containers and HOME
#
# Everything lives in HOME, a throwaway home whose path must be short (Unix
# socket paths are limited to 104 bytes). Nothing reads this machine's ~/.ssh,
# SSH agent or Herdr config: ssh runs through a wrapper that passes -F with the
# demo's own config, key and known_hosts, and Herdr's config dir is in HOME.
set -eo pipefail

cmd="${1:-}" home="${2:-}"
[[ -n "$cmd" && -n "$home" ]] || { echo "usage: herdr-demo.sh up|env|go|down HOME" >&2; exit 2; }
tapes="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$tapes/../../.." && pwd)"
# The machines' names: devbox and workbox, or TUIDEV_DEMO_MACHINES (two
# names; remote-demo.sh picks its own).
read -r -a MACHINES <<<"${TUIDEV_DEMO_MACHINES:-devbox workbox}"
[[ ${#MACHINES[@]} -eq 2 ]] || { echo "herdr-demo: TUIDEV_DEMO_MACHINES needs two names" >&2; exit 2; }
PREFIX=tuidev-demo-

die() { echo "herdr-demo: $*" >&2; exit 1; }

# The runtime is scripts/lib/container.sh's choice: TUIDEV_CONTAINER_RUNTIME,
# else Apple `container` on macOS, then podman. This tape runs those two. On
# some Macs an Apple container VM has no outbound network, so the image build's
# apt-get times out; TUIDEV_CONTAINER_RUNTIME=podman builds the same Containerfile.
demo_runtime=""
# shellcheck source=../../../scripts/lib/container.sh disable=SC1091
. "$repo/scripts/lib/container.sh"

need_runtime() {
    local rt
    if ! rt="$(tuidev_container_runtime)"; then
        if [[ -n "${TUIDEV_CONTAINER_RUNTIME:-}" ]]; then
            die "TUIDEV_CONTAINER_RUNTIME=${TUIDEV_CONTAINER_RUNTIME} is not on PATH (container or podman)"
        fi
        die "needs Apple's container CLI (brew install container; container system start) or podman (brew install podman; on macOS, podman machine start). Set TUIDEV_CONTAINER_RUNTIME=container|podman to choose"
    fi
    case "$rt" in
        container|podman) demo_runtime="$rt" ;;
        *) die "needs Apple's container CLI or podman (TUIDEV_CONTAINER_RUNTIME=container|podman); found $rt" ;;
    esac
}

# ctr VERB ARGS — one mapping onto the chosen runtime.
#   inspect IMAGE
#   build IMAGE --build-arg ... CONTEXT
#   run NAME PORT IMAGE
#   exec NAME CMD...
#   rm NAME
# Apple `container` keeps today's flags. Podman is `build -t`,
# `run -d --name --cpus 2 -m 1g -p 127.0.0.1:PORT:22`, `exec -i`, `rm -f`,
# `image inspect`.
ctr() {
    local verb="$1"; shift
    case "$demo_runtime:$verb" in
        container:inspect) container image inspect "$@" ;;
        podman:inspect)    podman image inspect "$@" ;;
        # `--progress plain`: `-q` can hang when its output is not a terminal.
        container:build)   container build --progress plain -t "$@" ;;
        podman:build)      podman build -t "$@" ;;
        container:run)     container run -d --name "$1" -c 2 -m 1G -p "127.0.0.1:$2:22" "$3" ;;
        podman:run)        podman run -d --name "$1" --cpus 2 -m 1g -p "127.0.0.1:$2:22" "$3" ;;
        container:exec)    container exec -i "$@" ;;
        podman:exec)       podman exec -i "$@" ;;
        container:rm)      container rm -f "$@" ;;
        podman:rm)         podman rm -f "$@" ;;
        *) die "no container command for ${demo_runtime:-unset} $verb" ;;
    esac
}

# The real path (/tmp is /private/tmp on macOS), so a pane's $PWD starts with
# $HOME and prints as ~.
[[ "$cmd" != up ]] || mkdir -p "$home"
[[ ! -d "$home" ]] || home="$(cd "$home" && pwd -P)"

# The environment every demo Herdr process gets: nothing inherited from a
# Herdr pane this may run in (HERDR_ENV, HERDR_SOCKET_PATH, ...), the demo
# HOME, and the ssh wrapper first on PATH. AGENTS_MAP_ROOT keeps `agents map`
# (remote-demo.sh; a plugin's popup gets the server's environment) to what
# runs under the demo home. TZ=UTC, the containers' zone: the times the sidebar
# shows agree across machines and say nothing of where this Mac is.
demo_env() {
    printf '%s\n' "HOME=$home" "USER=dev" "LOGNAME=dev" "SHELL=/bin/bash" "TERM=${TERM:-xterm-256color}" "TZ=UTC" \
        "LANG=en_US.UTF-8" "BASH_SILENCE_DEPRECATION_WARNING=1" "AGENTS_MAP_ROOT=$home" \
        "PATH=$home/.demo/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
}
run_demo() { local e=() l; while IFS= read -r l; do e+=("$l"); done < <(demo_env); env -i "${e[@]}" "$@"; }
herdr_demo() { run_demo herdr "$@"; }

# free_port — a loopback TCP port nothing listens on. Each container publishes
# its sshd there: macOS's Local Network privacy can keep a terminal from
# reaching a container's own address, but never loopback.
free_port() {
    local p=$(( 22200 + RANDOM % 700 ))
    while nc -z 127.0.0.1 "$p" >/dev/null 2>&1; do p=$((p + 1)); done
    echo "$p"
}

up() {
    need_runtime
    command -v herdr >/dev/null 2>&1 || die "needs herdr (./install.sh --pack herdr)"
    command -v jq >/dev/null 2>&1 || die "needs jq"
    local version image port m key
    version="$(herdr --version | awk '{ print $2 }')"
    # Tagged by Herdr's version and the Containerfile, so a change rebuilds it.
    image="${PREFIX}node:$version-$(shasum -a 256 "$tapes/herdr/Containerfile" | cut -c1-8)"
    [[ ${#home} -le 40 ]] || die "HOME path too long for Herdr's sockets: $home"
    [[ ! -e "$home/.config/herdr/herdr.sock" ]] || die "a demo Herdr may already run in $home; run: herdr-demo.sh down $home"

    mkdir -p "$home/.demo"
    if ! ctr inspect "$image" >/dev/null 2>&1; then
        echo "herdr-demo: building $image with $demo_runtime (Debian, OpenSSH, Herdr $version)"
        ctr build "$image" --build-arg HERDR_VERSION="$version" "$tapes/herdr" \
            > "$home/.demo/build.log" 2>&1 \
            || { tail -20 "$home/.demo/build.log" >&2; die "$demo_runtime build failed"; }
    fi

    mkdir -p "$home/.ssh" "$home/.demo/bin" "$home/.config/herdr"
    chmod 700 "$home/.ssh"
    key="$home/.ssh/demo_ed25519"
    [[ -f "$key" ]] || ssh-keygen -q -t ed25519 -N '' -C demo -f "$key"
    : > "$home/.ssh/config"
    : > "$home/.ssh/known_hosts"

    for m in "${MACHINES[@]}"; do
        ctr rm "$PREFIX$m" >/dev/null 2>&1 || true
        port="$(free_port)"
        ctr run "$PREFIX$m" "$port" "$image" > "$home/.demo/run-$m.out" 2>&1 \
            || { cat "$home/.demo/run-$m.out" >&2; die "could not start $PREFIX$m"; }
        ctr exec "$PREFIX$m" sh -c 'cat >> ~dev/.ssh/authorized_keys && chown dev:dev ~dev/.ssh/authorized_keys && chmod 600 ~dev/.ssh/authorized_keys' < "$key.pub"
        ctr exec "$PREFIX$m" sh -c 'cat > /usr/local/bin/demo-agent && chmod 755 /usr/local/bin/demo-agent' < "$tapes/herdr/demo-agent.sh"
        cat >> "$home/.ssh/config" <<EOF
Host $PREFIX$m
  HostName 127.0.0.1
  Port $port
  User dev
  IdentityFile $key
  IdentitiesOnly yes
  IdentityAgent none
  HostKeyAlias $PREFIX$m
  UserKnownHostsFile $home/.ssh/known_hosts
  GlobalKnownHostsFile /dev/null
  StrictHostKeyChecking accept-new
  LogLevel ERROR
EOF
    done

    # ssh for every demo process: only the demo's config, never ~/.ssh's.
    cat > "$home/.demo/bin/ssh" <<EOF
#!/bin/sh
exec /usr/bin/ssh -F "$home/.ssh/config" "\$@"
EOF
    chmod 755 "$home/.demo/bin/ssh"
    # Herdr itself, wherever this machine has it (the pack puts it in
    # ~/.local/bin, which the demo's PATH leaves out with the rest of HOME).
    ln -sf "$(command -v herdr || die "needs herdr (./install.sh --pack herdr)")" "$home/.demo/bin/herdr"
    ln -sf "$tapes/herdr/demo-agent.sh" "$home/.demo/bin/demo-agent"

    # Wait for sshd, and record each host key on first contact.
    for m in "${MACHINES[@]}"; do
        local tries=0
        until run_demo ssh -o ConnectTimeout=2 "$PREFIX$m" true 2>/dev/null; do
            tries=$((tries + 1)); [[ $tries -lt 30 ]] || die "ssh to $PREFIX$m never came up"; sleep 1
        done
    done

    # The shipped Herdr config, plus demo-only settings: no onboarding, no
    # update checks or sounds, and plain ssh (through the wrapper above); with
    # the cast, the pack's keys and sidebar rows too (its managed blocks; the
    # rows last, since TOML cannot close their table). TOML: top-level keys
    # come before the first table.
    { printf 'onboarding = false\n\n'; cat "$repo/configs/herdr/config.toml"
      printf '\n[update]\nversion_check = false\nmanifest_check = false\n\n[remote]\nmanage_ssh_config = false\n\n[ui.sound]\nenabled = false\n'
      if [[ -z "${TUIDEV_DEMO_NO_POPULATE:-}" ]]; then
          echo; cat "$repo/configs/herdr/keys.toml"; echo; cat "$repo/configs/herdr/sidebar.toml"
      fi
    } > "$home/.config/herdr/config.toml"

    # Local panes: bash with the same short prompt as the containers.
    printf '%s\n' "PS1='\\[\\e[1;36m\\]\\w\\[\\e[0m\\] \\[\\e[1;32m\\]❯\\[\\e[0m\\] '" > "$home/.bashrc"
    printf '%s\n' '[ -f ~/.bashrc ] && . ~/.bashrc' > "$home/.bash_profile"

    # The Mac's server, then the two machines (each starts its own server).
    # (exec, so no shell lingers holding the caller's stdout open.)
    local e=() l
    while IFS= read -r l; do e+=("$l"); done < <(demo_env)
    (cd "$home" && exec env -i "${e[@]}" herdr server > "$home/.demo/herdr-server.out" 2>&1 < /dev/null) &
    local tries=0
    # (Not `| grep -q`: grep leaving early ends herdr with SIGPIPE, which
    # pipefail counts as a failure however the status read.)
    until [[ "$(herdr_demo status 2>/dev/null)" == *"status: running"* ]]; do
        tries=$((tries + 1)); [[ $tries -lt 30 ]] || die "the local Herdr server did not start"; sleep 0.5
    done
    for m in "${MACHINES[@]}"; do
        herdr_demo machine add "$PREFIX$m" --label "$m" < /dev/null > "$home/.demo/machine-$m.out" 2>&1 \
            || { cat "$home/.demo/machine-$m.out" >&2; die "herdr machine add $m failed"; }
    done

    # tuidev on every machine, then the workspaces: LABEL DIR (in that
    # machine's home) BRANCH, and a tab for each "KIND SCENARIO TITLE" stand-in
    # or "shell". Titles are short: an agent row in tuidev's sidebar has about
    # 24 columns for the tab's name, the machine and the time together.
    # TUIDEV_DEMO_NO_POPULATE=1 leaves the fleet empty and without
    # tuidev, for a caller with its own cast and setup (remote-demo.sh).
    if [[ -z "${TUIDEV_DEMO_NO_POPULATE:-}" ]]; then
        tuidev_here
        for m in "${MACHINES[@]}"; do tuidev_on "$m"; done
        # (review+N: it finishes N seconds after `go`, which herdr.tape runs
        # just before its client attaches, so the client shows it as done.)
        populate "" myapp myapp fix-cache \
            "claude tests Fix flaky cache test" "claude review+5 Review diff" shell
        populate "" web web signup-form "codex review Sign-up form"
        populate "${MACHINES[0]}" api api fix-404 "claude approve Fix 404 routes" shell
        populate "${MACHINES[0]}" api-docs api-docs docs "claude review+4 API docs"
        populate "${MACHINES[1]}" infra infra canary "codex deploy Canary 1.5"
        populate "${MACHINES[1]}" api-tests api-tests rate-limit "claude ratelimit Rate limit"
    fi
    # A new remote server opens with an empty "~" workspace; drop it.
    for m in "${MACHINES[@]}"; do
        herdr_demo --machine "$m" workspace list \
            | jq -r '.result.workspaces[] | select(.label == "~") | .workspace_id' \
            | while IFS= read -r ws; do herdr_demo --machine "$m" workspace close "$ws" >/dev/null 2>&1 || true; done
    done
    # Let every stand-in print and report before a client attaches.
    sleep 3
}

# on MACHINE SCRIPT — SCRIPT in a shell on MACHINE (empty: this Mac, in the
# demo's environment).
on() {
    if [[ -n "$1" ]]; then run_demo ssh "$PREFIX$1" "$2"; else run_demo bash -c "$2"; fi
}

# tuidev_here — this checkout's agents and the tuidev.link plugin for the demo
# home, as the monitoring and herdr packs install them (the keys and sidebar
# rows are in its config already). The plugin's hooks run ~/.local/bin/agents.
tuidev_here() {
    mkdir -p "$home/.local/bin"
    ln -sf "$repo/bin/agents" "$home/.local/bin/agents"
    ln -sf "$repo/bin/agents" "$home/.demo/bin/agents"
    herdr_demo plugin link "$repo/configs/herdr/plugins/tuidev-link" >/dev/null \
        || die "could not link the plugin into the demo Herdr"
    herdr_demo server reload-config >/dev/null
}

# tuidev_on MACHINE — the same on a container: this checkout's agents and
# plugin copied into ~/.local/share/tuidev, linked into its Herdr.
# shellcheck disable=SC2016  # the remote shell expands ~ and $HOME
tuidev_on() {
    (cd "$repo" && COPYFILE_DISABLE=1 tar -cf - bin/agents lib/agents configs/herdr/plugins configs/herdr/keys.toml 2>/dev/null) \
        | on "$1" 'mkdir -p ~/.local/share/tuidev ~/.local/bin ~/.config/herdr && tar -xf - -C ~/.local/share/tuidev 2>/dev/null
            ln -sf ~/.local/share/tuidev/bin/agents ~/.local/bin/agents
            herdr plugin link ~/.local/share/tuidev/configs/herdr/plugins/tuidev-link >/dev/null
            { echo; cat ~/.local/share/tuidev/configs/herdr/keys.toml; } >> ~/.config/herdr/config.toml
            herdr server reload-config >/dev/null
            grep -q "local/bin" ~/.bashrc || echo "export PATH=\$HOME/.local/bin:\$PATH" >> ~/.bashrc' \
        || die "could not set up tuidev on $1"
}

# populate MACHINE LABEL DIR BRANCH TAB... — a workspace in ~/DIR on MACHINE
# (empty: this Mac), a git repo on BRANCH with one commit, and a tab for each
# TAB: "KIND SCENARIO TITLE..." runs a stand-in, "shell" is a shell. Tabs get
# no label, so the plugin's sync names them.
populate() {
    local m="$1" label="$2" dir="$3" branch="$4" pre=() cwd out pane ws="" tab kind scenario title cmdline
    shift 4
    [[ -z "$m" ]] || pre=(--machine "$m")
    # Herdr wants an absolute directory: the home as that machine reports it.
    cwd="$(on "$m" "mkdir -p ~/$dir && cd ~/$dir && { [ -d .git ] || { git init -q -b $branch && printf '# $dir\n' > README.md && git add README.md && git -c user.name=dev -c user.email=dev@example.invalid commit -q -m 'first commit'; }; } && pwd")"
    [[ "$cwd" == /* ]] || die "no directory ~/$dir on ${m:-Local}"
    for tab in "$@"; do
        if [[ -z "$ws" ]]; then
            out="$(herdr_demo "${pre[@]}" workspace create --cwd "$cwd" --label "$label" --no-focus 2>&1)" \
                || { echo "$out" >&2; die "workspace create $label on ${m:-Local} failed"; }
            ws="$(jq -r '.result.workspace.workspace_id' <<<"$out")"
        else
            out="$(herdr_demo "${pre[@]}" tab create --workspace "$ws" --cwd "$cwd" --no-focus 2>&1)" \
                || { echo "$out" >&2; die "tab create in $label on ${m:-Local} failed"; }
        fi
        pane="$(jq -r '.result.root_pane.pane_id' <<<"$out")"
        [[ -n "$pane" && "$pane" != null ]] || die "no pane in: $out"
        [[ "$tab" != shell ]] || continue
        read -r kind scenario title <<<"$tab"
        printf -v cmdline '%q ' demo-agent "$kind" "$scenario" "$title"
        herdr_demo "${pre[@]}" pane run "$pane" "$cmdline" >/dev/null
    done
}

# go — set the go mark (~/.demo/go) on every machine: the stand-ins started
# with SCENARIO+N finish N seconds later.
go() {
    local m
    : > "$home/.demo/go"
    for m in "${MACHINES[@]}"; do run_demo ssh "$PREFIX$m" 'mkdir -p ~/.demo && : > ~/.demo/go'; done
}

down() {
    local m tmpd=/nonexistent rt=""
    # Only a directory inside the temp dirs, compared as real paths (macOS's
    # TMPDIR ends in a slash and lives under a symlink).
    [[ -z "${TMPDIR:-}" ]] || tmpd="$(cd "$TMPDIR" 2>/dev/null && pwd -P)" || tmpd=/nonexistent
    # The machines' servers end with their containers; their profiles live in HOME.
    [[ -S "$home/.config/herdr/herdr.sock" ]] && { herdr_demo server stop >/dev/null 2>&1 || true; }
    # HOME is removed below even when this tape has no runtime to stop.
    if rt="$(tuidev_container_runtime)"; then
        case "$rt" in
            container|podman)
                demo_runtime="$rt"
                for m in "${MACHINES[@]}"; do
                    ctr rm "$PREFIX$m" >/dev/null 2>&1 || true
                done
                ;;
        esac
    fi
    case "$home" in
        /tmp/?*|/private/tmp/?*|"${tmpd:-/nonexistent}"/?*) rm -rf "$home" ;;
        *) echo "herdr-demo: left $home in place (not under /tmp)" >&2 ;;
    esac
}

case "$cmd" in
    up)   up ;;
    env)  demo_env | sed "s/'/'\\\\''/g; s/^\([A-Z_]*\)=\(.*\)$/export \1='\2'/"; echo "unset HERDR_ENV HERDR_SOCKET_PATH HERDR_PANE_ID HERDR_TAB_ID HERDR_WORKSPACE_ID HERDR_BIN_PATH HERDR_SESSION" ;;
    go)   go ;;
    down) down ;;
    *)    echo "usage: herdr-demo.sh up|env|go|down HOME" >&2; exit 2 ;;
esac
