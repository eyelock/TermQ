# /push — Push, PR, CI, and Merge

Push committed work, open a PR, monitor CI, and merge when ready.

1. **Review commit count** — run `git log origin/main..HEAD --oneline`. Since this project squash-merges, lean toward 1–3 commits per PR. WIP checkpoints, format commits, and implementation-journey fixes should be squashed away before pushing. See commit-conventions skill for guidance.
2. Invoke the logging-auditor agent on all changed files before pushing
3. Ensure the branch is up-to-date with main:
   ```bash
   git fetch origin main
   git log HEAD..origin/main --oneline   # if output, merge before pushing
   git merge origin/main
   ```
3. Push the branch to origin
4. Create a PR using the commit-conventions skill for title and description format
5. Monitor CI — report each check's status as it completes
6. When all CI checks pass, report the result and **ask before merging**
7. After merge: delete the remote branch, local branch, and worktree if applicable (consult commit-conventions skill for cleanup steps)
