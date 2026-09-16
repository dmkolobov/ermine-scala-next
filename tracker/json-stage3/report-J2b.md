# J2b as built: `Spread Json` (Part 1); the `Json a` constraint as a design only (Part 2)

(Report text written by the implementer agent, saved to this path by the orchestrator: the agent's harness blocked writing `.md` files.)

Branch `json-spread`, worktree `~/research/ermine/ermine-scala-wt-json-spread`, off `json-decode` d2177ca5 (J2a reviewed + `json-encode` f8a789d1 / J3a merged in). Uncommitted, as the brief says. 2026-09-16, inside the 4 h budget.

## What was built

| File | Change |
|---|---|
| `core/src/main/resources/modules/Json.e` | `data Spread a = Spread a` and the paragraph that states the rule |
| `core/.../json/Encode.scala` | the merge in `userData`; `objFields` factored out of the `JObj` node; `isSpread`, `spread`, `spreadArgument`; a `Spread` value anywhere else is an error; `reject`/`rejections` carry the three declaration refusals |
| `core/.../json/Schema.scala` | a spread field is not a property and its arm carries `additionalProperties: true`; the same three declaration refusals; a `Spread` type anywhere else is an export error |
| `core/.../json/Decode.scala` | `SpreadP` + `Gather`: a constructor with a spread field is OPEN and gathers the keys it does not declare, in document order; the same refusals; `spreadCon` |
| `core/.../json/Zod.scala` | `additionalProperties: true` renders `.passthrough()` (zod's default STRIPS unknown keys, which would throw the merged keys away) |
| `scalacheck-binding/.../TestSchema.scala` | `spreadData` in the generator (so every existing property covers spread types), `(s)` and `(s-pins)`, and `ChartProps` in the fixture gate |
| `scalacheck-binding/.../TestDecode.scala` | `(s)` and `(s-pins)`, four new poisons in `(d)`, `Spread` in `(a)`'s vocabulary |
| `core/src/test/resources/schema/UserSpread.{schema.json,zod.ts}` | new fixture (12 now); no existing fixture moved |
| `tracker/JSON-API-DESIGN.md` | new §3.7b' "Stage 2b as built" (numbered `b'` so J3b keeps §3.7c); §3.1 table row updated |
| `tracker/JSON-STAGE3-PLAN.md` | J2b row, handoff-log entry |
| `tracker/json-stage3/J2b-constraint-design.md` | Part 2: the design, and why it stops there |

Nothing outside `json/`, `modules/Json.e` and the two suites was touched. `Lib.scala` in particular is untouched: `Spread` is an ordinary Ermine declaration like `Inline`/`Deferred`, not a session primitive.

## The rule, in one paragraph

A NAMED constructor field whose DECLARED type is headed by `Json.Spread` is merged: the keys of the `JObj` it holds are written into the constructor's own object, after every declared field, in the object's own order. The exporter drops that field from `properties` and says `additionalProperties: true` (zod `.passthrough()`); the decoder gathers every key the constructor does not declare back into it, in document order. So `decode(encode v) == v` for a collision-free value, and `Validate` accepts exactly what `Decode` accepts, as in J2a.

## Decisions taken in code (the plan did not fix these)

1. **`Spread r` for a record type is REFUSED** (the brief asked for a decision with a justification). A record's — and a `data`'s — keys are known from its own declaration, so spreading one is no more than a second way to spell fields the constructor can already name, at the price of a second collision rule, a schema merge and a decode split to keep in step with the first. `Json` is the one case nothing else covers. `Spread` of anything but `Json` is refused **at the field** by the exporter, by `Decode.entry` and by `Encode.rejections` alike.
2. **At most one `Spread` field per constructor, refused at the declaration** (the brief allowed either this or a pinned merge order). Refused at the SECOND one's field index, in all three places.
3. **A collision is judged against every DECLARED field name that is a key of the document — an omitted `Maybe` field's included — and against `tag`; the SPREAD field's own name is NOT reserved.** Forced, not a preference, in both directions: the decoder reads a key matching a declared name as that field, so such a merged key would not come back; but the spread field's own name is no key of any document of the type, so the decoder gathers it like any other spare key and the encoder must be free to write it. Reserving it (the shape this stage was first built in) made the encoder refuse a document the exporter declares legal and the decoder accepts — the review's required fix, item 1 below. Both directions pinned, in `TestSchema.(s-pins)` and `TestDecode.(s-pins)`.
4. **A key the spread repeats is an error too.** "argonaut keeps the last" is containable inside a nested object, not when the keys become the parent's.
5. **A non-object payload is an error, `JNull` included.** `Spread jnull` does not mean "merge nothing"; `Spread (obj [])` does, and round-trips.
6. **The spread test reads the type as DECLARED, with no alias expansion** (`Encode.isSpread`, called by all three walkers on the pre-substitution field type). Three wanted consequences: a field at a type PARAMETER instantiated at `Spread Json` is not a spread field and all three refuse it where it stands; an alias for `Spread Json` likewise; and the encoder, which has no session to expand aliases with, cannot disagree with the other two.
7. **`additionalProperties: true` is emitted explicitly** rather than the key being dropped — `Validate` already reads `contains(false)`, and `Zod` must tell "open" from "not stated" to choose `.passthrough()`.
8. **Merged keys go out after ALL declared fields**, whatever index the spread field has; the generator puts it at a random position for exactly that reason.
9. **`Encode.rejections` reports the three declaration refusals**, so the stdlib sweep would catch such a declaration in `modules/`. Sweep is now 101 data types (`Spread` is the new one), still 80 rejected fields. It tests them in the exporter's and decoder's order (a second `Spread` before a positional one), so a declaration with both faults gets the same reason at the field those two name; being a sweep it additionally lists the first spread field, where they stop at the first fault (review suggestion, pinned).

## Departures from the brief

- `Spread r` for a record: answered NO (decision 1).
- "at most one `Spread` per constructor … or define the merge order and pin it; pick one": refused at the declaration.
- One addition the brief did not ask for: a committed fixture `UserSpread.{schema.json,zod.ts}` from `data ChartProps = ChartProps { chartTitle : String, chartExtra : Spread Json }`, so J3d has a `.passthrough()` example that the `tsc --strict` run covers and so a change in the shape is a reviewable diff. It moved no existing fixture.

## Properties (random declarations and values)

| Id | What | Size / non-vacuity |
|---|---|---|
| `TestSchema.(s)` | 80 random spread types: the document is the declared keys FOLLOWED BY the merged ones; the arm's `properties` are the declared fields alone; `additionalProperties` is `true`; the zod is `.passthrough()`; `Validate` accepts. A deliberate collision is an encode error at `$.<key>` naming the spread field | 80 cases, **22 collisions / 30 merges beside a declared field**, both asserted as floors |
| `TestSchema.(s-pins)` | exact arm text; an open arm beside a closed sibling in one `oneOf`; an omitted `Maybe` field still reserving its key while the **spread field's own name does not** (review fix); a merged `tag`; a bare `Spread` refused at encode and export; the three declaration refusals from the exporter AND `Encode.rejections` at the same field index, plus the doubly-bad declaration's precedence; **`Spread [..r]` and `Spread (Inline (\|..\|))` refused** (J3a's handoff note: a spread must never target a relation position); `Spread a` accepted by the sweep, refused by the exporter at `Spread Int` and by the encoder on the value, accepted at `Spread Json`; a well-formed spread field is not a rejection | 27 assertions |
| `TestDecode.(s)` | 60 probes (42 collision-free): round trip through the merged document; a key before every declared one and a key after every merged one accepted by BOTH validator and decoder; re-encoding shows they were gathered in document order | asserts ≥30 collision-free, ≥15 mixed |
| `TestDecode.(s-pins)` | two types differing only by the spread field: the closed one refuses `$.zz` (validator and decoder alike), the open one gathers it; the decoded field is `Spread (JObj [("zz", JNull)])`; no spare keys gives `Spread (JObj [])`; **a key equal to the spread field's own name validates, is gathered and is written back unchanged** (review fix, the other direction); `Spread a` plans at `Json` and is refused at `Int`, at the field | 13 assertions |
| `TestDecode.(d)` | four new poisons — a bare `Spread Json`, two spread fields, a positional spread, `Spread Int` — each refused by `entry` at the field it names in all six contexts, the exporter refusing the same | 100 cases over 16 poisons |
| existing, now covering spread | `shape` grew `spreadData`, so `(a)`/`(a2)` (encode vs schema), `(c)` (determinism), `(e)` (zod), `TestDecode.(a)`/`(a2)` (round trip), `(b)`+`(c)` (Validate iff Decode over 1,950 documents) and `(d2)` all carry spread types | `(a)`'s vocabulary check counts **35 of 200** round-trip cases with a `Spread Json` field and FAILS at zero |

**Not vacuous.** The generator's first version emitted `data S = Sc1 {  } | Sc2 { .. }` (a parse error) and falsified eleven properties at once — `(a)`, `(a2)`, `(c)`, `(e)`, `(r-c)`, `(r-d)`, `TestDecode.(a)`, `(a2)`, `(b)+(c)`, `(d2)`, `(d3)` — which is a demonstration that the spread row really does reach all of them. `(a)`'s vocabulary assertion is the standing guard against the row silently drying up. The agreement property moved from 537 valid / 1,409 invalid (J2a post-merge) to **561 valid / 1,384 invalid / 5 pinned gaps / 0 disagreements**: an "add key" mutation on a spread-bearing object is now legitimately accepted by both sides, which is exactly the change openness makes.

## Gates

`SP = /tmp/claude-1000/-home-dmitry-research-caliper/c359de0f-018b-42eb-960e-7519d0922cee/scratchpad/j2b/`

| # | Gate | Result | Log |
|---|---|---|---|
| 1 | `sbt -batch core/compile core/copyResources` | success | `SP/gate2-fix2.log` (post-review), `SP/gate2-final.log` |
| 2 | `TestDecode` + `TestJson` + `TestSchema` + `TestNamedFields` | **82/82** (TestDecode 13 = J2a's 11 + `(s)` + `(s-pins)`; TestJson 28; TestSchema 27 = 25 + `(s)` + `(s-pins)`; TestNamedFields 14); **"schema gate: 12 fixtures match"**; JSON sweep 101 data types / 80 rejected fields (was 100/80); agreement 561 valid / 1,384 invalid / 5 pinned gaps / **0 disagreements**; round-trip vocabulary **Spread 35 of 200** | `SP/gate2-fix2.log` (post-review, the numbers above), `SP/gate2-final2.log` |
| 3 | `core/testOnly *TestLoopTrace` | 3/3 properties and **720 solves / 720 segments / 720 agree; skipped=0, hashdiff=0, eqdiff=0** — the Lean binary was borrowed from the `wt-json-wrappers` worktree via `-Dermine.looptrace=…` instead of a 15-minute Mathlib rebuild; nothing here touches the solver | `SP/looptrace.log` |
| 4 | `corpus-run.sh --batch` + `corpus-verdicts.py` | **89 LOADED / 79 REJECTED / 0 UNKNOWN over 168**, unchanged | `SP/corpus-verdicts.log`, `SP/corpus-run.log` |
| 5 | `tracker/tools/repl-smoke.sh` | **PASS, 9 groups / 86 checks** (json 20) | `SP/repl-smoke.log` |
| 5 | `tracker/tools/lsp-smoke.sh` | **PASS, 577 checks** | `SP/lsp-smoke.log` |
| — | all 12 committed zod fixtures, `.passthrough()` one included: `tsc --strict --noEmit --target es2020 --module commonjs --moduleResolution node *.zod.ts` (tsc 5.9.3, zod 3.25.76) | exit 0 | `SP/tsc.log` |

The tsc flags matter and are recorded here because the defaults fail for two
unrelated reasons: with the default ES5 lib the run dies inside zod's own
`.d.ts` (`Map`/`Set`/`Symbol` absent), and `--target es2020` alone switches
module resolution to `classic`, which cannot find `zod` — so J3d wants either
these four flags or a checked-in `tsconfig.json` that says the same.

Gates 3, 4 and 5 were run before the review fix and are NOT re-run: the fix is
one expression in `Encode.userData` plus test pins, and none of the solver, the
corpus, the REPL or the LSP reads it. Gates 1 and 2 were re-run after it.

`tracker/repl-classpath.txt` was regenerated for the smokes and has been restored with `git checkout`; the tree shows only the nine modified files and the three new ones.

## Review round (FIX-THEN-LAND, `tracker/json-stage3/review-J2b.md`)

The one required fix and three of the four optional suggestions are applied.

1. **REQUIRED — a merged key equal to the spread field's OWN name.** The
   encoder reserved every declared field name, its own spread field included,
   so `data Cx = Cx { cxa : Int, cxs : Spread Json }` refused
   `Cx 1 (Spread (obj [("cxs", jnull)]))` while the exporter (which drops
   `cxs` from `properties` and opens the object) declared `{"cxa":1,"cxs":null}`
   legal and the decoder gathered it happily — the decoder accepting a document
   the encoder could never write, the stage's only three-walker disagreement.
   Fixed as the review specifies: `taken` now excludes spread fields
   (`Encode.userData`), so the spread field's own name merges and is gathered
   like any other spare key. Pinned in BOTH directions —
   `TestSchema.(s-pins)` asserts `Sp1 1 (Spread (obj [("sp1b", jnull)]))`
   encodes to `{"sp1a":1,"sp1b":null}`, `TestDecode.(s-pins)` asserts that same
   document validates, decodes and re-encodes unchanged. The `Encode` class
   comment, the `modules/Json.e` paragraph and §3.7b' now state the exception.
2. **Optional, taken — refusal precedence.** `Encode.rejections` now tests a
   second `Spread` before a positional one, the order the exporter and the
   decoder use, so `data Sq9 = Sq9 Int (Spread Json) (Spread Json)` gets "at
   most one Spread field" at field 2 from all three; the sweep additionally
   reports field 1 as positional, since it lists every field where the other
   two stop at the first fault. Pinned in `(s-pins)`.
3. **Optional, taken — `data S a = S { x : Spread a }`.** Pinned: the sweep
   accepts the declaration (the argument is decided at the instantiation), the
   exporter and `Decode.entry` refuse `S Int` at the field, both accept
   `S Json`, and the encoder refuses the value `S (Spread 3)`.
4. **Optional, taken — the tsc invocation** is recorded above with its flags,
   versions and the two reasons the defaults fail.
5. **Optional, noted not taken** — open issue 3 (merged keys keep the `JObj`'s
   order): nothing to do now, and J3d should not assume key order anywhere.

One incidental: `TestDecode.(s-pins)`'s new `Spread a` pin first called
`loadStatements` a second time in one session, which `ErmineFixture` refuses
("fixture writeback would capture the dynamic Test module"); the declaration
moved into the property's single `loadStatements` call.

## Part 2: the builtin `Json a` constraint — DESIGN ONLY

Written to `tracker/json-stage3/J2b-constraint-design.md`. The brief's gate ("implement only if the design is a check with no inference changes — a post-typecheck pass over instantiated `toJson#` call sites") **is not met**, for reasons that are facts about this compiler rather than judgement calls:

1. **The instantiation does not survive checking.** `Term` carries no type on any node (`Term.scala:21-113`) and there is no elaborated IR (`core/Core.scala` is unreferenced; evaluation runs on `Term`). In `Subst.inferType`'s `App` case the fresh meta for `forall a` is bound at `Subst.scala:1062` and **deleted at `:1068`** by `restrictTypes` (`hm.types = hm.types -- xs`, `:221`, with a comment at `:216-220` saying why), and the whole `SubstEnv` is per-block scratch (`Session.scala:59-60`). I verified both sites by reading them.
2. **`toJson#` has exactly one call site in the entire corpus** — `modules/Json.e:67` (`toJson = toJson#`) under `toJson : a -> Json`, where `a` is the wrapper's own skolem; `core/examples/` never mentions it. A pass over `toJson#` nodes would have nothing to reject.
3. **The real-constraint route changes inference by construction.** A `Requirements` in `hm.classes` (`Subst.scala:94`) is reached by `byInst` (`:384`), `entails` (`:392`), `simplifyPredicates` (`:400`), `split` (`:465`) and `generalize` (`:1766`), so an undischarged `Json a` is generalized into schemes and published in `.ei` interfaces — `toJson` becomes `Json a => a -> Json` and changes the type of everything that calls it. That is precisely the class-machinery behaviour change the user ruled out.
4. **Two checking drivers**, batch (`Session.loadModule`, `Session.scala:1002`) and LSP (`TolerantCheck.checkWith`, `TolerantCheck.scala:831`), so any hook is two hooks or one inside the checker.

The note names what is available without touching inference and recommends it: **the runner's boot-time check** (J3c already has `Decode.reportSignature` + `Decode.compile` for the `Params` half and can use `Schema.exportType`/`Encode.reject` for the `Node` half), with `bin/ermine-schema` and the `ermine/schema` LSP request as the interactive form. §5 of the note specifies a signature-level post-pass for whoever revisits it after J3b gives `Layout.Doc.Node` a name to key on; it should arrive as a warning first, in `SigEntail`'s three-mode style.

## Open issues

1. **`Maybe (Spread Json)`, `List (Spread Json)` and the like are refused** by the Spread-anywhere-else rule. Right for this stage (there is no object to merge into); an "optional spread" is spelled `Spread (obj [])`, which already works.
2. **A merged key is not validated at all.** `additionalProperties: true` says "any JSON", which is what `Spread Json` means. If a client ever needs the merged keys checked, the exporter could emit a schema instead of `true` — one line, plus teaching `Validate` and `Zod` to read it.
3. **Order, not sorting.** Merged keys keep the `JObj`'s order rather than being sorted like a record's. Deliberate (a `JObj` is a list and the author chose the order), but it does mean a spread-bearing document's key order depends on the value where every other object's depends only on the declaration.
4. Nothing from J2a's open-issue list was taken up or disturbed; `Schema.defName`'s lossy `keyOf` is untouched and a spread field never reaches it.
5. **A merged key CAN shadow nothing, but it can repeat what a sibling arm declares.** In a multi-constructor type only the arm's own field names are reserved, which is right (the tag picks the arm before any key is read), but a reader skimming one arm's schema will not see why a key is legal there and not next door. No action; noted for J3d.

## What the 2.11 port (P3) must know

- Everything added is in the 2.11-and-3 dialect: implicit parameters only, no `given`/`enum`/`extension`, `Either` through `.right.map`/`.right.flatMap`/`.fold` (no bare `map`/`getOrElse`/`foreach`), `ListBuffer` and `var` instead of `LazyList`, no `CollectionConverters`, no interpolation, JDK 8 APIs only. No new imports anywhere.
- `Decode.scala` gained a private `sealed abstract class Slot` with three case classes (`Const`, `Take`, `Gather`) at the `object Decode` level, and `private final case class SpreadP(con: Global) extends Plan`. If 2.11 objects that a private class escapes its defining scope (J2a's open issue 4 anticipated the same for `Plan`/`DataP`), widening those to `private[json]` is the whole fix.
- `Encode.isSpread` and `Encode.spreadArgument` are PUBLIC on purpose: the exporter and the decoder both call `isSpread`, which is what makes "a spread field" literally one function for all three walkers.
- `Encode.spreadArgument` calls `Schema.renderType`; `Schema` already called `Encode.jsonModule`, so the two objects were already mutually referential and both references are from method bodies, never initialisers.
- `modules/Json.e` gains `data Spread a = Spread a` — an ordinary declaration, so the 2.11 text is identical and there is no `Lib.scala` hook site.
- The new fixture `UserSpread.{schema.json,zod.ts}` must be copied across with the others; the 2.11 suite compares the same bytes.
- `Zod` renders `.passthrough()` only for `additionalProperties: true`; `Zod.scala` is a verbatim copy.