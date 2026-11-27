# Status

_Last updated: 2026-11-27_

## Current milestone

**Milestone 1** — done (committed locally, not yet pushed). Next: Milestone 2.

## Milestones

| # | Milestone | Status |
|---|-----------|--------|
| 0 | Repo, docs, `/onboard`, Claude tooling | done |
| 1 | `rails new`, Postgres, RSpec, gems, `/up` | done |
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

Push `master` and confirm all three CI jobs pass (`scan_ruby`, `lint`, `test`). Then Milestone 2: migrations and models for agencies, recipients, awards, sync_runs (with `recipient_key` and `pg_trgm`).

## Blockers

None.

## Open questions / risks

1. **`expiring_contracts` coverage gap.** The sync filters by transaction action date (last 365 days). Contracts that end soon but had no recent action won't be in the DB. Check at M3 whether the API can filter on period-of-performance end; otherwise add a second sync pass or a caveat in the tool description.
2. **Recipient upsert key can be null.** Plan: a non-null `recipient_key` column (USAspending ID, else normalized name) with a unique index.
3. **Agency `toptier_code` may be missing** from `spending_by_award` fields. Confirm against the cassette at M3; may need `/api/v2/references/toptier_agencies/`.
4. **`mcp` gem version / API.** Pinned `~> 1.11` (1.11.0 current). Confirm the transport and error shape at M6.
5. **Heroku Ruby version.** No `ruby` directive in the Gemfile, so `Gemfile.lock` has no `RUBY VERSION`. Confirm at M10 that the Heroku buildpack picks up 3.3.14 (add `ruby file: ".ruby-version"` if not).
6. **CI is unverified.** The test job (Postgres 16 service) passes locally only until pushed.

## Decisions log

- 2026-11-27: Rails app lives at the repo root (not a `fedcontracts/` subdirectory).
- 2026-11-27: One public repo, `fedcontracts-mcp` (default branch `master`). Registry name `io.github.adamfreemer/fedcontracts`. Positioning: curated hiring/recompete signals, not full USAspending coverage (that space is crowded).
- 2026-11-27: Planned `rails new . --api -d postgresql --skip-solid --skip-kamal --skip-test` (Heroku, single DB, RSpec).
- 2026-11-27: Claude tooling at project scope: `mcp-server-dev` and `playwright` plugins, Heroku MCP (`heroku mcp:start`) in `.mcp.json`. Use `gh` CLI instead of the GitHub MCP. No extra design plugins (`frontend-design` is enabled at user level).
- 2026-11-27: Heroku: Basic dyno or higher (Eco sleeps); Essential-0 Postgres should be enough.
- 2026-11-27: Rails 8.1.3 (current gem) rather than pinning 8.0.
- 2026-11-27: Ruby 3.3.14. Brakeman flagged a critical RCE in 3.3.6 (CVE-2026-132825). Built with RVM against Homebrew `openssl@3`: the default build mixed OpenSSL 1.1 libs with newer headers and failed.
- 2026-11-27: Kept the generated Rails CI (brakeman, bundler-audit, rubocop) and added an RSpec job. Kept the generated Dockerfile (unused on Heroku buildpacks).
