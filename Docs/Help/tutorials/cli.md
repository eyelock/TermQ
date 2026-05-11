# Tutorial 8: CLI Automation

Everything you can do in the TermQ UI, you can also do from the shell with `termqcli`. This opens up scripting, shell aliases, and LLM integration — the same board you manage visually, controllable from any terminal.

---

## 8.1 — Install the CLI

Open **Settings** (⌘,) and go to the **Tools** tab. Click **Install Command Line Tool**.

![Settings Tools Tab](../Images/settings-tools-tab.png)

This installs `termqcli` to `/usr/local/bin/`. You'll be prompted for your password. After installation, the button changes to show the current version and an Uninstall option.

Verify it works:

```bash
termqcli --version
```

---

## 8.2 — See your board

```bash
termqcli list
```

Lists every terminal on the board with its name, column, and key metadata. Add `--column "In Progress"` to filter to a specific column.

```bash
termqcli list --column "In Progress"
```

All output is JSON — pipe it to `jq` for filtering and formatting:

```bash
termqcli list | jq '.[].name'
```

---

## 8.3 — Open a terminal

```bash
termqcli open "Dev Server"
```

Opens the terminal in TermQ and returns its full details as JSON — including its LLM context fields (more on those in [Tutorial 9](tutorials/ai-context.md)).

Partial name matching works:

```bash
termqcli open "dev"    # Opens the first match for "dev"
termqcli open "/code"  # Match by working directory path
```

---

## 8.4 — Create a terminal from the shell

```bash
termqcli create \
  --name "API Server" \
  --description "FastAPI backend — uvicorn main:app --reload" \
  --column "In Progress" \
  --path ~/code/myapp \
  --tags env=local project=myapp
```

This creates the card on the board. If you want to open it immediately after:

```bash
termqcli open "API Server"
```

---

## 8.5 — Find terminals

```bash
termqcli find --query "myapp api"
```

Smart search: matches words across name, description, path, and tags simultaneously. Word separators like `-`, `_`, `/` are treated as boundaries, so `"mcp toolkit"` finds `"mcp-toolkit: migrate"`.

Filter by tag:

```bash
termqcli find --tag env=production
termqcli find --tag project          # Match any terminal with a "project" tag
```

Filter by favourites:

```bash
termqcli find --favourites
```

---

## 8.6 — Move and update terminals

```bash
# Move to Done when work is complete
termqcli move "Dev Server" "Done"

# Update fields without opening the editor
termqcli set "Dev Server" \
  --description "Updated: now running on port 3001" \
  --tags status=active

# Tags are additive by default — add --replace-tags to overwrite all
termqcli set "Dev Server" --tags env=local --replace-tags
```

---

## 8.7 — Check what needs attention

```bash
termqcli pending
```

This is the command LLM assistants should run at the start of every session. It returns terminals sorted by urgency: those with queued actions first, then by staleness (stale → ageing → fresh).

```bash
termqcli pending --actions-only   # Only terminals with a queued action
```

---

## 8.8 — Get workflow context

```bash
termqcli context
```

Outputs comprehensive documentation for the current board state — session start/end checklists, tag schema, command reference, and workflow examples. Useful to pipe to an LLM at the start of a session to orient it quickly.

---

## 8.9 — A practical example

Here's a shell function that creates a TermQ terminal for the current git repo and opens it:

```bash
tq-new() {
  local name="${1:-$(basename $PWD)}"
  termqcli create \
    --name "$name" \
    --column "In Progress" \
    --path "$PWD" \
    --tags "project=$(basename $PWD)"
  termqcli open "$name"
}
```

Call it from inside any git repo: `tq-new "Feature Work"`.

---

## What you learned

- `termqcli list` — see the whole board as JSON
- `termqcli open` — open a terminal by name, UUID, or path
- `termqcli create` — create a card from the shell
- `termqcli find` — smart search across all terminal metadata
- `termqcli move` / `termqcli set` — update cards without opening the UI
- `termqcli pending` — see what needs attention, sorted by urgency
- All output is JSON — pipe to `jq` for scripting

## Next

[Tutorial 9: Persistent AI Context](tutorials/ai-context.md) — Give your LLM assistant a memory that survives between sessions.
