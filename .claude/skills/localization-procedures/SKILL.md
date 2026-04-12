---
name: localization-procedures
description: TermQ localization workflows. Load when performing any localization task — extracting strings, translating, validating, auditing, or syncing language files.
---

# Localization Procedures

## Key Files

- `Sources/TermQ/Utilities/Strings.swift` — string key definitions (enum-based)
- `Sources/TermQ/Resources/en.lproj/Localizable.strings` — English base (source of truth)
- `Sources/TermQ/Resources/<lang>.lproj/Localizable.strings` — per-language files
- `scripts/localization/validate-strings.sh` — validates all 40 language files have matching keys
- `scripts/localization/generate-translations.sh` — creates translation templates
- `scripts/localization/extract-to-json.sh` — exports strings to JSON for translation

## Invariant: Never Ship Untranslated Strings

**`/* NEEDS TRANSLATION */` markers must never be committed or released.** They are a temporary scaffold only — their presence in any committed file is a localization failure.

- `validate` must fail (not warn) if any `/* NEEDS TRANSLATION */` marker exists in any language file
- `sync` must be followed immediately by `translate` for every affected language before any commit
- `add-string` must translate into all languages before committing — not just add placeholders
- Any release check that finds `/* NEEDS TRANSLATION */` markers must block the release

If translation cannot be completed right now, do not commit. Hold the English key addition until translations are ready.

## Actions

### extract — Find hardcoded strings

1. Search all Swift files in `Sources/TermQ/` for quoted strings
2. Filter out: `Strings.*` or `String(localized:)` calls, SF Symbol names, file paths, identifiers, debug/log strings
3. Group findings by file
4. For each string found, suggest: key name following `domain.action` convention, which `Strings.*` enum it belongs to
5. Output a summary table

### translate `<language>` — Translate to target language

1. Read `en.lproj/Localizable.strings`
2. Create or open `<language>.lproj/Localizable.strings`
3. For each English string: translate naturally (not literally), preserve format specifiers (`%@`, `%d`), keep technical terms unchanged, keep button labels concise
4. Create the language directory if needed
5. Report strings needing human review (ambiguous context)

### validate `[language]` — Check for missing strings

1. Parse English file as reference
2. For the specified language (or all if omitted): check missing keys, extra keys, untranslated strings (matching English exactly), broken format specifiers, `/* NEEDS TRANSLATION */` markers
3. **FAIL** (not warn) if any `/* NEEDS TRANSLATION */` marker is found — these must be translated before this check can pass
4. Output actionable report

### status — Show translation coverage

Count strings per language, calculate percentage vs English base.

Output table: Language | Strings | Coverage

### audit `<language>` — Review translation quality

Review for: consistency (same term translated differently), length issues (much longer than English), tone consistency, technical accuracy.

### add-string `<key>` — Add a new localizable string

1. Parse the key to determine domain (e.g., `settings.general_tab` → Settings enum)
2. Ask for English value and context/comment
3. Add to `Strings.swift` in appropriate enum
4. Add to `en.lproj/Localizable.strings`
5. Translate into all 39 non-English language files (see `translate` workflow)
6. Run `validate` to confirm zero `/* NEEDS TRANSLATION */` markers before committing

Do not commit after step 4 alone. The English addition and all translations must land in the same commit.

### sync — Sync missing keys to all languages

Sync is a two-phase operation. Both phases must complete before committing.

**Phase 1 — Identify and scaffold:**
1. Read English base
2. For each language: find keys in English but missing in target
3. Note which keys are missing — do not write placeholders to disk yet

**Phase 2 — Translate and write:**
1. For each missing key in each language: produce a proper native translation (see `translate` workflow)
2. Write the translated values directly — no `/* NEEDS TRANSLATION */` markers
3. Run `./scripts/localization/validate-strings.sh` to verify all keys present and no markers remain
4. Report keys added per language

If translation cannot be completed (e.g. awaiting external translators), do not commit the English key addition either. Keep both changes together.

## String Key Convention

Format: `domain.action` or `domain.noun`

Examples: `settings.general_tab`, `editor.field_title`, `terminal.close_button`

Keys map to enum cases in `Strings.swift`. Match the enum structure to the UI hierarchy.

## Supported Languages (40 total)

en, en-GB, en-AU, es, es-419, fr, fr-CA, de, it, pt, pt-PT, nl, sv, da, fi, no, zh-Hans, zh-Hant, zh-HK, ja, ko, pl, ru, uk, cs, sk, hu, ro, hr, sl, el, tr, he, ar, th, vi, id, ms, hi, ca
