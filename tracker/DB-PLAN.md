# DB-PLAN: a local SQL Server with generated corpus databases

**Status: APPROVED by the user 2026-09-24 ("love it. recommendations look good."): every recommendation in §0 is TAKEN as the decision. podman installed by the user (`sudo apt install podman uidmap slirp4netns`). Stage 0 starts from this commit.** Written from two
read-only surveys (`scratch-widget-preview/db-plan/SURVEY-CORPUS.md`, `SURVEY-ENV.md`,
ephemeral; every fact cited here is labelled MEASURED there with file:line or a command).

The user's brief, verbatim: *"The database story will be a major contributor here. I think
I want to set up a local SQL server with a password to test this. Do this with a fleet of
opus 5.5 agents. The agents should be able to communicate via local message board about
how to best accomplish their task. Their goal is to set up a SQL server instance containing
databases for various examples in our corpus. For instance, Sales.e needs tables dealing
with sales. science examples need other tables. HR examples others still. One thing I am
particularly interested in is 'procedural generation' for data ala fakerjs, but with
perhaps with more semantic understanding (i.e. realistic value ranges for numeric data,
geographical, demographic data, etc). This implies that we should be able to setup and
teardown dbs full of data, probably in a configurable way based on volume of data
desired). Draft a proposal for all of this and then proceed with implementation AFTER I
approve/resolve remaining questions."*

## 0. Questions for the user (each with the orchestrator's recommendation)

| # | Question | Options | Recommendation |
|---|---|---|---|
| D1 | How does SQL Server run here? | (a) container, rootless podman, image `mcr.microsoft.com/mssql/server:2022-latest`; (b) container, `2025-latest`; (c) native `mssql-server` (2025 only on Ubuntu 24.04) | **(a)**, unless the work server is 2025. A container is what tear-down wants (remove the volume = gone), and 2022 is the edition most work servers run. One `sudo apt install podman` needs your password once; everything after is rootless. |
| D2 | Memory cap for the instance | 2 GB / 3 GB / default (80% of RAM) | **`MSSQL_MEMORY_LIMIT_MB=2048`**: the box has 15 GiB with 4 GiB available and its swap full (MEASURED); the default would starve the editor and the language server. |
| D3 | Which login does the extension prompt for? | (a) `sa`; (b) one SQL login `ermine` with `db_owner` on the corpus databases and CREATE TABLE in `tempdb`; (c) one login per database | **(b)**: the scanner leaves `##` temp tables in `tempdb` and `memoRelWithPK` creates `MemoHash_*` tables in the connected database (MEASURED), so read-only is not enough, and `sa` should not be what a playtest types. |
| D4 | TLS locally | (a) `encrypt=true; trustServerCertificate=true` (the image's self-signed certificate); (b) mimic the work server with an internal CA | **(a)** now; (b) is Q3's and only answerable on the work network. |
| D5 | Database layout | (a) one database per domain (`ErmineSales`, `ErmineHR`, `ErmineScience`, …), tables in `dbo`; (b) one database, one schema per domain | **(a)**: tear-down per domain is `DROP DATABASE`; the `database "X"` string in an `.e` module is not emitted into SQL (MEASURED), so the connection decides, and one database per domain keeps that honest. |
| D6 | Domains in scope for the first cut | sales only / sales + HR + science / + finance + operations | **Sales first, then HR and science**, one stage each; finance and operations are the largest groups in the corpus (§2) and can follow the same machinery later. |
| D7 | Which reports run against the database? | (a) DB-backed twins of the ten previewable `Doc` fixtures (all sales); (b) plus NEW `Fetch Node` reports for HR and science written for the panel; (c) convert the 121 legacy writer examples | **(a) then (b)**. The 121 `core/examples` modules are legacy writer reports and cannot be previewed at all, DB or not (MEASURED); converting them is a separate programme. Their header comments are still the best specification of each domain's tables and are used as such. |
| D8 | How a DB-backed report is written | (a) new modules with `database "…"`/`table dbo.x : [...]` beside the literal ones; (b) replace the literals | **(a)**: the in-memory SQLite path and its tests pin the literals (`FetchData.e`'s totals are cited in comments). `FetchData.e` is the seam: a `DbFetchData.e` with two `table` statements backs all six `Fetch*` reports (MEASURED). |
| D9 | Where the generator lives, in what language | (a) TypeScript under `data/` (node, like the client); (b) Python under `tracker/tools/`; (c) Scala in `core` | **(a)**: node is already required, the client's test/bundle toolchain is the precedent, `@faker-js/faker` is MIT with zero dependencies and vendorable for the closed network, and a TypeScript domain model is type-checked. Scala would tie generation to sbt; Python would add a third toolchain to vendor. |
| D10 | Realism model | faker-only / a home-grown domain model with vendored reference data + faker for text / a learned generator (SDV) | **Home-grown domain model + faker for names and text.** Faker alone gives no correlated numbers and no referential integrity; SDV needs real data to learn from, pulls in torch and is BUSL-licensed (READ). |
| D11 | Volume tiers | fixed tiers / free row count | **Both**: named tiers `xs` (exactly today's literal rows, for pinning), `s` (~1 k rows per fact table), `m` (~100 k), `l` (~2 M, exercises `data.threshold`, deferred delivery and `tempdb` growth), plus `--rows` to override; every tier deterministic per `--seed`. |
| D12 | Persistence | ephemeral per playtest / kept | **Kept until torn down**: `db up <domain> --tier s` creates or replaces; `db down <domain>` drops; `db down --all` removes the container and volume. The playtest guide says which tier each group expects. |
| D13 | Should SQLite get the same data? | yes / no | **Yes, as a by-product**: the generator writes CSV + DDL, and a second loader fills a file-backed SQLite, so the SQLite-vs-MSSQL divergence (§9.3) becomes observable with identical rows. Cheap once the CSVs exist. |
| D14 | Order relative to WP-12(a) | data first / driver first | **Infrastructure and Sales data first, driver in parallel**: WP-12(a) needs something to connect to; both are stage 1. |
| D15 | The fleet's model | `opus` as the Agent tool offers it | The tool offers `opus`, `sonnet`, `haiku`, `fable`; `opus` is used and is the newest Opus the tool has; whether it is 5.5 is not verifiable from here. |

## 1. Facts the plan rests on

| Fact | Where |
|---|---|
| No example is database-backed; every relation is a literal sent to in-memory SQLite (`VALUES` up to 100 rows, a temp table above) | SURVEY-CORPUS §1, §2 (MEASURED) |
| The construct exists: `database "X"` + `table dbo.t : [f1, …]`, parsed at `SurfaceParsers.scala:654,820`, bound at `Session.scala:2050`; `"X"` is never emitted; column types are the Ermine field types, `Nullable T` for NULL; a NULL in a non-Nullable column fails the scan | SURVEY-CORPUS §3 (MEASURED) |
| Only the ten `Doc` fixtures (all sales) are previewable; the 121 `core/examples` modules are legacy writer reports | SURVEY-CORPUS §2.1 (MEASURED) |
| 56 example files describe their tables in header comments (`Fact:`, `Dimensions:`, `Table:`) | SURVEY-ENV §1 (MEASURED) |
| The preview is hard-wired to in-memory SQLite (`Preview.scala:2219-2221`); `build.sbt:111-113` has mysql, jTDS and sqlite drivers, no mssql-jdbc | SURVEY-CORPUS §1.2 (MEASURED) |
| `com.microsoft.sqlserver:mssql-jdbc:13.6.0.jre11`, 1.58 MB, all seven compile dependencies optional: vendorable | SURVEY-ENV §3 (READ) |
| Nothing SQL Server related on the box: no docker/podman, no sqlcmd, nothing on 1433; sudo needs a password once; Ubuntu 24.04, 12 cores, 15 GiB RAM with 4 GiB available and swap full, 40 GB free disk | SURVEY-ENV §1 (MEASURED) |
| Container images: `2022-latest` (626 MB) and `2025-latest` (634 MB); native install on 24.04 is 2025 only; Azure SQL Edge retired 2025-09-30 | SURVEY-ENV §2 (READ) |
| The image's `MSSQL_DB`, `MSSQL_USER`, `MSSQL_PASSWORD` create a database and a non-sa login at start; SA password policy 8+ chars, 3 of 4 classes | SURVEY-ENV §2 (READ) |
| Type mapping: Date -> `date` (read in GMT), Double -> `float`, Int -> `int`, String -> `nvarchar`, Bool -> `bit`, Byte signed vs `tinyint` unsigned; ~8 examples keep dates as `String` | SURVEY-CORPUS §5 (MEASURED) |
| The scanner assumes base tables have no duplicate rows | SURVEY-CORPUS §3.1 (MEASURED) |

## 2. The shape of the thing

```
data/                       TypeScript, node only, vendorable (D9)
  src/domains/sales.ts      the domain model: entities, distributions, seasonality
  src/domains/hr.ts
  src/domains/science.ts
  src/reference/            vendored reference data: countries+regions+populations,
                            name lists by locale, product taxonomies, units
  src/generate.ts           seed + tier + domain -> CSV per table + DDL (T-SQL and SQLite)
  src/load-mssql.ts         DDL then BULK INSERT from the mounted CSV dir (go-sqlcmd)
  src/load-sqlite.ts        the same CSVs into a file-backed SQLite (D13)
  test/                     determinism (same seed => same bytes), integrity (every FK
                            resolves, no duplicate rows, NULL only in Nullable columns),
                            realism bounds (price bands, dates in range, trees acyclic)
scripts/db.sh               db up|down|status  <domain> --tier --seed  (podman + loaders)
tracker/db/                 DDL per domain, the schema-to-Ermine-type map, the login,
                            the container recipe, the volume-tier table, the BOARD digest
core/src/test/resources/doc/DbFetchData.e   `database "ErmineSales"` + two `table`s (D8)
core/src/test/resources/doc/DbFetch*.e      the six Fetch reports over DbFetchData
docs/, Doc/…HR, …Science    new Fetch Node reports per domain (D7 b)
```

**Semantic realism, concretely (D10).** Sales: a product catalogue with categories and
price bands; regions weighted by vendored population figures; sales reps per region; daily
orders with weekday and seasonal shape, quantity by category, unit price with a small
per-order spread around the band; targets derived from history. HR: an org tree (acyclic,
bounded fan-out), grades with salary bands by role and country, hire dates with tenure
distribution, attrition, headcount plans that reconcile to the tree. Science: instruments
and stations with locations, measurement series with drift, noise and calibration events,
units, a stated NULL rate for `Nullable` readings, EAV tables for the trial/asset examples.
Every table's columns and Ermine types come from the corpus headers (§1) and the tracker's
type map; every generator is a pure function of `(seed, tier)`.

**What the server side needs (WP-12(a), WP-13 as decided).** The vendored driver in
`build.sbt`; a preview connection profile (`ermine.preview.database`: url, user, dialect
`mssql`) with the password PROMPTED and held for the window (§8, decided); the preview
choosing the profile's scanner instead of in-memory SQLite; `trustServerCertificate=true`
locally (D4). WP-15/16 (emitter gaps, `UnsupportedOnDialect`) surface as the first
DB-backed reports run and are ticketed as found, not pre-built.

## 3. The fleet and the message board

Roles, each an `opus` agent with its own brief, each stage reviewed by an agent that did
not write it, each commit gated as `tracker/GATE-POLICY.md` says:

| Role | Owns |
|---|---|
| infra | podman install (one sudo, asked of the user), the container recipe, memory cap, login, `scripts/db.sh up/down/status`, the TLS setting |
| schema | DDL per domain from the corpus headers + the type map; the SQLite twin DDL |
| generator | `data/` domain models, reference data, determinism and integrity tests |
| loader | bulk load, tiers, tear-down, timing table per tier |
| reports | `DbFetchData.e` + the six twins; new HR/science `Fetch Node` reports |
| server | WP-12(a) driver, the preview profile, the prompted password, WP-13 |
| verifier | independent review of every stage; the end-to-end check: the panel renders `DbFetchTopN` from the database at tier `s`, and `db down` leaves nothing behind |

**The board** is `scratch-widget-preview/db/BOARD.md` (durable across sessions, not in
the repo): append-only, one entry per post, `[timestamp] [role] [decision|question|
finding|handoff|blocked] text`. Rules: read the whole board before starting and before
any decision that touches another role's area; post a `question` and continue on the
parts that do not depend on the answer; answer questions addressed to your role; never
edit or delete another entry; direct `SendMessage` only for a blocking question, and post
the answer to the board too. The orchestrator folds `decision` entries into
`tracker/db/DECISIONS.md` at each stage's commit, so the repo carries the record and the
board stays ephemeral.

## 4. Stages and gates

| Stage | Content | Done-when | Gate |
|---|---|---|---|
| S0 | your D1-D15 answers folded in; podman installed (your password once); the image pulled | `podman run` of the image answers `SELECT 1` through go-sqlcmd with the `ermine` login | none (no repo change but `scripts/db.sh` + `tracker/db/`) |
| S1 | Sales: DDL, generator (tiers xs-l), loader, `db up/down`; WP-12(a) driver in parallel | tier `xs` loads exactly today's 8+4 rows; tier `s` in < 30 s; same seed => identical CSV bytes; integrity tests green; the driver resolves and a JDBC `SELECT 1` succeeds from Scala | pr |
| S2 | the preview profile + prompted password (WP-13); `DbFetchData.e` and the six twins | the panel renders `DbFetchTopN` from `ErmineSales` at tier `s`; the JSON tab shows the same totals SQLite shows for tier `xs` | pr + a playtest step |
| S3 | HR and science: DDL, generators, loaders, one `Fetch Node` report each | as S1/S2 per domain | pr |
| S4 | SQLite twin loader (D13); tier `l` and its timing table; `tempdb` growth measured (WP-14's count) | numbers in the tracker | nightly |
| S5 | playtest group F (the database) in the checklist; DECISIONS folded; WP-15/16 findings ticketed | you run group F | — |

Not in scope unless you say so: converting the 121 legacy writer examples; finance and
operations domains; the work server's CA (Q3); Windows (WP-17).
