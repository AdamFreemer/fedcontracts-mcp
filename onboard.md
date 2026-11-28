# Onboarding

How to pick up this project cold, whether you're a person or an agent.
Read in this order: `CLAUDE.md` (the spec), `status.md` (where things stand), then this file.
`examples.md` has the real contracts used to sanity-check tool output.

## What this is

FedContracts MCP: a Rails 8 remote MCP server exposing federal contract awards
from USAspending.gov. A scheduled sync loads awards into Postgres, and MCP tools
read only from Postgres. See `CLAUDE.md` for the full spec.

## Prerequisites

- Ruby 3.3.14 (see `.ruby-version`; RVM users: build with `--with-openssl-dir=$(brew --prefix openssl@3)`), Bundler 4. Non-interactive shells (agents, scripts) don't get RVM's auto-switch: run `source ~/.rvm/scripts/rvm && rvm use 3.3.14` first.
- PostgreSQL (local, running; CI uses 16)
- Node (for `npx @modelcontextprotocol/inspector`)
- `gh` CLI (logged in), Heroku CLI (`heroku login`)

## Local setup

```sh
bundle install
bin/rails db:prepare
```

## Running

```sh
bin/rails server        # http://localhost:3000/up returns 200; MCP at http://localhost:3000/mcp
```

## Tests

```sh
bundle exec rspec       # specs (FactoryBot, WebMock, VCR in spec/support/)
bin/rubocop             # lint (rails-omakase)
bin/brakeman --no-pager # security scan
bin/bundler-audit       # gem advisories
```

Real HTTP is blocked in tests. USAspending responses come from VCR cassettes in `spec/cassettes/`.
CI (`.github/workflows/ci.yml`) runs all four on pushes to `master` and on PRs.

## Loading data

```sh
DAYS=30 bin/rails sync:backfill   # quick local dataset (~3.3k awards, ~30s, plus end-date lookups)
bin/rails sync:backfill           # full 730 days (~102k awards, ~16 min), then 25 bulk end-date downloads (~35 min)
bin/rails sync:incremental        # last 7 days + one bulk end-date download; what Heroku Scheduler runs daily
DAYS=7 bin/rails sync:end_dates   # just the bulk end-date/parent-company fill (EndDateSync); default 730 days
```

`SYNC_NAICS=541511,541512` overrides the default IT/software NAICS set. Each run writes a `sync_runs` row; failures keep the error there.
DoD data lags ~90 days, so recent windows have little or no DoD.

**Never parallelize requests to USAspending.** It resets connections from clients that burst (it blocked our IP once at ~10 req/s). Prefer bulk downloads over per-award API calls.

## Connecting an MCP client

`/mcp` speaks JSON-RPC 2.0 over HTTP POST (MCP Streamable HTTP, stateless, JSON responses). Three methods matter: `initialize`, `tools/list`, `tools/call`.

```sh
# Raw
curl -s localhost:3000/mcp -H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream' \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"search_awards","arguments":{"agency":"USCIS","days":365}}}'

# MCP Inspector: web UI (pick "Streamable HTTP", URL http://localhost:3000/mcp)
npx @modelcontextprotocol/inspector
# ...or CLI
npx @modelcontextprotocol/inspector --cli http://localhost:3000/mcp --transport http --method tools/list

# Claude Code (can reach localhost)
claude mcp add --transport http fedcontracts http://localhost:3000/mcp
```

Claude.ai and Claude Desktop custom connectors connect from Anthropic's servers, so they need the deployed URL (M10).
Deployed hostnames must be listed in `MCP_ALLOWED_HOSTS` or the transport returns 403 (DNS-rebinding protection).

## Repo map

- `app/models/`: `Agency`, `Recipient`, `Award`, `SyncRun` (`SyncRun.data_freshness` feeds tool responses)
- `spec/factories/`: FactoryBot factories for all four models
- `app/mcp/mcp_endpoint.rb`: Rack app mounted at `/mcp`; builds the server (name, instructions, tools) and stateless transport
- `app/mcp/tools/`: MCP tool classes (thin). `Tools::Base` has the response helpers (`respond`, `error`, `award_json`, `data_freshness`)
- `spec/requests/mcp_spec.rb`: protocol-level specs (handshake, list, call, errors, host check)
- `app/services/data_health.rb`: freshness/staleness, recent run summaries, backlog; feeds `/health/data`, tool `data_freshness`, and the landing page
- `app/controllers/health_controller.rb`: `GET /health/data` (200 ok / 503 stale or never synced)
- `app/controllers/pages_controller.rb` + `app/views/pages/home.html.erb` + `app/views/layouts/pages.html.erb`: the landing page at `/` (the only HTML in this API-only app; inherits `ActionController::Base`)
- `config/initializers/rack_attack.rb`: per-IP throttles
- `app/queries/`: query objects, one per tool: `AwardSearch`, `RecentAwards`, `ExpiringContracts`, `CompanyProfile`; shared `AgencyFilter` (abbreviation/acronym/name matching) and `QueryLimits` (clamps)
- `spec/support/query_fixtures.rb`: fixed-date dataset modeled on `examples.md` for query specs
- `app/services/usaspending/client.rb`: Faraday client for `spending_by_award` (retries, 25s timeout, page-based; max 50k results per window)
- `app/services/usaspending/award_mapper.rb`: raw result -> Agency/Recipient/Award attributes keyed by natural keys
- `app/services/award_sync.rb`: fetches 30-day windows, upserts agencies -> recipients -> awards per page, records `sync_runs`
- `app/services/usaspending/bulk_download.rb`: async bulk award download (request, poll, stream zip, read the prime contracts CSV)
- `app/services/end_date_sync.rb`: fills `awards.potential_end_date` and `recipients.parent_name` from bulk downloads, same 30-day windows as `AwardSync`
- `lib/tasks/sync.rake`: `sync:backfill`, `sync:incremental`
- `spec/cassettes/usaspending/`: recorded real API responses; `cassette_body(name)` in specs reads one

## Conventions

- Stop after each milestone: run the specs, update `status.md`, commit.
- MCP tools never call USAspending live.
- Small POROs; explicit tool schemas; every public query method has a spec.

## Claude Code tooling (project scope)

- Plugins (`.claude/settings.json`): `mcp-server-dev`, `playwright`
- MCP servers (`.mcp.json`): `heroku` (requires `heroku login`)
- User-level (not in repo): `frontend-design`, `ruby-lsp`, Claude in Chrome
- `/onboard`: re-orients a fresh session using these docs

## Deploy

_Filled in as of Milestone 10._ See the Heroku section of `CLAUDE.md`.

Config vars so far:
- `MCP_ALLOWED_HOSTS`: deployed hostname(s), comma-separated. **Required**, or `/mcp` returns 403.
- `MCP_BEARER_TOKEN`: optional; when set, `/mcp` requires `Authorization: Bearer <token>`. Leave unset for the public demo.
- `MCP_RATE_LIMIT_PER_MINUTE`: optional, default 60 per IP.
- `SYNC_NAICS`: optional NAICS override for the sync.

Monitoring: point an external uptime monitor (UptimeRobot, Better Stack) at `GET /health/data`. It returns 503 when the last successful award sync is over 36 hours old.
