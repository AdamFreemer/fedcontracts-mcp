# Reference examples

Real contracts used to check that the tools give sensible answers. Each one
lists what the tools should surface and what a job seeker would do with it.
They drive query-spec factories (M5), manual checks in MCP Inspector (M6/M7),
and demo prompts in the README (M11).

Data pulled from USAspending on 2026-11-27.

---

## 1. USCIS DID(IT) II: Digital Innovation and Development

| Field | Value |
|---|---|
| Award | `70SBUR22F00000004` (delivery order under HHS IDIQ `75N98120D00227`) |
| URL | https://www.usaspending.gov/award/CONT_AWD_70SBUR22F00000004_7003_75N98120D00227_7529 |
| Incumbent | Excella, LLC (UEI `KMKUAFKECJ83`) |
| Agency | DHS / U.S. Citizenship and Immigration Services (USCIS Contracting Office ERBUR) |
| Obligated | $65.5M |
| Signed | 2021-12-23 |
| Period of performance | 2022-03-16 to **2026-10-15** (ended six weeks before this note) |
| Last modified | 2026-04-27 |
| NAICS / PSC | 541512 Computer Systems Design / DA01 App Development Support (labor) |
| Place of performance | Arlington, VA |

**What it shows:** a large agile-delivery labor contract at a civilian agency
whose period of performance just ended. Either the follow-on has been awarded
and hasn't appeared yet, or a bridge or extension is coming. As of this note,
no USCIS award mentions "Digital Innovation and Development" other than this one.

**Hiring signal:** when a big labor contract ends, staff move. The incumbent
(Excella) either keeps the team on a follow-on or releases people, and the
follow-on winner needs to staff up fast, often by hiring the incumbent's people.

**Expected tool behavior:**
- `search_awards(keyword: "DID(IT)", agency: "USCIS")` finds it. The keyword
  contains parentheses: USAspending's own keyword search returns **0** for
  `DID(IT)`, but our substring/trigram search should match.
- `search_awards(keyword: "digital innovation", agency: "DHS")` finds it.
- `company_profile(name: "Excella")` lists DHS/USCIS as a top agency and
  includes this award.
- `expiring_contracts(agency: "DHS", within_days: 180)` does **not** list it,
  because it has already ended. A "recently ended" view would catch it.
  That's a possible v2 feature, not in v1 scope.
- `recent_awards(agency: "USCIS")` should list the follow-on once it's
  awarded. Re-check this example then.

---

## 2. VA GI Bill Comparison Tool (GIBCT)

**Status: contract not yet identified.** No VA award mentions "GI Bill
Comparison" or "GIBCT". GIBCT is a VA.gov tool, so it's likely funded under a
broader VA.gov or education-services contract. Candidates found:

| Award | Recipient | Description | Period | Obligated |
|---|---|---|---|---|
| `36C10D21N0007` | Accenture Federal Services | Digital GI Bill Delivery Services | 2021-03-11 to 2025-09-29 | $494.1M |
| `36C10B22N00050002` | Coforma | VA.gov Product Teams: Benefits Crew | 2022-04-01 to 2024-03-31 | $9.7M |
| `36C10B23N00050005` | Coforma | VA.gov Benefits and Claims | 2023-03-28 to 2025-04-27 | $9.5M |
| `36C10B22F0126` | Oddball | VA.gov Platform | 2022-05-13 to 2026-05-12 | $71.5M |
| `36C10B25N00070011` | OddCore JV | VA.gov Core Veteran Experiences | 2025-09-29 to 2027-08-28 | $7.7M |

Next: confirm which contract (or which team/vendor) covers GIBCT, then fill in
this section the same way as DID(IT).

**What it shows either way:** VA digital work is split across many mid-size
product-team orders (often $5–20M, 1–2 years) on a shared vehicle. That means
frequent recompetes and many small vendors (Agile Six, Coforma, Oddball, Ad
Hoc-style shops), which suits job seekers who want small-company agile teams.

**Expected tool behavior (draft):**
- `search_awards(keyword: "VA.gov", agency: "VA")` returns the product-team
  orders above (where they fall inside the sync window).
- `expiring_contracts(agency: "VA")` surfaces the product-team orders ending
  soon, such as `36C10B25N00070011` ending 2027-08-28 once it falls inside the window.
- `company_profile(name: "Oddball")` shows a VA-heavy portfolio.

---

## Caveats these examples expose

- **Sync window.** We store contracts with any action in the last 365 days.
  DID(IT) was last modified 2026-04-27, so it's in a full backfill but not in
  the 30-day local dataset. Several VA candidates ended earlier and won't be in
  v1 data at all.
- **No job postings.** This server has award data only. "Related jobs" means
  hiring signals (who holds the work, when it ends, who may win it), not job
  listings. Pairing it with a job-search tool is the client's job.
