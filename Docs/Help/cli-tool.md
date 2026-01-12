# CLI Tool

The `termq` CLI tool lets you manage terminals from your shell. It outputs JSON for easy scripting and works great with LLM assistants like Claude.

## Installation

```bash
# Install after building
make install

# Or manually copy
cp .build/release/termq /usr/local/bin/
```

## Quick Start

```bash
# See what's in your board
termq list

# Open a new terminal for your current project
termq open --name "My Project" --column "In Progress"

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

Open a new terminal in TermQ at the current directory.

```bash
# Open in current directory
termq open

# Open with name and description
termq open --name "API Server" --description "Backend"

# Open in specific column
termq open --column "In Progress"

# Open with tags
termq open --name "Build" --tag env=prod --tag version=1.0

# Open in specific directory
termq open --path /path/to/project
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
    "llmPrompt": "Context for LLM"
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

# Set LLM prompt/context
termq set "Terminal Name" --llm-prompt "This terminal runs the API server"

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

## Using the LLM Prompt Field

The `llmPrompt` field lets you store context about a terminal that persists between sessions. This is useful for both humans leaving notes and AI assistants tracking state.

**Setting context:**
```bash
termq set "API Server" --llm-prompt "Running the backend API. Start with: npm run dev. Check logs for errors."
```

**Reading context:**
```bash
termq list | jq '.[].llmPrompt'
```

**Example uses:**
- What commands to run in this terminal
- Current task or objective
- Important notes or warnings
- State that should persist between sessions

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

1. **Start with `termq list`** to understand what terminals exist
2. **Check `llmPrompt`** fields for context left by the user or previous sessions
3. **Update `llmPrompt`** when you learn something important about a terminal
4. **Use columns** to track workflow (To Do → In Progress → Done)
5. **Use tags** for categorization (e.g., `project=myapp`, `env=prod`)
6. **Be descriptive** with names and descriptions so the board is self-documenting
