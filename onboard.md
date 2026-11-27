# Onboarding

How to pick up this project cold, whether you're a person or an agent.
Read in this order: `CLAUDE.md` (the spec), `status.md` (where things stand), then this file.

## What this is

FedContracts MCP: a Rails 8 remote MCP server exposing federal contract awards
from USAspending.gov. A scheduled sync loads awards into Postgres, and MCP tools
read only from Postgres. See `CLAUDE.md` for the full spec.

## Prerequisites

- Ruby 3.3.14 (see `.ruby-version`; RVM users: build with `--with-openssl-dir=$(brew --prefix openssl@3)`), Bundler 4
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

_Filled in as of Milestone 4._ `bin/rails sync:backfill` / `sync:incremental`.

## Connecting an MCP client

_Filled in as of Milestone 6._ MCP Inspector: `npx @modelcontextprotocol/inspector`.

## Repo map

- `app/models/`: `Agency`, `Recipient`, `Award`, `SyncRun` (`SyncRun.data_freshness` feeds tool responses)
- `spec/factories/`: FactoryBot factories for all four models
- `app/mcp/tools/`: MCP tool classes (thin)
- `app/queries/`: query objects (business logic)
- `app/services/`: `Usaspending::Client`, `AwardMapper`, `AwardSync`

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
