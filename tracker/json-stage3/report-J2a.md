# J2a as built: the params decoder (`json/Decode.scala`)

Branch `json-decode`, worktree `~/research/ermine/ermine-scala-wt-json-decode`, off `json-s3-base` a7e8e050. Uncommitted, as the brief says. 2026-09-16, ~2 h of the 4 h budget. (Report text written by the implementer agent, saved to this path by the orchestrator: the agent's harness blocked writing `.md` files.)

## What was built

| File | What |
|---|---|
| `core/src/main/scala/com/clarifi/reporting/ermine/json/Decode.scala` (new, 760 lines) | `compile` / `entry` / `decode` / `reportSignature`: type-directed `JSON => Runtime` |
| `scalacheck-binding/src/main/scala/TestDecode.scala` (new, ~560 lines) | eleven properties: round trip, agreement with `Validate`, error paths, `entry`, relations vs J3a's export, scale |
| `scalacheck-binding/src/main/scala/TestSchema.scala` | Stage 2a GENERATOR ROWS only (new `prims`, `fieldPool`, leaf and composite entries, the imports they need) plus one changed pin (`Char`) |
| `core/.../json/Schema.scala` | three fixes the new properties found (below) |
| `core/.../json/Validate.scala` | `minLength`; the `uuid` format is the canonical form |
| `core/.../json/Zod.scala` | renders `.min(n)` for `minLength` (one line) |
| `core/.../json/Encode.scala` | refuses a `tag`-named field in a tagged type instead of writing two `"tag"` keys (review finding 2) |
| `scalacheck-binding/src/main/scala/TestJson.scala` | one declaration per type name in the process (a pre-existing gate flake, below) |
| `tracker/JSON-API-DESIGN.md` | new §3.7b "Stage 2a as built" |
| `tracker/JSON-STAGE3-PLAN.md` | J2a row marked BUILT, handoff-log line |

The diff to `Schema.scala` / `Validate.scala` / `TestSchema.scala` is deliberately small and away from the relation code J3a is editing: in `Schema.scala` it is the `Char` line in `builtin` and the optional-key line in `constructor` (plus one new private helper beside `maybePayload`); in `Validate.scala` the string-keyword block and the `uuid` case; in `TestSchema.scala` new generator entries appended with `++`, one changed assertion (`Char`'s schema), and `imps` gaining `++ stage2Imports`. `imps` is the one line J3a may also touch.

## The decoder

- **Two phases.** `compile(ty)` walks the TYPE once — the exporter's walk: the same alias expansion to a fixed point, the same `unfurl`, the same `$defs` key (`Schema.defName`) for a `data` instantiation, inserted into the table BEFORE its fields are walked so a recursive type terminates — and returns a `Decoder` that needs no `SessionEnv`. `entry(ty)` is that walk alone; `decode(ty, j)` is compile-then-run.
- **The run phase keeps an explicit stack** (a frame per open array/object), so a 100,000-element list and a document nested far past argonaut's own parser both decode without growing the JVM stack. JSON paths are parent-linked and rendered only for an error: eager path strings cost the square of the nesting depth.
- **Values are what evaluation produces** (the round-trip property pins this, and it was checked against a deliberately broken build): `Data` through the registry's constructor `Global`; `Bool` as `Data(True/False)`; `Nullable`'s `Null` carrying `primTypes(t).withNull`, the witness `Null Int` and a database read both carry; `Date` a `java.util.Date` at UTC midnight and `Timestamp` a `java.sql.Timestamp`; `List#`/`Maybe#`/`Pair#` storing `extract`ed elements as `::#`/`Just#`/`toPair#` do, but `Vector` storing what `Session.whnfForeign` gives (its builders are foreign functions, and there an empty `Arr` — the unit value — arrives as Scala's `()`).
- **Refusals.** Compile time, naming the offending part of the type: a type variable (including a phantom `data` parameter), a `forall`, an open row, a function, `IO`, `FFI`, a `Field`/`Prim`/`PrimT` witness, a foreign type, a relation and the `Json.Inline`/`Json.Deferred` wrappers, an existential field, `Maybe (Maybe a)`, a `Nullable` of a type with no `PrimT`, an operator constructor, and a record-style field named `tag` in a multi-constructor type. Run time, with the JSON path into the INPUT (`$`, `.key`, `[i]`, `.args[i]`): a missing key at the object, an unknown key at the key, a bad tag at `.tag`.

### Decisions taken in code (the plan did not fix these)

1. **Integers**: a JSON number with no fractional part, in range — so `1.0` and `1e2` are integers and `1.5` is not (JSON Schema's `integer` reading, which keeps decoder and validator in step). The magnitude is checked before the value is materialised, so `1e1000000000` is refused without building it.
2. **Timestamp** accepts any ISO-8601 date-time WITH an offset (`ISO_OFFSET_DATE_TIME`, the encoder's `...SSS'Z'` included), keeping sub-millisecond nanos. That is the validator's own test, so the two agree by construction; zod's `.datetime()` is stricter (`Z` only), so everything a zod client sends decodes. `Date` is `ISO_LOCAL_DATE`, strict resolver (`2026-02-30` refused).
3. **GUID** must be the canonical 8-4-4-4-12 hex form — `UUID.fromString` alone also takes `"1-1-1-1-1"`, which zod rejects. `Validate` corrected to match.
4. **`Nullable a`** is refused unless `a` has a `PrimT` (the ten column types): its `Null` needs a witness. The exporter accepts e.g. `Nullable Char`; a deliberate difference, reported by `entry` with that wording.
5. **A phantom `data` parameter** is refused: the exporter can ignore it, a decoded value cannot carry it. Checked after the constructors are walked, so a variable a field DOES reach is still reported at that field.
6. **`Prim`'s argument is by name and turns a throw into a `Bottom`**, so every conversion is forced into a `val` first. Without that, `Long "99999999999999999999"` decoded to `Right(Bottom(NumberFormatException))`. The agreement property now also checks a successful decode contains no bottom.
7. **`java.sql.Timestamp.from` multiplies and wraps** out-of-range instants (JDK 21: year 999999999 comes back as year 169104628), so the instant is validated with `toEpochMilli` first.
8. **`Maybe Json` is kept, and it is the one non-injective spot**: `Just JNull` and `Nothing` both encode as `null`, and the decoder reads `null` as `Nothing`. Nested `Maybe (Maybe a)` is refused for exactly this reason; a raw-JSON parameter was judged worth the loss. A record-style `Maybe` FIELD stays injective (absent / `null` / value), which is why `Maybe (Maybe a)` is allowed there and pinned.
9. **`compile` is public** beside `entry`/`decode` so the runner keeps one `Decoder` per report instead of walking the type per request.
10. No `:decode` REPL command (the brief made it optional).

### Four Stage 1 bugs the new properties found, fixed here

1. `Schema.constructor` made a record-style field of type `Nullable a` or `Maybe# a` an OPTIONAL key (it read `maybePayload`, the wider test the nested-Maybe refusal wants), but `Encode` only omits a `Maybe` field and writes `null` for those two. `Schema` now uses the encoder's test (`Builtin.Maybe` alone). No committed fixture changed.
2. `Char` exported `maxLength: 1` with no `minLength: 1`, so `""` validated and zod accepted it while the decoder refused. Fixed in `Schema`, `Validate` (new `minLength`) and `Zod` (`.min(n)`).
3. `Validate`'s `uuid` format took `UUID.fromString`, which accepts `"1-1-1-1-1"`; zod's `.uuid()` and the decoder want the canonical form.
4. (review finding 2) A record-style field NAMED `tag` in a type with several constructors overwrote the discriminator: `Schema` emitted an arm whose `tag` had lost its `const` and whose `required` read `["tag","tag"]`, and `Encode` wrote two `"tag"` keys, of which argonaut keeps the last. The decoder refused it from the start; `Schema.constructor` and `Encode.userData` now refuse it too — the exporter and the decoder at the declaration (`Tgf.Tgfa[0]`), the encoder at the value's own `$.tag`, all three saying "collides with the discriminator" — and `Encode.rejections` reports it for the stdlib sweep (the sweep is unchanged: 100 types, 80 rejected fields, no `tag` case in `modules/`). Pinned three ways in `(map)` (all three refuse `data Tgf = Tgfa { tag : Int } | Tgfb { tgfx : Int }` at `Tgf.Tgfa[0]`, and a SINGLE-constructor `data Tg1 = Tg1 { tag : Int }` still works everywhere) and as a poison row in `(d)`. A declaration-level refusal beside Stage 1a's other selector refusals would be better and is a separate ticket — the brief forbade touching the parser/`Session` here.

### Known gaps, pinned rather than fixed

The validator accepts what the decoder refuses in exactly four places, because the schema cannot say it (property `(b2)` pins each; the agreement property counts them separately — 6 of 1,950 documents):

| Gap | Why |
|---|---|
| `Int` out of 32-bit range | the schema is `{"type":"integer"}`, unbounded |
| `Long` string out of 64-bit range | the schema is only `pattern: ^-?[0-9]+$` |
| `Double`/`Float` overflowing to infinity | `{"type":"number"}` has no finite range |
| `"12\n"` as a `Long` | Java's `$` also matches before a final newline; ECMAScript's does not, so zod is stricter than `Validate` here |

(The `tag`-collision case the review found is NOT in this table: it is fixed in all three places instead, item 4 above.)

Adding `minimum`/`maximum` to the `Int` schema would close the first but moves five committed fixtures, which J3a is regenerating in parallel; left for after the Stage 3 landings. Two further pins record that an instant or date beyond `java.sql.Timestamp`/`java.util.Date` range is refused by the decoder and accepted by the validator.

## Properties (all over random declarations and values, `TestSchema.shape`)

| Id | What | Size |
|---|---|---|
| (a) | `decode(ty, encode v) == v`, from the in-memory document and from its text, compared by a stack-safe walk that also compares the JVM class of every primitive | 200 fixed-seed cases; vocabulary histogram printed |
| (a2) | the same under ScalaCheck's generator | 100 |
| (a3) | corners the generator leaves out: `Int.MinValue`, `Long` bounds, `Short`/`Byte` bounds, tiny/huge doubles, `@1970/1/1`, `@9999/12/31`, epoch-negative timestamps, escapes, `()`, a `Maybe (Maybe Int)` field, a phantom parameter, a type alias, `Null String` | 20 pins |
| (b)+(c) | `Validate(exportType(ty), j)` empty IFF `decode(ty, j)` succeeds, over the encoding and 12 single mutations; and the decoder's error path is the mutation's or its parent's | 150 cases x 13 = 1,950 documents |
| (b2) | the four validator gaps and the three closed ones, pinned | 10 pins |
| (map) | the mapping decisions above, one assertion each, plus `reportSignature` | 20 pins |
| (d) | poisoned types (10 poisons x 6 contexts) refused by `entry` at the poison's path with the expected wording, and the exporter refuses the same ones bar the two deliberate differences (`Nullable Char`, a relation) | 100 |
| (d2) | every closed generated type accepted by both `entry` and the exporter | 100 |
| (d3) | (post-merge) every relation-bearing shape from J3a's `shape(2, rels = true)` is exported by the schema and refused by `entry`; every relation-free one is accepted by both | 120 cases, 15 of them relation-bearing |
| (e) | 100,000 records (2.7 MB) decode | 0.5-1.0 s |
| (e2) | argonaut's parser reads 4,100-21,000 nested arrays depending on the JVM's mood; three quarters of the measurement is read back, and a FIXED 100,000 levels decode in memory as `Json` and as a recursive record-style `data`, with a bad node at the bottom reported with its full path | 100,000 levels |

Generator additions in `TestSchema`: `Short`, `Byte`, `Float`, `Char`, `Date`, `Timestamp`, `GUID` as scalar rows; `Nullable p` over the ten column types; `Vector_V`, `List#`, `Maybe#`, `Pair#`; the stdlib `Json` type with a random document; and nullable/date/timestamp/GUID columns in the record field pool. `Vector` is imported ALIASED (`import Vector as V`): a plain `import Vector` makes every `[..]` literal ambiguous.

**Not vacuous.** (a) was run against a deliberately broken decoder twice: `Null`'s witness `withoutNull` instead of `withNull` falsified (a), (a2), (a3) and (map) (`scratch/mutation.log`), and — after the review — the wrong null WRAPPER (`Data(Nothing)` where a native `Maybe#`'s `Prim(None)` belongs) falsified (a), (a2) and (map) (`scratch/mutation2.log`), which is what closes the reviewer's optional finding 1 inside the property rather than only in a pin. The reviewer ran a third, independent mutation (`Prim(l.toShort)` -> `Prim(l.toInt)`) with the same result. The properties also failed on seven REAL bugs before the fixes in this report (`scratch/run1.log`, `run2.log`, `rep8.log`, `rep12.log`). (a) asserts each of 16 vocabulary entries appears in its 200 cases; (b)/(c) assert both verdicts occur in quantity (535 valid, 1,409 invalid).

Error-path distribution over the 1,409 invalid documents: `replace` same 443, `tweak` same 343, `add key` same 156, `drop key` parent 138, `append element` parent 122 / same 44, `drop element` parent 100, `retag` same 55 / sibling 8. Only `retag` reports away from the mutation, at a sibling key in the same object.

## Gates (post-merge with json-encode f8a789d1 = J3a)

`json-encode` f8a789d1 (the contract + J3a's relation arms) was merged into `json-decode`
40827243; the numbers below are from the merged tree. Pre-merge numbers are in the git
history of this file.

Logs in `/tmp/claude-1000/-home-dmitry-research-caliper/c359de0f-018b-42eb-960e-7519d0922cee/scratchpad/j2a/` (`scratch/` below).

| # | Gate | Result | Log |
|---|---|---|---|
| 1 | `sbt -batch core/compile core/copyResources` | success | `scratch/merge-compile.log`, `scratch/merge-suites2.log` |
| 2 | `TestDecode` + `TestJson` + `TestSchema` + `TestNamedFields` | **78/78, twice** (TestDecode 11 — the 10 of J2a plus `(d3)` for J3a's relation export —, TestJson 28, TestSchema 25, TestNamedFields 14; the 77 the coordinator expected plus `(d3)`). The **schema fixture gate says 11 fixtures match**. Before the merge the same four suites were 71/71 over 13 consecutive runs (`rep15`–`rep27`), after two reds that the review round fixed | `scratch/merge-suites2.log`, `scratch/merge-suites3.log` |
| 3 | `core/testOnly *TestLoopTrace` | 3/3 properties, the 720-case model differential SKIPPED: no `looptrace` binary in this checkout; neither this stage nor J3a touches the solver, `Type.scala`'s constraint construction or Lean | `scratch/merge-looptrace.log` |
| 4 | `corpus-run.sh --batch` + `corpus-verdicts.py` | **89 LOADED / 79 REJECTED / 0 UNKNOWN over 168**, unchanged | `scratch/corpus-verdicts3.log` |
| 5 | `tracker/tools/repl-smoke.sh` | green, all nine files PASS (including the 20 `json` checks) | `scratch/repl-smoke3.log` |
| 5 | `tracker/tools/lsp-smoke.sh` | green, 577 checks | `scratch/lsp-smoke3.log` |

`tracker/repl-classpath.txt` was regenerated for the smokes and restored with `git checkout`.

### The merge with J3a (f8a789d1)

Conflicts and how they were resolved:

| File | Resolution |
|---|---|
| `TestSchema.scala` (2 hunks) | J3a's `rels`-threaded `shape` kept, with J2a's `stage2Leaves(underMaybe)` appended to the leaves and `stage2Composites(depth, underMaybe)` to the composites; J2a's Stage 2a block kept whole beside J3a's `maybeShape(depth, rels)`. The Stage 2a composites pass `rels = false` inward ON PURPOSE: a foreign builder stores what `whnfForeign` gives it, which unwraps a `Rel` to its raw `Ext`, so a relation inside a `Vector` is not a value the walker can write. `recordShape` already uses J3a's `pickN`; nothing J2a added draws from a pool with `Gen.pick` (there is no `Gen.pick` left in the suite). |
| `Validate.scala` (header) | J3a's fuller format paragraph kept, with its `uuid` clause CORRECTED to the code both sides now share: the canonical 8-4-4-4-12 form (regex + `UUID.fromString`), because `UUID.fromString` alone also takes `"1-1-1-1-1"`. The body merged cleanly: one `minLength` block, J2a's canonical `uuid` check. |
| `JSON-STAGE3-PLAN.md` (2 hunks) | Stage table: J3a's rows, with the J2a row updated to `COMMITTED 40827243, json-encode merged in, landing`. Handoff log is append-only: J3a's entries kept verbatim, J2a's superseded line replaced by one new entry for the review round and this merge. |
| `Schema.scala`, `Zod.scala`, `JSON-API-DESIGN.md` | auto-merged; checked by hand — `Char`'s `minLength`, the `tag`-field refusal and `declaredMaybe` all survive beside J3a's relation arms; `Zod` has exactly one `minLength` line (both sides added it identically); both §3.7b and J3a's revision of the Stage 1b relation paragraph are present. |

Adapted after the merge (staged with it): `TestDecode` gained **`(d3)`**, which draws 120
shapes from J3a's `shape(2, rels = true)` and asserts that every relation-bearing one is
EXPORTED by the schema and REFUSED by `Decode.entry` with a message naming a relation,
while every relation-free one is accepted by both; 15 of the 120 carry a relation today and
the property fails below 10, so it cannot pass vacuously. `Inline (|sfPoison|)` and
`Deferred (|sfPoison|)` joined `(d)`'s poison list beside the bare relation (the exporter
accepts all three, `entry` refuses all three). `(a)` and `(b)` now assert that their cases
are relation-free — `TestSchema.typeAndValue` leaves `rels` false, so no relation reaches
the round trip or the agreement property, and flipping that default would fail here loudly
instead of drowning `(b)` in disagreements. The agreement numbers moved slightly with J3a's
unbiased `pickN` (537 valid / 1,409 invalid / 4 pinned gaps / **0 disagreements**, from
535 / 1,409 / 6).

## Review round (FIX-THEN-LAND verdict, `tracker/json-stage3/review-J2a.md`)

Both required fixes applied, plus the optional one; two further flakes surfaced while
verifying and are fixed.

1. **(e2) was flaky** (~1 gate run in 15 ended in a `StackOverflowError`): it re-parsed AT
   the depth its probe measured, and the probe swings with the JIT state of a JVM running
   four suites (4,114 to 21,259 across my runs). Now it reads back at **three quarters** of
   the measurement, wrapped so an over-measure fails with a message instead of an SOE, and
   the in-memory half uses a **fixed 100,000 levels** — that half is about the decoder being
   iterative, which has nothing to do with what the parser can read.
2. **The `tag`-field collision is now refused in all three places** (report item 4 above),
   pinned in `(map)` and added to `(d)`'s poison list with a fixed expected path
   (`Tg.Tga[0]`), since a declaration-level poison is refused where it is declared whatever
   context it sits in. `Encode.rejections` reports it too, so the stdlib sweep would catch
   such a declaration in `modules/`.
3. **Optional finding 1 taken**: `same`'s null equivalence now compares the WRAPPER
   (`Maybe` vs native `Maybe#`) and excuses only the payload ambiguity, and `(map)` pins
   `Maybe# Int`'s null as `Prim(None)`, a `Maybe`'s as `Nothing`, and that the two are not
   equal, with `==` rather than `same`. A mutation confirms the tightening bites.
4. **Found while verifying: `TestJson` had a pre-existing cross-property race** (run 8 of my
   repeats, `scratch/rep8.log`). `DataConDecl` is a process-global, last-writer-wins
   constructor map that the VALUE walker reads, ScalaCheck runs properties concurrently in
   one JVM, and `TestJson` declared `data Shape` three different ways and `data Series` two
   in `module Test` — so "named constructor fields are an object in declaration order" could
   encode `Circle 1.5` with the positional declaration another property had just registered.
   Fixed by giving each property its own type and constructor names (`ShapeP`/`ShapeR`,
   `SeriesP`), which is the rule `TestNamedFields`' `Nf` prefixes already follow; my own
   `Shp` pin was renamed `Shq` for the same reason (`TestSchema` declares a different
   `Test.Shp`). This is a base flake, not one this stage introduced — drop the hunk if you
   would rather ticket it separately, but the gate is flaky without it.
5. **Found while verifying: (a2)'s equivalence had a hole** (run 12, `scratch/rep12.log`):
   `Vector_V (Maybe# Json)` holding `Just# jnull` stores a RAW `Some(JNull)`, where the old
   guard only ran on `Runtime` values. Fixed by the same rewrite as item 3. The decoder was
   right; the comparison was not.
6. **Reviewer's optional 2 taken**: §3.7b now also names the whole-valued `JNum` ->
   `JInt` asymmetry (inherited from `parseJson#`) as a non-injective spot.
7. Reviewer's optional 3 (`DataP`'s `var`s, `compile` catching `NonFatal`) and 4
   (`Schema.defName` as a memo key) are NOT taken: both are judgement calls for J3c and
   whoever next touches `defName`; noted in the open issues below.

## Open issues

0. **Not taken from the review, on purpose**: making `DataP`'s three `var`s `val`s (safe
   today by final-field freeze, per the reviewer), and having `compile` catch `NonFatal` so
   an unexpected exception is a refusal rather than a 500. Both are one-liners J3c may want;
   I left the surface as reviewed. `Schema.defName`'s lossy `keyOf` as the decoder's memo key
   is a pre-existing note for whoever next touches `defName`. A DECLARATION-level refusal of
   a `tag` field (parser/`Session`, beside Stage 1a's selector refusals) is a separate
   ticket the brief put out of scope.
1. **`TestSchema.imps`** is the one line J3a is also likely to touch (`++ stage2Imports` appended).
2. **Adding `minimum`/`maximum` to the `Int` schema** closes the biggest validator/decoder gap; it moves committed fixtures, so it wants to land after J3a's fixture regeneration.
3. **`Maybe Json`** stays non-injective on purpose. Refusing it at export and at `entry` is a two-line change plus a generator exclusion.
4. **2.11 port risk**: `Decode.Decoder`'s constructor is `private[Decode]` and takes a private `Plan`. If 2.11 objects ("private class Plan escapes its defining scope"), widening `Plan`/`DataP`/`ConP`/`FieldP`/`Path` to `private[json]` is the whole fix. Note `enum` is a Scala 3 keyword — a field there is spelled `nullary`.
5. **Numeric denial of service** is bounded but not eliminated: a million-digit number still costs what parsing a million digits costs. The runner's body-size limit is the right place for that.
6. The schema's `Builtin.Vector` case (as against `Vector.Vector`) is mirrored in the decoder but looks dead.

## What J3c (the runner) must know

```scala
import com.clarifi.reporting.ermine.json.Decode

// 1. the report's type, from the session (Session.eval / SessionEnv.termNames)
val (scheme, fn) = Session.eval("report", imports)          // (Type, Runtime)

// 2. split it, ONCE per report
val (paramTy, nodeTy) = Decode.reportSignature(scheme).fold(e => refuse(e), identity)

// 3. compile the parameter type ONCE per report; cache the Decoder (it needs no session)
val decoder = Decode.compile(paramTy).fold(e => refuse(e), identity)

// 4. per request: decode `$.params` and apply
decoder(paramsJson) match {
  case Left(e)  => badRequest("$.params" + e.path.drop(1) + ": " + e.message)   // 400
  case Right(v) => Runtime.swhnf(fn).apply1(v)                                   // the Node
}
```

- `Decode.decode(ty, j)` is compile + run for one-offs; the runner should keep the `Decoder`, since `compile` needs the `SessionEnv` and the run does not.
- **Error paths are relative to the params document**: `$`, `$.key`, `$[i]`, `$.args[i]`. The `$.params` prefix is the runner's to add. `e.report` reads `cannot decode $.foo: ...`.
- A successful decode NEVER contains a `Bottom`; every failure is a `Decode.Error`. A refusal is a 400 with a path, not a 500.
- `reportSignature` refuses a polymorphic report and a non-function; it does not look inside either half. `entry`/`compile` on the parameter half refuses relations, `IO`, functions, open rows and the rest — so a report whose `Params` is undecodable fails at boot/lookup time.
- Catch `StackOverflowError` around **argonaut's parse** of the request body (~4,200 nested arrays overflow on a default stack). The decoder itself is iterative.
- 100,000 records decode in about half a second, dominated by the parse.
- `Json`-typed parameters accept any document exactly as `parse` builds it, and `null` in a `Maybe` position is `Nothing`.
