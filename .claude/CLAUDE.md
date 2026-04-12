# Claude — TermQ

## Architecture

Three tiers. Each has a distinct role:

```
/command        User invokes → thin orchestration script
    ↓
Agent           Specialist worker, own context window, skills preloaded
    ↓
Skill           Domain knowledge library, portable, self-contained
```

**At session start:** Load the `termq-dev` skill. Run `git status`. Check `.claude/sessions/` for handover notes.

---

## ABSOLUTE RULE — NEVER COMMIT DIRECTLY TO MAIN

**Direct commits to `main` are forbidden without exception.**

Every change — no matter how small, urgent, or "obvious" — goes through a branch and PR:

```
git checkout -b fix-<description>   # always start here
... implement ...
/verify
/commit
/push                               # opens PR, CI runs, user merges
```

There is no urgency, no hotfix, no one-liner that justifies bypassing this. If there is a genuine technical reason to land directly on main, the user must explicitly instruct it. Never decide this unilaterally.

---

## Core Development Workflow

For all features, fixes, and refactoring:

**Before coding:** Follow the implementation prep steps in the `termq-dev` skill (session-start reference). Do not use Edit or Write tools until context is gathered, files are read, and baseline passes.

### 0. Create a branch
```bash
git checkout -b <type>-<description>
```
This is not optional. Do it before any code changes.

### 1. Implement ↔ 2. Verify (loop until clean)

**Implement** — write code following the `code-style` skill

**Verify** → `/verify` — reviewer runs the quality gate + code analysis; localizer validates if UI files changed

Findings from /verify must be resolved before moving on.

### 3. Commit
→ `/commit` — local commit using `commit-conventions` skill for format

### 4. Push
→ `/push` — logging-auditor runs, then push branch, open PR, monitor CI, ask before merging

---

## Release Workflows

| Command | What it does |
|---|---|
| `/release` | Stable release from main |
| `/release-beta` | Beta pre-release from main |
| `/release-hotfix` | Critical patch from a tagged base |

All three invoke the `releaser` agent, which uses the `release` skill.

---

## Agents

| Agent | Auto-triggered when | Also invoked by |
|---|---|---|
| `termq-explorer` | Preparing for implementation | — |
| `reviewer` | Code changes are made | `/verify` |
| `logging-auditor` | Files touching logging change | `/push` |
| `localizer` | Localization work needed | `/localization` |
| `releaser` | Release requested | `/release*` |

---

## Skills

| Skill | Contains |
|---|---|
| `termq-dev` | Project structure, module map, toolchain rules, worktrees, settings architecture |
| `quality-gate` | The four checks that must pass before committing (build, lint, format, tests) |
| `code-style` | Swift 6 concurrency, error handling, memory management, UI components, testing |
| `logging-rules` | Logging privacy boundaries — app-wide, treat terminal output as user data |
| `localization-procedures` | Translation workflows, language codes, file paths, scripts |
| `commit-conventions` | Branch naming, commit format, PR template, merge rules |
| `release` | Stable, beta, and hotfix release procedures |

Skills are self-contained and portable. They do not reference project files, other skills, or commands. CLAUDE.md and commands reference skills — not the other way around.

---

## Standards

Every CI run consumes energy. The `quality-gate` skill defines what must pass locally before any push. If local checks pass but CI fails, that is a bug — investigate and file an issue.

---

## Directory Structure

```
.claude/
├── CLAUDE.md                  ← this file — navigation hub
├── settings.json              ← project permissions (committed, follows worktrees)
├── settings.local.json        ← personal overrides (gitignored)
├── commands/                  ← user-invocable LLM scripts (thin orchestrators)
│   ├── verify.md
│   ├── commit.md
│   ├── push.md
│   ├── localization.md
│   ├── release.md
│   ├── release-beta.md
│   └── release-hotfix.md
├── agents/                    ← sub-agent definitions
│   ├── termq-explorer.md
│   ├── reviewer.md
│   ├── logging-auditor.md
│   ├── localizer.md
│   └── releaser.md
├── skills/                    ← domain knowledge (agentskills.io format)
│   ├── termq-dev/
│   ├── quality-gate/
│   ├── code-style/
│   ├── logging-rules/
│   ├── localization-procedures/
│   ├── commit-conventions/
│   └── release/
├── plans/                     ← implementation plans (gitignored)
└── sessions/                  ← session handovers (gitignored)
```

---

## Choose Your Adventure

**Starting a session?**
→ Load `termq-dev` skill, `git status`, check `.claude/sessions/`

**Working on a feature or fix?**
→ implement → `/verify` → `/commit` → `/push`

**Localization work?**
→ `/localization <action> [language]`

**Creating a release?**
→ `/release`, `/release-beta`, or `/release-hotfix`

**Investigating only (no planned changes)?**
→ Use `termq-explorer` directly — no need for the full workflow

**Doc-only changes?**
→ Skip `/verify`, just `/commit` → `/push`
