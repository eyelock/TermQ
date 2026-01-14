#!/bin/bash
# Extract localization strings to JSON for LLM-based translation
# Usage: ./scripts/localization/extract-to-json.sh [language_code]
#
# Without arguments: outputs all English strings as JSON
# With language code: outputs strings needing translation for that language

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RESOURCES_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")/Sources/TermQ/Resources"
EN_STRINGS="$RESOURCES_DIR/en.lproj/Localizable.strings"
TARGET_LANG="${1:-}"

# Parse .strings file to JSON
strings_to_json() {
    local file="$1"
    local lang="$2"

    echo "{"
    echo "  \"language\": \"$lang\","
    echo "  \"strings\": ["

    local first=true
    while IFS= read -r line; do
        # Skip comments and empty lines
        if [[ "$line" =~ ^// ]] || [[ "$line" =~ ^/\* ]] || [[ -z "${line// }" ]]; then
            continue
        fi

        # Parse key = value
        if [[ "$line" =~ ^\"([^\"]+)\"[[:space:]]*=[[:space:]]*\"(.*)\"';'?$ ]]; then
            key="${BASH_REMATCH[1]}"
            value="${BASH_REMATCH[2]}"

            # Escape JSON
            value=$(echo "$value" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g')

            if [ "$first" = true ]; then
                first=false
            else
                echo ","
            fi

            echo -n "    {\"key\": \"$key\", \"english\": \"$value\", \"translation\": \"\"}"
        fi
    done < "$file"

    echo ""
    echo "  ]"
    echo "}"
}

if [ -z "$TARGET_LANG" ]; then
    # Extract all English strings
    strings_to_json "$EN_STRINGS" "en"
else
    # Extract strings for specific language (for translation review)
    TARGET_STRINGS="$RESOURCES_DIR/${TARGET_LANG}.lproj/Localizable.strings"

    if [ ! -f "$TARGET_STRINGS" ]; then
        echo "Error: No translation file found for $TARGET_LANG" >&2
        exit 1
    fi

    echo "{"
    echo "  \"language\": \"$TARGET_LANG\","
    echo "  \"strings\": ["

    first=true
    while IFS= read -r line; do
        if [[ "$line" =~ ^\"([^\"]+)\"[[:space:]]*=[[:space:]]*\"(.*)\"';'?$ ]]; then
            key="${BASH_REMATCH[1]}"

            # Get English value
            en_value=$(grep "^\"$key\"" "$EN_STRINGS" | sed 's/.*=\s*"\(.*\)";/\1/' || echo "")

            # Get target value
            target_value=$(grep "^\"$key\"" "$TARGET_STRINGS" | sed 's/.*=\s*"\(.*\)";/\1/' || echo "")

            # Escape JSON
            en_value=$(echo "$en_value" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g')
            target_value=$(echo "$target_value" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g')

            if [ "$first" = true ]; then
                first=false
            else
                echo ","
            fi

            echo -n "    {\"key\": \"$key\", \"english\": \"$en_value\", \"translation\": \"$target_value\"}"
        fi
    done < "$EN_STRINGS"

    echo ""
    echo "  ]"
    echo "}"
fi
