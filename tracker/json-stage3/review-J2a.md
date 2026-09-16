# Independent review of J2a (the params decoder)

Reviewer: an agent that did not write the stage. Worktree
`~/research/ermine/ermine-scala-wt-json-decode`, branch `json-decode`, base `a7e8e050`
(`json-s3-base`). Reviewed: `git diff a7e8e050` plus the untracked
`core/.../json/Decode.scala` and `scalacheck-binding/.../TestDecode.scala`. Read in the
order the brief names; review brief is `tracker/json-stage3/brief-review.md` (found in the
`ermine-scala-wt-json` worktree — it is not present in this one). ~1 h 45 m.

My logs: `/tmp/claude-1000/-home-dmitry-research-caliper/c359de0f-018b-42eb-960e-7519d0922cee/scratchpad/review-j2a/`
(`rv/` below). The implementer's are under `.../scratchpad/j2a/` (`sc/` below).

## Summary

The decoder is a careful, correct inverse of `Encode` on the serializable fragment. I
checked every primitive row against `Encode.scala` line by line and found no mapping
mismatch. The run phase is genuinely iterative, the compile phase is the exporter's walk,
values are built the way evaluation builds them (registry `Global`s, `Type.True/False`,
`Null` + `withNull` witness, `java.util.Date` at UTC midnight, `java.sql.Timestamp`,
`extract`ed elements for `List#`/`Maybe#`/`Pair#` against `whnfForeign` for `Vector`), and
the properties are not vacuous — I broke a case and three of them failed. Two things need
fixing before it lands: a flaky property that can redden the gate, and one
decoder/exporter disagreement that is neither pinned nor reported (and which I confirmed
produces a *broken* exported schema today).

## What I re-ran

| What | Command | Result | Log |
|---|---|---|---|
| Gate 1+2, as the brief spells them | `sbt -batch core/compile core/copyResources 'core/testOnly …TestDecode …TestJson …TestSchema …TestNamedFields'` | **Total 71, Failed 0, Errors 1, Passed 70** — `TestDecode.(e2)` raised `java.lang.StackOverflowError` | `rv/gate-review.log` |
| The same suites, 3 repeats (no recompile) | `sbt -batch 'core/testOnly …'` | 71/71 each | `rv/gate-rep-1..3.log` |
| `TestDecode` alone | `sbt -batch 'core/testOnly com.clarifi.reporting.TestDecode'` | 10/10 | `rv/decode-alone-1.log` |
| The 4 suites, 8 more repeats (with a diagnostic wrapper on (e2), since reverted) | as above | 71/71 each | `rv/diag-1..8.log` |
| Gate 1+2 again, 3 cold runs (sources touched, compile + test in one JVM) | as row 1 | 71/71 each | `rv/cold-1..3.log` |
| Mutation test (mine, independent of the implementer's) | `Decode.scala:476` `Prim(l.toShort)` → `Prim(l.toInt)`, then `TestDecode` | **(a), (a2), (a3) all fail**; reverted, sha256 restored | `rv/mutation-short.log` |
| Confirming finding 2 | `java -cp <scratch>:<classpath> SchemaMain -i Tagf 'Tagf'` on `data Tagf = A { tag : Int } | B { bx : Int }` | exporter emits a **broken** schema (below) | shown inline in this file |

CITED, not re-run (the diff cannot plausibly move them, and all four stage-1 source edits
are timestamped 06:09–06:23, before every one of these runs): TestLoopTrace 3/3 with the
720-case model differential SKIPPED because no `looptrace` binary exists in this checkout
(`sc/gate23.log`) — acceptable, the diff touches no solver, `Type.scala` or Lean code;
corpus **89 LOADED / 79 REJECTED / 0 UNKNOWN over 168**, unchanged (`sc/corpus-run.log`,
`sc/corpus-verdicts.log`); `repl-smoke.sh` all PASS including its 20 `json` checks
(`sc/repl-smoke.log`); `lsp-smoke.sh` PASS, 577 checks (`sc/lsp-smoke.log`).

I also verified `core/.../json/Decode.scala` is byte-identical to the implementer's
pre-mutation backup `sc/Decode.scala.bak`, i.e. their own mutation experiment was properly
reverted, and that `tracker/repl-classpath.txt` is unmodified, nothing under
`core/examples/` changed, and no committed fixture under `core/src/test/resources/schema/`
moved (none of the eight contains `maxLength`; `TestSchema.(gate)` passes).

## Correctness, against `Encode` line by line

Every row checked; no mismatch found.

| Type | `Encode` | `Decode` | Verdict |
|---|---|---|---|
| Int/Short/Byte | `b.int(_.intValue)` | `integral` + `toInt/toShort/toByte`, range-checked, fraction refused, magnitude tested before materialising | ok; JVM class pinned by `same` |
| Long | `b.str(l.toString)` | `^-?[0-9]+$` via `matcher.matches` (so no trailing-newline hole on the decoder side), `parseLong` in a forced `val` | ok |
| Double/Float | `finite`, NaN/∞ refused | any number finite at that width | ok |
| Bool | `Data(True/False)` → boolean | `Type.True`/`Type.False` | ok (`Global` equality includes `fixity.con`; the default `Idfix` is what evaluation produces) |
| String/Char | string / 1-char string | string / exactly one UTF-16 unit | ok |
| Date | `dateFmt` UTC on `java.util.Date` (`java.sql.Timestamp` matched first) | `ISO_LOCAL_DATE` strict → `new java.util.Date(atStartOfDay(UTC))` | ok; runtime class pinned in `(map)` against `Session.eval("@2026/9/16")`, and `same` compares `getClass` |
| Timestamp | `...SSS'Z'` of `ofEpochMilli(getTime)` | `ISO_OFFSET_DATE_TIME` → `Timestamp.from`, with `toEpochMilli` first to defeat `Timestamp.from`'s wrap | ok; widening to any offset is documented and matches `Validate`'s own `date-time` test |
| GUID | `u.toString` | canonical 8-4-4-4-12 only | ok |
| `Maybe a` | `Nothing`→null, `Just x`→x | null→`Nothing`, else `Just` | ok |
| `Nullable a` | `Null`→null, `Some x`→x | null→`Data(Null,[Prim(primTypes(t).withNull)])`, else `Data(Some,[v])` | ok — and this is exactly the shape `Runtime.NullableValue` destructures (`Data(Global("Builtin","Null",Idfix), …)`, `Prim(pt: PrimT)` inside) |
| `Maybe#`/`List#`/`Pair#` | `Prim(None/Some)`, native list, tuple | `Prim(None)`, `Prim(Some(unboxed v))`, `Prim(vs.map(unboxed))`, `Prim((unboxed,unboxed))` | ok — `unboxed` is exactly what `::#`/`Just#`/`toPair#` store (`x.extract[Any]`) |
| `Vector a` | array | `Prim(vs.map(foreign).toVector)` | ok — `foreign` reproduces `Session.whnfForeign` for every value the decoder can build, including the empty `Arr` → `()` case. Nice catch; the asymmetry with `List#` is real |
| tuples / `()` | `Arr` → array, empty → `[]` | array of exactly the arity → `Arr`; `[]` → `Arr()` | ok |
| closed record | sorted unqualified keys | `rowFields` sorted, exact key set, `new Rec(map)` | ok |
| `data`, all-nullary | constructor name (uses `decl.isEnum`) | same test, `Data(g, [])` | ok |
| `data`, record-style | named keys in declaration order, `"tag"` first iff `constructors.length > 1`, a declared-`Maybe` field omitted when `Nothing` | same test (`declaredMaybe` = `Builtin.Maybe` alone, the encoder's `isMaybe`), absent optional → `Nothing`, present → `Just` | ok |
| `data`, positional | `{"tag":C,"args":[…]}` always, including 0 args | same, `.args[i]` paths | ok |
| stdlib `Json` | itself | `ErmineJson.arr/obj` + `Encode.fromArgonaut` for scalars | ok, identical to `parseJson#` |

Other things I checked and am satisfied with:

- **Stack safety.** `run` is a genuine explicit-stack loop; `Path` is parent-linked and
  rendered only on error; `listOf` folds over a reversed list; `indexed`/`map`/`ListBuffer`
  are all iterative. 100,000 records decode in 616 ms here (`rv/gate-rep-1.log`). Compile
  recurses over the type, which is bounded by the source.
- **Recursion/memoisation.** `defs += key` before the fields are walked, so a recursive
  `data` terminates; the `DataRef` is resolved through the table at run time.
- **Thread safety.** `DataP`'s `var`s are written only during `compile`, and everything is
  reachable from `Decoder`'s final fields, so the final-field freeze publishes them safely
  to the request threads J3c will use. (See optional 3.)
- **The three Stage 1 fixes are right.** (1) `Encode.isMaybe` names `Builtin.Maybe` alone,
  so a `Nullable a`/`Maybe# a` named field really is written as `null` and really must stay
  a required key with a nullable schema — the old `maybePayload` reading was wrong, and
  `maybePayload` is still used for the nested-Maybe refusal at `Schema.scala:230`, so
  nothing is now dead. (2) `Char` genuinely needed `minLength: 1`; `Validate` gained the
  keyword and `Zod` `.min(n)`; no committed fixture moves. (3) `Validate`'s `uuid` taking
  `UUID.fromString` really did accept `"1-1-1-1-1"`. None of the three moves a fixture.
- **Decoder/validator agreement**: `Validate`'s `"integer"` is `toBigDecimal.isWhole`,
  which is exactly the decoder's "no fractional part" reading, so `1.0`/`1e2` agree on both
  sides. The four pinned gaps in the report are the four the schema genuinely cannot state,
  plus the two Timestamp/Date range pins; my run reproduces the implementer's numbers
  exactly (`535 valid, 1409 invalid, 6 pinned schema gaps, 0 disagreements`).
- **Dialect.** No `given`/`using`/`enum`/`extension`/`export`/`derives`, no `LazyList`, no
  `CollectionConverters`, no Java 9+ API, no `Either#map`/`flatMap` without `.right`, no
  top-level defs, no `?=>`, no `as` renames, no trailing commas. `while (true) … ;
  sys.error("unreachable")` is written the 2.11 way. The scalacheck API `TestDecode` uses
  (`Gen.Parameters.default.withSize`, `rng.Seed`, `forAllNoShrink`) is already used by
  `TestSchema` on the base, so the port carries no new scalacheck risk.
- **The 2.11 `private[Decode]` risk** (report open issue 4). My judgement: low. `Plan` and
  its subclasses are `private` members of `object Decode`, i.e. `private[Decode]`; the
  `Decoder` constructor is `private[Decode]`, the same scope, and `root` becomes a
  `private[this]` field, so nothing more visible than `Plan` mentions `Plan`. 2.11's
  "escapes its defining scope" check should be satisfied. The documented one-line
  mitigation (widen `Plan`/`DataP`/`ConP`/`FieldP`/`Path` to `private[json]`) is the right
  fallback if it is not; nothing else in the file is at risk.
- **Docs.** §3.7b and the plan's handoff line are accurate and short. The report is honest,
  including about the non-injective spot and the deliberate `entry`/exporter differences.

## Required fixes

### 1. `TestDecode.(e2)` is flaky and will intermittently redden the gate

`scalacheck-binding/src/main/scala/TestDecode.scala:527-534` (`parserDepth`), used at
`:540` and `:543`, and `:559` (`deep = 10 * limit`).

`parserDepth` binary-searches to the EXACT depth at which argonaut's recursive parser
overflows on this thread at that instant, and the property then re-parses at exactly that
depth (`:543`) and builds an in-memory document ten times deeper (`:559`). The measurement
is not stable: 3,864 / 4,114 / 4,115 / 4,476 / 4,608 / 8,192 / 8,505 in my runs, 16,384 and
19,627 in the implementer's two (`sc/gate23.log`, `sc/gate2-final.log`) — a 5× spread, because it depends
on the JIT/deopt state of a JVM that is also running three other suites (and, in the gate
command, has just run the Scala compiler in-process).

**Failure scenario, reproduced**: `sbt -batch core/compile core/copyResources 'core/testOnly
…TestDecode …TestJson …TestSchema …TestNamedFields'` — the gate command, on a JVM that also
did the compile — gave `Failed: Total 71, Failed 0, Errors 1, Passed 70` with
`(e2) … Exception raised on property evaluation. > Exception: java.lang.StackOverflowError`
(`rv/gate-review.log`). That is gate 2 red on an unchanged tree. It did not reproduce in the
14 further runs I made (11 `testOnly`, 8 of them carrying a stack-trace wrapper on the
property, plus 3 more full compile-and-test runs with the sources touched), so the rate is
roughly 1 in 15. I could not therefore capture the overflowing frame, and the run that did
fail is the only one whose JVM had also just compiled the two new files — but the mechanism
does not need pinning down to be a defect: the property deliberately operates at the exact
measured stack boundary, and it reports an `Error`, not a `Falsified`, so an occurrence
looks like a real crash to whoever reads the landing log.

**Fix** (test-only, no decoder change): take a margin instead of sitting on the boundary —

```scala
val limit = math.max(1, parserDepth * 3 / 4)   // :540
```

and, because the probe is a measurement rather than a guarantee, wrap the one call that
depends on it being exact:

```scala
val parsed = try parse("[" * limit + "]" * limit)
             catch { case _: StackOverflowError => sys.error("probe over-measured: " + limit) }
```

or, simplest and most deterministic, stop deriving the in-memory depth from the probe at all
(`:559`): use a fixed `deep = 100000` — the point of that half of the property is that the
DECODER is iterative, which has nothing to do with what the parser can read.

### 2. A third decoder/exporter disagreement, unreported and unpinned — and the exporter is broken there

`core/.../json/Decode.scala:348-349` refuses a record-style field named `tag` in a type with
more than one constructor. `core/.../json/Schema.scala:355-390` has no such check, and
`core/.../json/Encode.scala:406-409` builds `keys = "tag" :: fs.map(_._1)`, so both silently
produce a document/schema with a duplicated `"tag"` key, of which argonaut keeps the last.

The report's "Known gaps, pinned rather than fixed" table lists four validator-accepts /
decoder-refuses cases, and property `(d)`'s `poisons` list pins the two deliberate
`entry`/exporter differences (`Nullable Char`, a relation). This one is in neither, so
nothing in the suite would notice if it regressed in either direction — and the brief for
this stage says a disagreement must be fixed or "report the validator gap and pin it".

**Confirmed, not theoretical.** `data Tagf = A { tag : Int } | B { bx : Int }` through
`bin/ermine-schema`'s `SchemaMain` gives:

```json
"oneOf" : [
  { "type":"object",
    "properties": { "tag": { "type":"integer" } },      <- the "const":"A" discriminator is GONE
    "required": [ "tag", "tag" ],                       <- duplicated
    "additionalProperties": false },
  { "type":"object",
    "properties": { "tag": {"const":"B"}, "bx": {"type":"integer"} },
    "required": [ "tag", "bx" ], "additionalProperties": false } ]
```

and `Encode` for an `A 7` would emit `{"tag": 7}` — the discriminator overwritten by the
field. The decoder's refusal is the right call; the exporter and the encoder are what is
wrong, and a client generated from that schema (J3d) would get a discriminated union with a
missing discriminator.

**Fix** (any of these is small enough not to need another review):
- minimum: add the case to `report-J2a.md`'s gaps table and to §3.7b as a *fourth*
  deliberate decoder/exporter difference, and add a poison row to `TestDecode.poisons`
  (`:451-460`) — `("Tg", "data Tg = Tga { tag : Int } | Tgb { tgx : Int }", "tag", false)`
  with the type in place of the poison — so it is pinned the way the other two are; **or**
- better, and cheap: give `Schema.constructor` (`Schema.scala:373`) the same check the
  decoder has (`reject(path(i), "a field named tag collides with the discriminator …")`),
  make `Encode.rejections`/`reject` refuse it too, and then the poison row carries
  `schemaRefuses = true` and all three agree.

If the second form is taken, note that it is a change to code J3a is editing in parallel;
the first form touches only J2a's own files and the tracker.

## Optional suggestions (not blocking)

1. **`same`'s `jnullish` equivalence is broader than the non-injectivity it excuses**
   (`TestDecode.scala:73-80`, used at `:92`). It holds `Prim(None)` (`Nothing#`) equal to
   `Data(Builtin.Nothing)` (`Maybe`'s `Nothing`), so a decoder that built the wrong *wrapper*
   for a native `Maybe#` null would pass (a) — and `(map)`/`(a3)` do not pin `Maybe#` either.
   The code is right today; the property just cannot see it. One line in `(map)` closes it:
   `assert(ok("Maybe# Int", "null") == Prim(None))` (a direct `==`, which does discriminate,
   unlike `same`).
2. **Whole-valued `JNum` does not round-trip** (`JNum 2.0` → `2.0` → `JInt 2`), which is why
   `TestSchema.jsonValue` always adds a fraction. This is inherited from Stage 1's
   `Encode.fromArgonaut`/`parseJson#`, not new, and the generator comment says so — but §3.7b
   lists only `Maybe Json` as the non-injective spot; it is worth one clause there too.
3. **For J3c**: consider making `DataP`'s three `var`s `val`s (build the `ConP` list first,
   then construct `DataP`) so caching a `Decoder` in a plain `HashMap` across request threads
   needs no argument about final-field freeze. Also, `compile` catches only `Refuse`; an
   unexpected exception out of `Type.expandAlias`/`s.cons` would reach the runner as a 500
   rather than a refusal — a `catch { case NonFatal(e) => Left(Error("$", …)) }` would keep
   the report's "a refusal is a 400, not a 500" promise unconditional.
4. **`Schema.defName` is reused as the decoder's memo key** (`Decode.scala:302`). Its
   `keyOf` is lossy (a `ConcreteRho` becomes `Row_<sorted names>`, an unknown head becomes
   `T`), and where in the exporter a collision only merges two `$defs` entries, in the
   decoder it silently decodes one type as another. The exposure is pre-existing and I could
   not construct a collision between two well-kinded instantiations, so this is a note for
   whoever next touches `defName`, not a defect of this stage.
5. **The report's zod claim about `uuid`** ("zod's `.uuid()` … want the canonical form") is
   only half of it: zod 3's `.uuid()` also constrains the version and variant nibbles, which
   `new java.util.UUID(randomLong, randomLong)` — what `TestSchema` generates, and what a
   database column can hold — usually does not satisfy. There is no zod runtime harness in
   the repo, so neither side is checked; worth a look when J3d lands the TS package.
6. **Compile-time refusal paths mix spellings** (`$`, `$[]`, `Pz0.Pz0[1]`). It is documented
   in §3.7b and only `entry`'s errors are affected (never a client-facing one), so leave it —
   but J3c should not assume `Decode.Error.path` is a JSON path unless the error came from
   `Decoder.apply`.

## Properties: are they real?

Yes. Generators are over random declarations AND values (`TestSchema.shape` builds Ermine
source and loads it), the Stage 2a vocabulary is reached in quantity (my run: Short 22, Byte
26, Float 7, Char 7, Date 29, Timestamp 25, GUID 29, Nullable 54, Vector 34, `List#` 42,
`Maybe#` 28, `Pair#` 26, Json 56, record 28, record-style data 26, Maybe 26 of 200 cases —
and (a) asserts every one of those is non-zero), (b)/(c) assert both verdicts occur in
quantity, and (d)'s 100 cases cover 9 poisons × 6 contexts.

**Vacuity, checked independently of the implementer's own check.** I mutated
`Decode.scala:476` (`Short`) from `Prim(l.toShort)` to `Prim(l.toInt)` — a JVM-class change
that no JSON document can see — and ran `TestDecode`: `(a)` falsified after 0 tests, `(a2)`
after 5, `(a3)` raised; `Total 10, Failed 2, Errors 1, Passed 7` (`rv/mutation-short.log`).
Reverted; `sha256sum -c` confirms both `Decode.scala` and `TestDecode.scala` are
byte-identical to their pre-review state. Note that `(b)+(c)` stayed green under that
mutation, which is correct — representation is (a)'s job, not agreement's.

The one weakness is optional suggestion 1 above.

## Gates

| # | Gate | This review | Source |
|---|---|---|---|
| 1 | `core/compile core/copyResources` | success every run | `rv/*.log` |
| 2 | TestDecode + TestJson + TestSchema + TestNamedFields | 71/71 in 14 of 15 runs; **70/71 + 1 Error once** (finding 1) | `rv/gate-review.log`, `rv/gate-rep-*.log`, `rv/diag-*.log`, `rv/cold-*.log` |
| 3 | `*TestLoopTrace` | 3/3, 720-case differential SKIPPED (no `looptrace` binary); acceptable for this diff | cited, `sc/gate23.log` |
| 4 | corpus | 89 / 79 / 0 over 168, unchanged | cited, `sc/corpus-verdicts.log` |
| 5 | repl-smoke / lsp-smoke | PASS / PASS 577 checks | cited, `sc/repl-smoke.log`, `sc/lsp-smoke.log` |

Scope is clean: only the seven files the report names, nothing under `core/examples/`,
`tracker/repl-classpath.txt` untouched, no committed fixture moved.

## Verdict

FIX-THEN-LAND — the two required fixes above.
