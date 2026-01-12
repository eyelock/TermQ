# CLI Tool

The `termq` CLI tool lets you manage terminals from your shell. It outputs JSON for easy scripting and works great with LLM assistants like Claude.

## Installation

1. Open **TermQ → Settings** (or press ⌘,)
2. Click **Install Command Line Tool**
3. Enter your password when prompted

The CLI will be installed to `/usr/local/bin/termq`.

![Install CLI from Settings](Images/install-cli.png)

## Quick Start

```bash
# See what's in your board
termq list

# Open an existing terminal by name
termq open "My Project"

# Create a new terminal for your current project
termq create --name "My Project" --column "In Progress"

# Find terminals by name
termq find --name "api"

# Move a terminal to Done when finished
termq move "My Project" "Done"
```

## Understanding the Board

TermQ organizes terminals in a **Kanban board** with columns like "To Do", "In Progress", and "Done". Each terminal has:

- **Name & Description** - What this terminal is for
- **Column** - Current workflow stage
- **Tags** - Key-value metadata (e.g., `env=prod`)
- **Badges** - Visual labels
- **LLM Prompt** - Notes/context for AI assistants (see below)

## Commands

### Open a Terminal

Open an existing terminal by name, ID, or path. Returns terminal details as JSON (including `llmPrompt` for context).

```bash
# Open by name
termq open "API Server"

# Open by UUID
termq open "70D8ECF5-E3E3-4FAC-A2A1-7E0F18C94B88"

# Open by path (matches working directory)
termq open "/path/to/project"

# Open with partial name match
termq open "api"
```

**Output:** Returns the terminal's full details as JSON, which is useful for LLM assistants to read context.

### Create a Terminal

Create a new terminal in TermQ.

```bash
# Create in current directory
termq create

# Create with name and description
termq create --name "API Server" --description "Backend"

# Create in specific column
termq create --column "In Progress"

# Create with tags
termq create --name "Build" --tag env=prod --tag version=1.0

# Create in specific directory
termq create --path /path/to/project
```

### Launch TermQ

```bash
termq launch
```

### List Terminals

List all terminals as JSON (ideal for LLM consumption).

```bash
# List all terminals
termq list

# Use debug data directory
termq list --debug

# Filter by column
termq list --column "In Progress"

# List columns only
termq list --columns
```

**Output format:**
```json
[
  {
    "id": "UUID",
    "name": "Terminal Name",
    "description": "Description",
    "column": "Column Name",
    "columnId": "UUID",
    "tags": {"key": "value"},
    "path": "/working/directory",
    "badges": ["badge1", "badge2"],
    "isFavourite": false,
    "llmPrompt": "Persistent context",
    "llmNextAction": "One-time task (runs on next open)"
  }
]
```

### Find Terminals

Search for terminals by various criteria.

```bash
# Find by name (partial, case-insensitive)
termq find --name "api"

# Find by column
termq find --column "In Progress"

# Find by tag
termq find --tag env=prod

# Find by ID
termq find --id "70D8ECF5-E3E3-4FAC-A2A1-7E0F18C94B88"

# Find by badge
termq find --badge "prod"

# Find favourites only
termq find --favourites

# Combine filters
termq find --column "In Progress" --tag env=prod
```

### Modify Terminals

Update terminal properties via URL scheme (requires TermQ to be running).

```bash
# Rename a terminal
termq set "Terminal Name" --name "New Name"

# Set description
termq set "Terminal Name" --set-description "New description"

# Move to column
termq set "Terminal Name" --column "Done"

# Set badge
termq set "Terminal Name" --badge "prod, v2.0"

# Set persistent LLM context
termq set "Terminal Name" --llm-prompt "Node.js API server, uses PostgreSQL"

# Set one-time LLM action (runs on next open, then clears)
termq set "Terminal Name" --llm-next-action "Fix the auth bug discussed in issue #42"

# Add tags
termq set "Terminal Name" --tag env=prod --tag version=2.0

# Mark as favourite
termq set "Terminal Name" --favourite

# Remove favourite
termq set "Terminal Name" --unfavourite

# Use UUID instead of name
termq set "70D8ECF5-E3E3-4FAC-A2A1-7E0F18C94B88" --name "New Name"
```

### Move Terminals

Move a terminal to a different column.

```bash
# Move by name
termq move "Terminal Name" "Done"

# Move by UUID
termq move "70D8ECF5-E3E3-4FAC-A2A1-7E0F18C94B88" "In Progress"
```

## Debug Mode

All read commands (`list`, `find`) support `--debug` to use the debug data directory (`~/Library/Application Support/TermQ-Debug/`).

```bash
termq list --debug
termq find --debug --name "test"
```

## Error Handling

All commands output JSON for easy parsing:

**Success:**
```json
{"success": true, "id": "UUID"}
```

**Error:**
```json
{"error": "Error message", "code": 1}
```

## LLM Integration

TermQ supports any LLM CLI tool through **Init Command tokens**. This vendor-agnostic approach lets you use Claude Code, Aider, GitHub Copilot, or any other tool.

### Token Placeholders

Use these tokens in a terminal's **Init Command** field:

| Token | Description |
|-------|-------------|
| `{{LLM_PROMPT}}` | Persistent context (never auto-cleared) |
| `{{LLM_NEXT_ACTION}}` | One-time action (cleared after terminal opens) |

### Example Init Commands

```bash
# Claude Code - start interactive session with context
claude "{{LLM_PROMPT}} {{LLM_NEXT_ACTION}}"

# Aider - pass task directly
aider --message "{{LLM_NEXT_ACTION}}"

# GitHub Copilot
gh copilot suggest "{{LLM_NEXT_ACTION}}"

# Custom script
my-llm-wrapper.sh --context "{{LLM_PROMPT}}" --task "{{LLM_NEXT_ACTION}}"
```

### Setting LLM Fields via CLI

```bash
# Set persistent context (always available)
termq set "API Server" --llm-prompt "Node.js backend. Entry: src/index.ts. Uses PostgreSQL."

# Set one-time action (runs once, then clears)
termq set "API Server" --llm-next-action "Implement rate limiting. See plan in context."

# Read LLM fields
termq list | jq '.[] | {name, llmPrompt, llmNextAction}'

# Check pending actions
termq list | jq '.[] | select(.llmNextAction != "") | {name, llmNextAction}'
```

### How It Works

1. User sets **Init Command** with tokens (e.g., `claude "{{LLM_PROMPT}} {{LLM_NEXT_ACTION}}"`)
2. User or LLM sets `llmPrompt` and/or `llmNextAction` via CLI or UI
3. When terminal opens, tokens are replaced with actual values
4. If `{{LLM_NEXT_ACTION}}` was in the command and had a value, it's cleared after use
5. Empty tokens become empty strings (your LLM tool handles gracefully)

### Use Cases

**Persistent Context (`llmPrompt`):**
- Project background info
- Tech stack details
- Important notes that should persist

**Next Action (`llmNextAction`):**
- Parking work with "resume from here" instructions
- Queueing tasks for later
- Handoff between sessions

## Automation & Scripting

The CLI outputs JSON for easy parsing in scripts or by AI assistants.

**Example: Find all production terminals**
```bash
termq find --tag env=prod | jq '.[].name'
```

**Example: Move all "In Progress" to "Review"**
```bash
termq find --column "In Progress" | jq -r '.[].id' | xargs -I {} termq move {} "Review"
```

## Tips for AI Assistants

If you're an LLM assistant helping a user with TermQ:

1. **Use `termq open <name>`** to resume work - returns terminal details including both LLM fields
2. **Check `llmNextAction`** first - this is a pending task queued for you
3. **Check `llmPrompt`** for persistent background context
4. **Set `llmNextAction`** when parking work - user's Init Command will inject it on next open
5. **Update `llmPrompt`** for context that should persist (project info, notes)
6. **Use `termq create`** only when starting genuinely new work
7. **Use columns** to track workflow (To Do → In Progress → Done)

**Complete Workflow Example:**

```bash
# Session 1: User opens terminal, you do some work
termq open "API Project"
# Returns: llmPrompt="Node.js backend", llmNextAction=""

# You implement a feature, but need to pause. Queue next action:
termq set "API Project" --llm-next-action "Continue implementing rate limiting from line 42"

# Session 2: User opens terminal again
# Init Command: claude "{{LLM_PROMPT}} {{LLM_NEXT_ACTION}}"
# Becomes:      claude "Node.js backend Continue implementing rate limiting from line 42"
# llmNextAction is cleared, you pick up where you left off
```

**Parking Work Pattern:**
```bash
# Before ending session, queue the next task
termq set "My Terminal" \
  --llm-prompt "React frontend, uses Redux" \
  --llm-next-action "Implement the login form. See design in Figma link in description."
```
