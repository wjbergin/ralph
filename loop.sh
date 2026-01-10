#!/bin/bash
# loop.sh - Autonomous AI agent loop using Claude Code
# Usage: ./loop.sh [options] [max_iterations]
#
# Options:
#   --sandbox         Use Claude Code's native sandbox (recommended)
#   --docker          Use Docker Desktop sandbox
#   --podman          Use rootless Podman container
#   --dangerous       Use --dangerously-skip-permissions (no sandbox)
#   --interactive     Require approval for each action (safest)
#
# Examples:
#   ./loop.sh --sandbox 10       # Native sandbox, 10 iterations
#   ./loop.sh --docker           # Docker sandbox, default iterations
#   ./loop.sh --dangerous 5      # No sandbox (not recommended)

set -e

# Parse options
SANDBOX_MODE="sandbox" # Default to native sandbox
MAX_ITERATIONS=10

while [[ $# -gt 0 ]]; do
  case $1 in
  --sandbox)
    SANDBOX_MODE="sandbox"
    shift
    ;;
  --docker)
    SANDBOX_MODE="docker"
    shift
    ;;
  --podman)
    SANDBOX_MODE="podman"
    shift
    ;;
  --dangerous)
    SANDBOX_MODE="dangerous"
    shift
    ;;
  --interactive)
    SANDBOX_MODE="interactive"
    shift
    ;;
  *)
    if [[ $1 =~ ^[0-9]+$ ]]; then
      MAX_ITERATIONS=$1
    fi
    shift
    ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PRD_FILE="$SCRIPT_DIR/prd.json"
PROGRESS_FILE="$SCRIPT_DIR/progress.txt"
PROMPT_FILE="$SCRIPT_DIR/prompt.md"
ARCHIVE_DIR="$SCRIPT_DIR/archive"
LAST_BRANCH_FILE="$SCRIPT_DIR/.last-branch"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check prerequisites
check_prerequisites() {
  # Check for jq
  if ! command -v jq &>/dev/null; then
    log_error "jq not found. Install with: brew install jq (macOS) or apt install jq (Linux)"
    exit 1
  fi

  # Check for required files
  if [ ! -f "$PRD_FILE" ]; then
    log_error "prd.json not found at $PRD_FILE"
    log_info "Create one using prd.json.example as a template"
    exit 1
  fi

  if [ ! -f "$PROMPT_FILE" ]; then
    log_error "prompt.md not found at $PROMPT_FILE"
    exit 1
  fi

  # Check sandbox-specific prerequisites
  case $SANDBOX_MODE in
  docker)
    if ! command -v docker &>/dev/null; then
      log_error "Docker not found. Install Docker Desktop first."
      exit 1
    fi
    # Check for Docker sandbox support
    if ! docker sandbox --help &>/dev/null 2>&1; then
      log_error "Docker sandbox not available. Requires Docker Desktop 4.50+"
      log_info "Update Docker Desktop or use --sandbox for native sandboxing"
      exit 1
    fi
    log_info "Using Docker Desktop sandbox"
    ;;
  podman)
    if ! command -v podman &>/dev/null; then
      log_error "Podman not found. Install with: brew install podman (macOS)"
      exit 1
    fi
    log_info "Using rootless Podman container"
    ;;
  sandbox)
    if ! command -v claude &>/dev/null; then
      log_error "Claude Code CLI not found."
      log_info "Install: npm install -g @anthropic-ai/claude-code"
      exit 1
    fi
    log_info "Using Claude Code native sandbox"
    ;;
  dangerous)
    if ! command -v claude &>/dev/null; then
      log_error "Claude Code CLI not found."
      log_info "Install: npm install -g @anthropic-ai/claude-code"
      exit 1
    fi
    log_warn "⚠️  Running WITHOUT sandbox (--dangerously-skip-permissions)"
    log_warn "   Claude has unrestricted access to your system"
    read -p "Continue? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
      exit 1
    fi
    ;;
  interactive)
    if ! command -v claude &>/dev/null; then
      log_error "Claude Code CLI not found."
      log_info "Install: npm install -g @anthropic-ai/claude-code"
      exit 1
    fi
    log_info "Using interactive mode (will prompt for each action)"
    ;;
  esac
}

# Archive previous run if branch changed
archive_previous_run() {
  if [ -f "$PRD_FILE" ] && [ -f "$LAST_BRANCH_FILE" ]; then
    CURRENT_BRANCH=$(jq -r '.branchName // empty' "$PRD_FILE" 2>/dev/null || echo "")
    LAST_BRANCH=$(cat "$LAST_BRANCH_FILE" 2>/dev/null || echo "")

    if [ -n "$CURRENT_BRANCH" ] && [ -n "$LAST_BRANCH" ] && [ "$CURRENT_BRANCH" != "$LAST_BRANCH" ]; then
      DATE=$(date +%Y-%m-%d)
      FOLDER_NAME=$(echo "$LAST_BRANCH" | sed 's|^feature/||; s|^ralph/||')
      ARCHIVE_FOLDER="$ARCHIVE_DIR/$DATE-$FOLDER_NAME"

      log_info "Archiving previous run to $ARCHIVE_FOLDER"
      mkdir -p "$ARCHIVE_FOLDER"

      [ -f "$PRD_FILE" ] && cp "$PRD_FILE" "$ARCHIVE_FOLDER/"
      [ -f "$PROGRESS_FILE" ] && cp "$PROGRESS_FILE" "$ARCHIVE_FOLDER/"

      # Reset progress file for new feature
      echo "# Progress Log" >"$PROGRESS_FILE"
      echo "" >>"$PROGRESS_FILE"
      echo "## Codebase Patterns" >>"$PROGRESS_FILE"
      echo "" >>"$PROGRESS_FILE"
      echo "## Session Log" >>"$PROGRESS_FILE"
    fi
  fi
}

# Save current branch for next run comparison
save_current_branch() {
  BRANCH_NAME=$(jq -r '.branchName // empty' "$PRD_FILE" 2>/dev/null || echo "")
  if [ -n "$BRANCH_NAME" ]; then
    echo "$BRANCH_NAME" >"$LAST_BRANCH_FILE"
  fi
}

# Create or checkout feature branch
setup_branch() {
  BRANCH_NAME=$(jq -r '.branchName // empty' "$PRD_FILE")

  if [ -z "$BRANCH_NAME" ]; then
    log_warn "No branchName in prd.json, staying on current branch"
    return
  fi

  CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "")

  if [ "$CURRENT_BRANCH" != "$BRANCH_NAME" ]; then
    if git show-ref --verify --quiet "refs/heads/$BRANCH_NAME"; then
      log_info "Checking out existing branch: $BRANCH_NAME"
      git checkout "$BRANCH_NAME"
    else
      log_info "Creating new branch: $BRANCH_NAME"
      git checkout -b "$BRANCH_NAME"
    fi
  fi
}

# Get the next incomplete story
get_next_story() {
  jq -r '
        .userStories 
        | map(select(.passes != true)) 
        | sort_by(.priority // 999) 
        | first 
        | @json
    ' "$PRD_FILE"
}

# Check if all stories are complete
all_stories_complete() {
  INCOMPLETE=$(jq '[.userStories[] | select(.passes != true)] | length' "$PRD_FILE")
  [ "$INCOMPLETE" -eq 0 ]
}

# Count stories
count_stories() {
  TOTAL=$(jq '.userStories | length' "$PRD_FILE")
  COMPLETE=$(jq '[.userStories[] | select(.passes == true)] | length' "$PRD_FILE")
  echo "$COMPLETE/$TOTAL"
}

# Build the prompt for this iteration
build_prompt() {
  local STORY_JSON="$1"
  local ITERATION="$2"

  # Read base prompt
  PROMPT=$(cat "$PROMPT_FILE")

  # Read progress if it exists
  PROGRESS=""
  if [ -f "$PROGRESS_FILE" ]; then
    PROGRESS=$(cat "$PROGRESS_FILE")
  fi

  # Build the full prompt
  cat <<EOF
# Autonomous Agent Iteration $ITERATION

## Current Story
\`\`\`json
$STORY_JSON
\`\`\`

## Progress from Previous Iterations
\`\`\`
$PROGRESS
\`\`\`

## Instructions
$PROMPT

## Critical Reminders
1. Focus ONLY on the current story above
2. Run quality checks before committing
3. Update prd.json to mark the story as passes: true when complete
4. Append learnings to progress.txt
5. When finished, output: <complete>STORY_DONE</complete>
6. If ALL stories are done, output: <complete>ALL_DONE</complete>
EOF
}

# Run Claude Code for one iteration
run_iteration() {
  local ITERATION=$1
  local STORY_JSON=$2

  STORY_ID=$(echo "$STORY_JSON" | jq -r '.id // "unknown"')
  STORY_TITLE=$(echo "$STORY_JSON" | jq -r '.title // "Untitled"')

  log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  log_info "Iteration $ITERATION of $MAX_ITERATIONS"
  log_info "Story: [$STORY_ID] $STORY_TITLE"
  log_info "Progress: $(count_stories) stories complete"
  log_info "Mode: $SANDBOX_MODE"
  log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  # Build prompt
  FULL_PROMPT=$(build_prompt "$STORY_JSON" "$ITERATION")

  # Create temp file for prompt
  PROMPT_TMP=$(mktemp)
  echo "$FULL_PROMPT" >"$PROMPT_TMP"

  # Run Claude Code with appropriate sandbox mode
  case $SANDBOX_MODE in
  docker)
    # Docker Desktop sandbox
    cd "$PROJECT_ROOT"
    docker sandbox run claude-code --prompt "$(cat "$PROMPT_TMP")"
    CLAUDE_EXIT=$?
    ;;
  podman)
    # Rootless Podman container
    cd "$PROJECT_ROOT"
    podman run --rm -it \
      --userns=keep-id \
      --security-opt label=disable \
      -v "$PROJECT_ROOT:/workspace:Z" \
      -v "$HOME/.claude:/home/user/.claude:Z" \
      -w /workspace \
      -e ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY:-}" \
      ghcr.io/anthropics/claude-code:latest \
      claude --dangerously-skip-permissions --print "$(cat "$PROMPT_TMP")"
    CLAUDE_EXIT=$?
    ;;
  sandbox)
    # Native Claude Code sandbox
    cd "$PROJECT_ROOT"
    claude --sandbox --print "$PROMPT_TMP"
    CLAUDE_EXIT=$?
    ;;
  dangerous)
    # No sandbox (not recommended)
    cd "$PROJECT_ROOT"
    claude --dangerously-skip-permissions --print "$PROMPT_TMP"
    CLAUDE_EXIT=$?
    ;;
  interactive)
    # Interactive mode (prompts for approval)
    cd "$PROJECT_ROOT"
    claude --print "$PROMPT_TMP"
    CLAUDE_EXIT=$?
    ;;
  esac

  # Cleanup
  rm -f "$PROMPT_TMP"

  if [ $CLAUDE_EXIT -ne 0 ]; then
    log_error "Claude Code exited with error code $CLAUDE_EXIT"
    return 1
  fi

  return 0
}

# Main loop
main() {
  log_info "Starting autonomous agent loop"
  log_info "Max iterations: $MAX_ITERATIONS"

  check_prerequisites
  archive_previous_run
  save_current_branch
  setup_branch

  # Initialize progress file if it doesn't exist
  if [ ! -f "$PROGRESS_FILE" ]; then
    echo "# Progress Log" >"$PROGRESS_FILE"
    echo "" >>"$PROGRESS_FILE"
    echo "## Codebase Patterns" >>"$PROGRESS_FILE"
    echo "" >>"$PROGRESS_FILE"
    echo "## Session Log" >>"$PROGRESS_FILE"
  fi

  for ((i = 1; i <= MAX_ITERATIONS; i++)); do
    # Check if all done
    if all_stories_complete; then
      log_success "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      log_success "ALL STORIES COMPLETE!"
      log_success "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      exit 0
    fi

    # Get next story
    STORY_JSON=$(get_next_story)

    if [ "$STORY_JSON" == "null" ] || [ -z "$STORY_JSON" ]; then
      log_success "No more stories to process"
      exit 0
    fi

    # Run iteration
    if ! run_iteration "$i" "$STORY_JSON"; then
      log_error "Iteration $i failed"
      log_info "Check the output above for details"
      exit 1
    fi

    # Brief pause between iterations
    sleep 2
  done

  log_warn "Reached max iterations ($MAX_ITERATIONS)"
  log_info "Progress: $(count_stories) stories complete"
  log_info "Run again to continue"
}

main "$@"
