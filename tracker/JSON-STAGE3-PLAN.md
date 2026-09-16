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

## Stages

| Id | Branch | What | Depends on | Phase |
|---|---|---|---|---|
| J3a | json-wrappers | Schema exporter: relation union/arms, `nullable` + `rowCount`, row-polymorphic relation arm, zod discriminated union, fixtures | contract | 1 -- LANDED |
| J2a | json-decode | `json/Decode.scala` (type-directed JSON -> Runtime), entry-type check, round-trip + agreement properties | contract | 1 |
| J3b | json-doc | BUILT 2026-09-16 (report-J3b.md, design note §3.7c): `modules/Layout/Doc.e`; `json/Doc.scala`, `json/Write.scala` in the scanner effect; hot-loop row encoder; Buffered strategy; delivery policy + threshold; `PlanCache` + deferred tokens; per-relation row/byte log | contract | 1 |
| J3c | json-runner | `json/Runner.scala` (boot, report lookup, `Params -> Node` check, decode, apply, write on one connection), HTTP server (`POST /report/<Module>`, `GET /data/<token>`), `bin/ermine-serve` | J2a, J3b | 2 |
| J3d | json-client | BUILT 2026-09-16 (report-J3d.md, design note 3.7e): `modules/Layout/Widgets/{Format,Table,Drilldown,Scorecard}.e` + the `Layout/Widgets.e` umbrella (one module per widget: field selectors are module-global); `client/` TS package -- generated zod, dispatcher, legacy table adapters, `formatDisplay` port, `scorecard` end to end | J3a, J3b | 2 -- BUILT |
| J3e | json-charts | Chart/stylebox prop types and adapters (`axisChart`, `pieChart`, `drilldownPieChart`, `drilldownBar`, `styleBox`; `treeMap` registered as unsupported) | J3d | 3 |
| J2b | json-spread | `Spread Json` wrapper (encode merge, schema additional properties, decode leftovers); then the builtin `Json a` constraint if time allows | J2a, J3a | 3 |
| P1..P3 | json-encode-2.11 | 2.11 ports: P1 = contract+J3a+J2a, P2 = J3b+J3c, P3 = J3d+J2b | landings | after each |

Reviews: `brief-review.md`, one independent reviewer per stage before landing. Ports:
`brief-port-211.md`.

Phase 1 runs J3a, J2a, J3b concurrently. Phase 2 starts each stage as its dependencies land.
2.11 ports run concurrently with later Scala 3 stages, one port agent at a time on the 2.11
branch (they share `Lib.scala`).

## Handoff log

- 2026-09-16 06:00 plan written; contract compiled; TestJson+TestSchema+TestNamedFields 61/61.
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
