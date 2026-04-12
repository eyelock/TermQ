# /push — Push, PR, CI, and Merge

Push committed work, open a PR, monitor CI, and merge when ready.

1. Invoke the logging-auditor agent on all changed files before pushing
2. Ensure the branch is up-to-date with main:
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
