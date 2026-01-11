# CLI Tool

The `termq` CLI tool lets you manage terminals from your shell. It's designed for LLM-friendly automation with JSON output.

## Installation

```bash
# Install after building
make install

# Or manually copy
cp .build/release/termq /usr/local/bin/
```

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

## LLM Integration Tips

1. Use `termq list` to get all terminals as structured JSON
2. Use `termq find` to filter terminals by criteria
3. Parse the `llmPrompt` field for context about each terminal's purpose
4. Use `termq set --llm-prompt` to store LLM-relevant context
5. Use `termq move` to organize terminals into workflow columns
