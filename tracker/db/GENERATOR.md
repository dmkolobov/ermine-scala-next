# GENERATOR: the deterministic data generator (DB-PLAN stage S1, sales)

`data/` is a TypeScript package (node only). `(seed, tier, domain)` goes in and one CSV per base table of the contract comes out, plus a `manifest.json`. The same inputs give the same bytes every time. The column contract belongs to the schema role, in `data/schema/sales.contract.json` (doc: [SCHEMA-SALES.md](SCHEMA-SALES.md)). The generator never invents a column: a contract column that the model does not produce fails the run and names the table, row and column. Every value is checked against its contract column as it is written: type, NULL allowed or not, and `maxLength`.

```
cd data && npm install          # from the lockfile; see "Vendoring" for the closed network
npm run generate -- --domain sales --tier s --seed 42 [--rows N] [--out DIR] [--contract FILE]
npm run generate -- --help      # exit codes: 0 ok, 2 usage, 1 generation failed
npm test                        # tsc, then node --test dist/test/*.test.js
npm run timings -- --tiers xs,s,m,l
```

Output goes to `data/out/<domain>/<tier>/<table>.csv` plus `manifest.json`. With `--rows N`, the directory is `<tier>-<N>`. The manifest holds `generator`, `domain`, `database`, `tier`, `seed` (null at xs), `factRows`, `dateRange`, `contractVersion`, `contractSha256`, and `tables[name] = {file, rows, bytes, sha256}`. The loader reads this shape (board, 22:30). It has no timestamps, so two runs give byte-identical manifests.

## 1. Decisions

| # | Decision | Why |
|---|---|---|
| G1 | A home-grown domain model with `@faker-js/faker` for names only (D10) | Faker alone cannot give correlated numbers, referential integrity or seasonality: its numbers are independent uniform draws. SDV was rejected in SURVEY-ENV §4. The model owns every number and every foreign key. Faker writes only `repName` (`person.fullName`) and `customerName` (`company.name`). |
| G2 | Use faker 10.6.0, pinned exactly, rather than a vendored name list | It is MIT licensed, has zero dependencies and is one 3.9 MB package. Its 70+ locales give names in each market's own language and script: CJK for China, Japan and Korea, Arabic for the Gulf and Egypt. A hand-made list would have been English-only or a lot of typing. It can be vendored because the lockfile pins the tarball's sha512 (§5). |
| G3 | Faker is reseeded per entity: `faker.seed([u32, u32])`, drawn from the PCG stream `sales/dim_rep/name/<repId>` (or `dim_customer/name/<id>/<try>`) | Faker's own Mersenne Twister state then never carries from one entity to the next. A name depends only on (seed, entity id), not on how many faker calls came before it. |
| G4 | The PRNG is PCG32 (XSH-RR 64/32), written in-house | It is small and well known, with a published test vector. Its output is integer-only, so every platform gives the same stream. The 64-bit state is held as two uint32 halves, so no BigInt is on the hot path. |
| G5 | Each purpose has its own stream, `stream(seed, "sales/<table>/<purpose>")`. The PCG stream selector is FNV-1a-64 of that label. | Adding a column, table or purpose never shifts the draws of another. Test: a new seed changes `dim_rep`, `dim_customer`, `fact_order_line` and `fact_target`, but not `dim_date`. |
| G6 | Fact rows are streamed (a generator function). Dimensions are held in memory. Derived tables (`fact_target`, `sales_report`) are computed from aggregates the fact leaves behind. | Tier l is 2 M lines. Peak RSS at l is 328 MB (measured, §4). |
| G7 | `xs` is not generated: the emitter writes the contract's `tables[].xs.rows` as they stand and ignores the seed | The contract embeds the Doc fixture literals (schema, 22:24). A test proves the CSVs equal them, and a second test proves the `sales` view over them equals FetchData.e's eight rows and every `xsPinned` total. |
| G8 | `--rows N` keeps the named tier's dimensions and date range and writes exactly N fact lines | It gives predictable sizes for a timing run. Daily line budgets carry over from day to day, so orders are never cut short by the day boundary; only the very last order can be shortened to hit N exactly. |
| G10 | **No column ever holds the empty string, nullable or not; an empty CSV field means NULL** (REVIEW-S1 M3, amended in round 2; schema's contract amendment). `checkCell` rejects `''` in every column, naming the table, row and column (`test/emit.test.ts`: nullable String, nullable Int, non-nullable String, a model row failing `writeTable`). **When the contract's sha256 changes, as it did with this amendment, `data/out` must be regenerated**: every manifest records `contractSha256`, and the loader's `staleReason` refuses a stale directory. | MSSQL BULK INSERT loads a quoted `""` as NULL in a nullable column while SQLite keeps `''`, so the dialects would diverge because of the loader. The sales model never emitted `''`. Measured after each change: the xs and s/42 manifests are byte-identical to the ones before, `test/pinned-s42.json` is unchanged, and no xs or s CSV contains `""`. |
| G9 | The model covers the contract's columns by name. There is no generic interpreter of `hint`s. | The hints (kind, ranges, weights, nullRate) are the specification the model was written against, and the tests check the ones that matter (§3). A generic hint engine would have produced the uncorrelated numbers G1 rejects. |

## 2. PRNG and distributions

**PCG32 test vector.** This is O'Neill's reference `pcg32-demo` with `initstate = 42, initseq = 54`. The first six outputs are `0xa15c02b7 0x7b47f409 0xba1d3330 0x83d2f293 0xbfa4784b 0xcbed606e`. `test/pcg32.test.ts` pins these six values. The same test also compares 10 000 draws on each of 20 seeds against a literal BigInt transcription of `pcg_basic.c`, and pins the published FNV-1a-64 vectors (`""`, `"a"`, `"foobar"`).

**Helpers** (`src/lib/dist.ts`):

| Helper | Method |
|---|---|
| uniform, int, bernoulli | 53-bit float from two outputs; `pcg32_boundedrand_r` rejection for integers (no modulo bias) |
| normal | Box-Muller, cosine half |
| truncNormal | rejection, 64 tries, then the mean |
| lognormal | parameterised by its median and sigma |
| poisson | Knuth up to mean 30, a rounded normal above |
| Categorical | cumulative weights and binary search |
| allocate | largest-remainder integer allocation with a floor |

`log`, `exp` and `cos` come from V8's fdlibm port, which gives the same results on every platform. Every value that reaches a CSV is rounded to 2, 3, 4 or 6 decimal places.

**Dates** are integer day numbers (UTC), so no time zone ever enters. The CSVs carry `YYYY-MM-DD`.

## 3. The sales model: columns, ranges, reasons

Corpus sources for the ranges:

- `core/examples/Ai/SalesByRegion.e`: orders by product/region/channel, units 15-310, unit prices 22.50-899.
- `core/examples/Present/SalesDashboard.e`: a 21-field order fact. Discount is about 5-12% of gross, marginPct is 0.37-0.42, repScore is `Some 48..62`, unit prices around 89.
- `core/examples/Wide/SalesLedger.e`: productLine/family/tier, discountAmt, cogs.
- `core/examples/Ai/RevenueByPeriod.e`: a calendar dimension with year/quarter/month.

| Table.column | Rule (constant in `src/domains/sales.ts` or `src/reference/*.json`) | Reasoning |
|---|---|---|
| dim_region (s 8, m 12, l 20) | The N largest markets by `population x income factor` (H 1.0, UM 0.15, LM 0.04), with every group EMEA/APAC/AMER guaranteed a place. `populationWeight` is normalised to 6 dp and sums to exactly 1. `regionCode` is a lowercase slug (`us-south`, `china`, `united-kingdom`). | Population alone would make India and China 60% of a company pricing durable goods in USD. The income factor is a stated modelling choice, not a measurement. The United States is split into its four Census regions (2020 census counts), so its sales are not one region. |
| dim_product (40 / 200 / 1000) | Six categories (Lighting, Seating, Surfaces, Storage, Outdoor, Accessories), each with sub-categories. Each category's list-price range is cut into four log-equal bands: `low` 35%, `mid` 35%, `high` 20%, `premium` 10%. `listPrice` is log-uniform inside the band's inner 90%, then snapped to a price point (x.99 under 100, x9 above) that stays in the band. `unitCost = list x costRatio (0.38-0.58) x U(0.9, 1.1)`, below list. Popularity is lognormal(1, 0.9), which gives a few best-sellers. Names are `<series> <noun> [variant]`, unique case-insensitively. | Category ranges come from the corpus prices above (Lighting 12-180, Seating 90-780, Surfaces 240-1600). The cost ratios put gross margin at 42-62%, around SalesDashboard's marginPct. |
| dim_channel (4 / 5 / 6) | The first N of Direct, Online, Partner, Marketplace, Retail, Telesales. `isDirect` is Y/N. | Contract vocabulary. |
| dim_rep (24 / 60 / 150) | At least one per region, the rest by `sqrt(weight)`, so small markets are staffed thinly. Team is `<region> Field / Inside / Key Accounts`. `hireDate = lastHire - Exp(mean 1400 d)`, clamped to 2015-01-01 and no later than the tier start. `repScore ~ N(55 + 4 x min(tenure, 6 y), 12)` clamped to 0..100. It is NULL for a hire under 180 days or 4% "not yet reviewed". | Tenure-driven scores are the realistic correlation. The measured NULL rate is 12.5% (s) and 11.7% (m), against the contract's 0.15. |
| dim_customer (200 / 5000 / 50000) | By region weight, at least 2 per region. Tier is gold/silver/bronze in 10/30/60. 80% signed up between 2018-01-01 and the tier start. 20% are acquired during the range and never order before signing up. The first two customers in each region are always long-standing. Each customer has an account rep in their region. Order frequency is `tier factor (6 / 2.5 / 1) x lognormal(1, 0.6)`. | Customers are acquired over time, so the customer count grows through the range. The contract's `signupDate <= first orderDate` is tested. |
| dim_date (365 / 730 / 1096) | Every day of the contract's tier range. | Contract. |
| fact_order_line, daily volume | `weekday [Mon 1.1, Tue 1.2, Wed 1.2, Thu 1.15, Fri 0.95, Sat 0.25, Sun 0.15] x month [Jan .85, Feb .9, Mar 1.1, Apr .95, May 1.0, Jun 1.1, Jul .85, Aug .8, Sep 1.1, Oct 1.05, Nov 1.1, Dec 1.0] x quarter-end push 1.2 (last 10 days) x holiday 0.1 (Jan 1, Dec 24-26, 31) x trend 1.08^years x lognormal(1, 0.2) noise`, then allocated to exactly `factRows` lines | This is B2B buying with quarter-end pushes. Measured at m: Tue 20 410 lines against Sun 2 550; March and September are the peak months. |
| fact_order_line, per order | Region ~ populationWeight. Customer within the region by frequency weight, among those already signed up. Rep is the customer's account rep. Channel mix depends on customer tier (gold 60% Direct / 30% Partner; bronze 35% Online). Lines per order are `1 + Poisson(gold 2.2, silver 1.3, bronze 0.6)`, at most 8, with distinct products. | Measured lines per order: 2.46 (s), 2.35 (m). |
| product mix | For each calendar month, `popularity x category season`: office (Mar/Sep peaks), outdoor (0.5 in Jan to 1.5 in Jun), flat (Nov/Dec 1.2) | Test: Outdoor's share of lines in June is more than 1.8 x its share in January (m). |
| quantity | `round(lognormal(category median x tier factor (gold 2, silver 1.3), sigma 0.6-0.8))`, clamped to 1..50 and to `lineAmount <= 50 000` | Category medians are Lighting 6, Seating 4, Surfaces 2, Storage 3, Outdoor 4, Accessories 8. Measured quantity: median 6, p95 26 (m). |
| unitPrice | `listPrice x (1 + truncNormal(0, 1.5%, +-4%))`, 2 dp, clamped to the product's band | This is the "small spread around the band" (D10). Test: every line is inside its band and within 4.1% of list. |
| discountPct | Promotion (order level, by channel: Online 40%, Marketplace 30%, Retail 25%, Direct/Telesales 15%, Partner 10%) gives 5/10/15% at 50/35/15. A negotiated discount (Partner 75%, Marketplace 40%, Direct 35%, ...) adds `U(2%, channel max 5-18%)` in 0.5% steps. Quantity 20 or more adds 2%. The total is capped at 30%, 3 dp. | Measured: 59% of lines carry some discount. SalesDashboard's 5-12% sits inside this range. |
| promoCode | The campaign of the quarter plus YY (`NEWYEAR26`, `SPRING26`, `SCHOOL26`, `HOLIDAY26`, ...), only when discountPct > 0 | Measured non-NULL: 13.6% (s), 19.1% (m), against the contract's nullRate 0.8. |
| lineAmount | `round(quantity x unitPrice x (1 - discountPct), 2)` | Contract invariant, tested on every line. Measured median 592, p95 3 903 (m). |
| fact_target | Every region x quarter of the range: `actual x U(0.9, 1.2)`, rounded to 10 (under 10 000) or to 100. If a quarter has no sales, the region's mean is used. | Contract rule. Round targets look like plans. |
| sales_report | For each group: the last quarter of the range in thousands (2 dp), and its change against the previous quarter (3 dp) | Contract rule. A test recomputes both from the fact at s. |

**What the tests check** (26 tests in 5 files, `npm test`, about 2.2 s wall):

- PCG and FNV vectors, and the BigInt oracle.
- CSV quoting, NULL against `""`, and the number format.
- For xs, s and m: no duplicate rows, PK, UNIQUE (case-insensitive), every FK resolves, NULL only in nullable columns, types and lengths.
- lineAmount on every line. Order headers agree across lines. lineNo runs 1..n with no gaps. Rep and customer regions equal the line's region.
- Calendar contiguity and derived columns. hireDate is on or before the tier start. signupDate is on or before the first order.
- Bands (s, m). Region shares at m: each is within `10% x w + 3 sigma` of its weight; the largest relative error measured is 5.0%.
- Weekday and season shape (m). NULL rates (m).
- xs equals the contract literals and ignores the seed. The xs `sales` view equals FetchData.e and `xsPinned`. The s `sales` view has distinct keys with the minimal columns and types.
- `sales_report` is recomputed from the fact.
- Determinism:
  - two runs with the same seed give identical manifests and identical bytes;
  - `--rows 2500` gives exactly 2500 lines and runs the same way twice;
  - the s/42 sha256 per table is pinned in `test/pinned-s42.json`. Regenerate that file only for an intended model change, and say so here.
- Mutation probes, run once on the compiled JS:
  - uniform region weights: 2 tests fail;
  - `hireDate` after the tier start: 2 tests fail;
  - promoCode left unconditional: no test fails, because the mutant is equivalent (a promo always carries a discount).

## 4. Tiers: measured (seed 42, this box, node 24.20, one run each, 2026-09-24)

| tier | date range | regions / products / reps / customers | fact rows | rows, all tables | CSV bytes | wall | peak RSS |
|---|---|---|---|---|---|---|---|
| xs | the 8 sale days | 4 / 3 / 4 / 4 | 8 | 39 | 1 979 | < 0.01 s | 89 MB |
| s | 2026 | 8 / 40 / 24 / 200 | 1 000 | 1 676 | 83 104 | 0.04 s | 103 MB |
| m | 2025-2026 | 12 / 200 / 60 / 5 000 | 100 000 | 106 106 | 5 908 721 | 0.79 s | 166 MB |
| l | 2024-2026 | 20 / 1000 / 150 / 50 000 | 2 000 000 | 2 052 515 | 120 999 222 | 11.8 s (14.1 s via the CLI with the build) | 328 MB |

Row counts per table at s: dim_region 8, dim_product 40, dim_channel 4, dim_rep 24, dim_customer 200, dim_date 365, fact_order_line 1000, fact_target 32, sales_report 3. xs matches `sales.smoke.expected-xs.txt`: 4, 3, 1, 4, 4, 8, 8, 4, 3.

Two l runs with the same seed gave byte-identical manifests (`cmp`). The l tier is NOT covered by the integrity tests: reading 121 MB back into row objects would cost about 1.5 GB on a box with 3.5 GB available. At l only the emitter's per-cell checks and the determinism check ran.

## 5. Vendoring (the closed network, tracker §10)

- `data/package-lock.json` pins exactly four packages, each with a `resolved` registry URL and a sha512 `integrity`:
  - `@faker-js/faker 10.6.0` (runtime, MIT, `sha512-3RQHgEtv...GwivIQ==`);
  - `typescript 5.6.3` (build, the client's version);
  - `@types/node 22.9.0` (build, the client's version);
  - `undici-types 6.19.8` (brought in by @types/node).
- `package.json` uses exact versions only.
- `data/node_modules` is 29 MB, of which TypeScript is 22 MB and faker 3.9 MB. It is gitignored, as are `data/dist` and `data/out`.
- **Implication for the work network:** `npm ci` needs these four tarballs. Two ways to supply them:
  - (a) `npm pack` them on this box and commit them under `data/vendor/`, with the lockfile's `resolved` rewritten to `file:vendor/<tgz>`, so the integrity check still applies;
  - (b) an internal registry mirror.

  Neither is done yet. Option (a) adds about 5 MB of tarballs to the repo.
- Faker 10 is ESM-only and declares node `^20.19 || ^22.13 || >=24`. The package is ESM (`"type": "module"`, NodeNext), unlike `client/` (CommonJS). This was a choice, not an accident: a CommonJS build could only load faker through node's `require(esm)`.
- Faker's output is stable only within one version ("When upgrading ... you may get different values for the same seed"). Upgrading faker is therefore a model change, and it changes `test/pinned-s42.json`.

## 6. What is NOT realistic yet

- **Population figures** were typed in by hand, rounded to 0.1 M, and cite the U.S. Census Bureau IDB (public domain) and the 2020 US census. They were not re-checked row by row against the source tables from this box. Treat them as accurate to about 2% (unverified).
- **The income factor** (1 / 0.15 / 0.04) is a modelling choice. China is still the largest region (weight 0.256 at s).
- **One global seasonal curve** is used. The southern hemisphere (Brazil, Australia, South Africa, and so on) sees the same outdoor peak in June as the north. National holidays other than Jan 1 and Dec 24-26 and 31 are not modelled.
- **No price changes over time**: a product's list price is fixed across the whole range, with no inflation and no price-list revisions. There is no currency: every amount is USD.
- **No returns, cancellations or credit notes**: every line is a positive sale.
- **Targets use the same quarter's actuals** (the contract rule), not the prior year's, so the met rate is flat (about 1 in 3 quarters are met, by construction of U(0.9, 1.2)). A real plan would be set before the quarter.
- **Reps do not change region**, a customer's account rep never changes, and there is no attrition after hire.
- **Tier s is thin**: 1 000 lines over 8 regions and 365 days. The region shares at s deviate from the weights by up to 42% relative (measured). The weight test runs at m only.
- **Names in native script** (zh_CN, ja, ko, ar): about 1/3 of reps at l and 18 855 of the 50 000 customers at l are non-ASCII. That is realistic, and it exercises nvarchar and UTF-8 end to end. The loader must read the CSV as UTF-8: BULK INSERT needs `CODEPAGE = '65001'`.
- **Faker company names** contain commas ("Bahringer, Mohr and Bode"): 12 617 quoted fields in `dim_customer` at l. The loader needs `FORMAT = 'CSV'` (SQL Server 2017+) or an equivalent quote-aware path.
