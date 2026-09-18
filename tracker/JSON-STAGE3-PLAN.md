# JSON Stage 2 + 3 programme: decoder, wrappers, document runner, client

Started 2026-09-16. Orchestrator plan and handoff log. Design: `tracker/JSON-API-DESIGN.md`
(§3.2 document, §3.3 params, §3.4/§3.4a relations, §3.7 as-built, §5 Stage 2/3 rows).
Briefs: `tracker/json-stage3/brief-*.md`.

Goal (the user, 2026-09-16): one JSON object per response with every relation inline,
produced by a new document runner (new code, not ermine-writers).

## Working rules (the user, 2026-09-16)

- A branch per stage off `json-encode`; parallel Opus agents in their own worktrees for
  independent pieces. Scala 3 first, then a 2.11 port by copy plus hook sites. The Scala
  stays in the 2.11-and-3 dialect: implicits, no `given`/`enum`/`extension`, `Either` via
  `.right`/`.left` projections, no Scala-3-only syntax.
- Every feature property-tested with scalacheck generators over random declarations and
  values, not examples.
- Tier 0 gates (`tracker/GATE-POLICY.md`) before each commit; one full `core/test` per
  landing (baseline 1130 on Scala 3, 793 on 2.11, before additions); corpus verdicts
  89 LOADED / 79 REJECTED / 0 UNKNOWN over 168.
- An independent review before a landing commit. Never push. Never merge into
  `scala3-migration`/`backport-2.11`. Commit only reviewed green stages.
- Models (the user, 2026-09-16): the orchestrator runs on Fable; every implementer, reviewer
  and porter agent is launched on Opus.
- Parked, NOT to be worked: a binding named `null` is undefined in REPL expressions;
  the 2.11 fused parser rejects an operator constructor with no fixity in scope.

## Branches and landing mechanics

`json-s3-base` = `json-encode` 2071bfa0 + this plan, the briefs and the CONTRACT commit
(below). Every Phase 1 stage branches off it; it reaches `json-encode` with the first
landing (its code is reviewed as part of stage J3a's review).

Landing a stage X: review green -> orchestrator commits on `json-X` -> merges the current
`json-encode` INTO `json-X` (so earlier landings are present) -> Tier 0 + full `core/test`
on that tree -> `json-encode` fast-forwards to `json-X`. `json-encode` is never red.

Worktrees live beside the others: `~/research/ermine/ermine-scala-wt-json-<stage>`.
In a worktree regenerate `tracker/repl-classpath.txt` from its own `target/ermine-classpath`
before the REPL/LSP smokes, and never commit that file.

## The contract (commit on json-s3-base, written by the orchestrator)

- `Lib.json`: the stdlib `Json` type gains `JInline [..r]` and `JDeferred [..r]` beside
  `JRel [..r]` (existential row, like `JRel`).
- `modules/Json.e`: `data Inline r = Inline [..r]`, `data Deferred r = Deferred [..r]`,
  builders `relInline`, `relDeferred` (beside `rel`).
- `json/Encode.scala`: `sealed abstract class Delivery` = `ByRequest | Inline | Deferred`;
  `JsonBuilder.rel(path, r, delivery)`. The walker passes `ByRequest` for a bare relation
  and `JRel`, `Inline`/`Deferred` for the wrappers `Json.Inline`/`Json.Deferred` and the
  nodes `JInline`/`JDeferred`. `ErmineJson` builds the matching node; `ArgonautJson`
  still refuses every relation.
- `json/Wire.scala`: the wire's key names and the column-type vocabulary.
- `TestJson`: one property pinning the wrappers (28 properties).

### Wire contract (v1)

```
document  {"version": 1, "settings": {...}, "root": <Layout.Doc.Node, generic encoding>}
inline    {"kind": "inline",   "columns": [col...], "rows": [[cell...]...], "rowCount": n}
deferred  {"kind": "deferred", "columns": [col...], "token": "<opaque>", "expires": "<instant>"}
col       {"name": "<column>", "type": <Wire.columnTypes>, "nullable": <bool>}
```

- Column order: sorted by name (the `Header` and the record encoder both sort). Each row
  array follows it. Cells follow `Encode`'s mapping for the column's type: Int/Short/Byte
  and Double numbers (non-finite is an error), Long a decimal string, Bool a boolean, String
  a string, Date `yyyy-MM-dd` (UTC), Timestamp `yyyy-MM-dd'T'HH:mm:ss.SSS'Z'`, GUID the
  canonical string, a null `null`.
- Column `type` vocabulary: `Bool Byte Date Double GUID Int Long Short String Timestamp`
  (the PrimT names, except `UUID` is spelled `GUID`, the Ermine type name).
- `expires`: the Timestamp format above. `token`: at least 128 random bits, base64url, no
  padding; opaque to the client.
- Nodes are encoded by the GENERIC walker (named constructor fields): a multi-constructor
  `data` has `"tag"` first. `Layout.Doc.Node` therefore goes out as
  `{"tag":"Widget","name":"table","props":{...}}`, `{"tag":"VFlow","children":[...]}`, etc.
  SETTLED by J3b (2026-09-16), no field renamed: `Widget { name, props }`,
  `VFlow { children }`, `HFlow { children }`, `Grid { cells }`, `Tabbed { tabs }`,
  `Tab { label, content }` — and `Tab`, having one constructor, carries no `"tag"`:
  `{"tag":"Tabbed","tabs":[{"label":"a","content":{...}}]}`.
- `settings`: an object the runner is configured with (default `{}`), written verbatim.
- `errors`: reserved as the LAST top-level key for the `Streamed` strategy; not in v1.
- Request body (runner): `{"params": <JSON of the report's Params type>, "data":
  {"default": "inline"|"deferred", "strategy": "buffered", "threshold": <rows>|null}}`;
  `data` and each of its keys optional (defaults: inline, buffered, no threshold).
  `strategy: "streamed"` is refused in v1 with a 400.
- Delivery resolution: an explicit wrapper (`Inline`/`Deferred`, `JInline`/`JDeferred`)
  always wins; a bare relation takes `data.default`; a bare relation delivered inline whose
  row count exceeds `data.threshold` goes out deferred instead.
- Schema: a bare `[..r]` exports the union (`oneOf`, discriminated by `kind`), `Inline r`
  the inline arm only, `Deferred r` the deferred arm only.

## Running a report: the curl walkthrough (J3c, 2026-09-16)

`bin/ermine-serve` is the document runner behind the JDK's own HTTP server (no
new dependency).  Transcript below is REAL output against the example report
`core/src/test/resources/doc/Sales.e` with in-memory SQLite, elided only where
marked `...`.

```
$ bin/ermine-serve --root core/src/test/resources/doc --preload Sales --port 8080
listening on 8080                       # the only thing it writes to stdout

$ curl -s localhost:8080/health
{"status":"ok","version":1,"modules":["Bool","Builtin",...,"Relation.Sort","Sales",...]}

$ curl -s localhost:8080/report/Sales -H 'Content-Type: application/json' \
       -d '{"params": {"fromDay": "2026-01-05", "toDay": "2026-02-20",
                       "onlyRegion": "north", "orderBy": "ByAmount"}}'
{"version":1,"settings":{},"root":{"tag":"VFlow","children":[
 {"tag":"Widget","name":"heading","props":
   {"title":"Sales","sortColumn":"amount","matched":3,"total":4350.75}},
 {"tag":"Grid","cells":[
  [{"tag":"Widget","name":"table","props":{"kind":"inline","columns":[
      {"name":"amount","type":"Double","nullable":false},
      {"name":"day","type":"Date","nullable":false},
      {"name":"region","type":"String","nullable":false},
      {"name":"units","type":"Int","nullable":false}],
      "rows":[[840.0,"2026-01-19","north",2],[1200.5,"2026-01-05","north",3],
              [2310.25,"2026-02-14","north",7]],"rowCount":3}},
   {"tag":"Widget","name":"table","props":{"kind":"inline","columns":[
      {"name":"region","type":"String","nullable":false}],
      "rows":[["east"],["north"],["south"],["west"]],"rowCount":4}}],
  [{"tag":"Widget","name":"table","props":{"kind":"deferred","columns":[
      {"name":"amount","type":"Double","nullable":false},
      {"name":"item","type":"String","nullable":false},
      {"name":"units","type":"Int","nullable":false}],
      "token":"HyCqXpeUb93IWNkxqJnM2g","expires":"2026-09-16T15:20:12.814Z"}},
   {"tag":"Widget","name":"text","props":"line items on demand"}]]}]}}

$ curl -s localhost:8080/data/HyCqXpeUb93IWNkxqJnM2g
{"kind":"inline","columns":[{"name":"amount","type":"Double","nullable":false},
 {"name":"item","type":"String","nullable":false},
 {"name":"units","type":"Int","nullable":false}],
 "rows":[[75.5,"gizmo",1],[615.75,"doohickey",1],[840.0,"gizmo",2],
         [1200.5,"widget",3],[1550.0,"widget",4],[1990.0,"widget",5],
         [2310.25,"widget",7],[4100.0,"doohickey",11]],"rowCount":8}
```

A `Maybe` parameter may be left out of the object entirely; `data.default`
chooses the delivery of the BARE relations and `data.threshold` defers the ones
that are too big, while a `Deferred` wrapper in the report is deferred whatever
the request says:

```
$ curl -s localhost:8080/report/Sales \
       -d '{"params": {"fromDay": "2026-01-01", "toDay": "2026-12-31",
                       "orderBy": "ByDay"},
            "data": {"default": "inline", "threshold": 4}}'
... "heading" props {"title":"Sales","sortColumn":"day","matched":8,"total":12682.0};
    the 8-row table comes back "deferred" with a token, the 4-row regions table
    is still "inline", the line items are "deferred" as always ...
```

Every failure is `{"error":{"path":..,"message":..}}`.  What `path` MEANS is
decided by the status, and a client must read it that way:

| Status | `path` |
|---|---|
| 400 | a JSON path into the REQUEST body: `$`, `$.params...`, `$.data.<key>` |
| 404, 405, 413 | always `null` |
| 500 | a JSON path into the RESPONSE document -- the node the report could not encode, or the relation whose scan failed -- when there is one, else `null`.  NEVER a place in the request: the parameters already satisfied the report's own type, so a 500's path is diagnostic, not something to correct and resend |


```
$ curl -s -w ' [%{http_code}]' localhost:8080/report/Nope -d '{}'
{"error":{"path":null,"message":"no module named Nope"}} [404]

$ curl -s -w ' [%{http_code}]' localhost:8080/report/Sales \
       -d '{"params":{"fromDay":"nope","toDay":"2026-01-01","orderBy":"ByDay"}}'
{"error":{"path":"$.params.fromDay","message":"the string \"nope\" is not a date yyyy-MM-dd"}} [400]

$ curl -s -w ' [%{http_code}]' localhost:8080/report/Sales \
       -d '{"params":{...},"data":{"strategy":"streamed"}}'
{"error":{"path":"$.data.strategy","message":"the \"streamed\" strategy is not in version 1 of the wire; use \"buffered\""}} [400]

$ curl -s -w ' [%{http_code}]' localhost:8080/data/notarealtokenatall00
{"error":{"path":null,"message":"no such token, or it has expired"}} [404]

$ curl -s -w ' [%{http_code}]' localhost:8080/report/Sales     # no body, wrong method
{"error":{"path":null,"message":"this route takes POST"}} [405]
```

Note the ROW ORDER: a relation carries no sort order, so the rows are whatever
the scan yields, and the deferred re-request re-scans -- the same rows, not
necessarily the same order (J3b).  Flags: `--root DIR` and `--preload Module`
(both repeatable), `--db URL`, `--dialect sqlite|mssql|mysql|postgres|vertica`,
`--port N` (0 binds an ephemeral port and prints it), `--report-name NAME`,
`--ttl SECONDS`, `--max-tokens N`, `--threads N`, `--max-body BYTES`,
`--settings JSON`.  One INFO line per request on `ermine.json.http`
(`POST /report/Sales status=200 ms=31 bytes=255`) beside J3b's per-relation
lines on `ermine.json.doc`; both need a log4j configuration to be visible
(`res/conf/log4j.prp`, absent from the repository).

## Stages

| Id | Branch | What | Depends on | Phase |
|---|---|---|---|---|
| J3a | json-wrappers | Schema exporter: relation union/arms, `nullable` + `rowCount`, row-polymorphic relation arm, zod discriminated union, fixtures | contract | 1 -- LANDED |
| J2a | json-decode | `json/Decode.scala` (type-directed JSON -> Runtime), entry-type check, round-trip + agreement properties | contract | 1 -- COMMITTED 40827243, json-encode merged in, landing |
| J3b | json-doc | `modules/Layout/Doc.e`; `json/Doc.scala`, `json/Write.scala` in the scanner effect; hot-loop row encoder; Buffered strategy; delivery policy + threshold; `PlanCache` + deferred tokens; per-relation row/byte log | contract | 1 -- BUILT bf832e46, landing |
| J3c | json-runner | `json/Runner.scala` (boot, report lookup, `Params -> Node` check, decode, apply, write on one connection), HTTP server (`POST /report/<Module>`, `GET /data/<token>`), `bin/ermine-serve` | J2a, J3b | 2 |
| J3d | json-client | BUILT 2026-09-16 (report-J3d.md, design note 3.7e): `modules/Layout/Widgets/{Format,Table,Drilldown,Scorecard}.e` + the `Layout/Widgets.e` umbrella (one module per widget: field selectors are module-global); `client/` TS package -- generated zod, dispatcher, legacy table adapters, `formatDisplay` port, `scorecard` end to end | J3a, J3b | 2 -- BUILT |
| J3e | json-charts | Chart/stylebox prop types and adapters (`axisChart`, `pieChart`, `drilldownPieChart`, `drilldownBar`, `styleBox`; `treeMap` registered as unsupported) | J3d | 3 |
| J2b | json-spread | `Spread Json` wrapper (encode merge, schema additional properties, decode leftovers); then the builtin `Json a` constraint if time allows | J2a, J3a | 3 -- BUILT (Part 1; Part 2 = design only) |
| P1..P3 | json-encode-2.11 | 2.11 ports: P1 = contract+J3a+J2a, P2 = J3b+J3c, P3 = J3d+J2b | landings | after each |
| J3f | json-fetch | `modules/Layout/Fetch.e` (`Fetch a`: `scanRelation`, `scanRelationInOrder`, `scan`/`runScan`, a `Relation.Scan` runner) and its interpreter in `json/Runner.scala` (`Params -> Fetch Node` beside `Params -> Node`); four example reports `core/src/test/resources/doc/Fetch*.e`; six `TestRunner` properties | J3c, J3d, J3e | 4 -- BUILT (below) |

Reviews: `brief-review.md`, one independent reviewer per stage before landing. Ports:
`brief-port-211.md`.

Phase 1 runs J3a, J2a, J3b concurrently. Phase 2 starts each stage as its dependencies land.
2.11 ports run concurrently with later Scala 3 stages, one port agent at a time on the 2.11
branch (they share `Lib.scala`).

## Handoff log

- 2026-09-16 06:00 plan written; contract compiled; TestJson+TestSchema+TestNamedFields 61/61.
- 2026-09-16 J3b built on `json-doc` (uncommitted): `Layout/Doc.e`, `json/Doc.scala`,
  `json/Write.scala`, `json/PlanCache.scala`, `TestDoc`; the four suites 79/79; corpus
  89/79/0 over 168; REPL and LSP smokes green; `*TestLoopTrace` 3 properties but the Lean
  model replay SKIPPED (the executable is absent in this worktree). Two DB-layer bugs found:
  `RecordMap.SharingKeySet.get` threw on every lookup on Scala 3 (fixed in this stage), and
  `SqlExecution` reads a GUID column before `wasNull`, so a NULL GUID throws (NOT fixed).
- 2026-09-16 J3b reviewed FIX-THEN-LAND (`review-J3b.md`); both required fixes applied in the
  worktree: a refused row now leaves its scan by `Stop` so the driver tears it down (the
  writer no longer throws through `EffectfulProcedure.withDriver`), and the `RecordMap`
  comment / report / design note now state the real blast radius. `TestDoc` 20/20, the four
  suites 81/81, and `*TestLoopTrace` re-run against the Lean binary built in the `json-wrappers`
  worktree (`-Dermine.looptrace=`): **720/720 segments agree, 0 skipped**.
  **For the landing**: the `RecordMap` line restores record EQUALITY for records
  from a SQL scan, so `relational.uniqSorted`/`uniq` and `Set[Record]` deduplicate again — a
  relational-engine behaviour change whose real gate is the full `core/test`, not the JSON
  suites. A ticket for J3c: `relational/package.scala:121-128` needs
  `try k(d) finally teardown()` so a scan that throws on its own is torn down too.
- 2026-09-16 J3b landing gate (full `core/test` on bf832e46) found a REAL bug that
  `Layout/Doc.e` exposed: `Renamer 3.2a.6.4 corpus: siblings are sorted, and no two of them
  straddle` failed with 7 pairs, all record-style constructors straddling their own field
  symbols. Root cause in Stage 1a's `lsp/Symbols.scala`: selectors were emitted as SIBLINGS of
  the constructor whose span contains them. Fixed on `json-doc` (uncommitted, on top of the
  commit): a field symbol is now a CHILD of the constructor that declares it, which is the LSP
  Field-in-Struct shape and the one this builder already uses for every other container. No
  `.e` fixture in `tracker/lsp-tests/` has a record `data`, so no pinned LSP expectation
  changed and the smoke stays at 577 checks. Two new properties in `TestNamedFields` (random
  declarations + an exact tree) pin the shape where the syntax is generated; mutation-checked
  against the old shape. Also measured, not fixed: `TestTolerantCheck` alone on this tree x3,
  E11a green every time (58/58), so the landing run's E11a failure did not reproduce here.
- 2026-09-16 06:20 contract + plan committed a7e8e050 on json-s3-base; worktrees
  wt-json-wrappers / wt-json-decode / wt-json-doc created; J3a, J2a, J3b implementers launched.
  Later briefs (J3c, J3d, J3e, J2b, review, port) written, uncommitted in wt-json until the
  first landing.
- 2026-09-16 ~08:00 J2a BUILT (71/71), J3b BUILT (79/79), J3a BUILT (67/67; zod replay 370/0),
  all corpus 89/79/0. Reports saved by the orchestrator (subagent harness blocks .md writes).
  Reviews: J2a FIX-THEN-LAND (flaky (e2) depth probe; unpinned `tag`-field disagreement),
  J3b FIX-THEN-LAND (RowError must exit via Stop so the driver tears down; RecordMap comment
  and two gate figures corrected), fixes dispatched to the implementers; J3a review running.
  Process slip: briefs written after a7e8e050 were not in the stage worktrees; copied there.
  J3b found and fixed a Scala 3 inference bug in record/RecordMap.scala (SharingKeySet.get ->
  Nothing cast) that silently broke record equality / uniq dedup on the relational side: the
  landing full core/test is its real gate. Tickets for J3c: NULL in a GUID column NPEs in
  SqlExecution.nextRecord; EffectfulProcedure.withDriver lacks finally around teardown.
- 2026-09-16 ~08:30 J3a reviewed FIX-THEN-LAND (one fix: `Gen.hexChar` absent from the 2.11
  scalacheck; applied by the orchestrator, 67/67) and COMMITTED on json-wrappers with the
  contract, the briefs and review-J3a.md; landing gate (full core/test) running. J3b committed
  bf832e46 on json-doc after its fixes (81/81, looptrace 720/720), full core/test running.
  NOTE for J3b/J3d: the wrappers take a ROW, not a relation -- `Inline (|a, b|)` / `Inline r`,
  since `data Inline r = Inline [..r]`. J3a found `Gen.pick` biased in ScalaCheck 1.15.4
  (first pool element almost never kept; `TestSchema.pickN` replaces it) and that
  `Session.toHeader` MatchErrors on a GUID column (pre-existing).
- 2026-09-16 ~09:30 J2a review fixes applied on json-decode: the flaky `(e2)` depth probe
  now reads back at three quarters of its measurement with a fixed 100,000-level in-memory
  document, and the `tag`-field disagreement is refused by `Decode`, `Schema` AND `Encode`
  alike (pinned in `(map)` and `(d)`). Two further test flakes found while verifying and
  fixed: `TestJson` declared three different `data Shape`s and two `data Series` in one
  process, which the PROCESS-GLOBAL `DataConDecl` registry turns into a cross-property race
  (one red in twenty runs), and `TestDecode`'s null-wrapper equivalence had a hole for a
  raw `Some(JNull)` inside a native container. json-encode f8a789d1 (J3a) then merged into
  json-decode; see `tracker/json-stage3/report-J2a.md` for the post-merge gate numbers.
- 2026-09-16 ~12:00 J2b BUILT on json-spread (off json-decode d2177ca5): `Spread Json`
  merges into the encoder's object, opens the exporter's (`additionalProperties: true`,
  zod `.passthrough()`) and is gathered back by the decoder; `Spread` of anything but
  `Json`, a second one per constructor and a positional one are refused by the exporter,
  by `Decode.entry` and by `Encode.rejections` alike, at the same field. `TestSchema.shape`
  grew a spread row, so the encode/schema property, the round trip and the agreement
  property all carry spread types. **Part 2 (the builtin `Json a` constraint) is a DESIGN
  ONLY** -- `tracker/json-stage3/J2b-constraint-design.md`; see `report-J2b.md` for the
  gate numbers and the reason.
- 2026-09-16 J3b built on `json-doc` (uncommitted): `Layout/Doc.e`, `json/Doc.scala`,
  `json/Write.scala`, `json/PlanCache.scala`, `TestDoc`; the four suites 79/79; corpus
  89/79/0 over 168; REPL and LSP smokes green; `*TestLoopTrace` 3 properties but the Lean
  model replay SKIPPED (the executable is absent in this worktree). Two DB-layer bugs found:
  `RecordMap.SharingKeySet.get` threw on every lookup on Scala 3 (fixed in this stage), and
  `SqlExecution` reads a GUID column before `wasNull`, so a NULL GUID throws (NOT fixed).
- 2026-09-16 J3d built on `json-client` (uncommitted): `Layout/Widgets.e` +
  `Layout/Widgets/{Format,Table,Drilldown,Scorecard}.e`, `client/` (npm package,
  node_modules gitignored, `package-lock.json` committed, zod 3.23.8 / typescript
  5.6.3 pinned), `core/src/test/resources/modules/Doc/SalesReport.e`, `TestWidgets`
  (5 properties) with `WidgetCorpus` and `SalesReportDoc` runMains. Field selectors
  are MODULE-global in Ermine, so one module per widget -- the pattern J3e must
  follow. `table` is a keyword: the smart constructor is `tabular`, the registry
  name is still "table". Property (a) 5/5, node suite 33/33 over a 200-document
  corpus, `tsc --strict` and `check-generated.sh` green.
- 2026-09-16 J3e built on `json-charts` (uncommitted, off J3d c5f92b2d): five more Ermine
  modules under `Layout/Widgets/` (`Chart` holds the shared meta/axis/series vocabulary,
  one module per widget as J3d's field-selector rule requires), `client/src/charts.ts`,
  `client/test/charts.test.ts`, four more generated zod modules, chart generators in
  `TestWidgets`, and an `axisChart` + `pieChart` in `Doc/SalesReport.e`. All five live
  renderers of design note 4.1 are now adapted and `treeMap` is registered as
  unsupported (out of `defaultRegistry()`, `UNSUPPORTED_WIDGETS`). The ONE legacy callback
  that could not be avoided is `styleBoxData` (`withStyleBoxData` has no local branch), so
  the style box's grid renders but its cell-click popup does not. Scala 93/93
  (TestWidgets 6), node 59/59, `tsc --strict` and `check-generated.sh` green.
- 2026-09-16 J3e reviewed FIX-THEN-LAND (`review-J3e.md`); the one required fix applied in
  the worktree: the PIE CHART'S SLICE LABEL was emitted raw where
  `RelationRunner.runPieChartData` sends it FORMATTED (`lc.format.basicEval(labels)
  extractNullableString ""`, RelationRunner.scala:240), so a non-`Default` `pieLabelFormat`
  was silently inert and a Date label column would have put a `[y,m,d]` array in the legend.
  `pieRows` now formats the raw cell with `format.ts` and stringifies (null -> ""),
  threading a `FormatEnv` through `pieArgs`/`pieChartWidget` as `styleBoxWidget` already
  does. New pin `(x-pie-label)`, `(x-pie)` switched to a non-`Default` label format, and
  `(b)` now checks `row[0]`; reverting the fix fails all three. All eight optional items
  taken too. Node **60/60**.
  **A standing cost for later stages**: `tracker/tools/lsp-smoke.sh` boots a session of 129
  stdlib modules and takes 89-116 s depending on load; J3e raised its hang guard 120 -> 240 s
  after two timeouts. Every stage that adds modules moves this. The next agent that hits it
  should NOT simply double the number again — it wants a subset boot for the smoke, or a
  cached session.
- 2026-09-16 J3b reviewed FIX-THEN-LAND (`review-J3b.md`); both required fixes applied in the
  worktree: a refused row now leaves its scan by `Stop` so the driver tears it down (the
  writer no longer throws through `EffectfulProcedure.withDriver`), and the `RecordMap`
  comment / report / design note now state the real blast radius. `TestDoc` 20/20, the four
  suites 81/81, and `*TestLoopTrace` re-run against the Lean binary built in the `json-wrappers`
  worktree (`-Dermine.looptrace=`): **720/720 segments agree, 0 skipped**.
  **For the landing**: the `RecordMap` line restores record EQUALITY for records
  from a SQL scan, so `relational.uniqSorted`/`uniq` and `Set[Record]` deduplicate again — a
  relational-engine behaviour change whose real gate is the full `core/test`, not the JSON
  suites. A ticket for J3c: `relational/package.scala:121-128` needs
  `try k(d) finally teardown()` so a scan that throws on its own is torn down too.
- 2026-09-16 J3c BUILT on `json-runner` (uncommitted): `json/Runner.scala`, `json/Server.scala`,
  `json/ServeMain.scala`, `bin/ermine-serve`, `core/src/test/resources/doc/Sales.e`,
  `TestRunner` (16 properties, all green; two deliberate mutants falsify (a)/(c) and (b1)/(b6)).
  Concurrency: evaluation serialised behind one monitor, scans and writes concurrent —
  design note §3.7d. **Both DB tickets J3b handed on are FIXED**, each with a property:
  `SqlEmitter.EmitUuid_Strings.getUuid` reads a SQL NULL as a null UUID instead of throwing
  (so `SqlExecution.nextRecord`'s `wasNull` test can do its job), and
  `relational/package.scala`'s `EffectfulProcedure.withDriver` now has `try k(d) finally
  teardown()`. Two defects on the merged tip were also fixed in `TestDoc`: `(b-sql)`'s
  `badNulls == List("UUID")` is now empty (the GUID fix moved the measurement), and `(d)`'s
  `dImps` lacked the Stage 2a modules J2a added to `TestSchema.shape` (Date, GUID, Prim,
  Native.Maybe, Native.Pair, Vector as V), which failed 13 of its 80 cases with "undefined
  type" — a J2a/J3b merge gap, red on the tip before this stage touched anything.
- 2026-09-16 12:21 LANDED: json-encode = 5d0a2614, full core/test 1196/1196 on that tree (1130 at the
  start; the one quarantined refutation removed, TestRunner 17, TestWidgets 6, TestDoc 20, TestDecode 13,
  TestSchema 27, TestNamedFields 16, TestJson 28 added). client/scripts/check-corpus.sh on the landed tree:
  60/60 node tests over a 200-document corpus of all eight widgets. 2.11: json-encode-2.11 = d75dfb1f
  (P1 c8d0dac1, P2 438eeb0c, P3 d75dfb1f), full core/test 858/858. Nothing pushed; nothing merged into
  scala3-migration or backport-2.11. Stage worktrees wt-json-{wrappers,decode,doc,runner,client,spread,
  charts} are all ancestors of 5d0a2614 and can be removed. Orchestrator note: the last runs were started
  with nohup and finished unnoticed for three hours -- background jobs must be harness-tracked or polled.
- 2026-09-18 J3f BUILT on `json-fetch` (worktree `ermine-scala-wt-json-fetch`, from json-encode 6c44d72d):
  `scanRelation` / `scanRelationInOrder` for the JSON runner. The user's question: `Params -> Node` never
  sees a row, so the old `Report.e:617` bridge (rows to a continuation, list back to SQL via `relation`)
  had no counterpart. Design (design note §3.4b): a SEPARATE type `Layout.Fetch.Fetch a` -- `Done a |
  Scan Sort# Relation# (List Record# -> Fetch a)` -- with `done`, `scanRelation`, `scanRelationInOrder`,
  `scan`/`scanInOrder`/`runScan` (Cont, as before) and `runner : RunScan_S List (Fetch a)` for
  `Relation.Scan`; NO monad instance (the user: "before we just passed in a continuation"); `Node` and
  the generated zod untouched. `Runner.scala`: `Params -> Fetch Node` accepted beside `Params -> Node`
  (`resultKind`), `renderFetch` evaluates and writes inside one `Run[DB].run`, each step under
  `evalLock`, each scan outside it, `ScanFailed(n)` for a throwing scan; `Layout.Fetch` is loaded at
  boot. Examples, each a report a pure one cannot be, `core/src/test/resources/doc/`: `FetchHeadline`
  (heading numbers from the rows; an empty scan yields a text widget instead of a table),
  `FetchRunning` (`scanRelationInOrder` by day, running total + sequence number folded in Ermine,
  `relation`'d and `join`ed to `targets` IN SQL), `FetchTabs` (one tab per region found by a scan, each
  tab's table a plan that still defers: 4 tokens, north resolves to 3 rows), `FetchTopN` (SQL aggregate
  scanned largest-first, top N + "Other" slice for a pie, second scan of targets in the same `do`);
  `FetchData` holds the two literal relations. `TestRunner` 23/23 (17 + (fx1)-(fx4), (fx-conn): one
  connection for a report with two scans and an inline relation, (fx-err): a throwing continuation is a
  500 naming the report; (b3) gained the `Int -> Fetch Int` refusal). Three Ermine name clashes found
  by `bin/ermine :load` (`count`, `descending`, `columns` are global selectors) -- renamed. Gate:
  `scripts/gate.sh status` on the commit. NOT landed on json-encode; no 2.11 port; `Layout.Scan`
  (the `Report f z` runner) left as is.
