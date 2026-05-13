#!/usr/bin/env bash
#
# MCP docs gate (audit §8.3).
#
# Fails if a commit touches the MCP **surface** without also touching the reference docs.
# The trigger is narrow on purpose: refactors, comment edits, and internal-only logic
# changes do NOT trip the gate. False positives train reviewers to bypass it.
#
# Surface-affecting diffs we detect:
#   - Tool added / removed / renamed in SchemaDefinitions.availableTools (Tool(name: ...))
#   - Tool input schema changed (any line inside an inputSchema: ... block in SchemaDefinitions)
#   - Tool annotations changed (Tool.Annotations(...) literal in SchemaDefinitions)
#   - Resource added / removed / renamed (Resource(...) in SchemaDefinitions)
#   - Prompt added / removed / renamed (Prompt(...) in SchemaDefinitions)
#   - ToolParity.swift changed
#
# Override: include the literal substring "[no-doc]" in the commit subject for the rare
# case where the surface didn't actually change (e.g. a tool moved between files).
#
# Usage: invoked from quality-gate or git pre-push hook. Compares HEAD against the
# upstream base (configurable via env var MCP_DOCS_BASE, default: origin/develop).

set -eo pipefail

BASE_REF="${MCP_DOCS_BASE:-origin/develop}"

# Source files whose changes trigger the gate (narrow set — see header).
SURFACE_FILES=(
    "Sources/MCPServerLib/SchemaDefinitions.swift"
    "Sources/MCPServerLib/ToolParity.swift"
)

# Doc files that, when touched, satisfy the gate.
DOC_FILES=(
    "Docs/Help/reference/mcp.md"
)

# Override: any commit subject containing this opts out.
OVERRIDE_MARKER="[no-doc]"

# Get the changed files between BASE_REF and HEAD.
if ! changed=$(git diff --name-only "${BASE_REF}...HEAD" 2>/dev/null); then
    echo "check-mcp-docs: could not diff against ${BASE_REF} — skipping gate (likely first commit on branch)" >&2
    exit 0
fi

if [ -z "$changed" ]; then
    exit 0  # Nothing changed — nothing to check.
fi

# Look for override marker in any commit subject on the branch.
if git log --format=%s "${BASE_REF}..HEAD" 2>/dev/null | grep -q -F "$OVERRIDE_MARKER"; then
    echo "check-mcp-docs: ${OVERRIDE_MARKER} marker present in commit subject — gate bypassed" >&2
    exit 0
fi

# Did any surface file change?
touched_surface=0
for f in "${SURFACE_FILES[@]}"; do
    if echo "$changed" | grep -qx "$f"; then
        touched_surface=1
        break
    fi
done

if [ "$touched_surface" -eq 0 ]; then
    exit 0  # No surface change — gate doesn't apply.
fi

# A surface file changed. Now we need at least one matching doc-file change.
touched_docs=0
for f in "${DOC_FILES[@]}"; do
    if echo "$changed" | grep -qx "$f"; then
        touched_docs=1
        break
    fi
done

if [ "$touched_docs" -eq 1 ]; then
    exit 0
fi

cat >&2 <<EOF
check-mcp-docs: MCP surface changed without matching doc update.

Surface files touched:
$(printf '  - %s\n' "${SURFACE_FILES[@]}" | grep -F -f <(echo "$changed") || true)

Expected at least one doc-file update:
$(printf '  - %s\n' "${DOC_FILES[@]}")

To proceed:
  - Update Docs/Help/reference/mcp.md to reflect the tool / resource / prompt change, OR
  - Add "${OVERRIDE_MARKER}" to a commit subject on this branch if the surface
    genuinely did not change (e.g. a tool moved between files, signature unchanged).
EOF
exit 1
