# Review of J2b (`Spread Json`; the `Json a` constraint as design only)

Independent review, branch `json-spread`, worktree `~/research/ermine/ermine-scala-wt-json-spread`, uncommitted diff against `3f6d97d8` plus four untracked files. 2026-09-16, within the 2 h budget.

## What I re-ran

| Gate | Command | Result | Log |
|---|---|---|---|
| compile + suites | `sbt -batch core/compile core/copyResources 'core/testOnly TestDecode TestJson TestSchema TestNamedFields'` | **82/82**, `schema gate: 12 fixtures match`, JSON sweep **101 data types / 80 rejected fields**, agreement **561 valid / 1384 invalid / 5 pinned gaps / 0 disagreements**, round-trip vocabulary **Spread 35 of 200** | `REV/gate-suites.log` |
| tsc | `tsc --strict --noEmit --target es2020` over the 12 committed `*.zod.ts` | **exit 0** | — |
| zod semantics | node, zod 3.25.76 | `.passthrough()` keeps `{plotOptions,extra}`; the **default STRIPS** them; `.strict()` throws | — |
| mutation A | `fs = extra ++ kept.toList` (merged keys first) | **TestSchema.(s), TestDecode.(s), TestDecode.(s-pins) fail**; reverted | `REV/mutA.log` |
| mutation B | `taken = Set[String]()` (collision check dropped) | **TestSchema.(s), (s-pins) fail**; reverted | `REV/mutB.log` |

`REV = /tmp/claude-1000/-home-dmitry-research-caliper/c359de0f-018b-42eb-960e-7519d0922cee/scratchpad/review-j2b/`. Both mutations were compiled before running; after each revert the file md5 is back to `3ea3fe2e9ea746745a171e110530a9de` and `git diff --stat` is again 9 files / 722 insertions / 54 deletions. I recompiled after the last revert.

**Cited, not re-run** (all confirmed present and green in the implementer's logs under `…/scratchpad/j2b/`): TestLoopTrace 3/3, `720 solves / 720 segments / 720 agree; skipped=0, hashdiff=0, eqdiff=0`; corpus `89 LOADED / 79 REJECTED / 0 UNKNOWN over 168`; `repl-smoke` PASS 9 groups (json 20 checks); `lsp-smoke` PASS 577 checks. Nothing in the diff touches the solver, the parser or the LSP, so none needed re-running. Borrowing the Lean binary from `wt-json-wrappers` via `-Dermine.looptrace=…` is a read of another worktree, not a write; acceptable.

## Correctness: the three walkers

`Encode.isSpread` really is the single test, applied to the **pre-substitution declared** type in all three: `Encode.scala:427`, `Schema.scala:553`, `Decode.scala:356`. All three read `c.fields` from the same `DataConDecl`, so they cannot disagree about *which* field is the spread. Verified line by line:

- **Encoder merge** (`Encode.scala:427-461`, `495-529`): merged pairs go in `fs = kept.toList ++ extra`, i.e. after every declared field whatever the spread's index; `keys`/`kids` are built from `fs`, so the merged children are encoded by the generic walker at `$.k` (the parent's key), iteratively — no new stack growth. Collision set includes an omitted `Maybe` field's name and `tag` only when `tagged`; repeated key, non-object payload (`JNull` included) and a non-`Spread` value all error with the field in the message. Two spreads set `bad` before the loop, so `extra`'s single assignment is safe.
- **`Spread` anywhere else**: the value arm `Encode.scala:377`, the exporter arm `Schema.scala:308`, the plan arm `Decode.scala:214`, and `Encode.reject`'s new arm `Encode.scala:601` — the last is correctly placed **before** the `case d: DataConDecl => None` fallback, which matters now that `Spread` is a real declaration, and it makes `Maybe (Spread Json)` / `List (Spread Json)` static rejections too.
- **Exporter** (`Schema.scala:551-606`): the spread field is dropped from `props` and from `required`; `additionalProperties: jBool(spreads.nonEmpty)` is emitted explicitly, so `Validate` (`contains(false)`) opens and `Zod` can tell open from unstated. The sibling arm of a multi-constructor type stays `false` — pinned in `(s-pins)`.
- **Decoder** (`Decode.scala:812-845`): `allowed` excludes spread fields, `closed` is skipped, `spare = keys.filterNot(allowed.contains)` with `keys = o.fields` (argonaut 6.2.6 preserves document order, as J2a already relies on). `kids` expands the spread in place inside the `fs` traversal and `slots` consumes exactly `spare.size` from the same iterator at the same position — the alignment is correct. `spreadCon` resolves the instantiation and refuses non-`Json`; the fallback `Global("Json","Spread")` equals the registry's.
- **Round trip**: `decode(encode v) == v` holds for collision-free values with the spread at any index. `TestSchema.spreadProbe` places it at `min(pos, k)` for `pos ∈ 0..3`, `k ∈ 0..3`, so first/middle/last all occur; `TestDecode.(s)` round-trips 42 such cases and additionally inserts a key **before every declared one** and **after every merged one**, then re-encodes and compares the full key list — that is a real document-order check, and mutation A falsifies it.

**Declaration refusals** (Spread of non-`Json`, two spreads, positional spread) agree in the exporter (`Schema.scala:561-570`), `Encode.rejections` (`Encode.scala:556-561`) and `Decode.entry` (`Decode.scala:365-369`), at the same field index, pinned in `TestSchema.(s-pins)` (exporter **and** sweep) and in four `TestDecode.(d)` poisons across six contexts. The `Qz` context (`data Qz a = Qza | Qzb { qzf : a }` at `a = Spread Json`) is exactly decision 6's "a type parameter instantiated at `Spread Json` is not a spread field", and all three refuse it where it stands.

## Properties

Genuinely random over declarations and values: `spreadData` is a row of `TestSchema.shape`, so `(a)/(a2)/(c)/(e)/(r-c)/(r-d)` and `TestDecode.(a)/(a2)/(b)+(c)/(d2)` all carry spread types. Anti-vacuity is real and checked three ways: `(a)`'s `missing.isEmpty` fails at zero Spread cases (35 seen); `(s)` asserts floors of 10 collisions / 20 mixed merges (22 / 30 seen) and 30 collision-free / 15 mixed in the decode half (42 / 24 seen); and both of my mutations were caught. The agreement property's move 537→561 valid is explained (an "add key" mutation on a spread-bearing object is now legitimately accepted by both sides) and 0 disagreements holds.

## Dialect, scope, docs

No `given`/`using`/`enum`/`extension`/`export`/`derives`, no `LazyList`, no `CollectionConverters`, no Java 9+ API, no top-level defs, no `?=>`, no wildcard or `as` imports, no new imports at all. Every `Either` goes through `.right.map` / `.right.flatMap` / `.fold(f,g)` / `.isLeft` — no bare `map`, `getOrElse` or `foreach` on an `Either` in the added lines (the `foreach`es are `Option#foreach` and `List#foreach`). ScalaCheck API used (`Gen.sequence`, `Gen.frequency`, `Gen.const`, `samples(…, seed0)`) all already appear in the base files, so no repeat of J3a's `Gen.hexChar` problem. The implementer's P3 note about `private sealed abstract class Slot` / `SpreadP` possibly needing `private[json]` on 2.11 is right and all their uses are inside private members, so widening is a safe no-op fix.

Scope is clean: nine modified files plus the new fixture pair and two tracker notes; nothing under `core/examples/`; `tracker/repl-classpath.txt` unmodified. `JSON-API-DESIGN.md` §3.7c and the plan's J2b row / handoff entry are accurate and short.

## Part 2: the constraint design note

I verified each of the four factual claims against the source, and all four are exact:

1. `Term` carries no type on any node — `App` at `Term.scala:69`, `Sig` at `:75` (user-written `Annot` only), `Var` at `:85`; no session/lsp reference to `core/Core.scala`.
2. `Subst.scala`: `subsumeType` at `:1062`, `restrictTypes(txs)` at `:1068` in the `App` case; `restrictTypes`'s body `hm.types = hm.types -- xs` at `:221` with the "pointless to keep instantiations" comment at `:216-220`; the per-block `SubstEnv` at `Session.scala:59-60`.
3. `toJson#` has exactly one call site in the corpus: `modules/Json.e:67`; `grep toJson core/examples/` is empty; the primitive is `Lib.scala:1478` `primOp(c("toJson#"), …, FA(a => a ->: jsonT))` — instantiated at the wrapper's own skolem, so a pass over those nodes has nothing to reject.
4. `Requirements` at `Subst.scala:81-85`, `hm.classes` at `:94`, reached by `byInst :384`, `entails :392`, `simplifyPredicates :400`, `split :465`, `generalize :1766` — so an undischarged `Json a` would be generalized into schemes and published. `Session.loadModule :1002` and `TolerantCheck.checkWith :831` are indeed two drivers.

Stopping at the design is the right call under the brief's gate ("implement only if the design is a check with no inference changes — a post-typecheck pass over instantiated `toJson#` call sites"): the gate is unmeetable for reason 2 and pointless for reason 3. The note does **not** recommend inference changes — it explicitly rejects the real-constraint route (§3) and recommends (c) the runner's boot-time check with (d) the existing CLI/LSP query. §5 is labelled "if it is built anyway" and specifies a pass over *generalized schemes* (reading, not changing, inference) that should arrive as a warning. Consistent with the user's hold on class-constraint work.

## REQUIRED fix

**1. A merged key equal to the spread field's OWN name is refused by the encoder but accepted by the exporter and the decoder.**

- `core/src/main/scala/com/clarifi/reporting/ermine/json/Encode.scala:438` — `val taken: Set[String] = fields.map(_._1).toSet ++ (…"tag"…)` includes the spread field itself; the check fires at `:508`.
- **Failure scenario.** `data Cx = Cx { cxa : Int, cxs : Spread Json }`. Confirmed in the REPL on the reverted, recompiled tree:
  `:json (Cx 1 (Spread (obj [("cxs", jnull)])))` →
  `error: cannot encode $.cxs: the key "cxs" merged from the Spread field cxs collides with the declared field "cxs" of Cx`.
  But the exporter drops `cxs` from `properties` and emits `additionalProperties: true` (`Schema.scala:576, 606`; the committed `UserSpread.schema.json` shows exactly that shape for `chartExtra`), so `{"cxa":1,"cxs":null}` **validates**; and `Decode.recordStyle` builds `allowed` with `fs.filterNot(isSpreadField)` (`Decode.scala:815`), so `cxs` lands in `spare` (`:819`) and **decodes** to precisely `Cx 1 (Spread (JObj [("cxs", JNull)]))`. So the decoder accepts a document the encoder can never write, and `encode(decode d)` fails on a document the exported schema declares legal — a three-walker disagreement, and the only one in the stage.
  The message is also wrong on its face: it names "the declared field `cxs`", which is not a key of any document of this type. Report decision 3's justification ("the decoder reads a key matching a declared name as that field, so such a merged key would not come back") is true of every declared name **except** the spread field's own, which the decoder does not claim.
- **Fix** (one line, no test currently pins the present behaviour — `spreadProbe`'s keys are `sk0..`, `(s-pins)`' are `k`/`zz`/`tag`, so nothing breaks):
  ```scala
  val taken: Set[String] = fields.filterNot { case (_, t) => isSpread(t) }.map(_._1).toSet ++
                           (if (tagged) Set("tag") else Set[String]())
  ```
  Add one assertion to `TestSchema.(s-pins)` (e.g. `encOk("Sp1 1 (Spread (obj [(\"sp1b\", jnull)]))")` → `{"sp1a":1,"sp1b":null}`) and one to `TestDecode.(s-pins)` (the same document decodes to a `Spread` holding that key), so the direction is pinned either way.
  *If the conservative rule is preferred instead*, the code may stand, but then `modules/Json.e`'s paragraph, the `Encode` class comment (`:76-81`) and §3.7c must say the spread field's own name is reserved even though it is never a document key, and `(s-pins)` must pin it — that still leaves `Decode` accepting what `Encode` cannot write, so the code fix is the better of the two.

## Optional suggestions (not blocking)

- **Refusal precedence differs for a doubly-bad declaration.** `Encode.rejections` tests positional before second-spread (`Encode.scala:556-561`); the exporter (`Schema.scala:561-570`) and `Decode.entry` (`Decode.scala:365-369`) test second-spread first. For `data S = S Int (Spread Json) (Spread Json)` the sweep says "positional" at fields 1 and 2 while the other two say "at most one Spread field" at field 2. Both refuse, at a field, so there is no behaviour gap — only the reason and index differ, and only for declarations with two faults. Align the order or note it.
- **`Encode.spreadArgument` (`:570`) allows a type variable while `Schema`/`Decode` insist on `Json` at the instantiation.** That is the intended split (the sweep is declaration-level), but `data S a = S { x : Spread a }` has no test. A pin — sweep accepts the declaration, exporter/decoder refuse `S Int` at the field, encoder errors on the value — would keep a later refactor from silently changing it.
- **The tsc invocation is worth recording.** `SP/tsc.log` is empty and the flags are not in the report; with tsc's default ES5 lib the run fails inside zod's own `.d.ts` (`Map`/`Set`/`Symbol` not in lib). `--target es2020` (or a checked-in `tsconfig.json`) is what makes it exit 0, and J3d will need the same.
- Open issue 3 (merged keys keep the `JObj`'s order while every other object's order is declaration-driven) is correctly flagged; `(c)` determinism still passes, so nothing to do now, but J3d's client should not assume key order anywhere.

## Verdict

**FIX-THEN-LAND** — one required fix (item 1 above: exclude the spread field's own name from the encoder's collision set, or document-and-pin the stricter rule), plus the four optional suggestions. Everything else in the stage is correct, consistent across the three walkers, properly property-tested, non-vacuous under two independent mutations, in the 2.11 dialect, in scope, and accurately documented; Part 2 correctly stops at a design whose factual claims I verified one by one.