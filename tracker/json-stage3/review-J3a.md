# Review of J3a (relations in the schema exporter) and of the contract commit a5a53da4

Independent review, 2026-09-16, ~1 h 40 of the 2 h budget. Reviewer did not write either the
stage or the contract. Worktree `~/research/ermine/ermine-scala-wt-json-wrappers`, branch
`json-wrappers`, base `a5a53da4` (json-s3-base); the stage is uncommitted.
Scratch prefix `RP = /tmp/claude-1000/-home-dmitry-research-caliper/c359de0f-018b-42eb-960e-7519d0922cee/scratchpad/review-j3a/`.

Verdict in one line: the exported arms match the plan's wire contract key for key, the
row-polymorphic root rule is conservative (I could not make it accept anything it should
refuse — it over-refuses one corner), the `_` `$defs` spelling is deterministic and
collision-free, the `Gen.pick` claim is true and I confirmed it from the 1.15.4 bytecode, and
the properties are not vacuous (a mutation broke three of them). One required fix, in test
code, for the 2.11 port.

## 1. What I re-ran (not cited)

| Gate | Command | Result | Log |
|---|---|---|---|
| compile + suites | `sbt -batch core/compile core/copyResources 'core/testOnly ...TestJson ...TestSchema ...TestNamedFields'` | **67/67** (25+28+14), 65 s | `RP/gate-suites.log` |
| the same after my mutation was reverted | as above | **67/67**, 68 s | `RP/gate-after-revert.log` |
| vacuity mutation | `TestSchema` with `rowCount` dropped from the inline arm's `required` | **25 total, 2 failed + 1 error** (see §7) | `RP/mutation.log` |
| zod, compile | `tsc --strict --noEmit` over the **11 committed** `*.zod.ts` (copied fresh out of the repo, zod 3 from the implementer's `node_modules`) | exit 0 | `RP/ts2/` |
| zod, runtime | `node check.js` over the implementer's generated sample set | **180 schemas, 370 documents, 0 mismatches** | `j3a/ts/check.js` |
| lsp smoke (disputed: J3a changed a refusal message `lsp-client.py` asserts on) | `tracker/tools/lsp-smoke.sh` with `repl-classpath.txt` regenerated from this worktree's `target/ermine-classpath`, then restored | **PASS, 577 checks**, 94 s | `RP/lsp-smoke-review.log` |
| `Gen.pick` 1.15.4 | `javap -c org/scalacheck/Gen$.class` on the coursier jar | bug confirmed (§5) | `RP/sc/` |
| exporter probes | `SchemaMain` on my own modules, via `-cp <scratch>:<ermine-classpath>` (no repo file touched) | §3, §4, §6 | `RP/mods/modules/{Probe,Probe2,Shadow}.e` |
| REPL probe | `bin/ermine`, `:load` of a rogue `module Json` | §6 | `RP/rogue-repl.log` |

Cited, not re-run (the diff cannot plausibly move them, and the logs carry the numbers):
`TestLoopTrace` 3/3, `720 solves / 720 segments / 720 agree / skipped=0 / hashdiff=0`
(`j3a/looptrace2.log`); corpus `89 LOADED, 79 REJECTED, 0 UNKNOWN, 168 total`
(`j3a/corpus.log`); `repl-smoke.sh` PASS (`j3a/repl-smoke.log`).

`tracker/repl-classpath.txt` was regenerated for the smoke and restored byte-for-byte; the
worktree ends with exactly the stage's own modified/untracked files and nothing under
`core/examples/`.

## 2. The exported arms against the wire contract, key by key

Read off the committed fixtures (`UserRelation`, `UserInline`, `UserDeferred`,
`UserTableProps`) and `Schema.scala:418-480`.

| Plan (`JSON-STAGE3-PLAN.md` "Wire contract (v1)") | Exported | Verdict |
|---|---|---|
| `inline {"kind":"inline","columns":[col..],"rows":[[cell..]..],"rowCount":n}` | `properties` in exactly that order, all four `required`, `additionalProperties:false`, `rowCount` `{"type":"integer","minimum":0}` | ok |
| `deferred {"kind":"deferred","columns":[col..],"token":"..","expires":".."}` | same shape; `token` `{"type":"string","minLength":1}`, `expires` `{"type":"string","format":"date-time"}` | ok |
| `col {"name","type","nullable"}` | three consts for a closed row, all required, closed object | ok |
| column order sorted by name | `rowFields` sorts (`Schema.scala:388`); fixtures show `sfDate, sfInt, sfNote` | ok |
| `type` vocabulary = PrimT names with `UUID` spelled `GUID` | `Wire.columnType(Type.primTypes(t))`. I checked both ends: `PrimT#name` is exactly `Byte Short Int Long String Date Double Bool UUID Timestamp` (`PrimT.scala:78-207`) and `Type.primTypes` is exactly those ten types — `Float` and `Char` are commented out (`Type.scala:740-757`). So `Wire.columnTypes` is the vocabulary, not a parallel list that could drift | ok |
| `nullable` true exactly for `Nullable t` | `column` unwraps with `Type.Nullable`, which matches `AppT(nullable, _)` only — a `Maybe` field cannot be read as nullable | ok |
| bare `[..r]` = union, `Inline r` = inline arm, `Deferred r` = deferred arm | `relation(.., BothArms/InlineArm/DeferredArm)`; the wrappers are matched in `con` *before* the `data` path (`Schema.scala:290-293`) so they never become `$defs` or `{tag,args}` | ok |
| zod: `z.discriminatedUnion("kind", ...)`, `.strict()` arms, generic cells `z.union([...])` | all present in `UserRelation.zod.ts` / `UserTableProps.zod.ts`; the discriminator is looked up (`tag` first, then `Wire.Kind`) rather than hard-coded | ok |

The validator supports everything the new schemas use: `oneOf` with exactly-one semantics
(`Validate.scala:175-186`), `minimum`, `minLength`, `prefixItems` + `items` with 2020-12
semantics (`items` applies only past the prefix), `additionalProperties:false`. The
`date-time` check is `ISO_OFFSET_DATE_TIME`, so an `expires` without an offset is rejected —
which is what (r-b)'s `bad expires` mutants exercise.

Two things the schema cannot say, by construction, and which J3b must therefore enforce
itself: `rowCount == rows.length` (the schema only bounds it below by 0) and the token's
"at least 128 random bits, base64url" (only `minLength: 1` survives into JSON Schema).

## 3. The row-polymorphic root rule (`Ctx.abstractRowParameters`, Schema.scala:214-247)

I tried to make it accept something it should refuse. It refused every attempt. Probes are
`RP/mods/modules/Probe.e`, run through `SchemaMain` with the scratch dir prepended to the
classpath:

| Declaration | Named bare | Result |
|---|---|---|
| `data TableProps r = TableProps { title : String, rows : Inline r }` | `TableProps` | exported, `$defs` = `Probe.TableProps__` |
| `data Two r q = Two { a : Inline r, b : Deferred q }` | `Two` | exported, `Probe.Two____` |
| `data Nested r = Nested { t : TableProps r }` | `Nested` | exported, shares `Probe.TableProps__` |
| `data Bare r = Bare { plain : [..r] }`, `data Deep r = Deep { l : List (Inline r), m : Maybe (Deferred r) }` | both | exported (union / arrays / optional key all compose with the generic arm) |
| `data StarFirst a r = StarFirst a (Inline r)` | `StarFirst` | refused: "…only a ROW parameter can be left abstract, and the parameter a has kind \*" |
| `data RowFirst r a = RowFirst (Inline r) a` | `RowFirst` | refused, same message (the rule looks at *all* missing parameters, not just the first) |
| `data OpenRec r = OpenRec {..r}` | `OpenRec` | refused at `OpenRec.OpenRec[0]`: "open row; export at an instantiation" |
| partial application `Two (\|pa\|)` | — | exported (the remaining row parameter is abstracted) |
| `data Phantom r = Phantom { n : Int }` | `Phantom` | **refused**: "the parameter r has kind an unresolved kind" |

The last row is the only surprise, and it errs the safe way: an unused row parameter is
kind-generalised, `parameterKinds` falls back to a `VarK`, and `isRow(VarK)` is false. Nothing
unsound follows — but the message is opaque and a widget props type that declares a row it
does not (yet) use is refused. Optional fix, §10.

Two structural reasons the rule is sound rather than lucky:

- the only type constructors that take a rho-kinded argument are `Relation`, `Record` and a
  user `data` with a rho parameter. `Record` of a variable hits `rowFields`'s
  `case _: Part | VarT(_) => reject("open row")` (`Schema.scala:401`), and a user `data`
  just carries the variable one level deeper, where the same two cases apply. I confirmed
  the refusal propagates through a nesting (`Outer { a : Inline r, b : Inner r }` with
  `data Inner r = Inner {..r}` is refused, not silently generalised).
- the generic arm is a genuine superset of every instantiation's document: all ten column
  types encode to scalars (`Long`, `Date`, `Timestamp`, `GUID` as strings), so
  `string|number|boolean|null` cells and an `enum` of the ten names cover them. (r-c) is what
  ties this down empirically — 120 documents at three random rows per props type, all
  validated against the one schema.

One gap, already in the report as open issue 3 and worth repeating: a relation whose row
argument is a `Part` (a row-concatenation constraint) is refused by `rowFields`, not given the
generic arm, and no property exercises it. The brief's phrase "or has an open tail" therefore
has no implementation — but it also has no surface syntax I could find, so this is a latent
corner rather than a missing feature.

## 4. Is the `_` `$defs` spelling deterministic and collision-free?

Yes, and I checked the exact question asked (two types that differ only in variable spelling),
with `RP/mods/modules/Probe2.e`:

- `data A r = A { x : Inline r }`, `data B r q = B { u : A r, v : A q }` → exporting `B` gives
  `$defs = [Probe2.A__, Probe2.B____]` with **one** `A` entry referenced from both `u` and
  `v`. Correct, because the generic body genuinely does not mention the variable.
- `data C r = C { w : A r, y : A (|za|) }` → `$defs = [Probe2.A_Row_za, Probe2.A__,
  Probe2.C__]`: the abstract and the concrete instantiation get **distinct** keys. This is the
  collision that would have mattered, and it does not happen: `keyOf` spells a concrete row
  `Row_<sorted field names>` and a type constructor by its own name, neither of which can ever
  be `_`, and a type variable cannot be named `_` in source.
- `(r-pins)` additionally pins `TableProps q` ≡ `TableProps r` and the `Page`-nested case.

`$id` still carries the declared variable name (`ermine:Probe/TableProps r`). That is stable
per declaration and is what the `$id` is for, so it is not a determinism problem; it is worth
knowing on the client side that the `$id` and the `$defs` key spell the parameter differently.

A pre-existing (not J3a) nit in the same function: `keyOf`'s fallback `case (other, _) => "T"`
would make `Box <Part…>` and a user type named `T` share a key. Every `other` case is rejected
by the walker before a body is built, so it is unreachable; mentioning it only so it is not
re-discovered later.

## 5. The `Gen.pick` bias claim — CONFIRMED from the library bytecode

`scalacheck_3-1.15.4.jar`, `Gen$.pick$$anonfun$1`, offsets 145-156:

```
145: lload 15                       // x, the random long
147: ldc2_w 9223372036854775807L    // Long.MaxValue
150: iload 8 ; i2l ; lrem           // Long.MaxValue % count
154: land                           // x & (Long.MaxValue % count)
155: l2i ; istore 18                // i
158: iload 18 ; iload_1 ; if_icmpge // if (i >= n) skip
164: buf.update(i, t)
```

So the reservoir index is `x & (Long.MaxValue % count)`, not `(x & Long.MaxValue) % count`, and
it is a bitmask, not a modulus — for `count = 7` the mask is `0`, so the element *always*
lands on index 0; for `count = 5` the mask is `2`, so only indices 0 and 2 are ever replaced.
Over a 20-element pool `buf(0)` is overwritten in almost every run, which is exactly the
reported symptom ("the first pool element is almost never kept"). `pickN`'s replacement
(random keys, sort, take n) is uniform over subsets and returns in key order, which
`columnsGen`/`recordShape` then sort — fine.

The sweep the report suggests is still outstanding: `Gen.pick` survives at
`core/src/test/scala/com/clarifi/reporting/Gens.scala:42` (`atLeastOneOf`). Out of J3a's
scope; the orchestrator should file it.

## 6. The contract commit a5a53da4

**Delivery through nesting.** `Encode.step` reaches `data` for every `Data` node, so the
wrappers are recognised wherever they sit: `Just (Inline rel)` → `Builtin.Just` → `step` →
`Json.Inline`; `[Inline rel]` → spine → `step` per element; a named constructor field
`rows : Inline r` → `userData`'s `kept` list → `step`. A `Maybe (Inline r)` field is an
optional key by the declared type only, so a `Just` still reaches the wrapper. `ErmineJson`
maps the three deliveries onto `JRel`/`JInline`/`JDeferred` and `ArgonautJson` refuses all
three identically, so `render`/`pretty` still refuse a wrapped relation (pinned by the new
TestJson property, which also pins `Just` and list nesting). `Encode.reject` treats
`Json.Inline r` as an ordinary `data`, so a wrapper-bearing constructor field passes the
static check. I found no nesting hole.

`JsonBuilder.rel` now receives the argument **unforced** in the wrapper and `J*` cases (only
the bare `Rel | EmptyRel` case in `step` has already whnf'd it). The comment says so and J3b's
brief inherits it; the test's `DocBuilder` does `Runtime.swhnf(r)` first, which is the right
model for the writer.

**Can a user `data Inline` be mistaken for `Json.Inline`?** The walker keys on
`g.module == "Json" && g.string == "Inline"`, so:

- a user module with any other name is safe. Confirmed: `module Shadow where data Inline r =
  Inline [..r]` exports as `{"tag":"Inline","args":[<relation union>]}` under
  `$defs/Shadow.Inline_Row_qa`, i.e. an ordinary `data`, and the encoder's `userData` path
  matches. A module `My.Json` is `Global("My.Json", …)`, also safe.
- a module literally named `Json` **is** mistaken. Confirmed in the REPL: `:load` of a file
  containing `module Json where / data Inline a = Inline a` is accepted, `:type (Inline 3)`
  is `Inline Int`, and `:json (Inline 3)` answers *"cannot encode $: a relation has no inline
  encoding here"* (`RP/rogue-repl.log`). The exporter would likewise call `relation(Int)` and
  fail with "expected a concrete row, found Int".

I rate this LOW and not blocking: naming your module `Json` *replaces* the stdlib `Json`
module (in the same probe `toJson` became undefined), so the user has already lost the
library, and both failure modes are loud errors rather than wrong output. An optional
one-line guard is in §10.

## 7. Vacuity

Mutation: `Schema.scala:446`, `"required"` in `arm` changed to
`props.filterNot(_._1 == Wire.RowCount).map(...)` — i.e. `rowCount` present in `properties`
but no longer required by the inline arm. `sbt -batch core/compile core/copyResources
'core/testOnly ...TestSchema'` → **Total 25, Failed 2, Errors 1, Passed 22**:

- `(r-b)`: `mutation 'dropped key' accepted by the arm` — falsified on the first case.
- `(r-c)`: `mutation 'dropped key' of w430f3 accepted` — the generic arm too.
- `(gate)`: six fixtures differ (UserRelation, UserInline, UserTableProps, schema + zod).

So the relation properties are non-vacuous for a required arm key, and they fail *before* the
fixture check does, which is the important part — the fixtures alone would only prove the
exporter reproduces itself. The file was restored from `RP/Schema.scala.orig`; sha256
`0ecd459a…2260` before and after, `git diff --stat` identical, and the suites are 67/67 again
(`RP/gate-after-revert.log`).

Coverage of the properties themselves looks real rather than nominal: (r-a) asserts all
20 column kinds were met with at least one row (this is the assertion that found the
`Gen.pick` bug), (r-b) asserts all 10 mutation kinds were drawn *and* that every unmutated
document is accepted, (r-d) asserts all three deliveries were written by the walker, (r-c)
asserts the literal relation's `PrimExpr` cells equal the Ermine values' cells. The documents
are built from evaluated Ermine records through `Encode`, and the column descriptors from the
header `PrimT` through `Wire.columnType`, so the agreement is between two independent
spellings rather than one function compared with itself.

## 8. Dialect (2.11)

Grepped the added lines for `given/using/enum/extension/export/derives`, `Either#map`,
`LazyList`, `CollectionConverters`, JDK 9+ APIs, trailing commas, string interpolation:
clean. `java.util.Base64.getUrlEncoder.withoutPadding` is JDK 8. `Either` is used through
`.right.map` / `.left.toOption` / `.right.get`. `missing.find(...) foreach { case (v, k) => }`,
`List#lift`, `lazy val` in a method and a default argument on a `case class` are all 2.11.

One break, in test code:

- `TestSchema.scala:140` uses `Gen.hexChar`. The 2.11 branch pins **scalacheck 1.11.3**
  (`core/dependencies.sbt:17`, `scalacheck-binding/dependencies.sbt:3`), and I dumped that
  jar's `Gen$` API: it has `alphaChar alphaLowerChar alphaNumChar alphaStr alphaUpperChar
  numChar numStr identifier uuid …` and **no `hexChar`**. P1 will not compile. Required fix 1.

Everything else J3a adds that touches scalacheck (`Gen.const/choose/frequency/listOfN/oneOf/
sequence/zip`, `rng.Seed` through the existing `samples` helper) is present in 1.11.3 — the
2.11 TestSchema already carries shims for `Gen.delay`, `Gen.alphaNumStr` and the functional
`rng.Seed`, so this is the same class of thing, just not yet noticed.

## 9. Scope and docs

`git status` is exactly the stage's files: three `json/` sources, `TestSchema.scala`, six new
fixtures plus two regenerated, and the two tracker documents. No production file outside
`json/`; `Encode.scala`, `Lib.scala` and `modules/Json.e` are the contract commit's,
untouched. `bin/ermine-schema` needed no change and got none — correct, since the root rule
lives in `exportType` and the CLI, `exportNamed` and the LSP request all go through it.

The design-note paragraph ("Revised in J3a") and the `Schema.scala` header comment are
accurate against the code, including the new `Session.toHeader` remark: I checked
`PrimT.withName` (`PrimT.scala:215-226`) and it really has no `"GUID"` case while
`Session.scala:1687` calls `PrimT.withName(ty.string)` — so a `table` with a GUID column does
throw a `MatchError`, pre-existing. The plan's handoff entry is short and matches what I
re-ran. The report's departure list is honest; one unlisted departure is that the brief asked
for the *field pool* to be extended with `Nullable`/`Date`/`Timestamp`/`Short`/`Byte`/`GUID`
and the implementer built a separate `columnPool` instead, leaving `recordShape` on the
original five types. Harmless (records at those types are covered by `(a3)`/`(map)`, and the
json-decode branch extends `fieldPool` anyway), but the orchestrator should know the record
generator did not widen.

## 10. Merge with the parallel json-decode branch

I read `~/research/ermine/ermine-scala-wt-json-decode` read-only. It touches the same four
files. The merge is mechanical but not trivial — budget half an hour plus a suite run:

| File | Overlap | Difficulty |
|---|---|---|
| `Zod.scala` | both add the *identical* line `num("minLength") foreach …` at the same place; J3a additionally rewrites the `oneOf` block and the comment | clean or near-clean |
| `Validate.scala` | both add the *identical* `minLength` block; both rewrite the same doc-comment line | one comment conflict. **Semantic**: decode tightens `uuid` to the canonical 8-4-4-4-12 form; J3a's new comment says the opposite ("does not insist on the canonical widths"). Whoever lands second must fix that sentence |
| `Schema.scala` | decode edits the header comment (Char), `builtin`'s `"Char"` case and `constructor`'s `maybePayload` → `declaredMaybe`; J3a edits the header comment, `builtin`'s `"Relation"` case, `relation`/`column`/`columnType`, `exportType`/`exportNamed`, `Ctx`, `defName`/`keyOf` | one or two header-comment conflicts; the bodies do not overlap |
| `TestSchema.scala` | decode appends to `imps` (`++ stage2Imports`), `prims`, `fieldPool`, changes `primFor`, and adds `stage2Leaves`/`stage2Composites` into `shape`'s leaf and composite lists. J3a changes `shape`'s **signature** to `shape(depth, underMaybe, rels)` and threads `rels` through `maybeShape`/`listShape`/`tupleShape`/`positionalData`/`recordStyleData`/`parameterisedData`, and rewrites `recordShape` to use `pickN` | **the real work**: ~5-6 conflicting hunks in the first 200 lines. Resolution is prescribable: keep decode's `imps`/`prims`/`fieldPool`/`primFor`, keep J3a's `shape` signature and `pickN`, and have decode's `stage2Composites` take and thread `rels` (or default it to `false`, which merely keeps relations out of `Vector`/`List#`/`Pair#` shapes) |

Nothing here is a design clash; the two stages want the same `minLength` and disjoint parts of
`Schema.scala`. Landing J3a first and rebasing decode onto it is the cheaper order, because
decode's `TestSchema` additions are appends while J3a's are a signature change.

## Required fixes

1. **`scalacheck-binding/src/main/scala/TestSchema.scala:140** — `Gen.listOfN(32, Gen.hexChar)`.
   Failure: the 2.11 branch pins scalacheck 1.11.3, whose `Gen` has no `hexChar` (verified by
   disassembling `~/.ivy2/cache/org.scalacheck/scalacheck_2.11/jars/scalacheck_2.11-1.11.3.jar`),
   so stage P1's copy of this file will not compile and the report's "everything added is in
   the 2.11-and-3 dialect" claim is false.
   Fix: define the generator locally and use it in `hexGuid`, e.g.
   `private val hexDigit: Gen[Char] = Gen.oneOf("0123456789abcdef".toList)` then
   `Gen.listOfN(32, hexDigit)`. (`Gen.oneOf(Seq)` is present in 1.11.3.) No behavioural change
   on Scala 3; re-run `TestSchema` once and regenerate nothing — `hexGuid` only feeds value
   source, not a fixture.

## Optional suggestions (not blocking)

1. `Schema.scala:214-247` — a **phantom** row parameter (`data P r = P { n : Int }`) is refused
   with "the parameter r has kind an unresolved kind", because an unused parameter is
   kind-generalised to a `VarK`. Safe, but the message is not actionable. Either say
   "its kind could not be determined; a parameter that no relation uses can be dropped", or
   treat a `VarK` missing parameter as row-kinded *only* when the walk then succeeds. The
   first is the cheap one.
2. `Encode.scala:361-362` and `Schema.scala:292-293` — the wrappers are recognised by module
   name alone. A one-line guard would turn the `module Json` confusion of §6 into an ordinary
   `data` encoding instead of a relation refusal: in `Encode.data`, take the `rel` path only
   when `Runtime.swhnf(args(0))` is a `Rel | EmptyRel` and otherwise fall through to
   `userData` (whnf on a relation is the `Rel` node, not its rows, so laziness is preserved);
   in `Schema.con`, only when the argument is rho-kinded. Cheap insurance, no cost in the
   normal path. I would not hold the landing for it.
3. `Schema.scala:428-437` — a relation over the **empty** row emits
   `"columns": {"type":"array","prefixItems":[],"minItems":0,"maxItems":0}`. JSON Schema
   2020-12 says `prefixItems` MUST be a non-empty array, so a meta-schema-checking tool (ajv
   strict, and possibly whatever J3d uses) can reject the document. Reproduced with
   `ermine-schema -i Json -i Probe 'Inline (||)'` and `'[]'`. The `rows` key already special-
   cases `n == 0` as `{"type":"array","maxItems":0}`; doing the same for `columns` closes it.
   Pre-existing (Stage 1b emitted the same), and both `Validate` and the generated
   `z.tuple([])` accept it, so it is a portability nit only.
4. A `Part`-constrained relation row is refused rather than given the generic arm, and no
   property covers it (report open issue 3). Worth a pin the day a surface syntax exists.
5. `core/src/test/scala/com/clarifi/reporting/Gens.scala:42` still calls `Gen.pick` — the sweep
   the report asks for. Separate ticket.

## For the orchestrator and later stages

- Everything the report tells J3b and J3d is accurate as far as I checked it, including the
  `Session.toHeader`/GUID `MatchError` and "the wrappers take a ROW, not a relation".
- Add for J3b: the schema does **not** check `rowCount == rows.length` nor the token's
  entropy; both are the writer's to guarantee. And `JsonBuilder.rel` gets the wrapper's
  argument *unforced*.
- Add for J3d: `$id` spells the abstract parameter by its declared name (`TableProps r`) while
  the `$defs` key spells it `_` (`Test.TableProps__`); do not derive one from the other.

## Verdict

FIX-THEN-LAND — one required fix (§Required fixes item 1: `Gen.hexChar` at
`scalacheck-binding/src/main/scala/TestSchema.scala:140` breaks the scalacheck 1.11.3 the 2.11
port compiles against; replace it with `Gen.oneOf("0123456789abcdef".toList)`). Everything
else in this review is optional or informational. The contract commit a5a53da4 is sound as
written and can land with the stage.
