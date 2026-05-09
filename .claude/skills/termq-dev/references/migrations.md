# Migrations

Migration code in TermQ — one-shot upgrades that read legacy state and rewrite it to the current shape — has historically been written ad-hoc in whatever file needed it: a method on the persistence type here, an `init(from:)` decoder fallback there, a `didRunOnce` flag on a repository somewhere else.

This drifts. Removing a finished migration becomes archaeology: where was it called from, what tests assumed the legacy shape, did anyone else add a sympathetic fallback?

The right shape exists on the YNH side already and is the model TermQ should follow.

## Reference: YNH's filter-chain

`/Users/david/Storage/Workspace/eyelock/ynh/internal/migration/migration.go` defines:

```go
// Migrator is a single format migration step.
type Migrator interface {
    Applies(dir string) bool
    Run(dir string) error
    Description() string
}

// Chain is an ordered list of migrators.
type Chain []Migrator

func (c Chain) Run(dir string) ([]string, error) { ... }
```

Each migration is a single struct in its own file. Loaders call `DefaultChain().Run(dir)` before reading. Removing a legacy format = delete the migrator file and unregister it from `DefaultChain`. **No other code changes.**

## TermQ status

TermQ does not yet have an equivalent module. Issue [#295](https://github.com/eyelock/TermQ/issues/295) tracks the refactor.

Until that lands, migration-shaped code already lives in main paths in:

- `Sources/TermQ/ViewModels/YNHPersistence.swift` — `migrateLegacyHarnessKeys`, `migrateCanonicalIds`
- `Sources/TermQ/Services/HarnessRepository.swift` — `didRunIdentityMigration` flag and the `migrateLegacyHarnessKeys` call in `refresh()`
- `Sources/TermQ/Services/HarnessMigrationCoordinator.swift` — full coordinator
- `Sources/TermQ/Views/ContentView.swift` — `runMigrationIfNeeded()` + onChange wiring
- `Sources/TermQ/Services/EncryptionKeyStore.swift` — legacy keychain item migration
- `Sources/TermQShared/LocalYNHConfig.swift` — `init(from:)` absent-field backward compat

These are correct in isolation; they're owed to the chain when it's built.

## Rule for new migrations

**If you're about to add a new migration, stop and consider where it goes.**

- If issue #295 has been resolved and the chain exists: add a single migrator file, register in the chain, no other changes.
- If the chain doesn't exist yet:
  1. Add it.
  2. Move the new migration into it.
  3. Optionally fold one or two of the existing scattered migrations in as the same PR's example.
  4. Update issue #295's checklist with what's now extracted.

**Do not** add another scattered migration "just for now" — every one of those is a future archaeology project and a future-you trap. The pattern of "scope-creep migration into the file that happens to need it" is exactly what got TermQ here.

## Identifying migration code in review

Code is migration-shaped if any of these are true:

- It reads state in one shape and writes it back in another.
- It runs once per session/launch and is gated by a `didRun*` flag.
- It tolerates an absent / legacy field via `init(from decoder:)` or `?? defaultValue`.
- It exists to bridge between an old release and a new one and is expected to be removable later.

If a piece of code is migration-shaped, it should live in the migration module, not in the main code path that needs it. Reviewers should push back on PRs that put new migration logic in `*Repository`, `*Persistence`, `*Coordinator`, view models, or view bodies.

## When in doubt

If you're unsure whether something is migration-shaped, ask:

> *Will I want to delete this code in six months when nobody is on the old version anymore?*

If yes, it's migration. Treat it as migration even before #295 lands — at minimum, isolate it in a clearly-named function with a comment noting the version boundary, so the eventual extraction is mechanical.
