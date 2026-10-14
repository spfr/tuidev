# shellcheck shell=bash
# lib/agents/config.sh — every setting, and the patterns behind them.
#
# Owns: the AGENTS_* settings (agents.conf, the environment, the defaults),
#   the patterns that say what an agent, a stale helper, a supervisor, a
#   critical process and each job type look like, the run and data
#   directories, and this process's own pid and uid.
# The only module that does work when sourced: it reads agents.conf and
#   checks what the environment set (bin/agents sources it first).
# Uses: nothing.
# Public: agents_conf_load, agents_config, _agents_is_root; the settings, and
#   AGENTS_ORPHAN_PATTERNS (extend it here; it is not a setting).

# Precedence: environment, then the config file, then the defaults below. The
# file (configs/agents/agents.conf documents every key) is read line by line as
# KEY=value, never sourced: only the keys below are accepted, each value must
# match its shape, and anything else is reported and ignored.
AGENTS_CONF="${AGENTS_CONF:-${XDG_CONFIG_HOME:-$HOME/.config}/agents.conf}"
_AGENTS_CONF_KEYS="AGENTS_HOG_PCT AGENTS_HOG_MIN AGENTS_HOG_NOW AGENTS_HOG_TOP AGENTS_GRACE"
_AGENTS_CONF_KEYS+=" AGENTS_AWAKE_POLL AGENTS_NAMES AGENTS_NO_HERDR AGENTS_TERMINAL AGENTS_BAR_TITLE"
_AGENTS_CONF_KEYS+=" AGENTS_BAR_SECTIONS AGENTS_BAR_ICON AGENTS_BAR_TOP AGENTS_BAR_REFRESH"
_AGENTS_CONF_KEYS+=" AGENTS_TOOL_LONG AGENTS_LS_TOOLS AGENTS_WAIT_STUCK"
_AGENTS_CONF_KEYS+=" AGENTS_LID AGENTS_LID_MAX AGENTS_LID_MIN_BATTERY"
_AGENTS_CONF_KEYS+=" AGENTS_HISTORY AGENTS_HISTORY_DAYS AGENTS_AUTO_REAP"
_AGENTS_CONF_KEYS+=" AGENTS_HOOK_REAP AGENTS_HOOK_LOG"
_AGENTS_CONF_KEYS+=" AGENTS_JOB_TEST AGENTS_JOB_BUILD AGENTS_JOB_SERVER AGENTS_JOB_BROWSER AGENTS_JOB_MCP"
_AGENTS_BAR_TOKENS="count cpu mem load battery thermal awake warn"
_AGENTS_BAR_SECTION_NAMES="needs agents jobs stale hogs awake system"

# _agents_ere_ok VALUE — empty, or a printable extended regex that compiles in
# the awk that will use it, read the same way (ENVIRON, LC_ALL=C). Some awks
# only warn on stderr and exit 0 (an unknown class such as [[:<:]]), so any
# output fails it too.
_agents_ere_ok() {
    local re="$1" err
    [[ -n "$re" ]] || return 0
    [[ "$re" =~ ^[[:print:]]+$ ]] || return 1
    # Both must accept it: regcomp (status 2 = bad pattern) catches what
    # BusyBox awk lets through; awk catches what only it rejects. Newer bash
    # also says why on stderr: the caller's own message is enough.
    local rc
    { [[ "" =~ $re ]]; rc=$?; } 2>/dev/null
    [[ $rc -ne 2 ]] || return 1
    err="$(_AGENTS_ERE="$re" LC_ALL=C awk 'BEGIN { if ("" ~ ENVIRON["_AGENTS_ERE"]) n++ }' 2>&1 </dev/null)" || return 1
    [[ -z "$err" ]]
}

# _agents_conf_valid KEY VALUE — does VALUE have the shape KEY needs?
_agents_conf_valid() {
    local w allowed=""
    case "$1" in
        AGENTS_HOG_PCT|AGENTS_HOG_MIN|AGENTS_HOG_NOW|AGENTS_HOG_TOP|AGENTS_GRACE|AGENTS_AWAKE_POLL|AGENTS_BAR_TOP|AGENTS_TOOL_LONG|AGENTS_LS_TOOLS|AGENTS_WAIT_STUCK)
            [[ "$2" =~ ^[0-9]+$ ]] ;;
        AGENTS_NAMES)       [[ "$2" =~ ^[A-Za-z0-9._\ -]+$ ]] ;;
        AGENTS_NO_HERDR)    [[ "$2" =~ ^[01]?$ ]] ;;
        AGENTS_TERMINAL)    [[ "$2" =~ ^(auto|ghostty|iterm|terminal|wezterm|kitty)$ ]] ;;
        AGENTS_LID|AGENTS_HISTORY|AGENTS_AUTO_REAP) [[ "$2" =~ ^[01]?$ ]] ;;
        AGENTS_HISTORY_DAYS) [[ "$2" =~ ^[1-9][0-9]{0,3}$ ]] ;;
        AGENTS_HOOK_REAP|AGENTS_HOOK_LOG) [[ "$2" =~ ^[01]?$ ]] ;;
        AGENTS_JOB_TEST|AGENTS_JOB_BUILD|AGENTS_JOB_SERVER|AGENTS_JOB_BROWSER|AGENTS_JOB_MCP) _agents_ere_ok "$2" ;;
        AGENTS_LID_MAX)     [[ "$2" =~ ^([0-9]+[smhd])+$ ]] ;;
        AGENTS_LID_MIN_BATTERY) [[ "$2" =~ ^([0-9]|[1-9][0-9]|100)$ ]] ;;
        AGENTS_BAR_ICON)    [[ "$2" =~ ^[a-z0-9.]+$ ]] ;;
        AGENTS_BAR_REFRESH) [[ "$2" =~ ^[1-9][0-9]*[smhd]$ ]] ;;
        AGENTS_BAR_TITLE)    allowed="$_AGENTS_BAR_TOKENS" ;;
        AGENTS_BAR_SECTIONS) allowed="$_AGENTS_BAR_SECTION_NAMES" ;;
        *) return 1 ;;
    esac || return 1
    [[ -n "$allowed" ]] || return 0
    for w in $2; do
        case " $allowed " in *" $w "*) ;; *) return 1 ;; esac
    done
}

# agents_conf_load FILE — set each valid KEY=value the environment hasn't.
agents_conf_load() {
    local file="$1" line key val n=0
    [[ -r "$file" ]] || return 0
    while IFS= read -r line || [[ -n "$line" ]]; do
        n=$((n + 1))
        line="${line#"${line%%[![:space:]]*}"}"
        [[ -z "$line" || "$line" == \#* ]] && continue
        if [[ ! "$line" =~ ^([A-Z_]+)=(.*)$ ]]; then
            echo "agents: $file:$n: not KEY=value, ignored" >&2; continue
        fi
        key="${BASH_REMATCH[1]}"; val="${BASH_REMATCH[2]}"
        case "$val" in
            \"*\") val="${val#\"}"; val="${val%\"}" ;;
            \'*\') val="${val#\'}"; val="${val%\'}" ;;
            *)     val="${val%%[[:space:]]#*}"; val="${val%"${val##*[![:space:]]}"}" ;;
        esac
        case " $_AGENTS_CONF_KEYS " in
            *" $key "*) ;;
            *) echo "agents: $file:$n: unknown key $key, ignored" >&2; continue ;;
        esac
        if ! _agents_conf_valid "$key" "$val"; then
            echo "agents: $file:$n: bad value for $key ('$val'), ignored" >&2; continue
        fi
        [[ -n "${!key+set}" ]] && continue      # the environment wins
        printf -v "$key" '%s' "$val"
    done < "$file"
}
agents_conf_load "$AGENTS_CONF"

AGENTS_HOG_PCT="${AGENTS_HOG_PCT:-50}"   # lifetime-average CPU% that makes a hog…
AGENTS_HOG_MIN="${AGENTS_HOG_MIN:-30}"   # …once it has run this many minutes
AGENTS_HOG_NOW="${AGENTS_HOG_NOW:-90}"   # current CPU% hog (outside agent trees)
AGENTS_HOG_TOP="${AGENTS_HOG_TOP:-5}"    # hogs listed
AGENTS_TOOL_LONG="${AGENTS_TOOL_LONG:-20}"  # minutes before a tool command counts as long-running
AGENTS_LS_TOOLS="${AGENTS_LS_TOOLS:-5}"    # tool commands listed per session in ls
AGENTS_WAIT_STUCK="${AGENTS_WAIT_STUCK:-60}"  # minutes before a polling loop counts as stuck (0: never)
AGENTS_GRACE="${AGENTS_GRACE:-3}"        # seconds between SIGTERM and SIGKILL
AGENTS_AWAKE_POLL="${AGENTS_AWAKE_POLL:-60}"  # `awake agents` re-check, seconds
# `awake lid` (macOS, asks for an admin password): the longest it may run, the
# battery % below which its guard restores lid sleep, and whether the menu
# offers it (by default it does; the command works either way).
AGENTS_LID="${AGENTS_LID:-1}"
AGENTS_LID_MAX="${AGENTS_LID_MAX:-8h}"
AGENTS_LID_MIN_BATTERY="${AGENTS_LID_MIN_BATTERY:-20}"
# A value from the environment skips the file's checks: for these keys a bad
# one would break arithmetic, so it falls back to the default with a warning.
_agents_env_check() {   # KEY DEFAULT
    _agents_conf_valid "$1" "${!1}" && return 0
    echo "agents: bad $1 ('${!1}') in the environment; using $2" >&2
    printf -v "$1" '%s' "$2"
}
_agents_env_check AGENTS_WAIT_STUCK 60
_agents_env_check AGENTS_LID 1
_agents_env_check AGENTS_LID_MAX 8h
_agents_env_check AGENTS_LID_MIN_BATTERY 20
# Local history (never leaves the machine): 1 keeps it, 0 records nothing. Kept
# this many days. Auto-reap (opt-in) cleans up only what is safe to clean up.
AGENTS_HISTORY="${AGENTS_HISTORY:-1}"
AGENTS_HISTORY_DAYS="${AGENTS_HISTORY_DAYS:-30}"
AGENTS_AUTO_REAP="${AGENTS_AUTO_REAP:-0}"
_agents_env_check AGENTS_HISTORY 1
_agents_env_check AGENTS_HISTORY_DAYS 30
_agents_env_check AGENTS_AUTO_REAP 0
# Job types: where an agent tree's CPU goes. Each process in an agent tree (or
# a stale one) gets one job: agent (the CLIs themselves), browser (headless
# Chrome and friends, whatever started them), wait (a polling loop and what it
# runs), else the job of the nearest tool command above it (a `go test` and
# the test binaries it compiles), else its own match below (test, build,
# server, mcp, in that order), else other. A tool command is matched as the
# command it runs (agents_classify's tool_cmd), anything else by its argv. The
# defaults are EREs; AGENTS_JOB_<JOB> in agents.conf appends one (with |).
_AGENTS_JOB_TEST_RE='(^|[ /])(go test|gotestsum|cargo (test|nextest)|pytest|py[.]test|jest|vitest|mocha|ava|karma|rspec|phpunit|ctest|bats|tox|nox|playwright test|(swift|deno|bun|dotnet|mix|zig) test|(npm|pnpm|yarn) (run )?test(:[^ ]*)?|(mvn|gradle|gradlew)( [^ ]+)* test|make( -[^ ]+)* (test|check))( |$)|[.]test( |$)| -test[.]|(^|[ /])test_[^ /]*[.](sh|py)( |$)'
_AGENTS_JOB_BUILD_RE='(^|[ /])(go (build|install|vet|generate)|cargo (build|check|clippy|doc)|rustc|tsc|webpack|esbuild|rollup|swc|babel|turbo( run)? build|nx (build|run-many)|(vite|next|nuxt|astro|remix|svelte-kit|react-scripts|ng|gatsby|hugo) build|(npm|pnpm|yarn|bun) (run )?(build|compile|typecheck|lint)(:[^ ]*)?|gmake|cmake|ninja|bazel|bazelisk|buck2?|gradle|gradlew|mvn|xcodebuild|(swift|dotnet|zig) build|swiftc|clang|clang[+][+]|gcc|g[+][+]|cc1|cc1plus|ld|docker build|podman build|eslint|ruff|mypy|pyright|golangci-lint|shellcheck|biome)( |$)|(^|[ /])make( -[^ ]+)*( (all|build|install|lint|fmt|compile|dist|release|generate|vet|ci))+( |$)|(^|[ /])make( -[^ ]+)*$'
_AGENTS_JOB_SERVER_RE='(^|[ /])((npm|pnpm|yarn|bun) (run )?(dev|start|serve|preview|watch)(:[^ ]*)?|(next|nuxt|astro|remix|vite|svelte-kit|react-scripts|ng|expo|gatsby|hugo|jekyll|mkdocs|wrangler|vercel|netlify) (dev|serve|start|preview|server)|vite|webpack-dev-server|nodemon|tsx watch|uvicorn|gunicorn|hypercorn|flask run|manage[.]py runserver|rails (s|server)|puma|php -S|http-server|live-server|browser-sync|python[0-9.]* -m http[.]server|air|(docker|podman)[ -]compose( [^ ]+)* up|make( -[^ ]+)* (serve|server|dev|run|start|up|watch))( |$)|/server[.][cm]?js( |$)'
_AGENTS_JOB_BROWSER_RE='(^|/)(chrome-headless-shell|headless_shell|chromium|chromium-browser|chrome)( |$)|--headless|Chrome for Testing|Chromium[.]app|ms-playwright/|--remote-debugging-(pipe|port)|puppeteer'
# MCP: what agents_classify already calls an MCP server (npm exec, npx, the npx
# cache, "mcp" in the argv); never a tool command (`npx prettier` is not one).
_AGENTS_JOB_MCP_RE='(^|/)npm exec( |$)|(^|/)npx( |$)|/_npx/|mcp'
_agents_env_check AGENTS_JOB_TEST ""
_agents_env_check AGENTS_JOB_BUILD ""
_agents_env_check AGENTS_JOB_SERVER ""
_agents_env_check AGENTS_JOB_BROWSER ""
_agents_env_check AGENTS_JOB_MCP ""
# _agents_job_env — export the patterns the awk programs read (default|yours).
_agents_job_env() {
    export AGENTS_JRE_TEST="$_AGENTS_JOB_TEST_RE${AGENTS_JOB_TEST:+|$AGENTS_JOB_TEST}"
    export AGENTS_JRE_BUILD="$_AGENTS_JOB_BUILD_RE${AGENTS_JOB_BUILD:+|$AGENTS_JOB_BUILD}"
    export AGENTS_JRE_SERVER="$_AGENTS_JOB_SERVER_RE${AGENTS_JOB_SERVER:+|$AGENTS_JOB_SERVER}"
    export AGENTS_JRE_BROWSER="$_AGENTS_JOB_BROWSER_RE${AGENTS_JOB_BROWSER:+|$AGENTS_JOB_BROWSER}"
    export AGENTS_JRE_MCP="$_AGENTS_JOB_MCP_RE${AGENTS_JOB_MCP:+|$AGENTS_JOB_MCP}"
}
_agents_job_env
AGENTS_NAMES="${AGENTS_NAMES:-claude codex}"  # argv[0] basenames that are agents
AGENTS_TERMINAL="${AGENTS_TERMINAL:-auto}"    # where open-term opens windows
# Menu bar (SwiftBar plugin): what the title shows, which sections the menu
# has (in this order), its icon, how many top CPU processes the System
# section lists, and the refresh interval the pack names the plugin file with.
AGENTS_BAR_TITLE="${AGENTS_BAR_TITLE-count awake}"
AGENTS_BAR_SECTIONS="${AGENTS_BAR_SECTIONS-needs agents jobs stale hogs awake system}"
AGENTS_BAR_ICON="${AGENTS_BAR_ICON:-terminal}"
AGENTS_BAR_TOP="${AGENTS_BAR_TOP:-3}"
AGENTS_BAR_REFRESH="${AGENTS_BAR_REFRESH:-10s}"
AGENTS_RUN_DIR="${AGENTS_RUN_DIR:-${TUIDEV_STATE_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/tuidev}/run}"
# History: data, not config, so under XDG_STATE_HOME.
AGENTS_DATA_DIR="${AGENTS_DATA_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/tuidev/agents}"

# A process reparented to launchd/init (ppid 1), owned by you, whose argv
# matches one of these EREs is an orphaned agent helper. Add your own here.
# shellcheck disable=SC2034  # read by agents_classify (classify.sh)
AGENTS_ORPHAN_PATTERNS=(
    '(^|/)npm exec( |$)'             # npm exec PKG, how MCP configs start servers
    '(^|/)npx( |$)'
    '/_npx/'                         # anything run from the npx cache
    'chrome-devtools-mcp'
    '(^|/)mcp-server'
    '(^|/)caffeinate( |$)'           # Claude Code's rolling `caffeinate -i -t 300`
    '^([^ ]*/)?(node|bun|deno|uv|uvx|python[0-9.]*) .*mcp'
)
# The Codex app-server daemon: long-lived by design, never stale.
AGENTS_DAEMON_PATTERN='(^|/)codex app-server( |$)'
export AGENTS_DAEMON_PATTERN
# A listener whose binary lives here is an app, a system service or a packaged
# daemon (a `podman machine`'s gvproxy), not a dev server.
# shellcheck disable=SC2034  # read by agents_classify (classify.sh)
AGENTS_SYSTEM_PATTERN='^/(Applications|System|Library|usr/(libexec|sbin|bin))/|\.app/Contents/|^/(opt/homebrew|usr/local|home/linuxbrew/\.linuxbrew)/Cellar/|/libexec/'

# Never stale and never signalled, whatever runs under them: a process whose
# tree holds an agent, an interactive or login shell, or a session supervisor.
AGENTS_SUPERVISOR_NAMES="tmux screen SCREEN zellij herdr pm2 abduco dtach"
AGENTS_SHELL_NAMES="zsh bash fish sh dash ksh tcsh nu"
export AGENTS_SUPERVISOR_NAMES AGENTS_SHELL_NAMES   # read by the awk programs
# Never signalled (kill and term refuse them): the session's own processes and
# your terminal. /System/Applications (Messages, Mail…) stays allowed.
AGENTS_CRITICAL_NAMES="loginwindow Finder Dock WindowServer SystemUIServer ControlCenter launchd Ghostty ghostty Terminal iTerm2 WezTerm wezterm-gui kitty Alacritty alacritty"
AGENTS_CRITICAL_PATH='^/(System/Library|System/Volumes|usr/libexec|usr/sbin|sbin)/'
export AGENTS_CRITICAL_NAMES AGENTS_CRITICAL_PATH   # read by the awk programs

# This process and your uid. Overridable only by the test harness.
if [[ -n "${AGENTS_TESTING:-}" ]]; then
    AGENTS_SELF="${AGENTS_SELF:-$$}" AGENTS_UID="${AGENTS_UID:-$UID}"
else
    AGENTS_SELF=$$ AGENTS_UID="$UID"
fi

# _agents_is_root — true when running as root (the test harness may say so
# with AGENTS_EUID).
_agents_is_root() {
    local euid="$EUID"
    [[ -z "${AGENTS_TESTING:-}" ]] || euid="${AGENTS_EUID:-$EUID}"
    [[ "$euid" -eq 0 ]]
}

# 1 (the default) lets the hooks stop what they find; 0 turns them off.
AGENTS_HOOK_REAP="${AGENTS_HOOK_REAP:-1}"
_agents_env_check AGENTS_HOOK_REAP 1
# 1 logs each hook run (no command lines) to $AGENTS_DATA_DIR/hooks.log, to
# check on your machine when the hooks fire; off by default.
AGENTS_HOOK_LOG="${AGENTS_HOOK_LOG:-0}"
_agents_env_check AGENTS_HOOK_LOG 0
# agents_main resets AGENTS_DRY_RUN, so the hook reads the caller's value here.
_AGENTS_HOOK_DRY="${AGENTS_DRY_RUN:-false}"

# agents_config [--edit] — the effective settings and where they came from;
# --edit opens the file in your text editor.
agents_config() {
    local key
    if [[ "${1:-}" == --edit ]]; then
        [[ -r "$AGENTS_CONF" ]] || { echo "agents: $AGENTS_CONF does not exist" >&2; return 1; }
        open -t "$AGENTS_CONF"
        return
    fi
    if [[ -r "$AGENTS_CONF" ]]; then echo "# $AGENTS_CONF"; else echo "# $AGENTS_CONF (absent: defaults)"; fi
    for key in $_AGENTS_CONF_KEYS; do
        printf '%s=%s\n' "$key" "${!key-}"
    done
}
