# Status

_Last updated: 2026-11-27_

## Current milestone

**Milestone 3** — done. Next: Milestone 4.

## Milestones

| # | Milestone | Status |
|---|-----------|--------|
| 0 | Repo, docs, `/onboard`, Claude tooling | done |
| 1 | `rails new`, Postgres, RSpec, gems, `/up` | done |
| 2 | Migrations + models | done |
| 3 | `Usaspending::Client`, cassette, `AwardMapper` | done |
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

Milestone 4: `AwardSync` + `sync:backfill` / `sync:incremental`, then a 30-day local backfill and eyeball the data. Must:
- Chunk the time window (e.g. 30-day slices) to stay under the API's 50,000-result paging cap (risk 7).
- Upsert agencies and recipients first, then awards with resolved FKs; count and skip `AwardMapper::InvalidRecord`.
- Fill agency abbreviations from `/api/v2/references/toptier_agencies/` (risk 3).
- Read NAICS from ENV `SYNC_NAICS` with the spec default.

## Blockers

None.

## Open questions / risks

1. **`expiring_contracts` coverage gap — confirmed at M3.** The award search can't filter on period-of-performance end (`date_type` is only `action_date`, `date_signed`, `last_modified_date`, `new_awards_only`). Contracts ending soon with no action in the sync window are missing. Decide at M7: a caveat in the tool description (cheapest), or a longer backfill window.
2. **Recipient upsert key can be null.** Resolved in schema: non-null unique `recipient_key` (USAspending ID, else normalized name). The mapper (M3) owns the normalization.
3. **Agency key — resolved at M3.** `Awarding Agency Code` is the toptier code (e.g. `070` = DHS). The API does not return abbreviations, so "DHS"-style matching needs `/api/v2/references/toptier_agencies/` in the sync (M4).
4. **`mcp` gem version / API.** Pinned `~> 1.11` (1.11.0 current). Confirm the transport and error shape at M6.
5. **Heroku Ruby version.** No `ruby` directive in the Gemfile, so `Gemfile.lock` has no `RUBY VERSION`. Confirm at M10 that the Heroku buildpack picks up 3.3.14 (add `ruby file: ".ruby-version"` if not).
6. **Descriptions are truncated to 250 chars** by the search API. Keyword search only sees that prefix. Acceptable for v1; mention it in the `search_awards` description.
7. **Paging cap.** Page-based paging fails with 422 past 50,000 results (`page * limit`). A 365-day IT backfill is ~54k contracts. The cursor alternative (`last_record_*`) is labelled experimental, so the sync chunks the window instead.

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
- 2026-11-27: M3 `Award.action_date` = USAspending `Base Obligation Date` (date signed). The search API doesn't expose the latest transaction date, and the signed date is the better "who just won work" signal for `recent_awards`. The raw record keeps `Last Modified Date`.
- 2026-11-27: M3 sync request omits `date_type`, so the API default applies: latest action on/after the window start, signed on/before its end. Sort is `Base Obligation Date` desc (stable, unlike `Last Modified Date`).
- 2026-11-27: M3 retries on 429/5xx/timeouts (4 retries, exponential backoff with jitter); 4xx like 422 fail fast. Cassettes strip `Set-Cookie`.
