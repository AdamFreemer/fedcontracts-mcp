# Status

_Last updated: 2026-11-27_

## Current milestone

**Milestone 2** — done. Next: Milestone 3.

## Milestones

| # | Milestone | Status |
|---|-----------|--------|
| 0 | Repo, docs, `/onboard`, Claude tooling | done |
| 1 | `rails new`, Postgres, RSpec, gems, `/up` | done |
| 2 | Migrations + models | done |
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

Milestone 3: verify `spending_by_award` field names and filters against the API docs, build `Usaspending::Client`, record one real cassette, build `AwardMapper` from it. Resolve risks 1 and 3 there.

## Blockers

None.

## Open questions / risks

1. **`expiring_contracts` coverage gap.** The sync filters by transaction action date (last 365 days). Contracts that end soon but had no recent action won't be in the DB. Check at M3 whether the API can filter on period-of-performance end; otherwise add a second sync pass or a caveat in the tool description.
2. **Recipient upsert key can be null.** Resolved in schema: non-null unique `recipient_key` (USAspending ID, else normalized name). The mapper (M3) owns the normalization.
3. **Agency `toptier_code` may be missing** from `spending_by_award` fields. Confirm against the cassette at M3; may need `/api/v2/references/toptier_agencies/`. The schema makes it `NOT NULL UNIQUE`, so loosen that or switch the key if the field isn't there.
4. **`mcp` gem version / API.** Pinned `~> 1.11` (1.11.0 current). Confirm the transport and error shape at M6.
5. **Heroku Ruby version.** No `ruby` directive in the Gemfile, so `Gemfile.lock` has no `RUBY VERSION`. Confirm at M10 that the Heroku buildpack picks up 3.3.14 (add `ruby file: ".ruby-version"` if not).

## Decisions log

- 2026-11-27: Rails app lives at the repo root (not a `fedcontracts/` subdirectory).
- 2026-11-27: One public repo, `fedcontracts-mcp` (default branch `master`). Registry name `io.github.adamfreemer/fedcontracts`. Positioning: curated hiring/recompete signals, not full USAspending coverage (that space is crowded).
- 2026-11-27: Planned `rails new . --api -d postgresql --skip-solid --skip-kamal --skip-test` (Heroku, single DB, RSpec).
- 2026-11-27: Claude tooling at project scope: `mcp-server-dev` and `playwright` plugins, Heroku MCP (`heroku mcp:start`) in `.mcp.json`. Use `gh` CLI instead of the GitHub MCP. No extra design plugins (`frontend-design` is enabled at user level).
- 2026-11-27: Heroku: Basic dyno or higher (Eco sleeps); Essential-0 Postgres should be enough.
- 2026-11-27: Rails 8.1.3 (current gem) rather than pinning 8.0.
- 2026-11-27: Ruby 3.3.14. Brakeman flagged a critical RCE in 3.3.6 (CVE-2026-132825). Built with RVM against Homebrew `openssl@3`: the default build mixed OpenSSL 1.1 libs with newer headers and failed.
- 2026-11-27: Kept the generated Rails CI (brakeman, bundler-audit, rubocop) and added an RSpec job. Kept the generated Dockerfile (unused on Heroku buildpacks).
- 2026-11-27: M1 pushed; CI green on all three jobs (scan_ruby, lint, test).
- 2026-11-27: M2 schema: `awards.recipient_id` and `awarding_agency_id` are NOT NULL FKs; `raw` jsonb defaults to `{}`; `sync_runs.status` is a string enum (running/succeeded/failed); `SyncRun.data_freshness` = latest successful `finished_at`. Trigram index on `awards.description` only, per spec; fuzzy name indexes (recipients, agencies) deferred to M5 when the queries exist.
