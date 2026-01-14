#!/bin/bash
# generate-prd.sh - Generate PRD markdown and convert to prd.json
# Usage: ./generate-prd.sh "description of feature"

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRD_MD_FILE="$SCRIPT_DIR/prd.md"
PRD_JSON_FILE="$SCRIPT_DIR/prd.json"

# Colors
BLUE='\033[0;34m'
GREEN='\033[0;32m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }

show_help() {
    cat << 'EOF'
PRD Generator - Creates prd.md and prd.json

Usage:
  ./generate-prd.sh "feature description"

Examples:
  ./generate-prd.sh "add user authentication"
  ./generate-prd.sh "shopping cart with checkout flow"

This script will:
  1. Ask clarifying questions about your feature
  2. Generate prd.md with user stories
  3. Convert prd.md to prd.json for the loop.sh agent
EOF
}

# System prompt based on prd-generator.md
GENERATOR_PROMPT='You are a product requirements expert. Your job is to create detailed, well-scoped PRDs that can be executed by an autonomous AI coding agent.

## Process

### Step 1: Gather Requirements

Ask the user clarifying questions to understand:
1. **Goal**: What problem are we solving? What is the desired outcome?
2. **Scope**: What is in scope vs out of scope?
3. **Technical Context**: What stack/framework? Any existing patterns to follow?
4. **Constraints**: Timeline, dependencies, must-haves vs nice-to-haves?

Do not proceed until you have clear answers.

### Step 2: Break Down into Stories

Create user stories that are:
- **Small**: Completable in one AI context window (roughly 15-30 minutes of focused work)
- **Independent**: Can be completed without waiting for other stories
- **Testable**: Has clear acceptance criteria that can be verified
- **Ordered**: Lower priority numbers = implement first

### Step 3: Output Format

Generate a markdown PRD with this structure:

# [Feature Name]

## Overview
Brief description of what we are building and why.

## Technical Context
- Stack/framework
- Relevant existing patterns
- Key files/directories

## User Stories

### US-001: [Title]
**Priority**: 1
**Acceptance Criteria**:
- [ ] Criterion 1
- [ ] Criterion 2

**Technical Notes**: Implementation hints, patterns to follow, gotchas.

---

### US-002: [Title]
**Priority**: 2
...

## Story Sizing Guidelines

**Right-sized stories** (one context window):
- Add a database migration
- Create a single API endpoint
- Build one UI component
- Add a form with validation
- Write tests for one module
- Add a configuration option

**Too large** (split these):
- "Build the dashboard" -> Split into: layout, data fetching, charts, filters
- "Add authentication" -> Split into: model, login endpoint, session handling, UI
- "Refactor the API" -> Split into: one endpoint at a time

## Remember

- Each story should be achievable in ONE iteration
- Include enough technical context for an AI to implement without asking questions
- Acceptance criteria should be verifiable (not vague like "works well")
- Order stories so earlier ones do not depend on later ones'

CONVERTER_PROMPT='Convert the following PRD markdown to a JSON file with this exact structure:

{
  "projectName": "Feature Name",
  "branchName": "feature/kebab-case-name",
  "description": "What this feature does",
  "userStories": [
    {
      "id": "US-001",
      "title": "Short description",
      "priority": 1,
      "passes": false,
      "acceptanceCriteria": ["Criterion 1", "Criterion 2"],
      "technicalNotes": "Implementation hints"
    }
  ]
}

Rules:
- Extract all user stories from the markdown
- Set passes to false for all stories
- Use the priority numbers from the markdown
- Output ONLY valid JSON, no markdown code blocks or explanations'

if [ -z "$1" ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    show_help
    exit 0
fi

DESCRIPTION="$1"

# Step 1: Generate PRD markdown
log_info "Starting interactive PRD generation..."
log_info "Claude will ask clarifying questions before generating the PRD."
echo ""

claude --system-prompt "$GENERATOR_PROMPT" \
       --print "I want to build: $DESCRIPTION

Please ask me clarifying questions, then generate a detailed PRD with small, focused user stories." > "$PRD_MD_FILE"

log_success "Created $PRD_MD_FILE"
echo ""

# Step 2: Convert to JSON
log_info "Converting PRD to JSON..."

MD_CONTENT=$(cat "$PRD_MD_FILE")

claude --system-prompt "$CONVERTER_PROMPT" \
       --print "$MD_CONTENT" > "$PRD_JSON_FILE.tmp"

# Validate and clean up JSON
if jq empty "$PRD_JSON_FILE.tmp" 2>/dev/null; then
    mv "$PRD_JSON_FILE.tmp" "$PRD_JSON_FILE"
else
    # Try to extract JSON from output
    sed -n '/^{/,/^}/p' "$PRD_JSON_FILE.tmp" > "$PRD_JSON_FILE.extracted"
    if jq empty "$PRD_JSON_FILE.extracted" 2>/dev/null; then
        mv "$PRD_JSON_FILE.extracted" "$PRD_JSON_FILE"
        rm -f "$PRD_JSON_FILE.tmp"
    else
        echo "Failed to extract valid JSON. Check $PRD_JSON_FILE.tmp"
        exit 1
    fi
fi

log_success "Created $PRD_JSON_FILE"
echo ""

# Show summary
echo "Stories:"
jq -r '.userStories[] | "  [\(.id)] \(.title)"' "$PRD_JSON_FILE"
echo ""
log_success "PRD generation complete! Run ./loop.sh to start execution."
