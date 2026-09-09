# Review: F4 — the interface round-trip fix (ticket E1)

Reviewer, 2026-09-09, independent of the implementer.  Repository `/home/dmitry/research/ermine/ermine-scala`
at HEAD `1adbcb6` plus the UNCOMMITTED F4 deliverables.  Brief `tracker/loopmodel/briefs/brief-F4-review.md`;
implementer's report `tracker/loopmodel/F4-ROUNDTRIP.md`.  Reviewer scratch
`/home/dmitry/.claude/jobs/880c725d/tmp/review-F4/`; I edited nothing but that tree and this file; no commits;
`tracker/lean/` untouched and no Lean built; every `.ei` I caused is deleted and the checked-in `tracker/g1-*`
are untouched (`git status --porcelain tracker/g1-baseline` empty).  One JVM at a time,
`-Xmx2g -XX:ActiveProcessorCount=2` throughout; `sbt core/compile core/copyResources` before every `bin/ermine`
gate.

**VERDICT: ADVANCE.**  I reproduced the cause on a pre-fix compiler I built myself, re-derived the census to the
digit (7,448 / 53 / 34; 70 files holding a dotted-lower label = the 70 rewritten), reproduced the negative
control with every figure the report quotes, reproduced the timing bands, and re-ran every gate.  **No defect in
the parser change, the tests, the census or the measurement.**  One gate did not reproduce first time: my first
`core/test` run was 942 passed / **1 error**, in `TestLower` — a suite F4 does not touch, with a fixture-level
concurrency signature; my second run of the same tree was 943/943, and the flake does not reproduce in
isolation (R-1).  That is a reporting correction and a ticket, not a fault in the work, hence ADVANCE rather
than FIX-THEN-ADVANCE — but R-1 and R-2 should be written into the trackers before the commit, and R-3 is a
free strengthening of the new property that costs one line.

Method note, for reproducibility: `git stash` is not available to me either, so the "before" side everywhere in
this review is `git show HEAD:…/parsing/TypeParsers.scala` compiled with `dotty.tools.dotc.Main` against
`target/ermine-classpath` into `<scratch>/prefix-out`, that directory PREPENDED to the classpath of
`com.clarifi.reporting.ermine.session.Console` (and, for the negative control, of the ScalaCheck runner).  That
is F3's reviewer's recipe: a genuine pre/post pair differing in exactly one source file, without touching the
tree.  Scripts: `<scratch>/erm-pre.sh`, `<scratch>/erm-post.sh`, `<scratch>/corpus-iface.sh`, `<scratch>/battery.sh`.

## Findings

| # | rank | status | finding |
|---|---|---|---|
| **R-1** | medium | CONFIRMED | **`sbt core/test` is INTERMITTENT: my first run was 942 passed / 1 ERROR, my second 943/943.**  Run 1: `Failed: Total 943, Failed 0, Errors 1, Passed 942`, exit 1, 1,453 s, the error being `Lower 3.4a.negation applies primNeg to the whole chain: Exception raised on property evaluation. > Exception: scalaparsers.Death: Module not found: 'Test'` — the shared `ErmineFixture`'s dynamic `Test` module missing from a session that `ErmineFixture.baseEnv` seeds with it, under whole-suite parallelism.  Run 2, unchanged tree: `Passed: Total 943, Failed 0, Errors 0, Passed 943`, exit 0, 1,356 s.  It is NOT the parser change (`TestLower` exercises the lowering pipeline, not the interface grammar) and it does not reproduce in isolation (four targeted runs: `TestLower` alone 2× = 28/28; `TestLower` + the new suite 2× = 31/31).  The new suite's three properties are green in BOTH full runs.  So the report's figure is attainable but the gate is not deterministic, and the tracker line should say so rather than record a clean 943/943 — a suite that is red one run in two is a gate nobody can use.  The mechanism is S5's hazard, not F4's: six suites (`TestNewPipeline`, `TestLower`, `TestTolerantCheck`, `TestTolerantRead`, `TestStage1Pins`, `TestEditorBuffers`) touch `Session.depCache`/`loadModules` WITHOUT `ErmineFixture.literalLock`, while the interface suites clear the process-global dep cache under it — and the new suite holds that lock ~85 s per run and clears the cache five times, which lengthens the window.  Worth a ticket of its own. |
| **R-2** | low-medium | CONFIRMED | §6's parenthetical — "each side reading a tree the other side wrote (**the bytes are identical**, which is the point)" — is true only WITHIN a regime.  Measured on the PRE-FIX compiler alone: a cold-written tree and a warm-written tree differ in **16 of 241** interfaces (15 examples + `Layout/Report/Relation.ei`), in quantifier shape (`forall a b (k: rho)…` vs `forall {a b} (a1: a) (b1: b) (k: rho)…`), in an existential binder's kind (`(Has: rho -> a)` vs `(Has: a)`) and in constraint order.  So an `.ei`'s published bytes depend on the LOAD HISTORY of the session that wrote it.  None of it is F4's doing — it reproduces with the pre-fix compiler on both sides — and F4's substantive claim survives, because I verified the strong version directly: the post-fix compiler read all **241** interfaces the pre-fix compiler had written, rewrote **0** and moved **0** bytes.  But the parenthetical overstates, and the fact itself is recorded nowhere.  It deserves a ticket line: it is a live hazard for any future `.ei` byte comparison (the Tier 1 sweep included) and for the canonicaliser (`ROSE-COMPARISON.md` §3 rank 3). |
| **R-3** | low | CONFIRMED | **Property 3's alpha-equivalence is weaker than it needs to be, and the report's two-part justification is half right.**  I built both variants and ran them.  (A) `aeqs` replaced by plain `G1Compare.alphaEq`: property 3 falsifies on **15 of 245** interfaces (`Relation.ei :: joinWithDefault, lookbackJoin, setColumn`, `Op.ei :: %, *, +`, `Predicate.ei :: !=, &&, <`, `Helpers.ei`, `Signatures.ei`, `Legendary.ei`, `PresRow.ei`, `RTree.ei`, …) — so the change IS load-bearing.  (B) `aeqs` kept, but `Forall` binders paired POSITIONALLY as `G1Compare` pairs them, with only the complete (every-bijection) search retained: property 3 **PASSES**.  So of the two documented differences only the completeness one is needed on this corpus; the Forall relaxation buys nothing and could be dropped, making the property strictly stronger at no cost.  Neither `aeqs` nor `G1Compare.alphaEq` compares binder KINDS at all, so that hole is inherited rather than opened. |
| **R-4** | nit | CONFIRMED | `dottedFieldName` accepts strictly more than the printer can emit: `(upperName >> (ch('.') >> anyName).skipSome)` lets every segment after the first start lower case, so `(\|Mod.foo.bar\|)` parses as `Global("Mod.foo", "bar")`.  Nothing emits it, and the split (`lastIndexOf('.')`; `tailChar` excludes `.`) stays exact, so it is harmless — but the scaladoc says "the module path, then a final segment", which is not what the parser enforces.  Conversely the head IS still `upperName`, which is exactly right and worth one clause of comment: `SurfaceParsers.moduleNameTok` requires every segment of a module name to start upper case, so a lower-case module part is unreachable (I tried: `module lower where` is a syntax error, and a header-less file — the only other way to a `defaultModuleName` with a lower-case head — does not load at all, three spellings tried). |
| **R-5** | nit | CONFIRMED | The corpus fixture stages the whole corpus into `Files.createTempDirectory("ermine-ei-corpus")` and never deletes it: **3.5 MB per run of `core/test`**, left in `/tmp` forever (34 `ermine-*` trees are there now).  `TestInterfaceRoundTrip`/`TestInterfaceKey` leak temp trees too, so it is the house pattern rather than a new sin — but they leak kilobytes and this leaks megabytes on every test run. |
| **R-6** | nit | CONFIRMED | Two prose corrections.  (a) The ticket gives `SurfaceParsers.fieldStatementP`'s `identTok` as the reason BOTH N6/N7 (an abnormal label) and N8 (an operator label) are unreachable; it is N8's reason only.  `TypeNameParsers.ident` is `super.ident \| literalIdent`, so on a reading of the grammar a back-quoted label looks admissible inside a row — it is refused in practice (I verified, four spellings), but the stated mechanism does not cover that half.  (b) My timing bands sit ~0.5 s above the report's on the pre side (pre **36.11 / 36.38 / 36.54 / 36.74 / 37.02**, post **23.61 / 24.04 / 24.08 / 24.27**), so the tracker numbers should not be read as machine-exact.  Same conclusion, disjoint bands, ~12.3 s. |

## 1. The cause, the corrected scope, the census

### 1.1 Reproduced, on my own pre-fix build

Eight probes, one `bin/ermine` invocation per load, cold load then warm load, `.ei` mtime and md5 compared
(`<scratch>/battery.sh`, `<scratch>/forms/`):

| probe | the published signature (key header stripped) | pre-fix | post-fix |
|---|---|---|---|
| `R01Part` | `sig : forall (r: rho). r <- ((\|R01Part.foo\|), h) => Builtin.Relation r -> Builtin.Relation r` | **REWRITTEN** | warm |
| `R02PartUpper` | `… r <- ((\|R02PartUpper.Foo\|), h) => …` | warm | warm |
| `R03TypeArg` | `sig : Builtin.Relation (\|R03TypeArg.foo\|) -> …` | **REWRITTEN** | warm |
| `R04TypeArgUpper` | `… (\|R04TypeArgUpper.Foo\|) …` | warm | warm |
| `R05Record` | `sig : Builtin.Record (\|R05Record.foo\|) -> …` | **REWRITTEN** | warm |
| `R06Multi` | `… r <- ((\|R06Multi.foo, R06Multi.bar\|), h) => …` | **REWRITTEN** | warm |
| `R07Empty` | `sig : Builtin.Relation (\|\|) -> …` | warm | warm |
| `R09Odd` | `sig : Builtin.Record (\|R09Odd.a#b, R09Odd.c'd, R09Odd.e_1\|) -> …` | **REWRITTEN** | warm |

That is the implementer's F01–F07 battery independently rebuilt, plus the `#`/`'`/`_` label (N3), and it gives
the same answer.  **The corrected scope is confirmed: it is the LABEL, not the partition shape** — a lower-case
label fails as a part (`R01`), as an argument to `Relation` (`R03`) and as an argument to `Record` (`R05`), and
an upper-case label warm-reads in every one of those positions.  The two compilers publish IDENTICAL bytes for
all eight, and the post-fix compiler warm-reads all eight files the PRE-FIX compiler wrote.

### 1.2 The mechanism, checked in the source

`Pretty.ppName`'s `case Global(m,n,Idfix) => qualifiedGlobal(m,n)` and `qualifiedGlobal`'s
`case FullyQualified => m + "." + n` (`Pretty.scala:84–99`) publish the label fully qualified with no regard for
`n`'s case and — worth noting for N7 — with no back-quoting at all on that branch.  `Dep.writeInterface`
(`Session.scala:560`) is the only interface caller and goes through `prettyVarHasType(_, FullyQualified)`.
`TypeParsers.rho` read it back with `dottedName` = `upperName >> (ch('.') >> upperName).skipSome`.  Confirmed.

`recognizedCons` — the flag that puts `rho` on the dotted branch at all — is written in exactly two places in
the tree: `Session.scala:480` (`preCk`, reading an `.ei`) and `G1Compare.scala:142`.  So the branch is
interface-only by construction and the source language cannot reach it; §2 checks that empirically too.

### 1.3 The census, re-derived

My own corpus run (154-file batch, one JVM, interfaces ON) produced **241** interfaces — 156 under the stdlib
tree, 85 under `core/examples`, matching the report's split (the boot's 129, listed in
`tracker/tools/g1-modules.txt`, plus 27 more the examples pull in).  My own census script over all 241
(`<scratch>/census.py`):

```
interfaces 241
dotted-lower 7448 in 70 files
dotted-upper 53 in 5 files
empty rows 34
other 0
```

**Exactly the reported 7,448 / 53 / 34, and no other shape** — `other 0` in particular means not one BARE
(unqualified) label in 7,535 positions, which is the report's N5 ("`rho` globalises every label at parse time").
The 53 dotted-upper are `PivotTest.*` (48, an example) and `Field.Count` (5).  `Field.Count` occurs in the
stdlib's `Relation.ei` and `Relation/Aggregate.ei`, both boot modules; `Currency` and `Layout.Report.Relation`
are in neither the 129-module boot list nor anything it imports.  So the report's explanation of why the stdlib
looked clean holds on both halves.

**70 = 70, no cascade.**  Two consecutive warm runs with the pre-fix compiler rewrite **70 of 241** interfaces,
and the set of files holding at least one dotted-lower label is EXACTLY that set (`comm` both ways: empty and
empty, 70 in common).  The split is 68 examples + 2 stdlib (`Currency.ei`, `Layout/Report/Relation.ei`).  The
post-fix compiler rewrites **0 of 241**, measured three ways: post→post; post reading a PRE-fix-written tree
(0 rewritten, 0 bytes moved); and pre/post interleaved five times (0 on every post side, 70 on every pre side).

The ticket's original "18 of 268 … only a concrete row as a PART of a partition" is wrong in both the predicate
and the count, and F4's correction of it is right.

## 2. The fix: minimal, exact, and it does not touch source parsing

The diff is one call site (`dottedName.attempt` → `dottedFieldName.attempt` in `rho`) plus `dottedFieldName` and
`anyName`.  `dottedName` is untouched, so `interfaceCon` still demands an upper-case constructor.  `rho` has
three callers — `banana`, `brace`, `bracket` (`TypeParsers.scala:237–239`) — all three row syntaxes, and only
the banana form occurs in a published interface.

**Can it accept something `dottedName` rightly rejected?**  In this position no meaning can change, by
construction: both parsers split at `lastIndexOf('.')` (and `tailChar` — `letter | digit | _ | # | '` — excludes
`.`, so the split is exact), and both are greedy, so on any string `dottedName` accepts, `dottedFieldName`
consumes the same extent and returns the same `Global`.  Every string whose treatment changes is one
`dottedName` REJECTED, and in `rho` a rejection was always a parse ERROR one character later (`typeName` stops
at the dot and the row grammar then wants `,` or `|)`), never a different successful parse.  The change is
failure→success only.  R-4 records the one widening that reaches beyond what the printer can emit.

**Does it misparse a constructor as a label?**  `rho` only ever builds `ConcreteRho` labels, and both parsers
hand it the same `Global` for a constructor-shaped name.  Checked live: a SOURCE row whose label happens to be a
type constructor in scope (`Record (|Int|)`) resolves through `canonicalTypes` and publishes `(|Builtin.Int|)`,
read identically by both compilers, with byte-identical output.

**Does SOURCE parsing change?  No.**  Eleven source probes (`<scratch>/reach/`) — a dotted lower-case name in a
row (`(|Prelude.foo|)`), a dotted upper-case one (`(|Field.Count|)`), a bare constructor (`(|Int|)`), a mixed
row (`(|foo, Bar|)`), a back-quoted label, a type alias holding one, an operator label, a `field` statement with
a back-quoted name — run through BOTH compilers and diffed: the diagnostics are **byte-identical, line for line
and column for column**, and the `.ei` the two loadable probes publish are byte-identical.  That is what
§1.2's `recognizedCons` argument predicts.

**Are N7 (an abnormal label, published unquoted) and N8 (an operator-fixity label) reachable from source?**  I
tried six ways and reached neither:

| attempt | result |
|---|---|
| `sig : Record (\|``a b``\|) -> …` | rejected: the row grammar does not take a literal ident |
| `sig : Record (\|``ab``\|) -> …` (a legal-looking literal ident) | rejected the same way |
| `type R = (\|``a b``\|)` | rejected AT the back-quote: `expected '..', '\|)', constructor, identifier, or qualified name` |
| `field ``a b`` : Int` | rejected: `fieldStatementP` takes `identTok` (`SurfaceParsers.scala:618`) |
| `sig : Record (\|(++)\|)` | rejected — `typeName`'s `paren(opName(canonicalTypes))` fails with "forward reference to an operator with unknown precedence" for anything not already a type operator |
| `sig : Record (\|(<:)\|)` and `(\|(\|)\|)`, the tree's two REAL type-level operators (`Type/Cast.e`, `Constraint.e`), imported | rejected identically |

So the unreachability claim stands; R-6(a) corrects the mechanism the ticket gives for half of it.

`interfaceFormatVersion` correctly stays at 2: every pre-fix `.ei` is byte-valid and now readable, which §1.3
verifies end to end.

## 3. The tests

**Re-run alone, three times** (the ScalaCheck runner on the exported `core/Test/fullClasspath`, cwd = repo root,
one JVM each): green each time, 85 s / 85 s / 84 s, and `Prop.collect` reports
**`196 of 245 interfaces re-print byte-identically`** on all three — the report's figure, and deterministic.
Once inside the full suite: §4.

**The "RED before" claim: CONFIRMED, all three, with the reported numbers.**  Same runner, `prefix-out`
prepended (pre-fix `TypeParsers` only):

```
! Interface concrete row.warm read of a published concrete row: … warm Some(Full) …
! Interface concrete row.every corpus interface warm-reads, and none is rewritten:
      70 of 245 interfaces were rewritten on the second load
! Interface concrete row.every corpus interface parses and re-prints stably:
      70 of 245 interfaces did not round-trip (134 of 245 re-print byte-identically)
Found 3 failing properties.
```

Every figure in the report's negative-control block, reproduced.  I also checked the claim that the test's 70
and the repository's 70 are the same modules: I extracted the 70 file names from the failing property's own
message and compared them with the 70 `.ei` my repository run found rewritten — **identical, 70/70, no
difference either way**.

**Property 3's alpha-equivalence relaxation** — measured, not argued: see R-3.  `aeqs` differs from
`G1Compare.alphaEq` in exactly the two ways documented at its definition, and only ONE of them is a relaxation
(Forall binders opened rather than zipped; the Exists/Part multiset handling is `G1Compare`'s own — `alphaEq`
already calls `matchMultiset` for both — so answering EVERY bijection rather than the first is a completeness
fix).  Variant A (no `aeqs` at all) falsifies on 15 of 245; variant B (complete search, positional Forall)
passes.  So the property is weaker than it needs to be by exactly one of its two documented departures.  The
relaxation that IS needed is justified mechanically as well: `Part.apply` genuinely re-orders its right-hand
side and merges every concrete part into one `ConcreteRho` (`Type.scala:408–428`), so rhs order carries no
information — and my probe shows the reversal live (source `r <- (h, (|foo|))` is published
`r <- ((|R01Part.foo|), h)`).

**Robustness to the process-global dep cache.**  The fixture follows `TestInterfaceKey`'s pattern exactly:
`Session.depCache.clear()` inside `ErmineFixture.literalLock`, a private temp workspace, and — for property 1 —
a module that imports NOTHING, so `preChecked`'s "every import must itself be `Interface`" cannot make the
property depend on another suite's state.  The corpus fixture stages the stdlib into its own temp tree and
points `loadFile` at it, so the 156 stdlib interfaces it needs are its own, not the repository's.  Two details
I checked specifically:

* **no deadlock**: the `corpus` lazy val takes `literalLock` in its initialiser, and both properties that use it
  force it OUTSIDE their own `synchronized` block, so no thread ever holds the lock while waiting for the lazy
  val;
* **the second pass really is a second pass**: `pass()` builds a fresh `SessionEnv` and clears the dep cache,
  and the fixture sleeps 1.1 s first so an mtime move is observable.

Two smaller notes, neither a finding.  Property 1 does not sleep between its cold and warm loads, so its
`unchanged` clause would be blind to a rewrite on a filesystem with 1-second mtime granularity — but the load-
bearing assertion there is `warm ?= Some(CheckMethod.Interface)`, which is not.  And `parseSigs` uses
`interfaceSigs`, which unlike the real reader's `interfaceFile` is not anchored with `<< eof`, so a truncated
parse would not be caught by property 3 alone — property 2, which goes through the REAL reader, covers exactly
that.

The residual hazard is R-1's, and it is S5's rather than F4's: the six lock-free suites.  The new suite is on
the correct side of the discipline; it just holds the lock longer than anything before it.

## 4. Gates, re-run once

| gate | reported | my re-run |
|---|---|---|
| `sbt core/compile core/copyResources` | clean, one pre-existing warning | **clean**, exit 0; the `TypeParsers.scala:76` pattern warning is the only one, and it reproduces when compiling HEAD's version of the file, so it is not the fix's |
| `sbt 'core/testOnly *TestLoopTrace'` | 720/720, hashdiff 0, eqdiff 0 | **720 solves / 720 segments / 720 agree**, `skipped=0 hashdiff=0 eqdiff=0 nonpart=0 rejected=36 fuel=0`; 3 properties green |
| `corpus-run.sh --batch` | 85 / 69 / 0, 154 | **85 LOADED, 69 REJECTED, 0 UNKNOWN, 154 total** |
| `repl-smoke.sh` | all green | **all PASS** — aliasing 2, ffi 5, ffi-tolerant 9, pipedeof 12, relations 6, scoping 4, smoke 23, tauto 5 |
| `lsp-smoke.sh` | PASS 185, boot 129 | **PASS lsp (185 checks)**; the boot-129 assertion is the check `boot.reports 129 modules` inside those 185 (`lsp-client.py:117`), so it is covered |
| `g1-validate.sh` | 9/9, no baseline re-cut | **9/9**: 7 fixtures, double-run self-agreement (129 files, 1,447 signatures, EQUIVALENT), **no drift from `tracker/g1-baseline`**.  Worth recording: S5's review found this gate RED at 7 of 1,447 drift; it is green now, and F4 did not re-cut the baseline |
| corpus double run, interfaces ON | 0 of 241 rewritten | **0 of 241**, and 0 bytes moved — §1.3, three ways |
| `sbt core/test` | 943 / 943, 0 failed, 0 errors, 1,377 s | **run 1: 943 total, 942 passed, 1 ERROR, exit 1, 1,453 s** (`TestLower`'s `negation applies primNeg to the whole chain`, `Death: Module not found: 'Test'`); **run 2, same tree: 943 / 943, 0 failed, 0 errors, exit 0, 1,356 s**.  The suite total 943 = 940 + this stage's 3 is confirmed, and the new suite's three properties are green in both runs — but the gate is intermittent (R-1) |
| warm-load timing | pre 35.45–36.22, post 23.53–24.21 | **pre 36.11 / 36.38 / 36.54 / 36.74 / 37.02**, **post 23.61 / 24.04 / 24.08 / 24.27**, interleaved post/pre/post/pre/post, one JVM at a time, each side reading the tree the other wrote.  Bands disjoint, gap **~12.3 s**; the stdlib boot inside them does not move (6.47–7.04 s on both sides).  Reproduced |

The new suite was also run **alone three times** (§3) and inside the full suite twice, green every time.
Tier 2 was not required and I did not run it.

One further check of §5 of the report: its printed list of **the 70 affected modules** is exactly the set my own
runs found — I extracted the 70 names from the report and diffed them against the 70 `.ei` basenames my pre-fix
corpus run rewrote: **no difference either way**.

## 5. Prose

**Ticket E1.**  The correction is dated, keeps the old text beneath it rather than deleting it, and states the
real predicate (the label), the re-measured scope (70 of 241), the census, why the stdlib escaped, the fix, the
"no published byte moves" measurement, the three properties and the two unfixed printer forms.  Every number in
it matches my runs.  Corrections owed: R-2 (the byte-identity parenthetical) and R-6(a) (the N6/N7 mechanism).
`FIXED in <pending commit>` is the right placeholder while the work is uncommitted and must be filled at commit
time.

**The plan row.**  Accurate to the report; every number I re-ran appears in it at the value I measured, with
`core/test` the one exception (R-1).

**The printer/parser table, spot-checked by construction.**  `ppType` rows: **T7** `ConcreteRho` — the probes'
`.ei` show `(|Mod.a, Mod.b|)` exactly; **T8** `Con` — `Builtin.Relation`/`Builtin.Record` in every probe, and
`(->)` occurs 4 times across the corpus interfaces; **T10** `Part` — `R01Part`'s source `r <- (h, (|foo|))` is
published `r <- ((|R01Part.foo|), h)`, the rhs reversal the row claims, and `Type.scala:408` is the fold that
does it; **T1** `Forall` and **T2** `Exists` — `forall (r: rho). … => …` and
`(exists (c: rho) (s: rho). r3 <- (c, s, extra), …)` both occur verbatim in the corpus interfaces.  (T4's `(,,)`
does not occur in this corpus and I did not construct it.)  Name rows: **N1** `Field.Count` reads on both
compilers; **N2** is the bug, reproduced; **N3** `a#b, c'd, e_1` — probe `R09Odd`, red before and green after;
**N4** the empty row — `(||)`, warm on both compilers; **N5** never published — 0 bare labels in 7,535 census
positions; **N6/N7/N8** unreachable — six attempts, §2.  The ticket's cross-reference claim (every `.ei` reader
goes through `Session.splitInterfaceKey`) is true: the readers are `Session.dep`'s `preCk`, `G1Compare`, and the
two interface test suites, and all four call it.

## 6. What I did NOT do

* Tier 2 was not required (no default flips) and I did not run it.
* I did not run the Tier 1 interface sweep (`ei-diff.sh`).  The report's justification for skipping it is sound
  and I verified its premise directly rather than by argument: the post-fix compiler read 241 pre-fix
  interfaces and rewrote none, byte for byte.  R-2 qualifies the premise without overturning it.
* I did not build Lean and did not touch `tracker/lean/`.
* I did not chase `TestLower`'s flake to its mechanism (R-1) beyond establishing that it is not the parser
  change, does not reproduce in isolation, and lives in a suite whose fixture discipline S5's review already
  flagged.
