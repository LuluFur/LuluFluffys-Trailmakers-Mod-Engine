# LuluFluffy's Trailmakers Mod Engine

## Description
Modding engine / framework for Trailmakers. Scope TBD — to be expanded as design
decisions are made (engine architecture, mod loading model, target Trailmakers
runtime, scripting surface, etc.).

## Stack
TBD

## Strict Git Rules

These rules are non-negotiable. Violations require an explicit user override per-action.

### Branching
- `main` is protected. **Never** commit, merge, push, rebase, or reset directly on `main`.
- All work happens on a feature branch created from up-to-date `main`:
  - `feat/<short-kebab-desc>` — new functionality
  - `fix/<short-kebab-desc>` — bug fixes
  - `chore/<short-kebab-desc>` — tooling, deps, CI, non-code changes
  - `refactor/<short-kebab-desc>` — behavior-preserving restructures
  - `docs/<short-kebab-desc>` — documentation only
  - `test/<short-kebab-desc>` — tests only
  - `perf/<short-kebab-desc>` — performance work
- Branch names are lowercase kebab-case after the type prefix. No spaces, no underscores, no capitals.
- One branch = one logical change. Do not pile unrelated work onto a feature branch.
- Delete the branch (local + remote) immediately after merge.

### Commits
- **Conventional Commits, mandatory:** `type(scope): description`
  - Allowed types: `feat`, `fix`, `chore`, `refactor`, `test`, `docs`, `perf`, `style`, `ci`, `build`.
  - `scope` is required when the change is localized (e.g. `feat(loader): ...`). Omit only for repo-wide changes.
  - Description is imperative mood, lowercase, no trailing period, ≤ 72 chars on the subject line.
- Atomic commits: one commit = one logical change. If the diff needs the word "and" to describe it, split it.
- Body (optional) explains **why**, not what. Wrap at 72 chars. Separate from subject with a blank line.
- Breaking changes use `!` and a `BREAKING CHANGE:` footer: `feat(api)!: rename mod entrypoint`.
- Reference issues in the footer: `Refs: #12` or `Closes: #12`.
- **Never** use `--amend` on a commit that has been pushed.
- **Never** use `--no-verify` to bypass hooks. Fix the underlying failure.
- **Never** commit secrets, credentials, API keys, `.env` files, or large binaries.
- **Never** commit generated artifacts (`dist/`, `build/`, `node_modules/`, lockfile churn-only diffs).

### Pushing
- First push of a branch: `git push -u origin <branch>`.
- **Never** force-push to `main`. Period.
- Force-push to a feature branch is allowed only as `git push --force-with-lease` and only on a branch you own that has not been merged or reviewed by someone else.
- Always pull with `--rebase` (`git pull --rebase`), never with a merge commit on feature branches.

### Pull Requests
- All changes land via PR. No exceptions.
- PR title follows the same Conventional Commits format as the squash commit it will produce.
- PR description must include: **Summary**, **Why**, **Test plan**, and link to any tracking issue.
- PRs must be small. Target < 400 lines diff; split if larger.
- CI must be green before merge. No merging red builds.
- Merge strategy: **squash and merge** only. No merge commits, no rebase-merge on this repo.
- After merge: branch is auto-deleted (`gh pr merge --squash --auto --delete-branch`).
- Self-merge is permitted (solo project) but the PR must still exist for the audit trail.

### History & Recovery
- History on `main` is append-only. **Never** rewrite published history.
- Destructive ops (`reset --hard`, `clean -fdx`, `branch -D`, `checkout -- .`, `restore --staged .`) require explicit user confirmation per invocation.
- If recovering from a mistake, prefer `git revert` over `reset` on anything pushed.
- Use `git stash` (not `checkout .`) to set work aside.

### Repo Hygiene
- `.gitignore` is the single source of truth for ignored files. Don't `git add -f` past it without a reason in the commit body.
- LF line endings in the repo; `.gitattributes` enforces this if cross-platform issues appear.
- Tags are immutable. Releases use annotated tags: `git tag -a v0.1.0 -m "release v0.1.0"`.
- Semantic versioning: `MAJOR.MINOR.PATCH`.

### Hard No
- No direct commits to `main`.
- No force-push to `main`.
- No `--no-verify`.
- No `--amend` after push.
- No secrets in history.
- No `git config` changes without user approval.
- No interactive flags (`-i`) in automated runs.
