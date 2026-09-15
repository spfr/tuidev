#!/bin/bash
# scripts/lib/container.sh — pick a container runtime, in tuidev's preference
# order, and paper over the CLI differences the repo actually uses.
#
# Order: Apple `container` (macOS 26+, native Containerization.framework,
# one lightweight VM per container) → `podman` (FOSS, rootless) → `docker`.
# Override with TUIDEV_CONTAINER_RUNTIME=container|podman|docker.
#
# Every helper takes the runtime as its first argument so callers resolve it
# once (`rt="$(tuidev_container_runtime)"`) and stay explicit. The subcommand
# shapes that differ are wrapped here; build/run are identical across all three.
#
# Sourced by: scripts/container.sh (Makefile targets), scripts/update.sh,
# scripts/install/packs/sandbox-container.sh.

# Print the first usable runtime name, or return 1 with nothing printed.
tuidev_container_runtime() {
    local rt
    if [[ -n "${TUIDEV_CONTAINER_RUNTIME:-}" ]]; then
        rt="$TUIDEV_CONTAINER_RUNTIME"
        command -v "$rt" >/dev/null 2>&1 || return 1
        printf '%s\n' "$rt"
        return 0
    fi
    for rt in container podman docker; do
        # Apple's CLI is macOS-only; anything else named `container` on Linux
        # (e.g. a shell alias or an unrelated binary) is not what we want.
        if [[ "$rt" == container && "$(uname -s)" != Darwin ]]; then
            continue
        fi
        if command -v "$rt" >/dev/null 2>&1; then
            printf '%s\n' "$rt"
            return 0
        fi
    done
    return 1
}

# Human-readable label for messages.
tuidev_container_label() {
    case "$1" in
        container) echo "Apple container (native macOS)" ;;
        podman)    echo "Podman" ;;
        docker)    echo "Docker" ;;
        *)         echo "$1" ;;
    esac
}

_tuidev_builder_cpus() {
    local n; n="$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"
    n=$(( n / 2 )); (( n < 2 )) && n=2
    echo "$n"
}

# Bring the runtime's backing service/VM up (idempotent). docker has no
# tuidev-managed daemon; we only check it answers.
tuidev_container_up() {
    local rt="$1"
    case "$rt" in
        container)
            container system status >/dev/null 2>&1 || container system start
            # Apple's builder VM defaults to 2 CPUs / 2 GB, which makes image
            # builds crawl. Give it half the host's cores (min 2) and 4 GB;
            # override with TUIDEV_BUILDER_CPUS / TUIDEV_BUILDER_MEMORY. Resize
            # later with `container builder delete` then `make sandbox-up`.
            local st
            st="$(container builder status 2>/dev/null | awk 'NR==2 {print $3}')"
            case "$st" in
                running) ;;
                "")  container builder start \
                        --cpus "${TUIDEV_BUILDER_CPUS:-$(_tuidev_builder_cpus)}" \
                        --memory "${TUIDEV_BUILDER_MEMORY:-4g}" ;;
                *)   # stopped or wedged (e.g. after an interrupted build): recreate
                     container builder delete --force >/dev/null 2>&1 || true
                     container builder start \
                        --cpus "${TUIDEV_BUILDER_CPUS:-$(_tuidev_builder_cpus)}" \
                        --memory "${TUIDEV_BUILDER_MEMORY:-4g}" ;;
            esac
            ;;
        podman)
            podman info >/dev/null 2>&1 && return 0      # rootless Linux, or machine already up
            [[ "$(uname -s)" == Darwin ]] || return 1    # native Linux has no machine to start
            podman machine start 2>/dev/null || podman machine init --now
            ;;
        docker)
            docker info >/dev/null 2>&1 || {
                echo "docker daemon not reachable — start Docker and retry" >&2
                return 1
            }
            ;;
        *) echo "unknown runtime: $rt" >&2; return 2 ;;
    esac
}

tuidev_container_down() {
    local rt="$1"
    case "$rt" in
        container) container system stop ;;
        podman)    podman machine stop ;;
        docker)    : ;;   # not ours to stop
        *) echo "unknown runtime: $rt" >&2; return 2 ;;
    esac
}

# build <rt> <tag> <file> <context>
tuidev_container_build() {
    local rt="$1" tag="$2" file="$3" ctx="$4"
    "$rt" build -t "$tag" -f "$file" "$ctx"
}

# run <rt> <image> [cmd...]  — one-shot, removed on exit
tuidev_container_run() {
    local rt="$1" image="$2"; shift 2
    "$rt" run --rm "$image" "$@"
}

# pull <rt> <image>
tuidev_container_pull() {
    local rt="$1" image="$2"
    case "$rt" in
        container) container image pull "$image" ;;
        *)         "$rt" pull "$image" ;;
    esac
}

# rmi <rt> <image>  — Apple's CLI has no top-level `rmi`
tuidev_container_rmi() {
    local rt="$1" image="$2"
    case "$rt" in
        container) container image rm "$image" ;;
        *)         "$rt" rmi "$image" ;;
    esac
}
