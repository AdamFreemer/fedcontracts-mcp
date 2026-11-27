# Onboarding

How to pick up this project cold, whether you're a person or an agent.
Read in this order: `CLAUDE.md` (the spec), `status.md` (where things stand), then this file.

## What this is

FedContracts MCP: a Rails 8 remote MCP server exposing federal contract awards
from USAspending.gov. A scheduled sync loads awards into Postgres, and MCP tools
read only from Postgres. See `CLAUDE.md` for the full spec.

## Prerequisites

- Ruby 3.3+, Bundler
- PostgreSQL (local, running)
- Node (for `npx @modelcontextprotocol/inspector`)
- `gh` CLI (logged in), Heroku CLI (`heroku login`)

## Local setup

_Filled in as of Milestone 1._

```sh
bundle install
bin/rails db:prepare
```

## Running

_Filled in as of Milestone 1/6._

## Tests

_Filled in as of Milestone 1._ RSpec: `bundle exec rspec`.

## Loading data

_Filled in as of Milestone 4._ `bin/rails sync:backfill` / `sync:incremental`.

## Connecting an MCP client

_Filled in as of Milestone 6._ MCP Inspector: `npx @modelcontextprotocol/inspector`.

## Repo map

_Filled in as code lands._

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
