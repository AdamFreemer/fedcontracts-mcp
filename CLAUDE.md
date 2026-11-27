# FedContracts MCP: Build Spec

A remote MCP server, built in Rails 8, that exposes federal contract award data
from USAspending.gov as tools an AI client (Claude, ChatGPT, Cursor) can call.

Primary use: a live, deployed portfolio piece for freelance MCP work. It must be
small, fast, well tested, and reliable to demo. Favor shipping over breadth.

## Product framing

Contract awards are a leading signal of who is hiring and what is being bought.
The tools let an AI answer questions like:

- "Which companies won DHS software contracts in the last 90 days?"
- "What IT contracts at HHS end in the next 6 months?"
- "Give me a profile of Acme Corp's federal work: agencies, totals, trend."

Audience: job seekers and contractors looking for gigs, plus small contractors
doing market research.

## Stack

- Ruby 3.3+, Rails 8 (API-only: `rails new fedcontracts --api -d postgresql`)
- Gem `mcp` (~> 1.0), the official MCP Ruby SDK
- PostgreSQL
- Faraday for HTTP to USAspending
- RSpec, WebMock, VCR for tests
- rack-attack for rate limiting
- Deploy: Heroku (web dyno + Heroku Postgres + Heroku Scheduler)

No frontend beyond a single static landing page at `/` that explains the server
and shows the connection URL.

## Architecture

```
USAspending API --(rake sync, scheduled)--> Postgres <--(MCP tools read only)-- /mcp endpoint <-- AI client
```

Hard rule: MCP tool calls never hit USAspending live. They read only from our
Postgres. This keeps every tool call well under Heroku's 30 second router
timeout and makes the demo fast and predictable.

## Data model

### agencies
- `toptier_code` (string, unique), `name`, `abbreviation`
- `subtier_name` (nullable)

### recipients
- `usaspending_recipient_id` (string, unique, may be null for some awards; fall back to normalized name)
- `name`, `uei` (nullable), `parent_name` (nullable)
- `city`, `state`, `country`

### awards
- `generated_internal_id` (string, unique, upsert key)
- `piid` (contract number, nullable)
- `recipient_id` (FK), `awarding_agency_id` (FK)
- `awarding_sub_agency` (string)
- `description` (text)
- `amount` (decimal, 15,2)
- `start_date`, `end_date` (date; end_date = current period of performance end)
- `action_date` (date)
- `naics_code`, `naics_description`, `psc_code`
- `place_of_performance_state`
- `raw` (jsonb, the full source record for debugging)
- timestamps

Indexes: `end_date`, `start_date`, `action_date`, `naics_code`,
`awarding_agency_id`, `recipient_id`, and a GIN trigram or tsvector index on
`description` for keyword search.

### sync_runs
- `started_at`, `finished_at`, `status`, `records_upserted`, `error`
- Lets the landing page and a `data_freshness` field in tool responses say how
  current the data is.

## Ingestion

USAspending needs no API key. Base: `https://api.usaspending.gov`.

Primary endpoint: `POST /api/v2/search/spending_by_award/`
- `filters.award_type_codes`: `["A","B","C","D"]` (contracts only)
- `filters.time_period`: rolling window (default last 365 days on first run, last 7 days incrementally)
- `filters.naics_codes`: default IT/software set, configurable via ENV `SYNC_NAICS`
  - 541511, 541512, 541513, 541519, 518210
- `fields`: award ID, recipient, amounts, dates, agency, sub agency, description, NAICS, PSC, internal IDs
- Paginate with `page` / `limit` (max 100) until `hasNext` is false
- The API requires the `sort` field to also appear in `fields`

VERIFY FIRST: confirm exact field names and filter shapes against
https://api.usaspending.gov/docs/endpoints before writing the mapper. Record a
VCR cassette of a real response and build the mapper from it.

Implementation:
- `Usaspending::Client` (Faraday, retries with backoff on 429/5xx, 25s timeout)
- `Usaspending::AwardMapper` (raw hash -> attributes for Award, Recipient, Agency)
- `AwardSync` service: fetch pages, map, `upsert_all` on unique keys, write a `sync_runs` row
- Rake tasks:
  - `sync:backfill` (365 days, run once manually)
  - `sync:incremental` (last 7 days, overlapping window so late reports get picked up)

Note: DoD data publishes with a 90 day delay. Civilian agency data is fresher.
Mention this in tool descriptions where relevant.

## MCP layer

Endpoint: `POST /mcp`, stateless JSON request/response (Streamable HTTP without
long-lived streams). No sessions, no SSE.

VERIFY FIRST against the `mcp` gem 1.0 README and docs:
1. Whether to use the built-in Streamable HTTP Rack transport mounted in routes,
   or a controller calling `server.handle_json(request.body.read)`. Prefer the
   official transport if it supports stateless mode cleanly.
2. Preferred tool response shape in 1.0 (text content vs structured content).
   Return structured data if supported, with a short text summary.
3. How tool errors are surfaced (tool-level `isError` result vs JSON-RPC error).

Server: `MCP::Server.new(name: "fedcontracts", version: <app version>, tools: [...])`

### Tools (v1, exactly these four)

Each tool lives in `app/mcp/tools/`, is a thin class over a query object in
`app/queries/`, caps results (default 25, max 100), and includes
`data_freshness` (last successful sync time) in every response.

1. `search_awards`
   - inputs: `keyword` (string), `agency` (string, name or abbreviation, fuzzy), `naics_code`, `state`, `min_amount`, `days` (default 90), `limit`
   - returns: awards with recipient, agency, amount, dates, description, a usaspending.gov URL

2. `recent_awards`
   - inputs: `agency`, `days` (default 30), `limit`
   - returns: newest awards by action_date, grouped summary by recipient (count, total)
   - description should frame it as "who just won work and may be staffing up"

3. `expiring_contracts`
   - inputs: `agency`, `within_days` (default 180), `min_amount`, `limit`
   - returns: contracts whose end_date falls in the window, with incumbent recipient
   - description: "upcoming recompetes; incumbents and likely bidders may hire"

4. `company_profile`
   - inputs: `name` (fuzzy) or `uei`
   - returns: total obligated in window, award count, top agencies, top NAICS,
     trend by quarter, 5 most recent awards, 5 soonest expiring
   - if multiple matches, return candidates and ask the client to pick

Write tool descriptions carefully. They are the prompt the AI reads to decide
when to call a tool. Say what each tool is for, its data window, and its limits.

## Security and limits

- v1 is public and read-only. No OAuth.
- rack-attack: throttle `/mcp` by IP (e.g. 60 requests/minute).
- Validate and clamp all inputs (limit caps, day caps).
- Optional `MCP_BEARER_TOKEN` ENV: if set, require `Authorization: Bearer` header.
  Leave unset for the public demo.
- Never echo raw SQL errors to clients.

## Testing

- Unit specs for `AwardMapper` against recorded cassettes.
- Query object specs with factory data (FactoryBot).
- MCP request specs that exercise the real endpoint:
  - `initialize` handshake
  - `tools/list` returns the four tools with valid input schemas
  - `tools/call` for each tool, happy path and bad input
- A smoke rake task `mcp:smoke` that calls each tool against the running server.
- CI: GitHub Actions running RSpec with a Postgres service.

Manual check before every deploy: connect MCP Inspector
(`npx @modelcontextprotocol/inspector`) to the local and production URLs and call
each tool.

## Heroku deployment

- `Procfile`:
  ```
  web: bundle exec puma -C config/puma.rb
  release: bundle exec rails db:migrate
  ```
- Add-ons: Heroku Postgres, Heroku Scheduler.
- Scheduler job: `bundle exec rake sync:incremental` daily.
- Run `heroku run rake sync:backfill` once after first deploy.
- Use a dyno tier that does not sleep, so the demo never cold starts.
- Enable the `pg_trgm` extension in a migration if using trigram search.
- Config vars: `RAILS_MASTER_KEY`, `SYNC_NAICS` (optional), `MCP_BEARER_TOKEN` (optional).
- No worker dyno in v1. If sync outgrows the scheduler, move to Solid Queue on a worker dyno.

## Build order (milestones)

1. `rails new`, Postgres, RSpec, gems. Health check at `/up`.
2. Migrations and models for agencies, recipients, awards, sync_runs.
3. `Usaspending::Client` + record one real cassette. Build `AwardMapper` from it.
4. `AwardSync` + rake tasks. Run a 30 day backfill locally and eyeball the data.
5. Query objects with specs.
6. MCP endpoint + `search_awards` only. Verify end to end in MCP Inspector and in Claude.
7. Remaining three tools.
8. rack-attack, input clamping, error handling.
9. Landing page with connection instructions and data freshness.
10. Deploy to Heroku, backfill, schedule sync, smoke test production.
11. README with architecture diagram, example prompts, and screenshots of Claude using it.
12. Publish to the official MCP registry (registry.modelcontextprotocol.io) as a remote server.

Stop after each milestone, run the specs, and commit.
Update `status.md` at the end of each milestone (in the same commit).

## Non-goals for v1

- SAM.gov integration (keys expire every 90 days; add in v2)
- User accounts, OAuth, saved searches, alerts
- Grants, loans, subawards
- Any UI beyond the landing page

## Code style

- Small POROs for services and queries. Tools stay thin.
- No metaprogramming in tool definitions; explicit schemas.
- Every public query method has a spec.
