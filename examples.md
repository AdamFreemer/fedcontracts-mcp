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

**What Claude found (headless check, 2026-11-27):** no DID(IT) follow-on by
name. Three USCIS **ODOS 3.1** task orders were awarded 2026-09-14 (BridgePhase
$25.5M, Emerge Tek $18.4M, Softrams $7.7M; all start 2026-09-25 and end
2027-05-24). They began three weeks before DID(IT) II ended and total about
$51.5M, so the development work may have moved there. That's an unconfirmed
hypothesis: the descriptions don't mention DID(IT).

**Expected tool behavior:**
- `search_awards(keyword: "DID(IT)", agency: "USCIS", days: 3650)` finds it. The keyword
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

## 2. VA GI Bill Comparison Tool (GIBCT), under Digital GI Bill (DGIB)

GIBCT is a small page on VA.gov. It's maintained as part of Accenture
Federal's Digital GI Bill delivery contract, not as a contract of its own.
No award mentions "GIBCT" or "GI Bill Comparison", which is typical: product
teams sit inside large program contracts.

| Field | Value |
|---|---|
| Award | `36C10D21N0007` (order under VA T4NG IDIQ `VA11816D1013`) |
| URL | https://www.usaspending.gov/award/CONT_AWD_36C10D21N0007_3600_VA11816D1013_3600 |
| Prime | Accenture Federal Services LLC |
| Agency | VA / Veterans Benefits Administration (office 36C10D) |
| Obligated | $494.1M (reported ceiling ~$542M) |
| Signed | 2021-03-11 |
| Current period end | **2025-09-29** (USAspending `end_date`) |
| Potential end (all options) | **2030-09-29** |
| Last modified | 2026-02-24 (still active) |
| NAICS | 541512 |
| Subawards | **493 reports, $233.1M**, about 47% of obligations |
| Follow-on order | `36C10D24F0021` "VBA DGIB Support Services", Accenture, $383.7M, GSA vehicle `47QTCK18D0036`, **2023-12-30 to 2026-12-29** |

Largest reported subcontractors (first page of subaward reports, by amount):
Lefant ($80.3M), Four Points Technology ($22.3M), SteerBridge Strategies
($22.2M), V3Gate ($18.8M), Greenbrier Government Solutions ($14.8M), Systems
Engineering Solutions ($14.1M), Knowledge Vortex ($11.4M), Morgan 6 ($8.1M),
DynaVet Solutions ($6.0M), Gray Digital ($3.4M). Latest report: 2025-06.

**What it shows:**
- **The program moved vehicles.** A second Accenture order on a GSA vehicle
  started before the first one lapsed and ends **2026-12-29**, so a
  follow-on, bridge, or recompete decision on DGIB is imminent. Claude found
  this order in the headless check; it wasn't in the original research.
- **The current end date misleads.** The award "ended" in 2025 by `end_date`
  but runs to 2030 through option years. `expiring_contracts` keys on the
  current end, so it can flag option renewals as if they were recompetes, and
  it misses contracts like this one whose current end has already passed.
- **Subs do much of the hiring.** Nearly half the money flows to small
  businesses, many service-disabled veteran-owned. A job seeker on a product
  team like GIBCT is often employed by a sub, not by Accenture. Our v1 data
  (prime awards only) shows Accenture and none of those firms.
- **Sub awards show up late, or not at all, in prime data.** A new
  subcontract or task under this prime never appears as a prime award. It
  only appears in subaward reports, which primes file themselves, often
  months later.

**Expected tool behavior (v1):**
- `search_awards(keyword: "Digital GI", days: 3650)` finds the original order;
  `keyword: "DGIB"` finds the follow-on. A 730-day window misses both because
  search filters on signing date (the tool description now says to widen days).
- `expiring_contracts(agency: "VA")` lists `36C10D24F0021` (ends 2026-12-29).
- `company_profile(name: "Accenture Federal")` includes it as a top VA award.
- `expiring_contracts(agency: "VA")` lists the original `36C10D21N0007` only
  once its potential end (2030-09-29) falls inside the window.
- Nothing in v1 surfaces the subcontractors. See "Subawards" in `status.md`
  for the v2 case.

---

## Caveats these examples expose

- **Sync window.** We store contracts with any action in the last 365 days.
  DID(IT) was last modified 2026-04-27, so it's in a full backfill but not in
  the 30-day local dataset. DGIB was last modified 2026-02-24, so it's in a full
  backfill too.
- **No job postings.** This server has award data only. "Related jobs" means
  hiring signals (who holds the work, when it ends, who may win it), not job
  listings. Pairing it with a job-search tool is the client's job.
