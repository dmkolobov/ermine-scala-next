# SCHEMA-SALES: the ErmineSales schema and the Ermine-to-SQL column contract

DB-PLAN S1, schema role, 2026-09-24. Everything below is generated from, or checked against, one source file: `data/schema/build-sales-schema.mjs`.

| File | What it is | Status |
|---|---|---|
| `data/schema/build-sales-schema.mjs` | The single source. Edit this file and rerun `node data/schema/build-sales-schema.mjs`. Do not hand-edit the outputs. | ran |
| `data/schema/sales.contract.json` | The column contract that the generator and the loaders read | valid JSON, parsed by node |
| `data/schema/sales.mssql.sql` | Idempotent T-SQL DDL: tables, indexes, views | applied twice to ErmineSales through `scripts/db.sh sql -b`, exit 0 both times |
| `data/schema/sales.sqlite.sql` | The same DDL for SQLite (D13); STRICT tables | applied twice to a file DB: PASS |
| `data/schema/sales.smoke.sql` / `sales.smoke.sqlite.sql` | Row counts per table and view, plus the Fetch totals, as `k\|v` lines | both dialects match the expected file at xs |
| `data/schema/sales.smoke.expected-xs.txt` | The expected smoke output at tier xs | SQLite output matches it byte for byte; MSSQL output matches once sqlcmd's trailing empty line is dropped |
| `data/schema/verify-sqlite.mjs` | The serverless check: DDL twice, load xs, compare views to the literals, smoke diff, integrity rejections | PASS: 0 failed checks |

## 1. Two layers

* **Minimal layer.** This layer is what the Doc fixtures' Ermine `table` statements name. It has four **views**: `sales`, `sales_items`, `targets` and `calendar`. It also has one **base table**, `sales_report`. The column names equal the Ermine field names, as they must, because the decoder looks each result label up in the Ermine header (SURVEY-CORPUS §3.1, `SqlExecution.scala:62-71`).
* **Full layer.** This layer is a star schema for realistic generation. It has six dimensions (`dim_region`, `dim_product`, `dim_channel`, `dim_rep`, `dim_customer`, `dim_date`) and two facts (`fact_order_line`, `fact_target`). The views present the star as the minimal tables, so the same fixtures run unchanged at every tier.

Every view `GROUP BY`s its full key, so its rows are distinct at every tier. This matters because the scanner marks a base relation as already distinct (`SqlScanner.scala:1027-1031`; SURVEY-CORPUS §3.1).

## 2. The minimal layer

| Object | Kind | Columns, with their Ermine types | Backs | xs rows |
|---|---|---|---|---|
| `sales` | view: `fact_order_line` ⋈ `dim_region`, grouped by (region, day) | region `String`, day `Date`, amount `Double` (= SUM lineAmount), units `Int` (= SUM quantity) | `FetchData.e:20`, so all six `Fetch*` reports | the 8 literals of `FetchData.e:21-29` |
| `sales_items` | view: the same join plus `dim_product`, grouped by (region, day, item) | region `String`, day `Date`, item `String` (= productName), amount `Double`, units `Int` | the `Sale` record of `Sales.e:71-75` / `SalesRaw.e` | the 8 literals of `Sales.e:98-107` |
| `targets` | view: `fact_target` ⋈ `dim_region`, grouped by region | region `String`, target `Double` (= SUM targetAmount) | `FetchData.e:33` | the 4 literals |
| `calendar` | view over `dim_date` | day `Date`, monthName `String` | the module-local literal of `FetchCrosstab.e` | its 8 literals |
| `sales_report` | **base table** (a mart snapshot) | srRegion `String`, srSales `Double`, srDelta `Double` | `Doc/SalesReport.e:33-38` | the 3 literals |

**Why `sales_report` is a table and not a view.** No aggregation of the 8 sales rows produces its xs values (EMEA 120.5 / 0.125 and so on). At tiers s and above the generator derives it for each `regionGroup`: srSales is the last full quarter's sales in thousands, and srDelta is the change against the previous quarter.

**Totals that tier xs must reproduce.** Only the region amounts are pinned in a fixture's source; everything else is either a documented example output or a sum of the literals.

| Value | Source |
|---|---|
| north 4350.75, south 2605.75, east 4175.5, west 1550.0, all 12682.0 | pinned in the comment at `FetchData.e:18-19` |
| targets met = 2 (north, east) | documented in the `FetchTopN.e` header (`{"keep": 2}` gives north, east, Other); the comment at `FetchData.e:32` names the same two regions |
| running total ends at 12682.0 | `FetchRunning.e` header |
| units 34, target total 11500.0, months 3/3/2, srSales total 529.5 | sums of the literals; not pinned in any fixture |

The smoke file checks all of these (§6).

## 3. The full layer (star schema)

| Table | PK | FKs | Columns, with their Ermine types | Nullable |
|---|---|---|---|---|
| `dim_region` | regionId | none | regionId Int, regionCode String(40) UNIQUE, regionName String, regionGroup String(8) (EMEA/APAC/AMER), countryName String, countryCode String(2), populationWeight Double | none |
| `dim_product` | productId | none | productId Int, sku String(20) UNIQUE, productName String(80) UNIQUE, category, subCategory, priceBand String (low/mid/high/premium), listPrice Double, unitCost Double | none |
| `dim_channel` | channelId | none | channelId Int, channelName String UNIQUE, isDirect String(1) Y/N | none |
| `dim_rep` | repId | regionId → dim_region | repId Int, repName String, regionId Int, repTeam String, hireDate Date, repScore **Nullable Int** | repScore (NULL rate 0.15) |
| `dim_customer` | customerId | regionId → dim_region | customerId Int, customerName String(120), customerTier String, regionId Int, signupDate Date | none |
| `dim_date` | day | none | day Date, yearNo, quarterNo, monthNo Int, monthName String(7) `YYYY-MM`, quarterName String(7) `YYYY-Qn`, weekdayNo Int (ISO), weekdayName String | none |
| `fact_order_line` | (orderId, lineNo) | orderDate → dim_date.day; regionId, customerId, productId, repId, channelId → their dims | orderId, lineNo Int, orderDate Date, 5 FK Ints, quantity Int, unitPrice Double, discountPct Double, lineAmount Double, promoCode **Nullable String** | promoCode (NULL rate 0.8; non-NULL only when discountPct > 0) |
| `fact_target` | (regionId, yearNo, quarterNo) | regionId → dim_region | regionId, yearNo, quarterNo Int, targetAmount Double | none |

**NULL policy.** Every column is NOT NULL except the two columns above. Each of those two is declared `Nullable T` in Ermine, and a NULL anywhere else fails the scan (SURVEY-CORPUS §5). The xs tier contains one NULL (repScore of rep 4) so that the Nullable path is exercised at the smallest tier.

**Invariants the generator must hold** (`contract.invariants`, 11 of them). Among them:
* **No String column holds the empty string.** An empty CSV field, quoted `""` or unquoted, means NULL, which is legal only in a Nullable column. BULK INSERT loads `""` in a nullable column as NULL, so an empty string cannot survive the MSSQL load (REVIEW-S1 M3; contract `csv.null`).
* lineAmount = round(quantity × unitPrice × (1 − discountPct), 2). At xs, unitPrice = round(amount/units, 4) and discount is 0. All 8 literals reproduce their amount to the cent under this rule; the build script asserts it.
* The rep's region and the customer's region equal the line's region.
* All lines of one order share its date, region, customer, rep and channel.
* dim_date is contiguous over the tier range at s, m and l.
* The string natural keys are unique case-insensitively, because MSSQL's default collation is case-insensitive and SQLite's is BINARY (SURVEY-CORPUS §4).
* regionCode is lowercase ASCII, so MSSQL and SQLite sort it identically.

**Money columns are `float` rather than `decimal`.** The Ermine type is `Double`, and float is what the scanner itself uses for Double (SURVEY-CORPUS §5). Keeping float on both dialects keeps the SQLite twin's values identical. Values are generated rounded to cents. At tiers s and above, `SUM` over floats may differ between the dialects in the last ulp, because the summation order is not fixed (INFERRED, unmeasured).

**Indexes.**
* `ix_fol_region_date` on (regionId, orderDate); on MSSQL it INCLUDEs lineAmount, quantity and productId.
* `ix_fol_date`, `ix_fol_product`, `ix_rep_region`, `ix_customer_region`.

## 4. Tier row counts (D11)

| Table / view | xs | s | m | l |
|---|---|---|---|---|
| fact_order_line | 8 | 1 000 | 100 000 | 2 000 000 |
| dim_date (range) | 8 (the sale days) | 365 (2026) | 730 (2025-26) | 1 096 (2024-26) |
| dim_region | 4 | 8 | 12 | 20 |
| dim_product | 3 | 40 | 200 | 1 000 |
| dim_channel | 1 | 4 | 5 | 6 |
| dim_rep | 4 | 24 | 60 | 150 |
| dim_customer | 4 | 200 | 5 000 | 50 000 |
| fact_target (regions × quarters) | 4 | 32 | 96 | 240 |
| sales_report | 3 | 3 | 3 | 3 |
| views `sales`, `sales_items` | 8 | derived (the distinct keys) | derived | derived |
| view `targets` | 4 | 8 | 12 | 20 |
| view `calendar` | 8 | 365 | 730 | 1 096 |

Tier xs ignores the seed. It is exactly `tables[].xs.rows` in the contract.

## 5. Dialect differences (the only ones; also written at the top of both DDL files)

| # | MSSQL | SQLite | Why |
|---|---|---|---|
| D-1 | objects in `dbo`, written `dbo.x` | bare names in `main` | SQLite has no schemas; a qualified name refers to an ATTACHed database (SURVEY-CORPUS §3.1) |
| D-2 | Date is `date` | Date is `INTEGER` epoch milliseconds at 00:00 GMT | SqliteEmitter writes a Date literal as `d.getTime` (`SqlEmitter.scala:696`) and gives Date the type `integer` in its own DDL (`:724`), so a stored date must be comparable with that literal. The CSV carries `YYYY-MM-DD`; the SQLite loader converts it with `Date.UTC(y, m-1, d)`. |
| D-3 | `nvarchar(n)`, `float`, `int` | `TEXT`, `REAL`, `INTEGER`; tables are `STRICT` | STRICT makes a mistyped CSV value fail the load instead of being stored as text. `verify-sqlite.mjs` checks that a text date is rejected. |
| D-4 | `GO` between batches | none | `CREATE VIEW` must start a T-SQL batch |
| D-5 | `INCLUDE (...)` on `ix_fol_region_date` | plain index | SQLite has no INCLUDE |
| D-6 | FKs always enforced | FKs enforced only under `PRAGMA foreign_keys = ON` | the DDL sets the pragma for its own connection; the loaders must set it too |
| D-7 | guard: THROW when run in master, model, msdb or tempdb | none | protects the system databases |
| D-8 | column names `[bracketed]` | bare | `lineNo` is the reserved T-SQL keyword LINENO: the first apply failed with Msg 156 at `lineNo` (MEASURED). The scanner brackets every MSSQL column itself (`SqlEmitter.scala:616-617`), so a report field called `lineNo` still works. |

## 6. Smoke and expected output

To run the T-SQL smoke:

```
scripts/db.sh sql ErmineSales -i data/schema/sales.smoke.sql -h -1 -W -s '|' -b | sed '/^$/d' \
  | diff - data/schema/sales.smoke.expected-xs.txt
```

To run the SQLite smoke: `node data/schema/verify-sqlite.mjs` runs it as one of its checks.

At tier xs the output must equal `data/schema/sales.smoke.expected-xs.txt`. That file has 27 lines:
* one row count per table and per view (13 lines);
* the four region amounts, amount.all 12682.00 and units.all 34;
* items.amount.all 12682.00, target.all 11500.00 and targets.met 2;
* sales per month: 3, 3, 2;
* srSales.all 529.50 and null.repScore 1.

Money values are cast to `decimal(18,2)` on MSSQL and printed with `printf('%.2f')` on SQLite, so both dialects print the same text. The rows are ordered by an explicit sequence number, not by key, because a key sort would follow each dialect's collation. go-sqlcmd v1.10 adds one empty line after the result set, and the `sed` removes it (MEASURED). With that line removed, the MSSQL output equals the expected file.

**The server is loaded at tier xs.** I loaded ErmineSales at xs through a scratch INSERT script built from `tables[].xs.rows`; the BULK load belongs to the loader. `SELECT ... FROM sales` as `ermine` returned the 8 FetchData rows, `targets` the 4 targets, and `sales_report` the 3 SalesReport rows (MEASURED). The loader's first run replaces all of this, because the DDL is drop-then-create.

## 7. The `table` statements for `DbFetchData.e` (and the twins)

```
module DbFetchData where

-- The Fetch* seam backed by the ErmineSales database (tracker/db/SCHEMA-SALES.md).
-- Column names = field names; types = the contract's `ermine` values exactly.

import Date
import Relation

field region    : String
field day       : Date
field amount    : Double
field units     : Int
field target    : Double
field monthName : String   -- moved here from FetchCrosstab: the twin imports `calendar`

table sales    : [region, day, amount, units]
table targets  : [region, target]
table calendar : [day, monthName]
```

The twins of `Sales.e` and `SalesReport.e` need two more statements. Each belongs in the module that declares its fields:

```
field item : String
table sales_items : [region, day, amount, units, item]

field srRegion : String
field srSales  : Double
field srDelta  : Double
table sales_report : [srRegion, srSales, srDelta]
```

**Recommendation: bare names (`table sales`), with no `database "…"` block.** This departs from the example in DB-PLAN D8 (`database "…"` + `table dbo.x`). There are four reasons:

1. **SQLite cannot resolve `dbo.sales`.** The name is emitted bare as `dbo.sales` (`SqlEmitter.scala:36-37`). On SQLite that refers to an attached database called `dbo` (SURVEY-CORPUS §3.1, INFERRED). A file-backed SQLite profile opens the file as `main`, so the D13 twin could not serve the same module. A bare `sales` works on both dialects.
2. **MSSQL resolves a bare `[sales]` through the login's default schema, and for `ermine` that schema is `dbo`.** `SELECT SCHEMA_NAME()` as `ermine` in ErmineSales returned `dbo`, and an unqualified `SELECT ... FROM sales` returned the 8 rows (MEASURED 2026-09-24). This is the one dependency the recommendation adds. It is asked of infra on the board: keep `dbo` as the default schema when `db.sh up` re-creates the user.
3. **The parser accepts both spellings.** `dottedDefName` (`SurfaceParsers.scala:648-652`) splits on `.`, the last segment is bound as the term, and the others become `TableName.schema`. Underscores are identifier characters (`Lexer.scala:34-35`), so `sales_items` and `sales_report` bind as terms of those names. Both spellings are read in the source only (INFERRED); neither has been through a scan.
4. **The `database` string buys nothing and costs `joinOn`.** The string is never emitted into SQL (SURVEY-CORPUS §3). It does set the relation's db tag: a block-less table gets `""` (`NewPipeline.scala:474`), which is the same tag a literal carries. `joinOn` dies when the tags differ (`Lib.scala:741`). The Fetch reports join literals to tables: FetchRunning's `relation (withRunning rows)` ⋈ `targets`, and FetchCrosstab if its calendar stays a literal. Today they use natural `join`, which does not compare tags, but the block would make any future `joinOn` of a literal with a table fail.

**Where the types must match.** Every Ermine type above equals the contract's `ermine` field for that column. A mismatch, such as declaring `units : Double` or leaving out `Nullable` on repScore, fails at scan time rather than at compile time (SURVEY-CORPUS §5).

## 8. Verification done here, and what is still open

* Done:
  * **SQLite.** `node data/schema/verify-sqlite.mjs` printed `PASS verify-sqlite: 0 failed checks` (node 24.20.0, built-in `node:sqlite`, SQLite 3.53.4; there is no `sqlite3` binary on the box). It checked:
    * the DDL applied twice, so the file is idempotent;
    * xs loaded;
    * the `sales`, `sales_items`, `targets` and `calendar` views equal the fixture literals;
    * the storage classes of `sales` are integer, real and integer;
    * an epoch-ms Date filter over the Sales.e example range selects 6 rows;
    * the smoke output equals the expected file;
    * an FK violation, a NULL in a NOT NULL column, a text date in a STRICT table and a duplicate PK are each rejected.
  * **MSSQL (SQL Server 2022 CU27 in `ermine-mssql`).**
    * The DDL applied twice with exit 0.
    * xs loaded.
    * The smoke output equals the expected file once the trailing empty line is dropped.
    * The default schema is `dbo`, and bare names resolve.
    * All 13 objects are in `dbo`: 9 USER_TABLE and 4 VIEW, from `sys.objects`.
  * The contract JSON parses: 9 tables, 4 views, 57 + 13 columns, 9 FK edges.
* **Unverified:**
  * A scan through `sqlite-jdbc` of an INTEGER-ms `day` into an Ermine `Date` has not been tried, because no JVM was run. It is INFERRED from sqlite-jdbc reading INTEGER dates as epoch ms.
  * A real Ermine `table` statement has not been scanned against these objects. That is the reports and server stages' first check.

## 9. Note: `ErmineGate` (idea only, no DDL change now)

The `db` gate should load tier xs into **its own database**, for example `ErmineGate`, created by the gate, loaded from `sales.contract.json`'s xs rows and dropped afterwards. It should not read the shared `ErmineSales`, whose tier depends on whoever loaded it last. The same DDL applies unchanged, because the MSSQL file refuses only system databases (D-7) and the `.e` twins use bare names that resolve in whichever database the connection names.
