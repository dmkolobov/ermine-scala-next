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
| J3a | json-wrappers | Schema exporter: relation union/arms, `nullable` + `rowCount`, row-polymorphic relation arm, zod discriminated union, fixtures | contract | 1 |
| J2a | json-decode | `json/Decode.scala` (type-directed JSON -> Runtime), entry-type check, round-trip + agreement properties | contract | 1 |
| J3b | json-doc | BUILT 2026-09-16 (report-J3b.md, design note §3.7c): `modules/Layout/Doc.e`; `json/Doc.scala`, `json/Write.scala` in the scanner effect; hot-loop row encoder; Buffered strategy; delivery policy + threshold; `PlanCache` + deferred tokens; per-relation row/byte log | contract | 1 |
| J3c | json-runner | `json/Runner.scala` (boot, report lookup, `Params -> Node` check, decode, apply, write on one connection), HTTP server (`POST /report/<Module>`, `GET /data/<token>`), `bin/ermine-serve` | J2a, J3b | 2 |
| J3d | json-client | `modules/Layout/Widgets.e` prop types for the seven live widgets + one new widget; `client/` TS package: zod generated from those types, dispatcher, adapters to the legacy renderers, `formatDisplay` port, the new widget end to end | J3a, J3b | 2 |
| J2b | json-spread | `Spread Json` wrapper (encode merge, schema additional properties, decode leftovers); then the builtin `Json a` constraint if time allows | J2a, J3a | 3 |
| P1..P3 | json-encode-2.11 | 2.11 ports: P1 = contract+J3a+J2a, P2 = J3b+J3c, P3 = J3d+J2b | landings | after each |

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
