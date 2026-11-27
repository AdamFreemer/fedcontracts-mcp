# Status

_Last updated: 2026-11-27_

## Current milestone

**Milestone 5** — done. Next: Milestone 6.

## Milestones

| # | Milestone | Status |
|---|-----------|--------|
| 0 | Repo, docs, `/onboard`, Claude tooling | done |
| 1 | `rails new`, Postgres, RSpec, gems, `/up` | done |
| 2 | Migrations + models | done |
| 3 | `Usaspending::Client`, cassette, `AwardMapper` | done |
| 4 | `AwardSync` + rake tasks, 30-day local backfill | done |
| 5 | Query objects + specs | done |
| 6 | MCP endpoint + `search_awards`, verified in Inspector + Claude | not started |
| 7 | Remaining three tools | not started |
| 8 | rack-attack, input clamping, error handling | not started |
| 9 | Landing page | not started |
| 10 | Heroku deploy, backfill, scheduler, prod smoke test | not started |
| 11 | README, diagram, example prompts, screenshots | not started |
| 12 | Publish to MCP registry | not started |

## Next step

Milestone 6: `/mcp` endpoint + `search_awards` tool over `AwardSearch`. First verify against the `mcp` gem (1.11) README: stateless Streamable HTTP transport vs. a controller calling `handle_json`, structured vs. text content, and tool-error shape. Then check end to end in MCP Inspector and Claude, using the `examples.md` prompts.

## Blockers

None.

## Open questions / risks

1. **`expiring_contracts` coverage gap — confirmed at M3.** The award search can't filter on period-of-performance end (`date_type` is only `action_date`, `date_signed`, `last_modified_date`, `new_awards_only`). Contracts ending soon with no action in the sync window are missing. Decide at M7: a caveat in the tool description (cheapest), or a longer backfill window.
2. **Recipient upsert key can be null.** Resolved in schema: non-null unique `recipient_key` (USAspending ID, else normalized name). The mapper (M3) owns the normalization.
3. **Agency key — resolved at M3.** `Awarding Agency Code` is the toptier code (e.g. `070` = DHS). The API does not return abbreviations, so "DHS"-style matching needs `/api/v2/references/toptier_agencies/` in the sync (M4).
4. **`mcp` gem version / API.** Pinned `~> 1.11` (1.11.0 current). Confirm the transport and error shape at M6.
5. **Heroku Ruby version.** No `ruby` directive in the Gemfile, so `Gemfile.lock` has no `RUBY VERSION`. Confirm at M10 that the Heroku buildpack picks up 3.3.14 (add `ruby file: ".ruby-version"` if not).
6. **Descriptions are truncated to 250 chars** by the search API. Keyword search only sees that prefix. Acceptable for v1; mention it in the `search_awards` description.
7. **Paging cap — handled at M4.** Page-based paging fails with 422 past 50,000 results. The sync uses 30-day windows with `date_type: "action_date"`, which partition exactly (12 monthly counts summed to the 365-day total of 53,914; largest window ~7.7k).
8. **DoD has no recent data.** The 30-day local backfill had 0 DoD awards (90-day publication delay). Demo prompts should use civilian agencies (DHS, HHS, VA, Treasury), and tool descriptions must state the DoD delay.
9. **"Recent" vs. stored.** Of 3,297 awards with activity in the last 30 days, only 570 were signed in that window; the rest are older contracts with recent modifications (signed as far back as 2001). `recent_awards` must filter on `action_date` (signed), not just "is in the DB".
10. **Company acronyms aren't matched.** `company_profile(name: "GDIT")` finds nothing; the recipient is "GENERAL DYNAMICS INFORMATION TECHNOLOGY". Fine for v1; tool description should ask for the company's legal name.
11. **GIBCT contract not identified** (`examples.md` §2). Need Adam to confirm which VA contract or vendor covers it.

## Decisions log

- 2026-11-27: Rails app lives at the repo root (not a `fedcontracts/` subdirectory).
- 2026-11-27: One public repo, `fedcontracts-mcp` (default branch `master`). Registry name `io.github.adamfreemer/fedcontracts`. Positioning: curated hiring/recompete signals, not full USAspending coverage (that space is crowded).
- 2026-11-27: Planned `rails new . --api -d postgresql --skip-solid --skip-kamal --skip-test` (Heroku, single DB, RSpec).
- 2026-11-27: Claude tooling at project scope: `mcp-server-dev` and `playwright` plugins, Heroku MCP (`heroku mcp:start`) in `.mcp.json`. Use `gh` CLI instead of the GitHub MCP. No extra design plugins (`frontend-design` is enabled at user level).
- 2026-11-27: Heroku: Basic dyno or higher (Eco sleeps); Essential-0 Postgres should be enough.
- 2026-11-27: Rails 8.1 rather than pinning 8.0. (`rails new` used 8.1.3; the lockfile resolved to 8.1.4.1 under `~> 8.1.3`.)
- 2026-11-27: Ruby 3.3.14. Brakeman flagged a critical RCE in 3.3.6 (CVE-2026-132825). Built with RVM against Homebrew `openssl@3`: the default build mixed OpenSSL 1.1 libs with newer headers and failed.
- 2026-11-27: Kept the generated Rails CI (brakeman, bundler-audit, rubocop) and added an RSpec job. Kept the generated Dockerfile (unused on Heroku buildpacks).
- 2026-11-27: M1 pushed; CI green on all three jobs (scan_ruby, lint, test).
- 2026-11-27: M2 schema: `awards.recipient_id` and `awarding_agency_id` are NOT NULL FKs; `raw` jsonb defaults to `{}`; `sync_runs.status` is a string enum (running/succeeded/failed); `SyncRun.data_freshness` = latest successful `finished_at`. Trigram index on `awards.description` only, per spec; fuzzy name indexes (recipients, agencies) deferred to M5 when the queries exist.
- 2026-11-27: M3 `Award.action_date` = USAspending `Base Obligation Date` (date signed). The search API doesn't expose the latest transaction date, and the signed date is the better "who just won work" signal for `recent_awards`. The raw record keeps `Last Modified Date`.
- 2026-11-27: M3 sync request omits `date_type`, so the API default applies: latest action on/after the window start, signed on/before its end. Sort is `Base Obligation Date` desc (stable, unlike `Last Modified Date`).
- 2026-11-27: M3 retries on 429/5xx/timeouts (4 retries, exponential backoff with jitter); 4xx like 422 fail fast. Cassettes strip `Set-Cookie`.
- 2026-11-27: M4 sync uses `date_type: "action_date"` (not the API default). Same set of contracts over the full range, but adjacent windows don't overlap: the default would fetch ~240k records to get 54k.
- 2026-11-27: M4 agency abbreviations come from `/api/v2/references/toptier_agencies/`, fetched once per run. National Gallery of Art and Smithsonian have none upstream.
- 2026-11-27: M4 30-day local backfill: 3,297 awards (matches the API count exactly), 1,066 recipients, 54 agencies, 0 skipped, ~29s. Re-running is idempotent.
- 2026-11-27: M5 agency matching: toptier abbreviation, or sub-agency acronym derived from its name (USCIS, FEMA, CBP; aliases for CMS and CDC); only if no acronym matches, a 4+ character name fragment. Prevents "ICE" matching "Justice".
- 2026-11-27: M5 company matching groups recipient rows by normalized name (Leidos has 5 UEIs under one name). Exact UEI > exact name > substring > trigram. Trigram-only matches are always returned as candidates, never as a profile ("Excella" must not silently become "Excelous").
- 2026-11-27: M5 `recent_awards` and `search_awards` window on `action_date` (signed). `expiring_contracts` on `end_date`. Company trend = last 8 calendar quarters by signed date, zero-filled.
- 2026-11-27: Added `examples.md`: DID(IT) II (Excella/USCIS, ended 2026-10-15) and GIBCT (contract TBD) as reference cases for specs and demos.
