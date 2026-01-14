# Localization Command

Manage TermQ localization: extract strings, translate, validate, and audit.

## Usage

```
/localization <action> [language]
```

## Actions

### `extract` - Find hardcoded strings
Scan Swift files for potential hardcoded strings that need localization.

### `translate <language>` - Translate to target language
Translate all strings from English to the specified language code (e.g., `es`, `de`, `ja`, `zh-Hans`).

### `validate [language]` - Check for missing strings
Compare translations against English base. If language is omitted, checks all languages.

### `status` - Show translation coverage
Display statistics on translation coverage across all languages.

### `audit <language>` - Review translation quality
Review existing translations for quality, consistency, and potential issues.

### `add-string <key>` - Add a new localizable string
Interactively add a new string key to Strings.swift and all Localizable.strings files.

---

## Instructions for Claude

When this command is invoked, follow these workflows:

### For `extract`:
1. Search all Swift files in `Sources/TermQ/` for quoted strings
2. Filter out:
   - Strings already using `Strings.*` or `String(localized:)`
   - System identifiers (SF Symbols, file paths, identifiers)
   - Debug/logging strings
3. Group findings by file
4. For each hardcoded string found, suggest:
   - Appropriate key name following `domain.action` convention
   - Which `Strings.*` enum it belongs to
5. Output a summary table of all strings to extract

### For `translate <language>`:
1. Read `Sources/TermQ/Resources/en.lproj/Localizable.strings`
2. Create or read target `Sources/TermQ/Resources/<language>.lproj/Localizable.strings`
3. For each English string:
   - Translate naturally, not literally
   - Preserve format specifiers (`%@`, `%d`, etc.)
   - Keep technical terms (API names, commands) unchanged
   - Consider UI context (button labels should be concise)
4. Create the target language directory if needed
5. Write the translated `Localizable.strings` file
6. Report any strings that need human review (ambiguous context)

### For `validate [language]`:
1. Parse English `Localizable.strings` as the reference
2. For specified language (or all languages if omitted):
   - Check for missing keys
   - Check for extra keys (removed strings)
   - Check for untranslated strings (matching English exactly)
   - Check for broken format specifiers
3. Output a validation report with actionable items

### For `status`:
1. Count strings in English base
2. For each language directory found:
   - Count translated strings
   - Calculate percentage complete
3. Output a status table:
   ```
   Language    | Strings | Coverage
   ------------|---------|----------
   English     | 97      | 100% (base)
   Spanish     | 95      | 97.9%
   German      | 80      | 82.5%
   ```

### For `audit <language>`:
1. Read target language `Localizable.strings`
2. Review each translation for:
   - Consistency (same term translated differently)
   - Length issues (much longer than English, may overflow UI)
   - Tone consistency (formal vs informal)
   - Technical accuracy
3. Output audit findings with suggestions

### For `add-string <key>`:
1. Parse the key to determine domain (e.g., `settings.general_tab` -> Settings)
2. Ask for the English value
3. Ask for context/comment
4. Add to `Strings.swift` in appropriate enum
5. Add to `en.lproj/Localizable.strings`
6. For each existing language, add the key with `/* NEEDS TRANSLATION */` marker

---

## Language Codes

TermQ supports all 40 macOS languages:

| Code      | Language            | Code      | Language            |
|-----------|---------------------|-----------|---------------------|
| en        | English (base)      | pl        | Polish              |
| en-GB     | English (UK)        | ru        | Russian             |
| en-AU     | English (Australia) | uk        | Ukrainian           |
| es        | Spanish             | cs        | Czech               |
| es-419    | Spanish (Latin Am)  | sk        | Slovak              |
| fr        | French              | hu        | Hungarian           |
| fr-CA     | French (Canada)     | ro        | Romanian            |
| de        | German              | hr        | Croatian            |
| it        | Italian             | sl        | Slovenian           |
| pt        | Portuguese          | el        | Greek               |
| pt-PT     | Portuguese (Portugal)| tr       | Turkish             |
| nl        | Dutch               | he        | Hebrew              |
| sv        | Swedish             | ar        | Arabic              |
| da        | Danish              | th        | Thai                |
| fi        | Finnish             | vi        | Vietnamese          |
| no        | Norwegian           | id        | Indonesian          |
| zh-Hans   | Chinese (Simplified)| ms        | Malay               |
| zh-Hant   | Chinese (Traditional)| hi       | Hindi               |
| zh-HK     | Chinese (Hong Kong) | ca        | Catalan             |
| ja        | Japanese            |           |                     |
| ko        | Korean              |           |                     |

---

## Key Files

- `Sources/TermQ/Utilities/Strings.swift` - String key definitions
- `Sources/TermQ/Utilities/SupportedLanguage.swift` - Language picker model
- `Sources/TermQ/Resources/en.lproj/Localizable.strings` - English translations
- `Sources/TermQ/Resources/<lang>.lproj/Localizable.strings` - Other languages

## Scripts

- `scripts/localization/generate-translations.sh` - Create translation templates for all languages
- `scripts/localization/validate-strings.sh` - Validate all translations have matching keys
- `scripts/localization/extract-to-json.sh` - Export strings to JSON for LLM translation

---

## Examples

```bash
# Find all hardcoded strings
/localization extract

# Translate to Spanish
/localization translate es

# Check what's missing in German
/localization validate de

# See overall progress
/localization status

# Review Japanese translations
/localization audit ja

# Add a new string
/localization add-string settings.theme_label
```
