#!/bin/bash
# ============================================================================
# Ralph Wiggum - Autonomous AI Agent Orchestration
# ============================================================================
#
# An autonomous loop that runs AI coding agents until tasks complete.
# Inspired by Geoffrey Huntley's Ralph Wiggum technique.
#
# Usage:
#   ralph "Refactor auth module and ensure tests pass"
#   ralph --agent claude "Build a REST API for users"
#   ralph --agent opencode --max-iterations 10 "Fix all lint errors"
#   ralph --file tasks.md
#
# Supported agents: claude, opencode
#
# ============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Defaults
AGENT="claude"
MAX_ITERATIONS=20
ITERATION=0
PROMPT=""
PROMPT_FILE=""
COMPLETION_MARKER="RALPH_COMPLETE"
LOG_FILE=""
VERBOSE=false
DRY_RUN=false

# ============================================================================
# Helper Functions
# ============================================================================

print_banner() {
    echo -e "${PURPLE}"
    echo '  ____       _       _     '
    echo ' |  _ \ __ _| |_ __ | |__  '
    echo ' | |_) / _` | | `_ \| `_ \ '
    echo ' |  _ < (_| | | |_) | | | |'
    echo ' |_| \_\__,_|_| .__/|_| |_|'
    echo '              |_|          '
    echo -e "${NC}"
    echo -e "${CYAN}Autonomous AI Agent Orchestration${NC}"
    echo ""
}

print_status() {
    echo -e "${BLUE}[ralph]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[ralph]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[ralph]${NC} $1"
}

print_error() {
    echo -e "${RED}[ralph]${NC} $1"
}

show_help() {
    cat << 'EOF'
Ralph Wiggum - Autonomous AI Agent Orchestration

USAGE:
    ralph [OPTIONS] "prompt"
    ralph [OPTIONS] --file tasks.md

OPTIONS:
    -a, --agent <name>       AI agent to use: claude, opencode (default: claude)
    -m, --max-iterations <n> Maximum iterations before stopping (default: 20)
    -f, --file <path>        Read prompt from file instead of argument
    -l, --log <path>         Log output to file
    -v, --verbose            Show detailed output
    -d, --dry-run            Show what would run without executing
    -h, --help               Show this help message

EXAMPLES:
    # Simple task with Claude
    ralph "Fix all TypeScript errors in src/"

    # Use OpenCode with iteration limit
    ralph --agent opencode --max-iterations 10 "Refactor database layer"

    # Read complex tasks from file
    ralph --file PRD.md --max-iterations 30

    # Verbose mode with logging
    ralph -v -l ralph.log "Build REST API endpoints"

COMPLETION:
    Ralph runs until:
    1. The agent outputs "RALPH_COMPLETE" (or your custom marker)
    2. Maximum iterations reached
    3. Agent exits successfully with no pending tasks
    4. User interrupts with Ctrl+C

AGENTS:
    claude    - Anthropic's Claude Code CLI (default)
    opencode  - Open-source alternative, supports multiple models

TIPS:
    - Start with lower --max-iterations for new tasks
    - Use --dry-run to preview the command
    - Check logs with --log for debugging
    - Set API keys in environment or ~/.config/mcp-env

EOF
}

check_agent() {
    case "$AGENT" in
        claude)
            if ! command -v claude &>/dev/null; then
                print_error "Claude Code not found. Install: npm install -g @anthropic-ai/claude-code"
                exit 1
            fi
            ;;
        opencode)
            if ! command -v opencode &>/dev/null; then
                print_error "OpenCode not found. Install: curl -fsSL https://opencode.ai/install | bash"
                exit 1
            fi
            ;;
        *)
            print_error "Unknown agent: $AGENT"
            print_error "Supported: claude, opencode"
            exit 1
            ;;
    esac
}

build_prompt() {
    local base_prompt="$1"

    # Add Ralph completion instruction
    cat << EOF
$base_prompt

IMPORTANT: When you have completed ALL tasks and verified they work:
1. Output the exact text: $COMPLETION_MARKER
2. This signals that the autonomous loop can stop

If tasks remain incomplete or you encounter blocking issues, describe what's left to do.
Do NOT output $COMPLETION_MARKER until everything is truly complete and verified.
EOF
}

run_agent() {
    local full_prompt
    full_prompt=$(build_prompt "$PROMPT")

    case "$AGENT" in
        claude)
            if [[ "$DRY_RUN" == true ]]; then
                echo "claude --print \"$full_prompt\""
            else
                claude --print "$full_prompt" 2>&1
            fi
            ;;
        opencode)
            if [[ "$DRY_RUN" == true ]]; then
                echo "opencode \"$full_prompt\""
            else
                echo "$full_prompt" | opencode 2>&1
            fi
            ;;
    esac
}

check_completion() {
    local output="$1"
    if echo "$output" | grep -q "$COMPLETION_MARKER"; then
        return 0
    fi
    return 1
}

# ============================================================================
# Parse Arguments
# ============================================================================

while [[ $# -gt 0 ]]; do
    case $1 in
        -a|--agent)
            AGENT="$2"
            shift 2
            ;;
        -m|--max-iterations)
            MAX_ITERATIONS="$2"
            shift 2
            ;;
        -f|--file)
            PROMPT_FILE="$2"
            shift 2
            ;;
        -l|--log)
            LOG_FILE="$2"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        -*)
            print_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
        *)
            PROMPT="$1"
            shift
            ;;
    esac
done

# ============================================================================
# Main
# ============================================================================

print_banner

# Load prompt from file if specified
if [[ -n "$PROMPT_FILE" ]]; then
    if [[ ! -f "$PROMPT_FILE" ]]; then
        print_error "Prompt file not found: $PROMPT_FILE"
        exit 1
    fi
    PROMPT=$(cat "$PROMPT_FILE")
    print_status "Loaded prompt from: $PROMPT_FILE"
fi

# Validate prompt
if [[ -z "$PROMPT" ]]; then
    print_error "No prompt provided"
    echo "Usage: ralph \"your task description\""
    echo "       ralph --file tasks.md"
    exit 1
fi

# Check agent is available
check_agent

# Show configuration
print_status "Agent: $AGENT"
print_status "Max iterations: $MAX_ITERATIONS"
[[ -n "$LOG_FILE" ]] && print_status "Logging to: $LOG_FILE"
[[ "$VERBOSE" == true ]] && print_status "Verbose mode enabled"
[[ "$DRY_RUN" == true ]] && print_warning "Dry-run mode - no commands will execute"
echo ""

# Dry run - just show what would happen
if [[ "$DRY_RUN" == true ]]; then
    print_status "Would execute:"
    run_agent
    exit 0
fi

# Initialize log file
if [[ -n "$LOG_FILE" ]]; then
    echo "Ralph session started: $(date)" > "$LOG_FILE"
    echo "Agent: $AGENT" >> "$LOG_FILE"
    echo "Prompt: $PROMPT" >> "$LOG_FILE"
    echo "---" >> "$LOG_FILE"
fi

# Main loop
print_status "Starting autonomous loop..."
echo ""

while [[ $ITERATION -lt $MAX_ITERATIONS ]]; do
    ITERATION=$((ITERATION + 1))

    echo -e "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    print_status "Iteration $ITERATION/$MAX_ITERATIONS"
    echo -e "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    # Run agent and capture output
    OUTPUT=$(run_agent)
    EXIT_CODE=$?

    # Log output
    if [[ -n "$LOG_FILE" ]]; then
        echo "=== Iteration $ITERATION ===" >> "$LOG_FILE"
        echo "$OUTPUT" >> "$LOG_FILE"
        echo "" >> "$LOG_FILE"
    fi

    # Show output
    if [[ "$VERBOSE" == true ]]; then
        echo "$OUTPUT"
    else
        # Show truncated output
        echo "$OUTPUT" | tail -50
    fi

    echo ""

    # Check for completion
    if check_completion "$OUTPUT"; then
        print_success "Task completed! ($COMPLETION_MARKER found)"
        print_success "Total iterations: $ITERATION"

        if [[ -n "$LOG_FILE" ]]; then
            echo "---" >> "$LOG_FILE"
            echo "Completed at iteration $ITERATION" >> "$LOG_FILE"
        fi

        exit 0
    fi

    # Check for agent errors
    if [[ $EXIT_CODE -ne 0 ]]; then
        print_warning "Agent exited with code $EXIT_CODE"
        print_status "Continuing to next iteration..."
    fi

    # Brief pause between iterations
    sleep 2
done

# Max iterations reached
print_warning "Maximum iterations ($MAX_ITERATIONS) reached"
print_warning "Task may not be complete - review output and run again if needed"

if [[ -n "$LOG_FILE" ]]; then
    echo "---" >> "$LOG_FILE"
    echo "Stopped at max iterations: $MAX_ITERATIONS" >> "$LOG_FILE"
fi

exit 1
