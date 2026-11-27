# Status

_Last updated: 2026-11-27_

## Current milestone

**Phase 0: Project setup** (pre-Milestone 1) — in progress

## Milestones

| # | Milestone | Status |
|---|-----------|--------|
| 0 | Repo, docs, `/onboard`, Claude tooling | in progress |
| 1 | `rails new`, Postgres, RSpec, gems, `/up` | not started |
| 2 | Migrations + models | not started |
| 3 | `Usaspending::Client`, cassette, `AwardMapper` | not started |
| 4 | `AwardSync` + rake tasks, 30-day local backfill | not started |
| 5 | Query objects + specs | not started |
| 6 | MCP endpoint + `search_awards`, verified in Inspector + Claude | not started |
| 7 | Remaining three tools | not started |
| 8 | rack-attack, input clamping, error handling | not started |
| 9 | Landing page | not started |
| 10 | Heroku deploy, backfill, scheduler, prod smoke test | not started |
| 11 | README, diagram, example prompts, screenshots | not started |
| 12 | Publish to MCP registry | not started |

## Next step

Restart Claude Code so project plugins load, verify tooling, then start Milestone 1.

## Blockers

None.

## Open questions / risks

1. **`expiring_contracts` coverage gap.** The sync filters by transaction action date (last 365 days). Contracts that end soon but had no recent action won't be in the DB. Check at M3 whether the API can filter on period-of-performance end; otherwise add a second sync pass or a caveat in the tool description.
2. **Recipient upsert key can be null.** Plan: a non-null `recipient_key` column (USAspending ID, else normalized name) with a unique index.
3. **Agency `toptier_code` may be missing** from `spending_by_award` fields. Confirm against the cassette at M3; may need `/api/v2/references/toptier_agencies/`.
4. **`mcp` gem version / API.** Pin the current release; confirm the transport and error shape at M6.

## Decisions log

- 2026-11-27: Rails app lives at the repo root (not a `fedcontracts/` subdirectory).
- 2026-11-27: One public repo, `fedcontracts-mcp` (default branch `master`). Registry name `io.github.adamfreemer/fedcontracts`. Positioning: curated hiring/recompete signals, not full USAspending coverage (that space is crowded).
- 2026-11-27: Planned `rails new . --api -d postgresql --skip-solid --skip-kamal --skip-test` (Heroku, single DB, RSpec).
- 2026-11-27: Claude tooling at project scope: `mcp-server-dev` and `playwright` plugins, Heroku MCP (`heroku mcp:start`) in `.mcp.json`. Use `gh` CLI instead of the GitHub MCP. No extra design plugins (`frontend-design` is enabled at user level).
- 2026-11-27: Heroku: Basic dyno or higher (Eco sleeps); Essential-0 Postgres should be enough.
