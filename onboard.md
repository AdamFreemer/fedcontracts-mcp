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
bin/rails server        # http://localhost:3000/up returns 200
```

The MCP endpoint lands at Milestone 6.

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
DAYS=30 bin/rails sync:backfill   # quick local dataset (~3.3k awards, ~30s)
bin/rails sync:backfill           # full 365 days (~54k awards)
bin/rails sync:incremental        # last 7 days; what Heroku Scheduler runs daily
```

`SYNC_NAICS=541511,541512` overrides the default IT/software NAICS set. Each run writes a `sync_runs` row; failures keep the error there.
DoD data lags ~90 days, so recent windows have little or no DoD.

## Connecting an MCP client

_Filled in as of Milestone 6._ MCP Inspector: `npx @modelcontextprotocol/inspector`.

## Repo map

- `app/models/`: `Agency`, `Recipient`, `Award`, `SyncRun` (`SyncRun.data_freshness` feeds tool responses)
- `spec/factories/`: FactoryBot factories for all four models
- `app/mcp/tools/`: MCP tool classes (thin)
- `app/queries/`: query objects, one per tool: `AwardSearch`, `RecentAwards`, `ExpiringContracts`, `CompanyProfile`; shared `AgencyFilter` (abbreviation/acronym/name matching) and `QueryLimits` (clamps)
- `spec/support/query_fixtures.rb`: fixed-date dataset modeled on `examples.md` for query specs
- `app/services/usaspending/client.rb`: Faraday client for `spending_by_award` (retries, 25s timeout, page-based; max 50k results per window)
- `app/services/usaspending/award_mapper.rb`: raw result -> Agency/Recipient/Award attributes keyed by natural keys
- `app/services/award_sync.rb`: fetches 30-day windows, upserts agencies -> recipients -> awards per page, records `sync_runs`
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
