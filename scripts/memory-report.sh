#!/usr/bin/env bash
#
# TermQ memory report.
#
# Collects the diagnostics needed to triage a "TermQ uses a lot of memory" report:
#   1. Whether the memory belongs to TermQ, or to tmux / programs running inside terminals
#   2. TermQ's physical footprint (current and peak) and its breakdown by category
#   3. The heap's largest object types (type names only, never their contents)
#   4. A leak count (summary line only)
#   5. Board shape: card counts and terminal backends (no titles, paths or commands)
#
# Run it twice, a few hours apart, with the same tabs open: comparing the two reports
# separates steady growth (a leak) from a high-but-stable baseline.
#
# Privacy: the report never includes terminal output, card titles, paths, commands or
# environment variables. Home directory and user name are redacted. Full `leaks` output
# is deliberately not captured because it can print the contents of strings in memory.
#
# Usage:
#   scripts/memory-report.sh [--pid <pid>] [--quick] [--debug]
#     --pid    inspect this process instead of looking up TermQ by name
#     --quick  skip heap and leaks (they pause TermQ for a few seconds each)
#     --debug  inspect the debug build (TermQDebug.app / TermQ-Debug data directory)
#
# The report is written to ~/Desktop/termq-memory-<timestamp>.txt.

set -euo pipefail

PID=""
QUICK=0
APP_BUNDLE="TermQ.app"
DEFAULTS_DOMAIN="net.eyelock.termq.app"
DATA_DIR="$HOME/Library/Application Support/TermQ"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --pid) PID="${2:?--pid needs a value}"; shift 2 ;;
        --quick) QUICK=1; shift ;;
        --debug) APP_BUNDLE="TermQDebug.app"; DEFAULTS_DOMAIN="net.eyelock.termq.app.debug"; DATA_DIR="$HOME/Library/Application Support/TermQ-Debug"; shift ;;
        -h|--help) sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "Unknown option: $1" >&2; exit 2 ;;
    esac
done

if [[ -z "$PID" ]]; then
    # Both builds' executables are named TermQ; the bundle path tells them apart.
    # ps rather than pgrep: pgrep can miss GUI apps when run from a sandboxed shell.
    PID=$(ps -axo pid=,comm= | awk -v suffix="/$APP_BUNDLE/Contents/MacOS/TermQ" \
        'substr($0, length($0) - length(suffix) + 1) == suffix && !found { print $1; found = 1 }')
fi
if [[ -z "$PID" ]] || ! kill -0 "$PID" 2>/dev/null; then
    echo "$APP_BUNDLE is not running. Start it, use it as usual, then run this again." >&2
    exit 1
fi

OUT="$HOME/Desktop/termq-memory-$(date +%Y%m%d-%H%M%S).txt"

redact() {
    sed -e "s|$HOME|~|g" -e "s|/Users/$USER|/Users/USER|g" -e "s|\\b$USER\\b|USER|g"
}

section() {
    printf '\n==== %s ====\n' "$1"
}

app_version() {
    local exe plist
    exe=$(ps -o comm= -p "$PID")
    plist="$(dirname "$(dirname "$exe")")/Info.plist"
    if [[ -f "$plist" ]]; then
        printf '%s (%s)\n' \
            "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist" 2>/dev/null)" \
            "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist" 2>/dev/null)"
    else
        echo "unknown"
    fi
}

# Card counts and backends from every board file. Reads only structural fields.
board_summary() {
    local board count i total=0 live=0 backend
    local -a backends=()
    shopt -s nullglob
    for board in "$DATA_DIR"/board.json "$DATA_DIR"/board-*.json; do
        count=$(plutil -extract cards raw -o - "$board" 2>/dev/null || echo 0)
        for ((i = 0; i < count; i++)); do
            total=$((total + 1))
            if ! plutil -extract "cards.$i.deletedAt" raw -o - "$board" >/dev/null 2>&1; then
                live=$((live + 1))
                backend=$(plutil -extract "cards.$i.backend" raw -o - "$board" 2>/dev/null || echo "default")
                backends+=("$backend")
            fi
        done
    done
    shopt -u nullglob
    echo "Board files: $(find "$DATA_DIR" -maxdepth 1 -name 'board*.json' 2>/dev/null | wc -l | tr -d ' ')"
    echo "Cards (live / including deleted): $live / $total"
    echo "Live cards by backend override (default = follows the app setting):"
    if [[ ${#backends[@]} -gt 0 ]]; then
        printf '%s\n' "${backends[@]}" | sort | uniq -c | sed 's/^/  /'
    fi
    echo "App-level default backend: $(defaults read "$DEFAULTS_DOMAIN" defaultBackend 2>/dev/null || echo 'not set')"
    echo "Scrollback lines setting: $(defaults read "$DEFAULTS_DOMAIN" terminalScrollbackLines 2>/dev/null || echo 'default')"
}

echo "Collecting TermQ memory report for PID $PID..."

{
    echo "TermQ memory report"
    echo "Generated: $(date '+%Y-%m-%d %H:%M:%S %z')"
    echo "macOS: $(sw_vers -productVersion) ($(sw_vers -buildVersion)), $(uname -m)"
    echo "TermQ version: $(app_version)"
    echo "TermQ uptime (etime): $(ps -o etime= -p "$PID" | tr -d ' ')"
    echo "Physical RAM: $(($(sysctl -n hw.memsize) / 1024 / 1024 / 1024)) GB"

    section "Processes (RSS in KB) — is the memory TermQ's, tmux's, or a child program's?"
    ps -axo pid,ppid,rss,etime,comm | awk 'NR == 1 || tolower($0) ~ /termq|tmux/' | grep -v -E 'awk|memory-report' | redact
    echo
    echo "Largest children of TermQ and of tmux (programs running inside terminals):"
    tmux_pids=$(ps -axo pid=,comm= | awk '$2 ~ /(^|\/)tmux$/ { print $1 }' | paste -sd, - || true)
    ps -axo pid,ppid,rss,comm \
        | awk -v parents="$PID,${tmux_pids}" 'BEGIN { n = split(parents, p, ","); for (i = 1; i <= n; i++) if (p[i] != "") want[p[i]] = 1 }
                                          NR > 1 && ($2 in want) { print }' \
        | sort -k3 -nr | head -15 | awk '{ n = split($4, parts, "/"); printf "  pid=%s rss_kb=%s %s\n", $1, $3, parts[n] }'
    echo "tmux sessions: $(tmux ls 2>/dev/null | wc -l | tr -d ' ')"

    section "Board shape"
    board_summary

    section "footprint"
    footprint "$PID" 2>&1 | head -40 | redact

    if [[ $QUICK -eq 0 ]]; then
        section "heap — largest object types (type names only)"
        # awk (not head) so heap is never cut off mid-write, which would trip pipefail.
        heap "$PID" -sortBySize 2>/dev/null \
            | awk '/^All zones:.*bytes\)/ { print } /COUNT +BYTES/ { p = 1 } p && n++ < 32' | redact || true

        section "leaks — summary only"
        # leaks exits non-zero when it finds leaks. Keep only the summary and root-type lines:
        # its full output can include the contents of strings in memory.
        leak_lines=$(leaks "$PID" 2>/dev/null | grep -E 'leaks for .* total leaked bytes|^ {6}[0-9]+ \(.*ROOT (CYCLE|LEAK)' || true)
        if [[ -z "$leak_lines" ]]; then
            echo "leaks unavailable"
        else
            grep -E 'leaks for' <<< "$leak_lines" || true
            echo "Leak roots by type:"
            grep -E 'ROOT (CYCLE|LEAK)' <<< "$leak_lines" \
                | sed -E 's/.*ROOT (CYCLE|LEAK): <([^ >]+).*/  \2/' \
                | sort | uniq -c | sort -rn | awk 'NR <= 15' || true
        fi
    fi
} > "$OUT" 2>&1

echo "Report written to: $OUT"
echo
echo "Please also tell us, in the issue:"
echo "  - roughly how many tabs were open when you ran this"
echo "  - what you were doing just before memory got high (e.g. lots of output, a long-running agent)"
echo "If you can, run this again a few hours later with the same tabs open, and attach both reports."
