#!/bin/bash
# The Herdr screenshot's fleet (docs/assets/tapes/README.md): a Herdr server on
# this Mac and two Linux machines, devbox and workbox, each a container running
# sshd and Herdr, saved in the Mac's Herdr as SSH machines. The runtime is Apple
# `container` or podman (TUIDEV_CONTAINER_RUNTIME; detection is
# scripts/lib/container.sh). Each machine runs a few scripted agent stand-ins
# (herdr/demo-agent.sh) that report their state through Herdr's hook API.
#
#   herdr-demo.sh up HOME     build the image if needed, start everything
#   herdr-demo.sh env HOME    print the environment for a Herdr client (eval it)
#   herdr-demo.sh down HOME   stop the servers, remove the containers and HOME
#
# Everything lives in HOME, a throwaway home whose path must be short (Unix
# socket paths are limited to 104 bytes). Nothing reads this machine's ~/.ssh,
# SSH agent or Herdr config: ssh runs through a wrapper that passes -F with the
# demo's own config, key and known_hosts, and Herdr's config dir is in HOME.
set -eo pipefail

cmd="${1:-}" home="${2:-}"
[[ -n "$cmd" && -n "$home" ]] || { echo "usage: herdr-demo.sh up|env|down HOME" >&2; exit 2; }
tapes="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$tapes/../../.." && pwd)"
MACHINES=(devbox workbox)
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
# HOME, and the ssh wrapper first on PATH.
demo_env() {
    printf '%s\n' "HOME=$home" "USER=dev" "LOGNAME=dev" "SHELL=/bin/bash" "TERM=${TERM:-xterm-256color}" \
        "LANG=en_US.UTF-8" "BASH_SILENCE_DEPRECATION_WARNING=1" \
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

    mkdir -p "$home/.ssh" "$home/.demo/bin" "$home/.config/herdr" "$home/myapp" "$home/web"
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
    ln -sf "$tapes/herdr/demo-agent.sh" "$home/.demo/bin/demo-agent"

    # Wait for sshd, and record each host key on first contact.
    for m in "${MACHINES[@]}"; do
        local tries=0
        until run_demo ssh -o ConnectTimeout=2 "$PREFIX$m" true 2>/dev/null; do
            tries=$((tries + 1)); [[ $tries -lt 30 ]] || die "ssh to $PREFIX$m never came up"; sleep 1
        done
    done

    # The shipped Herdr config, plus demo-only settings: no onboarding, no
    # update checks or sounds, and plain ssh (through the wrapper above).
    # TOML: top-level keys come before the first table.
    { printf 'onboarding = false\n\n'; cat "$repo/configs/herdr/config.toml"
      printf '\n[update]\nversion_check = false\nmanifest_check = false\n\n[remote]\nmanage_ssh_config = false\n\n[ui.sound]\nenabled = false\n'
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
    until herdr_demo status 2>/dev/null | grep -q 'status: running'; do
        tries=$((tries + 1)); [[ $tries -lt 30 ]] || die "the local Herdr server did not start"; sleep 0.5
    done
    for m in "${MACHINES[@]}"; do
        herdr_demo machine add "$PREFIX$m" --label "$m" < /dev/null > "$home/.demo/machine-$m.out" 2>&1 \
            || { cat "$home/.demo/machine-$m.out" >&2; die "herdr machine add $m failed"; }
    done

    # Workspaces and stand-ins: LABEL DIR (in that machine's home) KIND SCENARIO.
    populate "" myapp myapp claude tests
    populate "" web web codex review
    populate devbox api api claude approve
    populate devbox api-docs api claude review
    populate workbox infra infra codex deploy
    populate workbox api-tests api claude tests
    # A new remote server opens with an empty "~" workspace; drop it.
    for m in "${MACHINES[@]}"; do
        herdr_demo --machine "$m" workspace list \
            | jq -r '.result.workspaces[] | select(.label == "~") | .workspace_id' \
            | while IFS= read -r ws; do herdr_demo --machine "$m" workspace close "$ws" >/dev/null 2>&1 || true; done
    done
    # Let every stand-in print and report before a client attaches.
    sleep 3
}

# populate MACHINE LABEL DIR KIND SCENARIO — a workspace in ~/DIR on MACHINE
# (empty: this Mac) running one stand-in.
populate() {
    local m="$1" label="$2" cwd="$home/$3" kind="$4" scenario="$5" pre=() out pane
    if [[ -n "$m" ]]; then
        pre=(--machine "$m")
        # Herdr wants an absolute directory: the remote home, as ssh reports it.
        cwd="$(run_demo ssh "$PREFIX$m" "mkdir -p ~/$3 && cd ~/$3 && pwd")"
        [[ "$cwd" == /* ]] || die "no directory ~/$3 on $m"
    fi
    out="$(herdr_demo "${pre[@]}" workspace create --cwd "$cwd" --label "$label" --no-focus 2>&1)" \
        || { echo "$out" >&2; die "workspace create $label on ${m:-Local} failed"; }
    pane="$(jq -r '.result.root_pane.pane_id' <<<"$out")"
    [[ -n "$pane" && "$pane" != null ]] || die "no pane in: $out"
    herdr_demo "${pre[@]}" pane run "$pane" "demo-agent $kind $scenario" >/dev/null
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
    down) down ;;
    *)    echo "usage: herdr-demo.sh up|env|down HOME" >&2; exit 2 ;;
esac
