#!/bin/bash
# scripts/container.sh — runtime-agnostic entry point for the Makefile's
# container targets. Picks Apple `container` → podman → docker (see
# scripts/lib/container.sh) so `make container-test` works the same on a
# Mac with native containers, a Mac with Podman, or a Linux/CI box with Docker.
#
# Usage:
#   scripts/container.sh runtime          # print the runtime that would be used
#   scripts/container.sh up | down        # start / stop its VM or service
#   scripts/container.sh build            # build the Linux parity test image
#   scripts/container.sh test             # build + run the core-tagged tests
#   scripts/container.sh clean            # remove the test image
#
# Env: TUIDEV_CONTAINER_RUNTIME (force one), TUIDEV_TEST_IMAGE (default mactui-test)

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/container.sh disable=SC1091
. "$SCRIPT_DIR/lib/container.sh"

IMAGE="${TUIDEV_TEST_IMAGE:-mactui-test}"

need_runtime() {
    local rt
    rt="$(tuidev_container_runtime)" || {
        echo "no container runtime found. Preference order: Apple container (macOS 26+," >&2
        echo "https://github.com/apple/container/releases) → podman (brew install --cask podman) → docker" >&2
        exit 1
    }
    printf '%s\n' "$rt"
}

cmd="${1:-}"; shift || true
case "$cmd" in
    runtime)
        need_runtime ;;
    up)
        rt="$(need_runtime)"; tuidev_container_up "$rt" ;;
    down)
        rt="$(need_runtime)"; tuidev_container_down "$rt" ;;
    build)
        rt="$(need_runtime)"
        echo "→ building $IMAGE with $(tuidev_container_label "$rt")"
        tuidev_container_up "$rt"
        tuidev_container_build "$rt" "$IMAGE" "$REPO_ROOT/Dockerfile" "$REPO_ROOT" ;;
    test)
        "$0" build
        rt="$(need_runtime)"
        tuidev_container_run "$rt" "$IMAGE" "$@" ;;
    clean)
        rt="$(need_runtime)"
        tuidev_container_rmi "$rt" "$IMAGE" 2>/dev/null || true ;;
    *)
        sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
