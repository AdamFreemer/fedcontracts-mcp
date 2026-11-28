# Status

_Last updated: 2026-11-27_

## Current milestone

**Milestone 9** — done. Next: Milestone 10 (deploy; needs Adam for account steps).

## Milestones

| # | Milestone | Status |
|---|-----------|--------|
| 0 | Repo, docs, `/onboard`, Claude tooling | done |
| 1 | `rails new`, Postgres, RSpec, gems, `/up` | done |
| 2 | Migrations + models | done |
| 3 | `Usaspending::Client`, cassette, `AwardMapper` | done |
| 4 | `AwardSync` + rake tasks, 30-day local backfill | done |
| 5 | Query objects + specs | done |
| 6 | MCP endpoint + `search_awards`, verified in Inspector + Claude | done |
| 7 | Remaining three tools | done |
| 8 | rack-attack, input clamping, error handling | done |
| 9 | Landing page | done |
| 10 | Heroku deploy, backfill, scheduler, prod smoke test | not started |
| 11 | README, diagram, example prompts, screenshots | not started |
| 12 | Publish to MCP registry | not started |

## Next step

Milestone 10: Heroku deploy. Checklist:
- `Procfile` (web + release per spec); `ruby file: ".ruby-version"` in Gemfile so the buildpack uses 3.3.14 (risk 5).
- Production `config.hosts` from `MCP_ALLOWED_HOSTS` (the landing page reflects the Host header; escaped, but restrict it anyway). Confirm `request.base_url` is https behind Heroku's router.
- Adam: create app (Basic dyno or higher, Essential-0 Postgres), set config vars (`RAILS_MASTER_KEY`, `MCP_ALLOWED_HOSTS`), add Heroku Scheduler job `bundle exec rake sync:incremental` daily ~10:00 UTC, sign up an uptime monitor on `/health/data`.
- First deploy: `heroku run rake sync:backfill` (awards ~16 min, then 25 bulk end-date downloads ~35 min). A one-off dyno is fine for that; watch Essential-0 storage (~110k awards with raw jsonb).
- Smoke test: `/`, `/health/data`, MCP Inspector against the prod URL, a headless Claude run.

## Blockers

None.

## Open questions / risks

1. **`expiring_contracts` coverage gap — mitigated at M7.** The award search can't filter on period-of-performance end. DID(IT) II proved the gap: its last action was 2025-11-20, one week outside a 365-day window, and it ends 2026-10-15. Backfill is now 730 days, since a contract in its final option year can go 12–18 months without an action. Contracts quiet for 2+ years are still missed; the tool description says so.
2. **Recipient upsert key can be null.** Resolved in schema: non-null unique `recipient_key` (USAspending ID, else normalized name). The mapper (M3) owns the normalization.
3. **Agency key — resolved at M3.** `Awarding Agency Code` is the toptier code (e.g. `070` = DHS). The API does not return abbreviations, so "DHS"-style matching needs `/api/v2/references/toptier_agencies/` in the sync (M4).
4. **`mcp` gem — resolved at M6.** 1.11's `StreamableHTTPTransport` supports `stateless: true` + `enable_json_response: true`; mounted directly as a Rack app. Argument validation against the input schema is built in (tool-level `isError`); unexpected exceptions become a generic JSON-RPC error with no message (CWE-209), reported via `exception_reporter`.
5. **Heroku Ruby version.** No `ruby` directive in the Gemfile, so `Gemfile.lock` has no `RUBY VERSION`. Confirm at M10 that the Heroku buildpack picks up 3.3.14 (add `ruby file: ".ruby-version"` if not).
6. **Descriptions are truncated to 250 chars** by the search API. Keyword search only sees that prefix. Acceptable for v1; mention it in the `search_awards` description.
7. **Paging cap — handled at M4.** Page-based paging fails with 422 past 50,000 results. The sync uses 30-day windows with `date_type: "action_date"`, which partition exactly (12 monthly counts summed to the 365-day total of 53,914; largest window ~7.7k).
8. **DoD has no recent data.** The 30-day local backfill had 0 DoD awards (90-day publication delay). Demo prompts should use civilian agencies (DHS, HHS, VA, Treasury), and tool descriptions must state the DoD delay.
9. **"Recent" vs. stored.** Of 3,297 awards with activity in the last 30 days, only 570 were signed in that window; the rest are older contracts with recent modifications (signed as far back as 2001). `recent_awards` must filter on `action_date` (signed), not just "is in the DB".
10. **Company acronyms aren't matched.** `company_profile(name: "GDIT")` finds nothing; the recipient is "GENERAL DYNAMICS INFORMATION TECHNOLOGY". Fine for v1; tool description should ask for the company's legal name.
11. **Current vs. potential end date — resolved.** A sample of 40 contracts "expiring in 180 days" had 19 with option years remaining. `EndDateSync` fills `potential_end_date` for every award from USAspending bulk downloads (one per 30-day window; daily run = 1 download). `expiring_contracts` labels each result `final_period` / `options_remaining` / `unknown` and supports `recompete_only`. After the 2-year fill: 102 of 102,020 awards unchecked; of 16,511 ending in 180 days, 12,335 final period, 4,174 options remaining, 2 unknown. USAspending's download service occasionally fails to generate a file ("An error occurred."); each window is retried once, then skipped and reported, without aborting the run.
12. **Subawards (v2 candidate, strong).** Spec lists subawards as a v1 non-goal. DGIB shows why they matter for this audience: 47% of obligations ($233M) went to 20+ small subs, and that's where many engineers are employed. Small firms looking for primes to team with are a likely user group too. Bear case: subaward data is self-reported by primes, first tier only, late and patchy, and it needs a second sync, table, and tool. `spending_by_award` supports `subawards: true` mode, so the client mostly carries over. Don't start before v1 ships.
13. **USAspending blocks bursts — monitoring added at M8.** On 2026-11-27 a 4-thread enrichment run (~10 req/s, right after a 100k-record backfill) got our IP connection-reset on every endpoint (curl too). Never parallelize calls to USAspending; both syncs are sequential, and end dates now come from a handful of bulk downloads instead of per-award calls. If production gets blocked, the daily incremental sync fails and data_freshness goes stale until it lifts. Tool calls are unaffected (Postgres only). M8: `/health/data` returns 503 when the last successful award sync is over 36h old (point an external uptime monitor at it in M10); dropped connections raise `Usaspending::Client::ConnectionRefused` and runs are flagged `rate_limited`; tool responses carry `data_freshness.stale`.

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
- 2026-11-27: GIBCT confirmed as part of Accenture Federal's DGIB contract `36C10D21N0007` (VA/VBA). `examples.md` §2 updated with subaward data. Exposed risks 11 (current vs. potential end date) and 12 (subawards).
- 2026-11-27: M6 `/mcp` = official transport mounted in routes, stateless JSON, `serve_subscriptions_listen: false`. Fresh server + transport per request (cheap; reload-safe). Host-header protection on: loopback by default, deployed hosts via `MCP_ALLOWED_HOSTS` (must be set on Heroku at M10).
- 2026-11-27: M6 tool responses: `structuredContent` plus two text blocks (one-line summary, same JSON). The gem doesn't text-serialize Hash structured content, and some clients only read text. Every payload has `data_freshness`. Awards expose `signed_date` (= `action_date`) to avoid the ambiguous name.
- 2026-11-27: M6 input schemas are closed (`additionalProperties: false`) with explicit bounds, so bad input is a readable tool error. Unmatched agency is a tool error with guidance; no matches is an empty success.
- 2026-11-27: M6 verified with curl, MCP Inspector CLI, and a headless Claude Code session (`claude -p --mcp-config`): asked about DHS software/cloud awards without naming the tool, Claude called `search_awards(agency: DHS, days: 30, limit: 100)` and separated license resales from staffing signals.
- 2026-11-27: M7 (Adam's call) fetch the real end date rather than caveat-only, after the 19/40 sample. Backfill window raised to 730 days because DID(IT) II fell just outside 365.
- 2026-11-27: M7 `expiring_contracts` matches on current end OR potential end in the window, ordered by the event date (current end if still ahead, else potential end). DGIB-style contracts (current period lapsed, options running) appear when their potential end nears.
- 2026-11-27: M7 tool descriptions point at each other ("for X prefer Y"), state the 2-year window, the DoD lag, prime-only scope, and how to read resale vs. services awards. `company_profile` returns `ambiguous` with candidates as a normal result (not an error) and tells the client to ask the user.
- 2026-11-27: 365-day backfill: 53,897 awards + 17 skipped (Treasury bureau orders with no agency code upstream) = API count 53,914. ~8 min.
- 2026-11-27: M7 EndDateEnricher first used 4 threads; that produced SSL EOF errors and then an IP block from USAspending. Rewritten as sequential, rate-limited (0.4s between requests), prioritized (soonest end first), capped (5,000/run), with a circuit breaker (10 consecutive failures). Simpler code too: no threads, no interlock workaround.
- 2026-11-27: 730-day backfill: 102,020 awards + 17 skipped (Treasury bureau orders without an agency code). ~16 min.
- 2026-11-27: M7 result limit max lowered 100 -> 50 (spec said 100). A 100-contract `expiring_contracts` response was 76k chars, over Claude Code's tool-output limit; 50 is ~38k. Dropped `naics_description` from award lists.
- 2026-11-27: M7 `expiring_contracts` reports `unchecked_count` and says so in the summary, so an empty `recompete_only` result isn't mistaken for "no recompetes" while enrichment is incomplete.
- 2026-11-27: M7 headless Claude checks with `examples.md` prompts (DID(IT), DGIB, VA recent + expiring) used all four tools sensibly. Found an unconfirmed DID(IT) -> ODOS 3.1 link and a DGIB follow-on order ending 2026-12-29. Exposed the payload-size bug and the signing-date window trap in `search_awards` (description now says to widen `days`).
- 2026-11-27: Pipeline visibility (Adam's call): public status panel on the M9 landing page plus an external uptime alert on `/health/data`. No admin portal (would need auth, mostly duplicates `heroku logs`/console; buttons can't run multi-minute jobs inside Heroku's 30s request limit). Read-only admin behind Basic auth remains an easy v1.1 add-on.
- 2026-11-27: M8 `sync_runs.kind` (`awards` | `end_dates`) + `details` jsonb. EndDateEnricher records its own run (checked/failed/remaining/stopped_early); `sync:*` tasks exit non-zero if enrichment stopped early. `data_freshness` only counts award runs.
- 2026-11-27: M8 `/health/data` is public, so it summarizes failures (status, counts, `rate_limited`) and never echoes error text. 30 req/min/IP.
- 2026-11-27: M8 rack-attack: `/mcp` 60 req/min/IP (`MCP_RATE_LIMIT_PER_MINUTE`), JSON-RPC-shaped 429 with Retry-After. In-memory store: per process, so limits multiply with dynos/Puma workers. Disabled in specs except `rate_limit_spec`.
- 2026-11-27: M8 optional `MCP_BEARER_TOKEN` (constant-time compare, 401 + WWW-Authenticate). Transport `max_request_bytes` 64 KiB. String inputs have `maxLength` (keyword/name 200, agency 100).
- 2026-11-27: Potential end dates now come from USAspending bulk downloads (Adam's call), replacing per-award lookups: one async download per 30-day window (25 for the backfill, 1 daily, ~70–90s each to generate). `EndDateSync` also fills `recipients.parent_name` (spec field, previously always empty). Option status no longer limited to awards >= $100k.
- 2026-11-27: Not re-architecting the award sync onto bulk downloads for v1. Checked first: CSV descriptions are identical to the search API's (my M3 "truncated at 250" was from a 10-row sample; ~1.5% of descriptions are exactly 250, max is 2,200). The CSV has no USAspending recipient ID (would force re-keying recipients by UEI). Its extra fields (latest action date, total value with options, set-aside/small-business flags, parent award) would be new tool features. Candidate for v1.1.
- 2026-11-27: M9 built by a background agent in an isolated worktree (separate test DB, port 3002), reviewed and fast-forward merged. `PagesController < ActionController::Base` + ERB + inline CSS, no JS framework or external assets. Tool summaries render from `McpEndpoint::TOOLS`; status panel from `DataHealth#report` / `#recent_runs` (no error text). `/` throttled 60/min/IP.
- 2026-11-27: `EndDateSync` retries a failed window download once, then continues and marks the run failed with `details.failed_windows` (the 2-year fill hit one "An error occurred." from USAspending and aborted before this). Dropped connections still stop the run at once.
