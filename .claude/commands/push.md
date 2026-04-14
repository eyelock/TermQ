# /push — Push, PR, CI, and Merge

Push committed work, open a PR targeting the correct base branch, monitor CI, and merge when ready.

1. **Determine the base branch** from the current branch name:
   - `develop` or `hotfix/*` → base is `main`
   - Any other branch → base is `develop`

2. **Review commit count** — run `git log origin/<base>..HEAD --oneline`. Since this project
   squash-merges, lean toward 1–3 commits per PR. WIP checkpoints, format commits, and
   implementation-journey fixes should be squashed away before pushing. See commit-conventions
   skill for guidance.

3. **Invoke the logging-auditor agent** on all changed Swift files before pushing.

4. **Ensure the branch is up-to-date** with the base:
   ```bash
   git fetch origin <base>
   git log HEAD..origin/<base> --oneline   # if output, merge before pushing
   git merge origin/<base>
   ```

5. **Push the branch** to origin.

6. **Create a PR** with an explicit base — use the commit-conventions skill for title and
   description format:
   ```bash
   gh pr create --base <base> --title "<title>" --body "<body>"
   ```

7. **Monitor CI** — report each check's status as it completes.

8. When all CI checks pass, report the result and **ask before merging**:
   ```bash
   gh pr merge --squash
   ```

9. After merge: delete the remote branch, local branch, and worktree if applicable.
   Consult commit-conventions skill for cleanup steps — feature branches verify against
   `origin/develop`; `develop` and `hotfix/*` verify against `origin/main`.
