#!/bin/bash
# prd.sh - Generate and convert PRDs using Claude
# Usage: 
#   ./prd.sh generate "description of feature"   # Interactive PRD creation
#   ./prd.sh convert path/to/prd.md              # Convert markdown to JSON
#   ./prd.sh edit                                # Edit existing prd.json

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROMPTS_DIR="$SCRIPT_DIR/prompts"
PRD_FILE="$SCRIPT_DIR/prd.json"

# Colors
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }

show_help() {
    cat << EOF
PRD Generator for Autonomous Agent Loop

Usage:
  ./prd.sh generate "feature description"   Create a new PRD interactively
  ./prd.sh convert path/to/prd.md           Convert markdown PRD to JSON
  ./prd.sh edit                             Edit existing prd.json with Claude
  ./prd.sh status                           Show current PRD status

Examples:
  ./prd.sh generate "add user favorites to my Rails app"
  ./prd.sh convert tasks/user-favorites.md
  ./prd.sh status

The workflow is:
  1. generate - Claude asks questions, creates markdown PRD
  2. convert  - Transform markdown to prd.json
  3. Run loop.sh to execute the stories
EOF
}

generate_prd() {
    local DESCRIPTION="$1"
    
    if [ -z "$DESCRIPTION" ]; then
        echo "Usage: ./prd.sh generate \"description of feature\""
        exit 1
    fi
    
    log_info "Starting interactive PRD generation..."
    log_info "Claude will ask clarifying questions before generating the PRD."
    echo ""
    
    # Read the generator prompt
    SYSTEM_PROMPT=$(cat "$PROMPTS_DIR/prd-generator.md")
    
    # Run Claude interactively
    claude --system-prompt "$SYSTEM_PROMPT" \
           --print "I want to build: $DESCRIPTION

Please ask me clarifying questions, then generate a detailed PRD with small, focused user stories."
    
    echo ""
    log_success "PRD generation complete!"
    log_info "Save the output to a .md file, then run: ./prd.sh convert <file.md>"
}

convert_prd() {
    local MD_FILE="$1"
    
    if [ -z "$MD_FILE" ] || [ ! -f "$MD_FILE" ]; then
        echo "Usage: ./prd.sh convert path/to/prd.md"
        echo "File not found: $MD_FILE"
        exit 1
    fi
    
    log_info "Converting $MD_FILE to prd.json..."
    
    # Read the converter prompt
    SYSTEM_PROMPT=$(cat "$PROMPTS_DIR/prd-to-json.md")
    
    # Read the markdown file
    MD_CONTENT=$(cat "$MD_FILE")
    
    # Run Claude to convert (non-interactive, just output)
    claude --system-prompt "$SYSTEM_PROMPT" \
           --print "Convert this PRD to JSON:

$MD_CONTENT" > "$PRD_FILE.tmp"
    
    # Validate JSON
    if jq empty "$PRD_FILE.tmp" 2>/dev/null; then
        mv "$PRD_FILE.tmp" "$PRD_FILE"
        log_success "Created $PRD_FILE"
        echo ""
        echo "Stories:"
        jq -r '.userStories[] | "  [\(.id)] \(.title)"' "$PRD_FILE"
    else
        log_info "Claude output wasn't pure JSON. Extracting..."
        # Try to extract JSON from the output
        grep -Pzo '\{[\s\S]*\}' "$PRD_FILE.tmp" | head -1 > "$PRD_FILE.extracted"
        if jq empty "$PRD_FILE.extracted" 2>/dev/null; then
            mv "$PRD_FILE.extracted" "$PRD_FILE"
            rm -f "$PRD_FILE.tmp"
            log_success "Created $PRD_FILE"
        else
            echo "Failed to extract valid JSON. Raw output:"
            cat "$PRD_FILE.tmp"
            rm -f "$PRD_FILE.tmp" "$PRD_FILE.extracted"
            exit 1
        fi
    fi
}

edit_prd() {
    if [ ! -f "$PRD_FILE" ]; then
        echo "No prd.json found. Run 'generate' first."
        exit 1
    fi
    
    log_info "Opening prd.json for editing with Claude..."
    
    CURRENT=$(cat "$PRD_FILE")
    
    claude --print "Here's the current prd.json:

\`\`\`json
$CURRENT
\`\`\`

What would you like to change? I can:
- Add new stories
- Modify existing stories
- Reorder priorities
- Update acceptance criteria

Tell me what to change and I'll output the updated JSON."
}

show_status() {
    if [ ! -f "$PRD_FILE" ]; then
        echo "No prd.json found."
        exit 0
    fi
    
    echo ""
    echo "Project: $(jq -r '.projectName' "$PRD_FILE")"
    echo "Branch:  $(jq -r '.branchName' "$PRD_FILE")"
    echo ""
    echo "Stories:"
    jq -r '.userStories | sort_by(.priority) | .[] | 
        if .passes then "  ✅ [\(.id)] \(.title)" 
        else "  ⬜ [\(.id)] \(.title)" end' "$PRD_FILE"
    echo ""
    
    TOTAL=$(jq '.userStories | length' "$PRD_FILE")
    DONE=$(jq '[.userStories[] | select(.passes == true)] | length' "$PRD_FILE")
    echo "Progress: $DONE/$TOTAL complete"
}

# Main
case "${1:-}" in
    generate)
        shift
        generate_prd "$*"
        ;;
    convert)
        convert_prd "$2"
        ;;
    edit)
        edit_prd
        ;;
    status)
        show_status
        ;;
    *)
        show_help
        ;;
esac
