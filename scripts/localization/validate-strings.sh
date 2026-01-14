#!/bin/bash
# Validate localization strings across all language files
# Usage: ./scripts/localization/validate-strings.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RESOURCES_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")/Sources/TermQ/Resources"
EN_STRINGS="$RESOURCES_DIR/en.lproj/Localizable.strings"

# Extract keys from a .strings file
extract_keys() {
    grep -E '^"[^"]+"\s*=' "$1" | sed 's/"\([^"]*\)".*/\1/' | sort
}

echo "Validating localization strings..."
echo "Base file: $EN_STRINGS"
echo ""

# Get English keys as reference
EN_KEYS=$(extract_keys "$EN_STRINGS")
EN_COUNT=$(echo "$EN_KEYS" | wc -l | tr -d ' ')

echo "English (base): $EN_COUNT keys"
echo ""

# Track issues
HAS_ISSUES=0

for LPROJ in "$RESOURCES_DIR"/*.lproj; do
    LANG=$(basename "$LPROJ" .lproj)
    STRINGS_FILE="$LPROJ/Localizable.strings"

    if [ "$LANG" == "en" ]; then
        continue
    fi

    if [ ! -f "$STRINGS_FILE" ]; then
        echo "WARNING: $LANG - Missing Localizable.strings"
        HAS_ISSUES=1
        continue
    fi

    LANG_KEYS=$(extract_keys "$STRINGS_FILE")
    LANG_COUNT=$(echo "$LANG_KEYS" | wc -l | tr -d ' ')

    # Find missing keys
    MISSING=$(comm -23 <(echo "$EN_KEYS") <(echo "$LANG_KEYS"))
    MISSING_COUNT=$(echo "$MISSING" | grep -c . || true)

    # Find extra keys (in translation but not in English)
    EXTRA=$(comm -13 <(echo "$EN_KEYS") <(echo "$LANG_KEYS"))
    EXTRA_COUNT=$(echo "$EXTRA" | grep -c . || true)

    if [ "$MISSING_COUNT" -gt 0 ] || [ "$EXTRA_COUNT" -gt 0 ]; then
        echo "ISSUES: $LANG ($LANG_COUNT keys)"
        if [ "$MISSING_COUNT" -gt 0 ]; then
            echo "  Missing $MISSING_COUNT keys:"
            echo "$MISSING" | head -5 | sed 's/^/    - /'
            if [ "$MISSING_COUNT" -gt 5 ]; then
                echo "    ... and $((MISSING_COUNT - 5)) more"
            fi
        fi
        if [ "$EXTRA_COUNT" -gt 0 ]; then
            echo "  Extra $EXTRA_COUNT keys (not in English):"
            echo "$EXTRA" | head -5 | sed 's/^/    - /'
            if [ "$EXTRA_COUNT" -gt 5 ]; then
                echo "    ... and $((EXTRA_COUNT - 5)) more"
            fi
        fi
        HAS_ISSUES=1
    else
        echo "OK: $LANG ($LANG_COUNT keys)"
    fi
done

echo ""
if [ "$HAS_ISSUES" -eq 1 ]; then
    echo "Validation completed with issues."
    exit 1
else
    echo "All translations validated successfully!"
    exit 0
fi
