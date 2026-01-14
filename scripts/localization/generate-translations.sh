#!/bin/bash
# Generate translation template files for all supported languages
# Usage: ./scripts/localization/generate-translations.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RESOURCES_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")/Sources/TermQ/Resources"
EN_STRINGS="$RESOURCES_DIR/en.lproj/Localizable.strings"

# All macOS supported language codes
LANGUAGES=(
    "es"        # Spanish
    "es-419"    # Spanish (Latin America)
    "fr"        # French
    "fr-CA"     # French (Canada)
    "de"        # German
    "it"        # Italian
    "pt"        # Portuguese
    "pt-PT"     # Portuguese (Portugal)
    "nl"        # Dutch
    "sv"        # Swedish
    "da"        # Danish
    "fi"        # Finnish
    "no"        # Norwegian
    "pl"        # Polish
    "ru"        # Russian
    "uk"        # Ukrainian
    "cs"        # Czech
    "sk"        # Slovak
    "hu"        # Hungarian
    "ro"        # Romanian
    "hr"        # Croatian
    "sl"        # Slovenian
    "el"        # Greek
    "tr"        # Turkish
    "he"        # Hebrew
    "ar"        # Arabic
    "th"        # Thai
    "vi"        # Vietnamese
    "id"        # Indonesian
    "ms"        # Malay
    "zh-Hans"   # Chinese (Simplified)
    "zh-Hant"   # Chinese (Traditional)
    "zh-HK"     # Chinese (Hong Kong)
    "ja"        # Japanese
    "ko"        # Korean
    "hi"        # Hindi
    "ca"        # Catalan
    "en-GB"     # English (UK)
    "en-AU"     # English (Australia)
)

echo "Generating translation templates..."
echo "Base file: $EN_STRINGS"
echo ""

for lang in "${LANGUAGES[@]}"; do
    LPROJ_DIR="$RESOURCES_DIR/${lang}.lproj"
    STRINGS_FILE="$LPROJ_DIR/Localizable.strings"

    if [ ! -d "$LPROJ_DIR" ]; then
        mkdir -p "$LPROJ_DIR"
        echo "Created: ${lang}.lproj/"
    fi

    if [ ! -f "$STRINGS_FILE" ]; then
        # Copy English as template
        cp "$EN_STRINGS" "$STRINGS_FILE"

        # Update the header comment
        sed -i '' "s/English localization strings./${lang} localization strings./" "$STRINGS_FILE"

        echo "  Created: ${lang}.lproj/Localizable.strings"
    else
        echo "  Exists:  ${lang}.lproj/Localizable.strings"
    fi
done

echo ""
echo "Done! Created translation templates for ${#LANGUAGES[@]} languages."
echo ""
echo "Next steps:"
echo "1. Translate strings in each .lproj/Localizable.strings file"
echo "2. Run 'make build' to verify translations compile"
echo "3. Test by changing language in Settings > General > Language"
