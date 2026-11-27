---
description: Re-orient on this project from its docs and repo state, then propose the next step
---

You are picking up the FedContracts MCP project, possibly in a fresh session with no prior context.

1. Read `CLAUDE.md`, `status.md`, and `onboard.md` in the repo root.
2. Check the repo state: `git status --short`, `git log --oneline -15`, and the current branch.
3. Check the environment and note any failures (don't fix them yet):
   - `bundle check` (if a Gemfile exists)
   - `bin/rails db:version` (if a Rails app exists)
   - `heroku auth:whoami` and `gh auth status`
4. Report back concisely:
   - Current milestone and what's done
   - Uncommitted work, or anything in git that disagrees with `status.md` (flag drift)
   - Environment problems found
   - Open blockers/risks from `status.md`
   - The proposed next step, as a short plan with verification checks
5. Stop and wait for the user's go-ahead before making changes.

$ARGUMENTS
