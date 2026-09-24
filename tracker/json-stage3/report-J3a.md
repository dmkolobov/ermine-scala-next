# J3a as built: relations in the schema exporter (the §3.4a union, the wrappers, the generic arm)

Branch `json-wrappers`, worktree `~/research/ermine/ermine-scala-wt-json-wrappers`, off `json-s3-base` a5a53da4. Uncommitted. 2026-09-16, ~3 h of the 4 h budget. (Report text written by the implementer agent, saved to this path by the orchestrator: the agent's harness blocked writing `.md` files.)

## What was built

| File | Change |
|---|---|
| `core/src/main/scala/com/clarifi/reporting/ermine/json/Schema.scala` | the relation delivery union and its two arms, keys from `Wire`; the third column const `nullable`; the column `type` via `Type.primTypes` + `Wire.columnType`; the GENERIC (row-variable) arm; `abstractRowParameters` at the root; `keyOf` spells a type variable `_`; header comment rewritten |
| `.../json/Zod.scala` | `z.discriminatedUnion("kind", ...)` for the delivery arms (discriminator now looked up: `tag`, else `Wire.Kind`); `minLength` -> `.min(n)`; comment |
| `.../json/Validate.scala` | `minLength`; the comment now states exactly what its three `format` checks do and how zod's `.datetime()` differs |
| `scalacheck-binding/src/main/scala/TestSchema.scala` | column pool (ten types x plain/`Nullable`), relation shapes in the generator, `pickN`, five new properties (r-a)...(r-d) + (r-pins), the document writer played by the test (`DocBuilder`), the zod sample dump; (c) and (e) extended to wrapper-bearing shapes |
| `core/src/test/resources/schema/` | `UserRelation.*` regenerated; new `UserInline.*`, `UserDeferred.*`, `UserTableProps.*` (11 fixtures, schema + zod each) |
| `tracker/JSON-API-DESIGN.md` | "Stage 1b as built": a "Revised in J3a" paragraph on the relation row |
| `tracker/JSON-STAGE3-PLAN.md` | J3a marked built; handoff-log entry |

No production file outside `json/` was touched; `Encode`, `Lib`, `modules/Json.e` are the contract commit's, unchanged. `bin/ermine-schema` needed no change (the root rule lives in `Schema.exportType`, so CLI, `exportNamed` and the LSP request all inherit it).

## The shapes, as they now export

```
bare  [..r]    {"oneOf":[<inline arm>, <deferred arm>]}
Inline r       <inline arm>            Deferred r   <deferred arm>
inline arm     {"type":"object","properties":{"kind":{"const":"inline"},"columns":...,"rows":...,
                "rowCount":{"type":"integer","minimum":0}},
                "required":["kind","columns","rows","rowCount"],"additionalProperties":false}
deferred arm   ... "token":{"type":"string","minLength":1},
                 "expires":{"type":"string","format":"date-time"} ...
closed row     columns = prefixItems of {"name":{const},"type":{const},"nullable":{const}},
               minItems = maxItems = n; rows = array of n-tuples of the field schemas
row variable   columns = array of {"name":string,"type":enum Wire.columnTypes,"nullable":boolean};
               rows = array of arrays of string|number|boolean|null
```

## Decisions taken in code (the plan did not fix these)

1. **The wrappers take a ROW, not a relation.** `data Inline r = Inline [..r]` makes `Inline : rho -> *`, so the type is `Inline r` or, concretely, `Inline (|a, b|)` — **not** `Inline [a, b]`, which is a kind error in a declaration and reaches the exporter as nonsense from `replType` (which does not kind-check). Fixtures and properties use the row spelling.
2. **A column `type` is `Wire.columnType` of the field's `PrimT`** (`Type.primTypes`, the table `field` declarations are checked against), not a name read off the `Con` — so exporter and writer share one spelling (`UuidT` -> `GUID`) instead of agreeing on strings. A type with no `PrimT` is refused at the column; defensive only, since `field` itself accepts nothing but the ten types and `Nullable` of each.
3. **`nullable` is a const from the DECLARED type** and the cell schema keeps its `anyOf ... null`: two views of one fact, the row schema authoritative for a cell, the descriptor a label for the client.
4. **Abstract row parameters at the ROOT only** (`Ctx.abstractRowParameters`): an under-applied `data` type is applied to its own declaration variables when every missing parameter is row-kinded; a missing `*` parameter is refused. Nothing else accepts a free variable — an open row is the generic arm only INSIDE a relation, a bare `{..r}` record is the same error as before.
5. **A `$defs` key spells every type variable `_`** (`Test.TableProps__`), not by declared name: the generic schema does not depend on which variable stands there, so `TableProps r`, `TableProps q` and the `r` of an enclosing `data Page s = Page { body : TableProps s }` are one schema and one key at any nesting depth. `$id` still renders the type as asked (`ermine:Test/TableProps r`).
6. **The `*`-parameter refusal keeps the old wording** with the new reason appended, because `tracker/tools/lsp-client.py` asserts on that phrasing.
7. **Zod's discriminator is looked up, not hard-coded**: `tag` if every arm pins it, else `kind`.
8. **`Validate`'s `date-time` stays `ISO_OFFSET_DATE_TIME`** (offset required, seconds optional) — RFC 3339; zod's `.datetime()` is stricter (`Z` only). Both accept the wire's `yyyy-MM-dd'T'HH:mm:ss.SSS'Z'`.
9. **Test-side**: the test writes the wire objects itself (`DocBuilder`, a `JsonBuilder` that is `ArgonautJson` except at a relation), so documents are produced by the real walker with the real `Delivery` and only the relation objects are hand-built.

## Departures from the brief

- The column `type` const is derived from the `PrimT` rather than matched against `Wire.columnTypes` (decision 2). Same strings, one source.
- `$defs` spelling: `_` chosen over the declared name (decision 5), because the declared name is not stable under nesting.
- Property (b)'s mutation mix is printed by the property; a second, generic-arm mix is printed by (r-c), because the generic arm cannot see some pinned-arm mutations (wrong `nullable`, wrong row length).

## Properties (random declarations and values)

| Id | What | Size / non-vacuity |
|---|---|---|
| (r-a) | a hand-built inline document validates against `[..r]` AND `Inline r` and FAILS against `Deferred r`; deferred the mirror image. Columns from the pool's `PrimT` through `Wire.columnType`, cells by `Encode` on evaluated Ermine records | 150 cases / 900 verdicts; coverage 303 rows, 133 null cells, 25 empty relations, **20/20** column kinds met with a row — this assertion caught `Gen.pick`'s bias |
| (r-b) | one random mutation is rejected by BOTH the arm and the union | 150 cases, 300 mutants; mix: `bad expires 18, bad rowCount 20, cell type 16, dropped key 46, empty token 19, extra key 41, row length 19, wrong column type 35, wrong kind 40, wrong nullable 46`; each case also asserts the UNMUTATED document is accepted |
| (r-c) | a random props `data` with one row parameter: `exportNamed` gives ONE schema (byte-identical across three random instantiations of `r`) accepting each instantiation's document; a generic mutation is rejected; the literal relation's `PrimExpr` cells equal the Ermine values' cells | 40 props types x 3 rows = 120 documents, 243 relations |
| (r-d) | random `data` (record-style and positional, relations nested anywhere) exports, its zod renders, and the walker-written document validates | 100 cases; asserts all three deliveries were written (inline 51, deferred 34, request 28) — ties `Encode`'s wrapper recognition to the exporter's arm choice |
| (c) | byte-identical across declaration order AND load order, wrapper-bearing shapes included | 100 cases |
| (e) | `Zod.render` succeeds and names every `$defs` entry, wrappers included | 100 cases |
| (r-pins) | wrapper is neither `$defs` nor `{tag,args}`; arm key order; a `Nullable` descriptor verbatim; `Test.TableProps__` identical from `exportNamed`, from `TableProps q`, and inside `Page`; `$id`; `z.discriminatedUnion("kind")`; `*`-parameter refusal; open-record refusal; `field sfChar : Char` refused by the language | — |

## Gates

Scratch prefix `SP = /tmp/claude-1000/-home-dmitry-research-caliper/c359de0f-018b-42eb-960e-7519d0922cee/scratchpad/j3a/`.

| # | Gate | Result | Log |
|---|---|---|---|
| 1 | `sbt -batch core/compile core/copyResources` | success | `SP/gate-suites-final.log`, `SP/compile-final.log` |
| 2 | `TestSchema` + `TestJson` + `TestNamedFields` | **67/67** (25 + 28 + 14; base was 61, TestSchema 19 -> 25); "schema gate: 11 fixtures match" | `SP/gate-suites-final.log` |
| 3 | `core/testOnly *TestLoopTrace` | 3/3 properties; `720 solves; 720 segments; 720 agree; skipped=0; hashdiff=0; eqdiff=0` | `SP/looptrace2.log` |
| 4 | corpus batch + verdicts | **89 LOADED / 79 REJECTED / 0 UNKNOWN over 168**, unchanged | `SP/corpus.log` |
| 5 | `repl-smoke.sh` | PASS, 9 groups / 86 checks (json 20) | `SP/repl-smoke.log` |
| 5 | `lsp-smoke.sh` | **PASS, 577 checks** | `SP/lsp-smoke3.log` |
| J3a | `tsc --strict --noEmit` over all 11 fixtures | OK | `SP/ts/` |
| J3a | 180 generated zod modules compiled with `tsc --strict`, replayed against the validator's verdicts | **370 documents (220 accept / 150 reject), 0 mismatches** | `SP/ts/check.js`; regenerate with `ERMINE_ZOD_SAMPLES=<dir> sbt 'core/testOnly ...TestSchema'` |
| — | `bin/ermine-schema -i Json Inline`, `--zod -i Json Deferred` | generic arms printed | `SP/cli.log` |

Gate notes: `TestLoopTrace` first ran with the replay SKIPPED — no worktree had the Lean binary; `cd tracker/lean && lake build looptrace` (~15 min, Mathlib) built it in THIS worktree and the 720/720 is from the run after (`.lake` is gitignored). `lsp-smoke.sh` failed twice before passing: once on the `ermine/schema` refusal message (fixed by decision 6, not by changing the check), once on 7.2/7.4 debounce timings while the Lean build saturated the machine. `tracker/repl-classpath.txt` was regenerated for the smokes and restored.

## Open issues

1. **`Gen.pick` is biased in ScalaCheck 1.15.4** — its reservoir step computes `x & Long.MaxValue % count`, i.e. `x & (Long.MaxValue % count)`, so the FIRST pool element is almost never kept. Found by (r-a)'s coverage assertion. `TestSchema.pickN` replaces it, and `recordShape` (same bias on `fieldPool`, so `sfInt` was nearly never generated in Stage 1b) now uses it too. Other suites still call `Gen.pick`; worth a sweep.
2. **`Session.toHeader` throws on a GUID column**: it reads `PrimT.withName(ty.string)`, whose cases spell it `"UUID"`, never `"GUID"` -> `MatchError` for a `table` with a GUID column. Pre-existing.
3. A relation over a row with a **`Part` constraint** is not exercised by any property.
4. **An existentially bound row is still refused** (`data X = forall r. X (Inline r)`), though the generic arm would describe it exactly. One line in `constructor` would allow it.
5. `x-ermine: {module, type, hash}` (§3.5's drift guard) still unimplemented; fixture byte-equality plays that role in-repo.

## What later stages must know

**J3b (document writer)**
- Keys and vocabulary from `Wire`; fixture key order is `kind, columns, rows, rowCount` and `kind, columns, token, expires`.
- A column descriptor has THREE required keys, `additionalProperties:false`: `{"name","type","nullable"}`; `type` = `Wire.columnType(primT)` — `GUID`, never `UUID`, never a `Nullable` spelling.
- `rowCount` required and >= 0; `token` non-empty; `expires` must carry an offset (`Z`). An empty relation is `"rows":[], "rowCount":0` and validates.
- Columns sorted by name, every row array in that order — a `Legend`-ordered column list will fail validation against a concretely-typed relation's schema.
- The `Delivery` handed to `JsonBuilder.rel` is binding: `Inline` MUST produce the inline arm, `Deferred` the deferred one; only `ByRequest` may choose.
- Beware `Session.toHeader` with GUID columns (open issue 2).

**J3d (TS client)**
- Prop types are `data TableProps r = TableProps { title : String, rows : Inline r, detail : [..r] }` — wrappers take a ROW. Export them BY NAME (`bin/ermine-schema -i <Module> TableProps`, or `{"module","name"}` over LSP): the row parameter is left abstract and the zod is one schema for every relation the widget is used with. `UserTableProps.{schema.json,zod.ts}` is the committed example.
- Generic arm zod: `z.discriminatedUnion("kind", [...])` for a bare relation, a single `.strict()` object for `Inline`/`Deferred`; cells are `z.union([z.string(), z.number(), z.boolean(), z.null()])`, and the client reads the JSON type off the descriptor (`Long`, `Date`, `Timestamp`, `GUID` are STRINGS; `Int`/`Short`/`Byte`/`Double` numbers; `Bool` boolean).
- A `$defs` key with a free row parameter is `Module.Type__` -> TS `Module_Type__`; stable, generated.
- A props FIELD name is an Ermine field selector and may not shadow a global in scope ("field selector `every` would shadow global definition"); `title`, `rows`, `detail`, `body`, `more`, `plain` are fine; `table` is a KEYWORD and cannot be a field name at all.
- `z.string().datetime()` (what `expires` compiles to) accepts a `Z` offset only — which is what the wire promises.

**J2b (`Spread Json`)** — the relation arms and column descriptors are closed objects and are validated with `.strict()` on the client; a spread must not target a relation position.

**P1 (2.11 port)** — everything added is in the 2.11-and-3 dialect: implicits only, `.right.map`/`fold`/`.left.toOption`, `java.util.Base64` (JDK 8), no `CollectionConverters`, no `LazyList`, no interpolation. The only scalaz touch is `NonEmptyList` in the test's `DocBuilder`, spelled `tups.head :: tups.tail.toList`, which compiles on 7.1 and 7.2.
