# Autonomous Agent Loop for Claude Code

An autonomous AI agent loop that runs Claude Code repeatedly until all PRD items are complete. Each iteration is a fresh Claude Code instance with clean context. Memory persists via git history, `progress.txt`, and `prd.json`.

Based on [Geoffrey Huntley's Ralph pattern](https://ghuntley.com/ralph/).

## Sandboxing Options

The script supports multiple sandboxing approaches for security:

| Mode           | Flag            | Security   | Speed  | Notes                                          |
| -------------- | --------------- | ---------- | ------ | ---------------------------------------------- |
| Native Sandbox | `--sandbox`     | ✅ High    | Fast   | Default. Uses Claude Code's built-in isolation |
| Docker Sandbox | `--docker`      | ✅ High    | Medium | Requires Docker Desktop 4.50+                  |
| Podman         | `--podman`      | ✅ High    | Medium | Rootless containers, works without Docker      |
| Interactive    | `--interactive` | ✅ Highest | Slow   | Prompts for each action                        |
| Dangerous      | `--dangerous`   | ❌ None    | Fast   | Full system access, not recommended            |

**Recommendation:** Use `--sandbox` (default) or `--docker` for autonomous operation.

## How It Works

```
┌─────────────────────────────────────────────────────────┐
│                      loop.sh                            │
│  ┌───────────────────────────────────────────────────┐  │
│  │ 1. Read prd.json                                  │  │
│  │ 2. Find next story where passes: false            │  │
│  │ 3. Spawn fresh Claude Code instance               │  │
│  │ 4. Claude implements story, runs checks, commits  │  │
│  │ 5. Claude updates prd.json (passes: true)         │  │
│  │ 6. Claude appends learnings to progress.txt       │  │
│  │ 7. Loop continues until all stories pass          │  │
│  └───────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
```

## Prerequisites

- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) installed and authenticated
- `jq` installed (`brew install jq` on macOS)
- A git repository for your project

## Setup

1. Copy these files to your project:

```bash
mkdir -p scripts/agent
cp loop.sh prompt.md prd.json.example scripts/agent/
chmod +x scripts/agent/loop.sh
```

2. Create your PRD:

```bash
cp scripts/agent/prd.json.example scripts/agent/prd.json
# Edit prd.json with your actual stories
```

3. Customize `prompt.md` for your project:
   - Update quality check commands for your stack
   - Add project-specific conventions

## Usage

```bash
# Default: native sandbox, 10 iterations
./scripts/agent/loop.sh

# Explicit sandbox modes
./scripts/agent/loop.sh --sandbox 10      # Native sandbox (recommended)
./scripts/agent/loop.sh --docker 10       # Docker Desktop sandbox
./scripts/agent/loop.sh --podman 10       # Rootless Podman
./scripts/agent/loop.sh --interactive 5   # Prompt for each action
./scripts/agent/loop.sh --dangerous 10    # No sandbox (not recommended)
```

### Using Docker Desktop Sandbox

Requires Docker Desktop 4.50+:

```bash
./scripts/agent/loop.sh --docker
```

Docker handles container isolation, credential management, and workspace mounting automatically.

### Using Rootless Podman

For systems without Docker or preferring Podman:

```bash
# Install Podman
brew install podman      # macOS
sudo apt install podman  # Linux

# Build the container image (once)
cd scripts/agent
podman build -t claude-sandbox .

# Run
./loop.sh --podman
```

Podman runs rootless by default, meaning the container has no elevated privileges on the host.

## Key Files

| File               | Purpose                                               |
| ------------------ | ----------------------------------------------------- |
| `loop.sh`          | The bash loop that spawns fresh Claude Code instances |
| `prompt.md`        | Instructions given to each Claude Code instance       |
| `prd.json`         | User stories with `passes` status                     |
| `prd.json.example` | Example PRD format                                    |
| `progress.txt`     | Append-only learnings for future iterations           |
| `Dockerfile`       | Container image for Podman/Docker sandboxing          |

## PRD Format

```json
{
  "projectName": "Feature Name",
  "branchName": "feature/my-feature",
  "userStories": [
    {
      "id": "US-001",
      "title": "Short description",
      "priority": 1,
      "passes": false,
      "acceptanceCriteria": ["Criterion 1", "Criterion 2"],
      "technicalNotes": "Optional implementation hints"
    }
  ]
}
```

## Creating a PRD

### Option 1: Use Claude directly (easiest)

Just ask Claude to generate a prd.json for you. Here's a template:

```
I need a prd.json for an autonomous coding agent. Feature:

[DESCRIBE YOUR FEATURE]

Stack: [Rails/Django/Next.js/etc]

Ask me clarifying questions, then output prd.json with 4-8 small stories.
Each story should be completable in ~15-30 minutes.
```

Claude will ask questions, then generate the JSON. Save it as `prd.json`.

### Option 2: Use the prd.sh helper

```bash
# Interactive generation (Claude asks questions)
./prd.sh generate "add user favorites to my Rails app"

# Convert existing markdown PRD to JSON
./prd.sh convert tasks/my-feature.md

# Check current status
./prd.sh status
```

### Option 3: Write it manually

Copy `prd.json.example` and edit it directly.

### Story Sizing

Each story should fit in one AI context window. Good sizes:

| ✅ Good                    | ❌ Too Big             |
| -------------------------- | ---------------------- |
| Add a database migration   | Build the dashboard    |
| Create one API endpoint    | Add authentication     |
| Build a single component   | Refactor the API       |
| Add form validation        | Implement search       |
| Write tests for one module | Add full test coverage |

If a story feels big, split it.

## Critical Concepts

### Fresh Context Each Iteration

Each iteration spawns a **new Claude Code instance** with clean context. The only memory between iterations is:

- Git history (commits from previous iterations)
- `progress.txt` (learnings and patterns)
- `prd.json` (which stories are done)

### Right-Size Your Stories

Each story should be completable in one context window. If a task is too big, Claude runs out of context and produces poor code.

**Good story sizes:**

- Add a database column and migration
- Add a UI component to an existing page
- Create an API endpoint with basic CRUD
- Add a filter dropdown to a list

**Too big (split these):**

- "Build the entire dashboard"
- "Add authentication"
- "Refactor the API layer"

### Feedback Loops Are Essential

The loop only works if there are quality checks:

- Type checking catches type errors
- Tests verify behavior
- Linting catches style issues

If checks fail, Claude fixes them before committing. Broken code compounds across iterations.

### progress.txt Is Your Memory

This file persists learnings across iterations:

```markdown
## Codebase Patterns

- Use `sql<number>` template for aggregations
- Always use `IF NOT EXISTS` for migrations
- Export types from actions.ts for UI components

## Session Log

### Iteration 1 - US-001 - 2025-01-09

- Added migration for users.status column
- Discovered: migrations require IF NOT EXISTS
```

## Debugging

```bash
# See which stories are done
cat prd.json | jq '.userStories[] | {id, title, passes}'

# See learnings from previous iterations
cat progress.txt

# Check git history
git log --oneline -10
```

## Security Considerations

### Why Sandboxing Matters

When running autonomously, Claude Code can:

- Execute arbitrary bash commands
- Read/write files anywhere it has access
- Install packages
- Make network requests

Sandboxing limits the blast radius if something goes wrong.

### Native Sandbox (`--sandbox`)

Claude Code's built-in sandbox uses OS-level primitives:

- Filesystem isolation (only write to workspace)
- Network allowlisting
- Process containment

Configure in `~/.claude/settings.json`:

```json
{
  "sandbox": {
    "permissions": {
      "write": ["./"],
      "read": ["/"],
      "network": ["api.anthropic.com", "github.com", "npmjs.org"]
    }
  }
}
```

### Container Sandbox (`--docker` or `--podman`)

Container isolation provides:

- Separate filesystem namespace
- Network isolation (configurable)
- Resource limits
- No access to host processes

The container only sees:

- Your project directory (mounted at `/workspace`)
- Claude credentials (mounted read-only)

## Customization

### Stack-Specific Quality Checks

Edit `prompt.md` to match your stack:

**Rails:**

```bash
bundle exec rubocop
bundle exec rspec
```

**Django:**

```bash
python -m mypy .
python -m pytest
```

**Go:**

```bash
go build ./...
go test ./...
```

### Project Conventions

Add project-specific rules to `prompt.md`:

```markdown
## Project Conventions

- Use snake_case for Ruby, camelCase for JavaScript
- All API endpoints return JSON with { data, error } shape
- UI components go in app/components/
```

## Troubleshooting

**Claude Code not found:**

```
Install Claude Code: https://docs.anthropic.com/en/docs/claude-code
```

**jq not found:**

```bash
brew install jq  # macOS
apt install jq   # Linux
```

**Stories not completing:**

- Check if stories are too large (split them)
- Review progress.txt for patterns of failure
- Run manually to debug: `cat prompt.md | claude`

## License

MIT
