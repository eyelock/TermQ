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

4. **Check for uncompressed images** — if any PNG files in `Docs/` are being added or modified
   in this push, check for large files:
   ```bash
   git diff --name-only origin/<base>..HEAD -- 'Docs/**/*.png'
   ```
   For each PNG in the diff, check its size. If any file is larger than 300 KB, stop and warn:
   > "Large image detected: <path> (<size>). Run `make compress-images` before pushing."
   Do not proceed until the user confirms they want to push anyway, or the images are compressed.

5. **Ensure the branch is up-to-date** with the base:
   ```bash
   git fetch origin <base>
   git log HEAD..origin/<base> --oneline   # if output, merge before pushing
   git merge origin/<base>
   ```

6. **Push the branch** to origin.

7. **Create a PR** with an explicit base — use the commit-conventions skill for title and
   description format:
   ```bash
   gh pr create --base <base> --title "<title>" --body "<body>"
   ```

8. **Monitor CI** — report each check's status as it completes.

9. When all CI checks pass, report the result and **ask before merging**:
   ```bash
   gh pr merge --squash
   ```

10. After merge: clean up the branch and worktree.
    Follow the post-merge cleanup steps in the commit-conventions skill exactly — order matters
    to avoid CWD becoming invalid. Feature branches verify against `origin/develop`;
    `develop` and `hotfix/*` verify against `origin/main`.
