# SUBSUME-STAGE2-REVIEW — Opus reviewer, 2026-09-16 evening

Reviewer of stage S2 (`subsume-s2`, worktree `~/research/ermine/ermine-scala-wt-subsume-s2`, UNCOMMITTED).
I did not write the stage. Read in order: `briefs/brief-review.md`, `briefs/brief-S-common.md`,
`tracker/PROMPT-subsume-termination.md` Part B, `SUBSUME-PLAN.md`, `briefs/brief-S2.md` (the REBRIEFED
harness version), `SUBSUME-STAGE2.md`, then `git diff` plus the new files; for landed context,
`SUBSUME-STAGE0-REVIEW.md`, `SUBSUME-STAGE1A.md`/`-REVIEW`, `SUBSUME-STAGE1B.md`/`-REVIEW` in the
programme worktree (read-only).

My scratch and every log path below: `<r>` = `/home/dmitry/research/ermine/scratch-subsume/review-s2/`.
The implementer's are `<s>` = `/home/dmitry/research/ermine/scratch-subsume/s2/`.

---

## 0. Verdict

**FIX-THEN-LAND.**

The stage does what the rebrief asked and does it honestly. Nothing under `core/src/main` changed
(`git diff --stat -- core/src/main` is empty; I checked, not inherited), every converted property keeps
its verdict, the three pins are real pins — I mutated two of them and both went red — and every gate
number in the report reproduces or is present in a log that says what the report says it says. The
headline saving is real: I measured the B1 suite alone at **189 s** against the 1,282 s the report
measured before the change on this same tree.

One finding is a **one-line code change** (F-1) and it matters, because it is the single place where a
green can still be vacuous, and because the report claims the property already asserts what F-1 adds.
The rest are documentation corrections to the report and to one docstring. No finding touches a verdict,
a theorem or the compiler; none of them justifies REWORK, and none of them needs a re-run beyond the
suite that changes.

---

## 1. What I re-ran, with numbers and logs

| what | command | result | log |
|---|---|---|---|
| compile | `sbt core/compile core/copyResources` | **exit 0** (no-op: the implementer's tree was already built) | `<r>/compile.log` |
| test sources compile after my mutations were reverted | `sbt core/compile core/copyResources core/Test/compile` | **exit 0**, no new warning | `<r>/recompile-after-revert.log` |
| **the B1 suite ALONE at the DEFAULT `minSuccessfulTests`** | `timeout 600 sbt 'core/testOnly com.clarifi.reporting.TestDateAndScan'` | **189 s (03:09), exit 0, `Passed: Total 13, Failed 0`** — all thirteen read `OK, proved property`, including both B1 properties and `(B1-bound)` | `<r>/b1-review.log` |
| `TestRowRefusals` alone | `sbt 'core/testOnly com.clarifi.reporting.TestRowRefusals'` | **16 s, `Passed: Total 1`**, `(rr) … OK, proved property` | `<r>/rr-and-lsp.log` |
| `lsp-smoke.sh` | `tracker/tools/lsp-smoke.sh` (classpath regenerated from this worktree by the implementer) | **`PASS lsp (578 checks)`, exit 0** | `<r>/rr-and-lsp.log`, server log `<r>/lsp-smoke-server.log` |
| the LSP case's own latency, from my run's server log | — | `19:34:07.472 >> didOpen RowUnsat.e` → `19:34:07.550 << publishDiagnostics` = **78 ms**, `typecheck 0.06s`, one diagnostic, `severity 1`, range `line 17`, message `… Row partitions are unsatisfiable at field 'RowUnsat.startDate' …` | `<r>/lsp-smoke-server.log:81-85` |
| **Mutation A — non-vacuity of the generator**: make a generated case SATISFIABLE (`TestRowRefusals.scala:124`, `module("B"+k, extras, kept)` → `module("B"+k, extras, List("s","e"))`) | `sbt 'core/testOnly …TestRowRefusals …TestDateAndScan'` | **RED**: `! (rr) …: Falsified after 0 passed tests` / `case 1 missing {s,e} with 0 payload column(s): the bad program was not refused (14121 ms): accepted` | `<r>/mutation.log` |
| **Mutation B — the B1 pin's message**: `TestDateAndScan.scala:265`, `"Row partitions are unsatisfiable"` → `"ZZ-NO-SUCH-MESSAGE-ZZ"` | same invocation | **RED**: `! (B1-bound) …: Falsified after 0 passed tests` / `refused, but not by the row-label check: refused: SubsumeB1Bad1<dynamic>:13:7: Row partitions are unsatisfiable at field 'SubsumeB1Bad1.startDate': a part contains it but the whole does not` | `<r>/mutation.log` |
| both mutations reverted | `md5sum` against copies taken before | **byte-identical** (`a820652b…`, `d295374c…`); `git status --porcelain` back to the eleven paths it had | — |
| `.ei` hygiene | `find core -name '*.ei'` | **0** before my runs and **0** after | — |
| nothing shipped changed | `git diff --stat -- core/src/main` | **empty** | — |

Two independent mutations, two reds, no other property red in the mutated run, and the mutated run's
own wall clock (184 s) is the same as the clean one — so the deadline pins are not paying for the
non-vacuity.

### The census, counted myself

`git grep -n '\bno(' HEAD -- scalacheck-binding/src/main/scala/` gives **25** hits, of which one is the
`def no` (`TestErmine.scala:220`) and three are prose (`TestSigEntail.scala:14,66,107`): **21 live call
sites in 6 files** — `TestDateAndScan` 1, `TestErmine` 7 (`:244,246,247,248,303,317,321`),
`TestLetSignatures` 2, `TestScopes` 4, `TestSigEntail` 6, `TestStage1Pins` 1. The report's correction of
the brief (24-in-5 → 21-in-6, with the brief's five files holding 14) is **exactly right**. After the
stage: 4 hits, of which three are prose/definition and one is the live kept site. `rejects(` 24 hits =
20 call sites + the definition + three prose references. Every one of the twenty reads `OK, proved
property` in the implementer's full `core/test` after-log, and the same twenty read `OK, passed 100
tests` in the before-log (I grepped both).

**The kept site is the right one and it is the only one.** `TestScopes.scala:122` is
`forAll(imported) { n => no(sessionProof(implicit s => loadStatements(s"$n = 1", imps))) }` — the only
converted-or-kept body that consumes generated input; every other one of the twenty is a literal
program string. It still reads `OK, passed 100 tests`.

**`TestRelations.scala` is dead, as claimed, and I verified the mechanism rather than the conclusion.**
Line 1 opens `/*package com.clarifi.reporting`; there is a second `/*` at line 78 closed at line 80 —
Scala block comments NEST, so the outer comment survives it and closes at line 215 `}*/`. No
`TestRelations.class` or `TestErmineRelations.class` exists anywhere under `core/target`. Its seven
`no(` occurrences are correctly left alone, and the report's note for whoever revives the file is the
right disposition.

## 2. What I did NOT re-run, and what its log actually says

Per the review brief I did not repeat the full suite or the corpus. I opened each log:

* **`<s>/full-core-test-BEFORE.log`** ends `Passed: Total 1070, Failed 0, Errors 0, Passed 1070` and
  `Total time: 1698 s (28:18)`; `<s>/full-core-test-BEFORE.done` = `rc=0 wall=1702s`. **Says what the
  report says.**
* **`<s>/full-core-test.log`** ends `Failed: Total 1072, Failed 1, Errors 0, Passed 1071`,
  `Total time: 524 s (08:44)`; `.done` = `rc=1 wall=528s`. The single red is
  `Legends & presentations.extra args are ignored: Falsified after 65 passed tests` /
  `Expected 2/24/08–7/8/06 but got 2/11/34–7/8/06`, which is the registered quarantine at
  `tracker/GATE-POLICY.md:48` (*"a seed-dependent date-formatting flake, ~1 run in 3 alone … exactly this
  property red gets ONE re-run"*); `<s>/legend-rerun.log` = `Passed: Total 46, Failed 0`, 3 s. **Says
  what the report says.** 1,070 → 1,072 is exactly `(B1-bound)` + `(rr)`; no property disappeared.
* **`<s>/gate-corpus-verdicts.txt`** ends `89 LOADED, 79 REJECTED, 0 UNKNOWN, 168 total` — the
  prompt's invariant, unmoved. **`<s>/gate-corpus-diff.txt`** lists `2 of 168 files differ` and I read
  both hunks: `shouldfail_sk03_field_copy_append_self` and `sk05_derived_skolem_field_copy`, each
  differing only in the absolute prefix `…-subsume-s0` vs `…-subsume-s2` inside one
  `Cannot unify skolem variable with empty relation` message — same file, same line, same clause.
  **No rejection became an acceptance or the reverse.** Confirmed against the S0 baseline directory
  `scratch-subsume/s0/corpus-base` (present, 170 entries).
* **`<s>/gate-looptrace.log`**: 3/3 properties, `segments=720 replayed=720 skipped=0 hashdiff=0 eqdiff=0
  nonpart=0`, controls 46/720 and 58/720 — the S0-review baseline.
* **`<s>/gate-repl-smoke.log`**: eight PASS groups including `smoke (23)` and `tauto (5)`.
* **`<s>/lsp-smoke-server.log:81-85`**: `18:37:12.666` didOpen → `18:37:12.724` publishDiagnostics =
  **58 ms**, `typecheck 0.04s`. My own run reproduces it at **78 ms** on a busier machine.
* **Tier 1 is correctly NOT triggered**: no `Subst.scala`, `Constraints.scala`, `Type.scala`, trace or
  executable-Lean change; the whole diff is test sources, an LSP fixture, the smoke client and docs.

---

## 3. Findings

### F-1 (FIX — one line) `TestRowRefusals.scala:147`: the generator asserts "refused", never "refused by THIS check"

```scala
bad.startsWith("refused: ") :|
  (c.describe + ": the bad program was not refused (" + badMs + " ms): " + bad),
```

`(B1-bound)` (`TestDateAndScan.scala:265`) does check the cause — `badOut.get.contains("Row partitions
are unsatisfiable")` — and my Mutation B proves that check bites. The generator, which is the one suite
whose programs are MACHINE-GENERATED and therefore the one most likely to die for the wrong reason, does
not.

**Failure scenario.** Any future change that makes a bad module die before the row check — a new shape
whose declared row is malformed, a generated name that collides in the shared session, a `field`
redeclaration, a parse error of the kind the `sfx` comment already had to dodge (*"NO underscore in a
generated name … the module would die for the wrong reason"*) — leaves all sixteen cases green while the
suite asserts nothing whatever about row unsatisfiability. The positive twin is only a partial guard: it
catches breakage that ALSO breaks the twin, and bad and twin differ exactly in the relation's declared
columns, which is precisely the part the generator varies.

This is not hypothetical bookkeeping: the report's own §2.4 claims the property has this strength —
*"they are refused by **the same row-label check that refuses B1** … not by some accident of the
generator"* — and it does not. That sentence is true of the observed run; it is not true of the code.

**Fix (one line, zero runtime cost, green as written — §2.4's log shows the message is there):**

```scala
List(
  bad.startsWith("refused: ") :| (c.describe + ": the bad program was not refused (" + badMs + " ms): " + bad),
  bad.contains("Row partitions are unsatisfiable") :|
    (c.describe + ": refused, but not by the row-label check: " + bad),
  (good == "accepted") :| (…))
```

(then `32 assertions` in §3.2 becomes 48). Re-run `TestRowRefusals` alone — 16 s — and nothing else.

### F-2 (report §1.1 and the `rejects` docstring) "Nothing asserted that sweep" is false

`no` DID assert it. Under `no`, every one of the hundred evaluations had to fail; a refutation that the
solver's id order made ACCEPT at one base in a hundred turned the property red. That is an assertion,
and it is exactly the failure mode this programme cares about. The trade the stage makes is still the
right one — one base × 20 fixed programs plus 16 fresh bases × 16 generated programs, in 69 % less wall
clock, against 100 bases × 1 program each — but it should be stated as *"an assertion that is now made
once per program instead of a hundred times"*, not as unasserted accidental coverage. The point is not
academic: the S0 review's §4.4 records a **2× id-base outlier** (`base-16` library boot 26.79 s against
12.35–12.79 s elsewhere), so id-order sensitivity in this area is measured, not imagined. Same sentence
in `TestErmine.scala:239-242`.

### F-3 (report §1.1) the in-tree precedent for `rejects` is not cited, and it is stronger

`TestStage1Pins.scala:35-47` already has `failsMatching(stmts, re, imports)`:

```scala
case d: Death => if (re.r.findFirstIn(d.getMessage).isDefined) proved else falsified :| (…)
```

— a refutation that is **`proved` in one evaluation AND checks the cause**, in the tree since Stage 1,
used by 14 properties (plus 2 of `failsAtLine`). §1.1's argument for a new name rather than a fix to
`no` is correct and I endorse it, but the report presents the "proved refutation" idea as new machinery
and answers the cause question with silence. It should cite `failsMatching`, and say what is true: the
cost of a cause check is near zero (the `Death` message is already in `Result.labels`, because
`sessionProof`/`sessionProp` build `falsified :| e.getMessage`, so a `rejectsWith(re)(p: Prop)` is four
lines in `ErmineFixture`), and it is already being paid at fourteen sites. The natural tidy — move
`failsMatching` into `ErmineFixture` and express it through `rejects` — is **out of scope for this
landing** and should be a ticket, not a condition.

### F-4 (report §5.1) the theorems are about Lean MODELS; the tie to the compiler is measured, not proved

§5.1 reads *"The walk at `Subst.scala:648` is total. `Rowpartition/SubsumeEscape.lean`, `runV_steps`"*
and *"The row loop is bounded … `Loop/RejectTerm.lean`, `budgetSP_terminates`"*. Those are theorems
about models. S1b §8 is explicit about the gap — *"The tie between the model and the compiler is L2's
measured differential (2,355,430 corpus solve segments, 0 mismatches), not a proof"* — and §5.1 is the
paragraph that goes into `SUBSUME-PLAN.md`'s running answer, so it is the one place the gap must be
carried. One sentence. While there: `solveSeedP_terminates` is conditional on `buildQueue` succeeding
and on a nonzero effective budget (S1b §8); §5.1 carries the budget half (`dequeuePolicy=shipped`) and
drops the `buildQueue` half. And `budgetSP_terminates`'s fuel is existential — it bounds steps, not wall
clock — which is right for a termination answer but should not be read as a latency claim anywhere.

### F-5 (docstring) `ErmineFixture.loadNamed` drops `underZone`'s fence and does not say so where the next caller will look

`TestDateAndScan.scala:21-26` documents `underZone`'s invariant: it takes `literalLock` *"the same
monitor `loadStatements` takes, so no module load can be in flight on another thread"*, and it changes
the JVM default timezone for a whole property body. `loadNamed` (`TestErmine.scala:303-307`)
deliberately takes no lock, so that invariant no longer holds for its callers. The B1 pin's own comment
argues it through correctly (a changed default zone can only change the date VALUES a module computes,
never whether it type-checks, and both new pins assert verdicts only) and I agree with the argument —
`TestRowRefusals` is in the same position and is likewise verdict-only. But the argument lives at one
call site, not in `loadNamed`'s docstring, and `TestRowRefusals` is already a second caller that
inherits it silently. **Fix:** one sentence in `loadNamed`'s docstring — *"no `literalLock`, so a
`loadNamed` load can be in flight while `underZone` has the JVM default timezone changed: assert on
VERDICTS, never on date values."*

### F-6 (report §4.1) the two full runs are described in the wrong order

*"the Scala changes were reverted to a saved patch for the first, and restored for the second"* reads as
if the BEFORE run came first. The logs say the AFTER run ran first (`full-core-test.log` completes
18:47:49, 524 s) and the BEFORE run second (`full-core-test-BEFORE.log` completes 19:19:07, 1,698 s),
with `compile-before-full.log` at 18:50 and `compile-restore.log` at 19:20 in between. Immaterial to the
figures — and the load-average asymmetry the report discloses cuts AGAINST the stage, which is the right
way round — but the sentence should match the logs.

### F-7 (nit) two different numbers for the same quantity

Report §2.2 and §3.2 say the generator adds **~20 s** to a `core/test`; the source comment at
`TestRowRefusals.scala:64` says it *"adds about three seconds to a `core/test`"*. Both are far inside the
brief's two minutes (my standalone run: 16 s total including sbt start-up), but the brief asked for *the*
number. Pick one and say which measurement it is (standalone wall vs. incremental cost inside a parallel
full run).

### Non-findings, recorded because they were the things worth disputing

* **`rejects` cannot weaken a refutation's verdict.** `no` maps `False => True, _ => False`; `rejects`
  maps `False => Proof, _ => False`. Identical on every status: refused green, accepted red, `Exception`
  red, `Undecided` red, and `Proof`/`True` (an accepted program) red. The `"must fail"` label is kept.
  The only difference is that ScalaCheck stops at a `Proof`.
* **Could a refutation now pass vacuously on an unrelated failure?** Yes — and it could before, in
  exactly the same way and to exactly the same degree. `typeChecks`/`sessionProof`/`sessionProp` catch
  `Death`, which the lexer, the parser, the renamer and the checker all raise, so a module that fails to
  parse reads as "refused" under `no` just as it does under `rejects`. **This is not a regression**, and
  `rejects` is no laxer than `no` on the cause. Where a cause check is cheap and the program is
  generated, it should be there — that is F-1, and only F-1. Converting the twenty fixed-program sites
  to a message-checking form would be churn with real risk of mis-transcribed expectations; I do not ask
  for it.
* **`bounded` is sound.** `TestErmine.scala:~283`: daemon thread (so a wedged check cannot hold the JVM
  open), `join(ms)`, answer in an `AtomicReference`, and the string `"did not finish in <ms> ms"` when
  the join times out — both pins assert on it, so **a hung check is a red property in bounded time, not
  a wedged run**, which is the whole deliverable. The `try/catch Throwable` inside the thread means no
  exception is lost. The only leak is the intended one: a genuinely diverged check leaves one spinning
  daemon thread for the life of the JVM (no `interrupt()` is attempted, and the Ermine checker would
  not honour one anyway), which can slow later suites in that run — but that run is already red. Worth a
  sentence in the docstring; not worth a fix.
* **Dropping `literalLock` is safe, and this is the load-bearing bit of §2.3.** `Session.depCache` is
  `new java.util.concurrent.ConcurrentHashMap[…]().asScala` (`Session.scala:110`), so `loadNamed`'s
  unlocked `-=` can neither corrupt the map nor race `loadStatements`' locked eviction; and a `Literal`'s
  identity is its module NAME (`Session.scala:328-341`), which every `loadNamed` caller mints uniquely,
  so it never touches the shared `"Test"` key the lock exists for. The report's diagnosis of its own red
  — the deadline was bounding the QUEUE because `underZone` holds that monitor for a whole property body
  — checks out at the source (`TestDateAndScan.scala:51-56`), and the harness rule it records (§7 item 4)
  is worth keeping. Finding it and reporting it rather than widening the deadline is the right call.
* **The shared warm session cannot HIDE a refusal.** Every case is evaluated (the `List` is built before
  `Prop.all`), an acceptance is a red, and `Prop.all` short-circuits only on a failure. Order-dependence
  in the shared session can therefore produce a false RED (a later case failing on earlier state) or a
  green-for-the-wrong-reason — and the latter is exactly F-1, which is why F-1 is the one code change I
  ask for. Names are suffixed per case (`sB1`/`sG1`, `rB1`/`rG1`), so no case can capture another's
  declarations; each case runs on its own thread and so draws its own `Supply` ids
  (`tlSupply` is a `ThreadLocal`, `TestErmine.scala:78`), which is what makes "sixteen fresh id bases"
  true.
* **The LSP case: it fails, it does not skip — but the red comes from the script, not the check.**
  `diagnostics_for` → `wait_for` (`lsp-client.py:82-99`) blocks on the server's stdout with no per-call
  timeout, so a server that really did pin a core would leave the client blocked; what turns that into a
  red is `lsp-smoke.sh:25`'s `timeout 120` on the whole client, with `rc 124` printing
  `FAIL lsp (timed out)` and exiting non-zero. So the hazard IS gated. The in-case assertion
  (`row_ms < 20000`) is a "not forever" bound, not the debounce ceiling; the debounce-ceiling claim rests
  on the server log (58 ms implementer, 78 ms mine), which is the honest reading and is what §3.3 says.
  The five checks and the `573 + 5 = 578` arithmetic are verifiable from the diff and match my run.
* **`.ei` hygiene, `repl-classpath.txt`, no commits, no `nohup`**: all correct. The classpath file points
  at this worktree and is properly excluded from the stage's changed-file list.

---

## 4. The answer I would sign

> *Does the checker terminate on a refused row program (`subsumeType`'s escape check)?*

**YES for this path — proved where the report says proved, measured where it says measured — and the
stage's §5.1 is the right shape for it, with F-4's one missing sentence.**

What carries it, in the order of strength:

1. **Theorem (model):** `Rowpartition/SubsumeEscape.lean`'s `runV_steps` — the walk at `:648` is total
   with no hypothesis at all, because `Type.scala:653`'s `v.extract` reads a kind ANNOTATION and follows
   no binding; `escs_total_on_cyclic` returns even on the environment that makes H2's described function
   diverge. S1a review LAND.
2. **Theorem (model):** `Loop/RejectTerm.lean`'s `budgetSP_terminates` (and
   `budgetSP_terminates_of_buildQueue`), `solveSeedP_terminates`, `runsP_noAliasChain` — the row loop
   stops at the shipped defaults under any dequeue policy, the rest of `Subst.solve`'s row fragment is
   total, and no cyclic binding is reachable. S1b review LAND. Both 1 and 2 are statements about Lean
   models; the tie to the compiler is L2's measured differential, **not a proof** (F-4).
3. **Measurement (S0, review CONFIRMED):** the B1 module is refused in 0.06–0.09 s at seventeen `Supply`
   id bases, the escape check returned on all 492,200 traced calls (worst single call 29 ms), 0 cycles in
   984,400 identity-marked walks.
4. **Measurement (this stage, reproduced by me):** the resident language server answers the same program
   with the row-label diagnostic 58 ms / 78 ms after the `didOpen`, type-check 40 ms / 60 ms — Part B's
   *"a server that pins a core forever"* is refuted on the same input, in the editor, and it is now a gate.
5. **Measurement (this stage, reproduced by me):** sixteen generated unsatisfiable row programs per run,
   each refused on a deadline thread, each twin accepted, none reaching its deadline.

**Carried limits, unchanged from S1b §8 and to be quoted with the YES:** `subsumeType` **as a whole** has
no termination theorem; `:648` has one only for the `fskvs` half, only over the loop's own entries, and
only as a bound on the ANSWER's size; `SigEntail.enforce` is not covered; under
`-Dermine.dequeuePolicy=shipped` (budget off) there is **no loop termination theorem at all**;
`solveSeedP_terminates` assumes `buildQueue` succeeded; the budget theorem's fuel is existential and
bounds no wall clock; and nothing here licenses citing any `runSP_*` soundness theorem at the shipped
defaults (S1b's open item — the stage correctly cites none).

**And the thing that did not return was the PROPERTY, not the checker.** That is the stage's real
finding and it is now measured twice on one tree: 1,282 s → 189 s for the B1 suite alone at the shipped
default N, 1,698 s → 524 s for a full `core/test`. **H1 and H2 stay refuted; H3 survives only as
"`:648` is where the sampler landed"; no S3 budget is owed** — a budget bounds a computation that may
not terminate, and this one terminates.

---

## 5. What a FIX-THEN-LAND re-check needs

F-1 (one line in `TestRowRefusals.scala` plus the `32 assertions` count in §3.2) with
`sbt 'core/testOnly com.clarifi.reporting.TestRowRefusals'` green — 16 s — and F-2 through F-7 applied to
the report and the two docstrings. Nothing else needs re-running: no compiler source, no gate input and
no other suite is touched by any of them. I will re-check those and nothing more.

---

## 6. Re-check — 2026-09-16 evening, same reviewer

The implementer applied all seven findings. I re-checked **only the findings**, as the handoff asked:
the F-1 diff and one re-run of the suite it changes, the corrected report sections, the two docstrings,
and that the compiler is still untouched. No other suite, gate or log was re-run — nothing else changed.

### Verdict: **LAND**

### F-1 — the one code change: applied, and pinned better than I asked

`TestRowRefusals.scala:88` names the cause once —

```scala
private val rowRefusal = "Row partitions are unsatisfiable"
```

— and `:165` adds it as its own conjunct with its own label, between the "refused" conjunct and the
twin's, carrying a comment that states the failure scenario and cites `failsMatching`. `diff` against
my pre-re-check copy shows this and the F-7 docstring rewrite and nothing else in the file.

Two things are better than the minimum I asked for:

* **The constant is the stable PREFIX, not the whole sentence.** Its docstring records that the run's
  id order decides which clause follows — *"the whole contains it but no part does"* vs *"a part
  contains it but the whole does not"* — and both appear in this programme's logs (B1 gives one,
  `RowUnsatBad1` the other). A fix that had matched the full clause would have been flaky by
  construction. This one cannot be.
* **Two mutations, each falling on its OWN conjunct**, where the first version of §2.4 had one that hit
  only the "refused" side. I read both logs and they say what §2.4 says:
  `<s>/rr-mutA.log` (bad case made satisfiable) → `the bad program was not refused (19497 ms):
  accepted`; `<s>/rr-mutB.log` (`rowRefusal` → `"ZZ-NO-SUCH-MESSAGE-ZZ"`) → `refused, but not by the
  row-label check (19065 ms): refused: RowUnsatBad1<dynamic>:14:9: Row partitions are unsatisfiable at
  field 'RowUnsatBad1.eB1' …`. Each is `Failed: Total 1, Failed 1`; `<s>/rr-f1-final.log` is clean at
  22 s.

**My own re-run** (`sbt 'core/testOnly com.clarifi.reporting.TestRowRefusals'`, `<r>/rr-recheck.log`):
**20 s, `Passed: Total 1, Failed 0`, `(rr) … OK, proved property`, exit 0.**

And §2.4 now says the thing that was actually wrong, in its own words: *"That last clause was true of the
observed run and NOT of the code, until review F-1."* That is the correction, not a paraphrase of it.

### F-2 … F-7 — all applied, all checked against the text rather than against §8's table

| # | what I checked | verdict |
|---|---|---|
| F-2 | §1.1's "What is lost" paragraph, and `TestErmine.scala:239-253` | **FIXED.** Both now say every one of the hundred draws had to fail under `no`, so it was a real assertion; both cite the S0 review's 2× `base-16` outlier as why id-order sensitivity here is measured; both state the trade as a trade (once per program × 20, plus 16 fresh bases × 16 generated programs, against 100 bases × 1). |
| F-3 | §1.1's new precedent paragraph | **FIXED.** `failsMatching` (`TestStage1Pins.scala:35-47`) is quoted with its `proved`/`falsified` arms, its 14 + 2 users are counted, and the cost answer is right: the `Death` message is already in `Result.labels` because `sessionProof` builds `falsified :| e.getMessage`, so `rejectsWith(re)` is four lines. The `ErmineFixture` tidy is ticketed and explicitly not done — which is what I asked for. |
| F-4 | §5.1 items 1 and 2 | **FIXED, and this was the one that mattered most.** Both now say **"in the MODEL"**; `budgetSP_terminates_of_buildQueue` is named; `solveSeedP_terminates` carries **both** hypotheses (`buildQueue` succeeded AND a nonzero effective budget); the gap travels with them — *"the tie between the model and the compiler is L2's measured differential — 2,355,430 corpus solve segments, 0 mismatches — which is a measurement, not a proof"* — and the existential fuel is stated to bound steps and no wall clock. The §5.1 "not covered" paragraph is unchanged and still carries S1b §8 in full. |
| F-5 | `loadNamed`'s docstring, `TestErmine.scala:~315-321` | **FIXED.** Both halves are there where the next caller will read them: why dropping the lock is sound (`Session.depCache` is a `ConcurrentHashMap`, `:110`; a `Literal`'s identity is its module NAME, `:328-341`, minted uniquely, so the shared `"Test"` key is never touched) and what it costs (a load can be in flight while `underZone` has the JVM default timezone changed) with the rule in bold: **assert on VERDICTS here, never on date values**. `bounded`'s docstring separately records the one intended leak. |
| F-6 | §4.1's opening paragraph | **FIXED.** It now states the order the logs give — AFTER first (completes 18:47:49, 524 s), revert at 18:50, BEFORE second (completes 19:19:07, 1,698 s), restore at 19:20, then §2.1's run 4 — and the load-average asymmetry that cuts against the stage is still disclosed. |
| F-7 | §2.2, §3.2 and `TestRowRefusals.scala:56-70` | **FIXED.** One decomposition everywhere: ~20 s of work = one 19.5 s library-closure read + ~0.1 s a case, so ~3 s is the sample itself; standalone wall 16–29 s with sbt start-up. My re-run at **20 s** sits inside that, and §3.2's assertion count is correctly 32 → **48 (3 per case)** with loads still 32. |

### Still true after the fixes

`git diff --stat -- core/src/main` is **empty** — no compiler source, no gate input, no theorem and no
other suite was touched by any of the seven. `find core -name '*.ei'` = **0**. The working tree is the
same eleven paths plus this review. Nothing committed.

### Residual (cosmetic, for the orchestrator at landing — not a condition)

* **R-1.** §1.1's closing pointer reads *"is a ticket, not a condition of this landing (§7 item 7)"*;
  the ticket is **§7 item 6** (item 7 is "For the reviewer"). §8's F-3 row cites item 6 correctly. One
  character.

### The answer I sign, unchanged

**YES for this path**, exactly as in §4 above — and §5.1 now states it with the model-level wording and
the L2 gap, so the sentence that goes into `SUBSUME-PLAN.md`'s running answer no longer claims more than
the theorems give. The carried limits from S1b §8 are unchanged: no termination theorem for `subsumeType`
as a whole, `:648` covered only for the `fskvs` half as a bound on the answer's size, `SigEntail.enforce`
uncovered, and **no loop termination theorem at all under `-Dermine.dequeuePolicy=shipped`**. No S3
budget is owed.
