# SUBSUME-STAGE2 — the harness stage: refutations proved once, refusals pinned under a deadline

Stage S2 of the `subsume-termination` programme (`tracker/PROMPT-subsume-termination.md`,
brief `tracker/satterm/briefs/brief-S2.md`, REBRIEFED 2026-09-16 as a harness stage).
Worktree `~/research/ermine/ermine-scala-wt-subsume-s2`, branch `subsume-s2` off
`subsume-termination` (3fe4e8c3).

**No compiler change. Nothing under `core/src/main` is touched; `Subst.scala` is not touched.
Nothing committed.**

Scratch, and every log path below, is `<s>` = `/home/dmitry/research/ermine/scratch-subsume/s2/`.

---

## 0. The answer, before the evidence

> *Does the checker terminate on a refused row program (`subsumeType`'s escape check)?*

**YES.** This stage produces no new evidence for that verdict and needs none: it rests on
S1a's `runV_steps` (the walk at `:648` is a total function, no hypothesis), S1b's
`budgetSP_terminates` / `solveSeedP_terminates` / `runsP_noAliasChain` (the row loop is bounded
at the shipped defaults, the rest of `Subst.solve`'s row fragment is total, no cyclic binding is
reachable), and S0's measurement that the B1 module is refused in **0.06–0.09 s** at seventeen
`Supply` id bases with the escape check returning on all 492,200 traced calls. §5 states the
answer in the form the programme asks for, with what it does and does not cover.

What this stage does is remove the thing that made the question look open, and it was never in
the compiler:

* `ErmineFixture.no` rewrote a refuted result to `True` (*passed*), not `Proof` (*proved*), so
  ScalaCheck ran `minSuccessfulTests = 100` complete checks of a fixed program. Measured on
  this tree, the B1 suite alone at the shipped default took **1,282 s** and was GREEN at the
  end: `+ … REJECTED (B1): OK, passed 100 tests`, `Passed: Total 12` (`<s>/b1-before.log`).
  On S0's tree the reviewer measured 1,099 s (`SUBSUME-STAGE0-REVIEW.md` §2.2).
* `ErmineFixture.rejects` rewrites it to `Proof`. Same verdict, **one** evaluation. The same
  suite now takes **195 / 187 / 181 s** over three runs, 13/13 green each
  (`<s>/b1-final-{1,2,3}.log`, `<s>/after-runs2.out`) — **1,095 s saved per run** at the median,
  against the review's predicted 915 s. Across the whole suite, two complete `sbt core/test`
  runs on this tree with nothing else changed between them: **1,698 s → 524 s**, 1,070/1,070
  green → 1,071 green + one documented quarantine that re-runs green — **1,174 s, 69 % of a
  full run** (§4.1). Nineteen refutations besides B1 were asking for a hundred evaluations too.
* And the hazard the prompt worried about most is now a gate rather than a worry: the resident
  language server answers this exact program with a diagnostic **58 ms** after the `didOpen`,
  of which the type-check is 40 ms (`<s>/lsp-smoke-server.log`, §3.3). Part B's *"a server that
  pins a core forever"* is refuted by a measurement, not explained away.

**One new red was found and fixed inside the stage** (§2.3): the first version of the B1
deadline pin used `typeChecks`, whose `loadStatements` takes the process-global
`ErmineFixture.literalLock` — the same lock `underZone` holds for a whole property body in that
suite. Two of three runs then went red at exactly 60,000 ms with nothing wrong. The pin now
loads through `loadNamed`, which takes no lock, so its deadline bounds the CHECK and not the
QUEUE.

---

## 1. What was built

| path | what | lines |
|---|---|---|
| `scalacheck-binding/src/main/scala/TestErmine.scala` | `ErmineFixture.rejects`, `bounded`, `outcomeOf`, `loadNamed`; a doc comment on `no` saying when it is still right; 7 call sites converted | +110 / −7 |
| `scalacheck-binding/src/main/scala/TestRowRefusals.scala` | **NEW** — the generator of unsatisfiable row programs with positive twins, every case on a deadline thread, all of them in one warm session | +176 |
| `scalacheck-binding/src/main/scala/TestDateAndScan.scala` | the B1 refutation → `rejects`; the `(B1-bound)` deadline pin; import list | +81 / −2 |
| `scalacheck-binding/src/main/scala/TestSigEntail.scala` | 6 sites converted, 3 doc references corrected | +9 / −9 |
| `scalacheck-binding/src/main/scala/TestScopes.scala` | 3 sites converted (the fourth deliberately kept as `no`) | +3 / −3 |
| `scalacheck-binding/src/main/scala/TestLetSignatures.scala` | 2 sites converted | +2 / −2 |
| `scalacheck-binding/src/main/scala/TestStage1Pins.scala` | 1 site converted | +1 / −1 |
| `tracker/lsp-tests/RowUnsat.e` | **NEW** — the B1 program as a file the editor opens | +18 |
| `tracker/tools/lsp-client.py` | the `RowUnsat.e` block: one diagnostic, severity 1, the row-label message, a range inside the file, answered in bounded time | +24 |
| `tracker/satterm/SUBSUME-STAGE2.md` | this report | — |

`tracker/repl-classpath.txt` was regenerated from this worktree's `target/ermine-classpath`
before the smoke gates, as the common brief requires; it is **not** a change of this stage.

### 1.1 The combinator, and why a new name rather than a fix to `no`

```scala
def no(p: Prop): Prop      = p map { r => r.copy(status = r.status match {case False => True;  case _ => False}, …) }
def rejects(p: Prop): Prop = p map { r => r.copy(status = r.status match {case False => Proof; case _ => False}, …) }
```

`rejects` has exactly `no`'s verdict — refused is green; accepted, thrown or undecided is red,
and `Exception`/`Undecided` stay failures as they were — and differs in one status: a refutation
is *proved*, so ScalaCheck stops after one evaluation, exactly as `sessionProof` already does
for every non-refutation property in these suites. The `"must fail"` label is kept.

**A new name, not a fix in place**, for one reason that is a correctness argument and two that
are not:

1. `TestScopes.scala:122` is `forAll(imported) { n => no(sessionProof(…)) }`. Its body consumes
   generated input and EVERY draw must fail; mapping the first draw to `Proof` would short-
   circuit the generator and silently drop the other ninety-nine. Changing `no` in place would
   have done that invisibly. It is the only such site today, and the two names make the
   distinction reviewable at every future site.
2. `no` is a general "invert this Prop" combinator; `rejects` states the stronger claim, "this
   refutation is deterministic, so one evaluation settles it". That claim belongs at the call
   site, where someone can check it.
3. A one-line diff at each site beats a silent semantic change to twenty-one of them.

**The in-tree precedent, which the first version of this report failed to cite** (review F-3).
`ErmineFixture` is not where the idea starts: `TestStage1Pins.scala:35-47` has had
`failsMatching(stmts, re, imports)` since Stage 1 —

```scala
case d: Death => if (re.r.findFirstIn(d.getMessage).isDefined) proved
                 else falsified :| ("report did not match /" + re + "/: " + …)
```

— a refutation that is **`proved` in one evaluation AND checks the cause**, used by 14 properties
(plus 2 of its sibling `failsAtLine`). So the "proved refutation" half of `rejects` is not new
machinery; what is new is applying it to the twenty `no(…)` sites that never had it.

**And what a message check costs, since `failsMatching` answers that too: near nothing.** The
`Death` message is already in the result — `sessionProof`/`sessionProp` build `falsified :|
e.getMessage`, so it is sitting in `Result.labels` — which means a `rejectsWith(re)(p: Prop)`
would be four lines in `ErmineFixture` and no extra work at run time. This stage adds the cause
check exactly where the programs are MACHINE-GENERATED and can therefore die for the wrong
reason (`TestRowRefusals`, §3.2, review F-1) and at the B1 pin (§3.1). It does **not** convert
the twenty fixed-program sites to a message-checking form: that would be churn with a real risk
of mis-transcribed expectations, the reviewer explicitly did not ask for it, and `rejects` is no
laxer on the cause than the `no` it replaces. The natural tidy — move `failsMatching` into
`ErmineFixture` and express it through `rejects` — is a ticket, not a condition of this landing
(§7 item 6).

**What is lost, said plainly** (corrected after review F-2; the first version of this paragraph
called the lost coverage unasserted, and that was false). A deterministic property run 100 times
was run at 100 different `Supply` id bases, and under `no` **every one of those hundred had to
fail**: a refutation that some id order made ACCEPT at one base in a hundred turned the property
red. That is a real assertion, not accidental coverage, and it is exactly the failure mode this
programme cares about — the S0 review's §4.4 records a measured **2× id-base outlier**
(`base-16` library boot 26.79 s against 12.35–12.79 s elsewhere), so id-order sensitivity in this
area is measured, not imagined.

What `rejects` does is make that assertion **once per program instead of a hundred times**, and
the stage buys the breadth back on the other axis: `TestRowRefusals` (§3.2) asserts it over
**sixteen fresh id bases across sixteen DIFFERENT generated programs**, where the old arrangement
gave a hundred bases across one fixed program — in 69 % less wall clock. That is a trade, and it
is recorded as a trade rather than as a free saving.

### 1.2 The call sites — the brief says 24 in 5 files, and the real number is 21 in 6

The brief names "24 call sites in 5 files (`TestScopes`, `TestLetSignatures`, `TestStage1Pins`,
`TestDateAndScan`, `TestSigEntail`)". Those five hold **14**. Two corrections, both found by
grepping rather than by trusting the count:

* **`TestErmine.scala` itself has 7 more** — `Occurs.fun`, `Occurs.Maybe`, `Occurs.kind`,
  `Maybe.Maybe`, `Different op types comparison`, `DataCon.Argument.Kind`,
  `Type.HigherKinded.Argument` — which the brief's list omits. Live, converted.
* **`core/src/test/scala/com/clarifi/reporting/TestRelations.scala` has 7 more, and they are
  NOT call sites.** That file is **one block comment from its first line to its last**: line 1
  is `/*package com.clarifi.reporting` and line 215 is `}*/`. Nothing in it compiles —
  `core/target/scala-3.3.8/test-classes/…/TestRelations.class` does not exist, `"relation ADTs"`
  and `"Ermine relations"` appear nowhere in a full `core/test` (`<s>/full-core-test.log`), and
  `sbt 'core/testOnly com.clarifi.reporting.TestErmineRelations'` answers `No tests to run`
  (`<s>/relations-after.log`). I converted its seven occurrences, then **reverted** them: a
  seven-line diff inside a block comment buys no coverage and misleads the next reader into
  thinking it does. **If that file is ever revived, its `no(…)` at lines 122, 125, 126, 127,
  128, 156 and 161 must be converted with it** — five conjuncts of `combine` and two of
  `aggregate`, each deterministic, each currently the single `True` that would drag an
  otherwise all-`Proof` conjunction down to *passed* (`Result.&&` maps `Proof && True` to
  `True`) and ask for a hundred evaluations of a thirteen-load property.

So: **21 live sites in 6 files. 20 converted, 1 deliberately kept.**

| # | site | property | body | before | after |
|---|---|---|---|---|---|
| 1 | `TestDateAndScan.scala:186` | a dateDiff combine over a relation WITHOUT the dates is now REJECTED (B1) | `typeChecks`, fixed | 100 tests | **1, proved** |
| 2 | `TestStage1Pins.scala:102` | after a do rebinding the outer type no longer applies | `typeChecks`, fixed | 100 | **1** |
| 3 | `TestLetSignatures.scala:151` | a let signature with a too-weak row context is refused by the entailment check | `typeChecks`, fixed | 100 | **1** |
| 4 | `TestLetSignatures.scala:157` | interleaved equations of one name are refused in a let block | `typeChecks`, fixed | 100 | **1** |
| 5 | `TestScopes.scala:125` | let bindings do not leak into the enclosing scope | `typeChecks`, fixed | 100 | **1** |
| 6 | `TestScopes.scala:128` | where bindings do not leak into the enclosing scope | `typeChecks`, fixed | 100 | **1** |
| 7 | `TestScopes.scala:181` | a data constructor operator may not be shadowed | `typeChecks`, fixed | 100 | **1** |
| — | `TestScopes.scala:122` | a top-level definition still may not shadow an import | **`forAll(imported)`** | 100 | **100, UNCHANGED** |
| 8 | `TestSigEntail.scala:48` | control: inference alone refuses a record lacking the field | `typeChecks`, fixed | 100 | **1** |
| 9 | `TestSigEntail.scala:52` | S3: an unconstrained row signature is REJECTED | `typeChecks`, fixed | 100 | **1** |
| 10 | `TestSigEntail.scala:55` | S3: a wrong-label row signature is REJECTED | `typeChecks`, fixed | 100 | **1** |
| 11 | `TestSigEntail.scala:60` | S3: a record-to-record unconstrained signature (modify) is REJECTED | `typeChecks`, fixed | 100 | **1** |
| 12 | `TestSigEntail.scala:69` | S3: an unconstrained row ANNOTATION is REJECTED | `typeChecks`, fixed | 100 | **1** |
| 13 | `TestSigEntail.scala:81` | S3: a let-bound unconstrained signature is REJECTED | `typeChecks`, fixed | 100 | **1** |
| 14 | `TestErmine.scala:343` | Occurs.fun | `sessionProof`, fixed | 100 | **1** |
| 15 | `TestErmine.scala:345` | Occurs.Maybe | `sessionProof`, fixed | 100 | **1** |
| 16 | `TestErmine.scala:346` | Occurs.kind | `sessionProof`, fixed | 100 | **1** |
| 17 | `TestErmine.scala:347` | Maybe.Maybe | `sessionProof`, fixed | 100 | **1** |
| 18 | `TestErmine.scala:402` | Different op types comparison | `sessionProof`, fixed | 100 | **1** |
| 19 | `TestErmine.scala:416` | DataCon.Argument.Kind | `sessionProof`, fixed | 100 | **1** |
| 20 | `TestErmine.scala:420` | Type.HigherKinded.Argument | `sessionProof`, fixed | 100 | **1** |
| (dead) | `TestRelations.scala:122,125,126,127,128,156,161` | combine / aggregate | file is one block comment | — | — |

Every one of the twenty reads `OK, proved property` in the full `core/test`
(`<s>/full-core-test.log`, §4.1); before the change each of them asked for a hundred.

**The site kept, and why it is not an oversight.** `TestScopes.scala:122` keeps `no`: its body
is `forAll(imported) { n => … }` and every generated import name must fail. It is the one site
where a hundred evaluations are the point rather than the cost, and it still reads
`OK, passed 100 tests`.

---

## 2. What was measured

All from the worktree root with
`PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH`,
`ERMINE_JAVA_OPTS="-Xmx2g -XX:ActiveProcessorCount=4"`. Other lanes were running JVMs for most
of the stage (load average 5–7), which the gate policy expects; no figure here is a
tracker-grade perf number and none was taken alone. **One asymmetry is recorded because it cuts
against this stage's claim and not for it**: the full `core/test` BEFORE run happened to land in
a quiet window (load average 1.9) while the AFTER run shared the machine (load 5–7), so §4.1's
saving is a lower bound.

### 2.1 The B1 suite alone, at the DEFAULT `minSuccessfulTests`, before and after

```
sbt 'core/testOnly com.clarifi.reporting.TestDateAndScan'
```

| | wall | properties | the B1 refutation | log |
|---|---|---|---|---|
| **before** (this tree) | **1,282 s (21:22)** | 12/12 green | `OK, passed 100 tests` | `<s>/b1-before.log` |
| before (S0's tree, the reviewer) | 1,099 s (18:19) | 12/12 green | `OK, passed 100 tests` | `SUBSUME-STAGE0-REVIEW.md` §2.2 |
| **after**, run 1 | **195 s** | 13/13 green | `OK, proved property` | `<s>/b1-final-1.log` |
| **after**, run 2 | **187 s** | 13/13 green | `OK, proved property` | `<s>/b1-final-2.log` |
| **after**, run 3 | **181 s** | 13/13 green | `OK, proved property` | `<s>/b1-final-3.log` |
| **after**, run 4 (the restored tree, after the full before/after pair) | **182 s** | 13/13 green | `OK, proved property` | `<s>/b1-final-4-restored.log` |

**1,095 s saved per run of this suite** at the median (1,282 − 187), against the review's
predicted 915 s off a 1,099 s baseline. The residue — 187 s for thirteen properties — is the
eleven A3/A4/C5 properties that were always there plus the new deadline pin; none of them runs
more than once.

Property count went 12 → 13: the two B1 properties are unchanged, and `(B1-bound)` is new.

### 2.2 The generator suite alone, and what bounds its sample

```
sbt [-Dermine.test.rowRefusals.n=N] 'core/testOnly com.clarifi.reporting.TestRowRefusals'
```

| N (cases; each is 2 module loads) | wall | log |
|---|---|---|
| 1 | 22 s | `<s>/rowrefusals-scale.log` |
| 8 | 29 s | `<s>/rowrefusals-1.log` |
| 16 (the shipped default) | 24 s / **20 s** | `<s>/rowrefusals-16.log`, `<s>/rr-final.log` |
| 24 | 24 s | `<s>/rowrefusals-scale.log` |

**Flat inside the noise**, because ~20 s of every column is sbt start-up plus the fixture's one
library-closure read and a case is ~0.1 s after that. The vacuity run (§2.4) shows the first
case at **19,522 ms** and everything after it cheap, which is the same statement from inside.

**The cost, as one number** (review F-7 — the first version of this report said ~20 s and the
source comment said ~3 s; they are two different quantities and both are now stated wherever
either appears): the suite does about **20 s of work** — one library-closure read, measured at
**19.5 s**, plus **~0.1 s a case**, so **~3 s of it is the sample itself** and the rest is a boot
that any fixture in this suite pays once. Standalone wall clock is **16–29 s** including sbt
start-up. All three readings are far inside the brief's two minutes, and the sample size is not
bounded by wall clock at all. What bounds it is the shape space — three
missing-date subsets by three payload widths is nine shapes — and the id sweep: each case draws
fresh `Supply` ids, so a bigger sample sweeps more order-dependence. Sixteen covers the nine
shapes with room to spare.

**Which loader was used, as the brief asks.** The shared session, through the new
`ErmineFixture.loadNamed`: every case gets its own module name, so it collides with nothing and
all thirty-two loads go into ONE warm `mkEnv`. `loadStatements` was NOT used, because it names
every case `module Test`, must evict the process-global dep cache around each one, and reads the
whole import closure per case — 9.1 s apiece (`SUBSUME-STAGE0.md` §6.2), i.e. about five minutes
for this sample where the shared session costs twenty seconds.

### 2.3 The red this stage found in its own pin, and the fix

The first version of `(B1-bound)` used the fixture's `typeChecks` under a 60 s deadline. Three
runs at the default N: **270 s (RED), 228 s (green), 219 s (RED)** (`<s>/after-runs.out`,
`<s>/b1-after-{1,2,3}.log`). Both failures were the deadline:

```
expected a refusal naming "Row partitions are unsatisfiable"; got after 60001 ms: did not finish in 60000 ms
expected the program to check; got after 60000 ms: did not finish in 60000 ms
```

Nothing diverged. `typeChecks` → `loadStatements` takes `ErmineFixture.literalLock`, the
process-global monitor that serialises dynamic `"Test"` literal loads — and `underZone`, three
properties up in the same file, holds that same lock for a whole property body, several
library-scale loads long, while ScalaCheck runs the suite's properties on a pool. The deadline
was bounding the QUEUE.

The pin now loads through `loadNamed`, which gives it its own module names and takes no lock, so
the deadline bounds the check. Three runs after the fix: **195 / 187 / 181 s, all green**
(§2.1). The generator's per-case deadline was raised from 60 s to 180 s for the same reason: its
first case pays the cold closure read, and a divergence pin that cries wolf is worse than none.

This is worth recording beyond the stage: **a deadline pin that wraps `loadStatements` is
measuring lock contention**, and any future one should use `loadNamed` or budget for the lock.

### 2.4 Non-vacuity of the generator

Two mutations at once — require the bad program to be ACCEPTED and its twin to be REFUSED —
then revert (`<s>/rowrefusals-vacuity.log`, the file restored from `<s>/TestRowRefusals.scala.keep`):

```
! unsatisfiable row programs (S2).(rr) …: Falsified after 0 passed tests.
case 1 missing {e} with 2 payload column(s): the bad program was not refused (19522 ms):
  refused: RowUnsatBad1<dynamic>:14:9: Row partitions are unsatisfiable at field
  'RowUnsatBad1.eB1': the whole contains it but no part does
```

The property is not vacuous, the generated programs really are refused, and they are refused by
**the same row-label check that refuses B1** — `Row partitions are unsatisfiable at field …`,
the twelve `slbl` records of `SUBSUME-STAGE0.md` §1.4 — not by some accident of the generator.

**That last clause was true of the observed run and NOT of the code, until review F-1.** The
property asserted only `startsWith("refused: ")`, so any future change that made a generated
module die before the row check — a colliding name, a `field` redeclaration, a parse error of the
kind the no-underscore rule already had to dodge — would have left sixteen cases green while the
suite asserted nothing about row unsatisfiability. The cause conjunct is now in the code
(`TestRowRefusals.scala:165`), and two fresh mutations pin it, each falling on its own conjunct
(`<s>/rr-mutA.log`, `<s>/rr-mutB.log`, reverted, `md5sum` identical):

| mutation | expected to break | result |
|---|---|---|
| make a bad case SATISFIABLE (`module("B"+k, extras, kept)` → `… List("s","e")`) | the "refused" conjunct | **RED**: `case 1 missing {s} with 0 payload column(s): the bad program was not refused (19497 ms): accepted` |
| make the demanded cause unreachable (`rowRefusal` → `"ZZ-NO-SUCH-MESSAGE-ZZ"`) | the NEW cause conjunct | **RED**: `case 1 missing {s,e} with 2 payload column(s): refused, but not by the row-label check (19065 ms): refused: RowUnsatBad1<dynamic>:14:9: Row partitions are unsatisfiable at field 'RowUnsatBad1.eB1': the whole contains it but no part does` |

Clean again afterwards: `Passed: Total 1`, 22 s (`<s>/rr-f1-final.log`).

---

## 3. The pins

### 3.1 `(B1-bound)` — the B1 pair under a deadline (`TestDateAndScan.scala`)

One property, one private session, two module loads on a daemon thread joined with a deadline
(the `(iso)` idiom of `TestRunner.scala:915-947` on `json-encode`). It asserts five things:

1. the bounded pair FINISHED (outer deadline **180 s**);
2. the B1 program was **refused**;
3. the refusal names **`Row partitions are unsatisfiable`** — the row-label check, not some
   other death;
4. the positive twin was **accepted**;
5. the twin's WARM check took **under 30 s**.

Two bounds, because one of them cannot be tight. The outer 180 s covers a COLD session — the
first load into a fresh `mkEnv` reads the whole import closure, ~20 s measured alone and more
under a full `core/test`. The inner 30 s covers the twin's warm check, which is the number that
means anything (0.1–0.2 s in every measurement of this programme) and is the bound a real
divergence would blow.

Counts: 1 property, 5 assertions, 2 module loads, 4/4 runs green (§2.1).

### 3.2 `TestRowRefusals` — the generator (NEW suite)

Random `field`s, a relation carrying a random subset of them, a `combine_Op` of a `dateDiff_Op`
over the two date columns of which a random NON-EMPTY subset is missing — the B1 shape,
generalised — built the way `TestSchema.shape` builds source on `json-encode`. Each case has a
positive twin: the same program over a relation that carries every column.

* **16 cases** per run, 32 module loads, each on its own deadline thread (180 s).
* Every bad case must be **refused**, **by the row-label check** (`Row partitions are
  unsatisfiable`, review F-1), never accepted, never hung; every twin must **check**.
* One shared warm session (`loadNamed`), so the closure is read once (§2.2).
* The sample is drawn once from one `Seed`, and the seed is in the property's label, so a
  failure is reproducible with `-Dermine.test.rowRefusals.seed=<base64>`. A `forAll` here would
  have asked ScalaCheck for 100 draws — the very cost this stage removed.
* 4 runs green (`<s>/rowrefusals-16.log`, `<s>/rr-final.log`, `<s>/rr-restore.log`, plus the scaling runs); non-vacuous
  (§2.4).

Counts: 1 property, **48 assertions (3 per case** — refused, refused by the row-label check,
twin accepted — after review F-1), 32 loads; **~20 s of work, ~3 s of it the cases themselves**
(§2.2).

### 3.3 The LSP smoke case (`tracker/lsp-tests/RowUnsat.e`, `tracker/tools/lsp-client.py`)

The B1 program as a file the editor opens. Five checks: exactly one diagnostic; severity 1
(Error); the message contains `Row partitions are unsatisfiable`; the range lies inside the
file; and the diagnostic arrives within 20 s of the `didOpen`.

Measured, from the server's own log (`<s>/lsp-smoke-server.log`):

```
18:37:12.666 >> textDocument/didOpen RowUnsat.e
18:37:12.720 check: RowUnsat read 0.01s, typecheck 0.04s (reused 0 of 1 components)
18:37:12.724 diagnostics: didOpen RowUnsat.e -> 1 diagnostic(s) in 0.1s
18:37:12.724 << publishDiagnostics … "severity":1, "message":"…RowUnsat.e:18:7: Row partitions
             are unsatisfiable at field 'RowUnsat.startDate': a part contains it but the whole
             does not"
```

**58 ms from `didOpen` to `publishDiagnostics`**, of which the type-check is 40 ms — inside the
debounce window rather than merely inside a timeout. That is the direct refutation of Part B's
*"a user who types that line gets a server that pins a core forever"*, on the same input, in the
resident session, and it is now a gate.

`lsp-smoke.sh` count: **573 before → 578 after** (`<s>/gate-lsp-smoke-baseline.log`,
`<s>/gate-lsp-smoke.log`). The brief expected 577 before; the figure on THIS tree is 573,
measured by restoring `lsp-client.py` from `HEAD`, running the script, and putting mine back.
The delta is exactly the five checks added.

---

## 4. Gates

**Tier 1 is NOT triggered and was not run.** Nothing in `Subst.scala`, `Constraints.scala`,
`Type.scala`, the row trace or executable Lean changed — nothing under `core/src/main` changed
at all. Every changed file is a test source, an LSP test fixture, the smoke client, or a
tracker document (§1).

| gate | result | log |
|---|---|---|
| `sbt core/compile core/copyResources core/Test/compile` | **green**, no new warning | `<s>/compile-after3.log` |
| `sbt -Dermine.looptrace=<wrappers>/… 'core/testOnly *TestLoopTrace'` | **3/3 properties**, `segments=720 replayed=720 skipped=0 hashdiff=0 eqdiff=0`, **720 agree** — the baseline the S0 review recorded | `<s>/gate-looptrace.log` |
| `tracker/tools/corpus-run.sh --batch` + `corpus-verdicts.py` | **89 LOADED / 79 REJECTED / 0 UNKNOWN, 168 total** — unmoved | `<s>/gate-corpus-verdicts.txt`, `<s>/corpus-after/` |
| the same, diffed against S0's baseline listing `scratch-subsume/s0/corpus-base` | **0 verdicts differ.** `2 of 168 files differ` and both differences are the absolute worktree prefix `…-subsume-s0` vs `…-subsume-s2` inside one message of `sk03`/`sk05`; same file, same line, same clause | `<s>/gate-corpus-diff.txt` |
| `tracker/tools/repl-smoke.sh` | **PASS smoke (23 checks), PASS tauto (5 checks)** | `<s>/gate-repl-smoke.log` |
| `tracker/tools/lsp-smoke.sh` | **PASS lsp (578 checks)**, 573 on the same tree without this stage's block | `<s>/gate-lsp-smoke.log`, `<s>/gate-lsp-smoke-baseline.log` |
| the B1 suite alone, default N, three times (four, with the confirmation run on the restored tree), each under a `timeout 1800` deadline | **195 / 187 / 181 / 182 s, 13/13 green each** | `<s>/b1-final-{1,2,3}.log`, `<s>/b1-final-4-restored.log` |
| `sbt core/test` in full, twice (before and after) | **1,698 s → 524 s**, 1,070 → 1,072 properties, no verdict moved; one documented quarantine red in the after run, green on its allowed single re-run | `<s>/full-core-test-BEFORE.log`, `<s>/full-core-test.log`, `<s>/legend-rerun.log` |
| `.ei` hygiene | **0** at the end of the stage: the gate run left none (`<s>/ei-after.txt`), and the seven that the two full `core/test` runs wrote under `core/target/scala-3.3.8/classes/modules/` were deleted (`find core -name '*.ei'` = 0). None is tracked — `build.sbt:8` excludes `*.ei`. | `<s>/ei-after.txt` |

### 4.1 The full `core/test`, before and after

Two complete runs of `sbt core/test`, on this tree, with nothing else changed between them.
**Order, per the logs** (corrected after review F-6): the AFTER run came FIRST — it completes at
18:47:49 after 524 s — and the BEFORE run second, after the Scala changes were reverted to a
saved patch (`<s>/compile-before-full.log`, 18:50), completing at 19:19:07 after 1,698 s; the
changes were then restored (`<s>/compile-restore.log`, 19:20) and the suite re-confirmed green
(§2.1, run 4). `<s>/s2-scala.patch` is the patch; `git status` is identical either side of it.

| | wall | properties | result | log |
|---|---|---|---|---|
| **before** | **1,698 s (28:18)** | 1,070 | `Passed: Total 1070, Failed 0, Errors 0` — fully green | `<s>/full-core-test-BEFORE.log` |
| **after** | **524 s (8:44)** | 1,072 | `Failed: Total 1072, Failed 1, Errors 0, Passed 1071` — the one red is the documented quarantine | `<s>/full-core-test.log` |

**1,174 s saved per full `core/test` — 19 minutes 34 seconds, 69 % of the run** — against the
review's prediction of ~915 s. It is larger than the prediction because the prediction counted
only the B1 property; nineteen other refutations were each asking for a hundred evaluations too
(§1.2), and they are cheaper per evaluation than B1 only because their fixtures write the
import closure back into `baseEnv` and B1's `onlyTest` does not.

**The saving is a LOWER bound**, and the direction matters: the *before* run had the machine
nearly to itself (load average 1.9) while the *after* run shared it with other lanes
(load 5–7). A fair comparison would make the gap wider, not narrower.

Property count 1,070 → 1,072: `(B1-bound)` and `(rr)` are the two new ones. **No property was
removed and no verdict changed** — every converted property reports the same green it did
before, in one evaluation instead of a hundred.

**The one red, and why it is not this stage's**: `Legends & presentations.extra args are ignored`,
`Falsified after 65 passed tests`, `Expected 2/24/08–7/8/06 but got 2/11/34–7/8/06`. That is
GATE-POLICY.md's registered quarantine — *"a seed-dependent date-formatting flake, ~1 run in 3
alone (S2 review V-4); ticket E13; exactly this property red gets ONE re-run"*. Re-run alone as
the policy allows: `sbt 'core/testOnly com.clarifi.reporting.writers.TestLegend'` →
`+ … extra args are ignored: OK, passed 100 tests`, `Passed: Total 46, Failed 0`, 3 s
(`<s>/legend-rerun.log`). It is a `forAll` over generated dates in a suite this stage does not
touch, and it passed in the *before* run with a different seed.

`tracker/repl-classpath.txt` was regenerated from this worktree's `target/ermine-classpath`
before the smoke gates (2,279 bytes, first entry
`…/ermine-scala-wt-subsume-s2/core/target/scala-3.3.8/classes`), per the common brief; it is not
reported as a change.

---

## 5. THE TITLE QUESTION, AND WHICH OF H1/H2/H3 SURVIVE

### 5.1 The answer

> *Does the checker terminate on a refused row program (`subsumeType`'s escape check)?*

**YES.** Stated in the form the programme asks for, and separating what is a theorem from what
is a measurement — this stage proves nothing new and claims nothing new:

1. **The walk at `Subst.scala:648` is total — in the MODEL.**
   `Rowpartition/SubsumeEscape.lean`, **`runV_steps`** — no acyclicity hypothesis, no
   well-formedness hypothesis, none at all, because the walk follows no binding:
   `Type.scala:653`'s `v.extract` is the variable's KIND ANNOTATION. `escs_total_on_cyclic`
   returns on the cyclic environment that makes H2's *function* diverge (`follow_diverges`).
   S1a review verdict LAND.
2. **The row loop is bounded at the shipped defaults, and the rest of `Subst.solve`'s row
   fragment is total — in the MODEL.** `Loop/RejectTerm.lean`, **`budgetSP_terminates`** (and
   `budgetSP_terminates_of_buildQueue`), **`solveSeedP_terminates`** — which is conditional on
   **`buildQueue` succeeding** AND on a nonzero effective budget, both hypotheses, not just the
   budget one; **`runsP_noAliasChain`** (no cyclic binding reachable, under three named side
   conditions); `envTermSize_eq_len` and `runsP_env_len_le` bound what the loop can leave behind.
   S1b review verdict LAND.
   **And the gap that must travel with 1 and 2** (review F-4; S1b §8 states it and the first
   version of this paragraph dropped it): *these are theorems about Lean MODELS. The tie between
   the model and the compiler is L2's measured differential — 2,355,430 corpus solve segments, 0
   mismatches — which is a measurement, not a proof.* Nor is `budgetSP_terminates` a latency
   claim: its fuel is existential, so it bounds STEPS and no wall clock.
3. **Measured on the input the programme is named after**: the B1 module is refused in
   **0.06–0.09 s** at seventeen `Supply` id bases, the escape check RETURNED on all 492,200
   traced calls with a worst single call of 29 ms, and there were **0 cycles in 984,400
   identity-marked walks** (`SUBSUME-STAGE0.md` §1.5–§1.7, review CONFIRMED).
4. **Measured in the editor, by this stage**: the resident language server publishes a
   diagnostic for that program **58 ms** after the `didOpen`, type-check 40 ms (§3.3). This is
   the one part of the answer S2 contributes, and it is a measurement, not a theorem.
5. **Measured across a family, by this stage**: sixteen generated unsatisfiable row programs per
   run, each refused by the row-label check on a deadline thread, each twin accepted, no case
   ever reaching its deadline (§2.2, §2.4).

**What is still NOT covered**, carried forward unchanged from S1b §8 so that this report cannot
be read as claiming more: `subsumeType` **as a whole** has no termination theorem. `:648` has one
only for the `fskvs` half, over the loop's own entries, as a bound on the ANSWER's size;
`SigEntail.enforce` is not covered; and under `-Dermine.dequeuePolicy=shipped` (budget off) there
is no loop termination theorem at all. The answer above is *yes for this path, proved where it is
proved and measured where it is measured* — not *yes for every program*.

### 5.2 The three hypotheses

**H1 (finite but explosive): REFUTED**, by S0's measurement (`hm.types.size` ≤ 1,566, tree
nodes ≤ 35,921, depth ≤ 23, tree/DAG ratio ≤ 4.39, and the maxima IDENTICAL in the run that
refuses in 0.06 s and the run that did not return) and by S1a's `escs_cost_le_subPass`, which
bounds the walk by one substitution pass in node visits. Nothing in this stage disturbs it.

**H2 (cyclic substitution): REFUTED**, twice over — by reading (`v.extract` is a kind
annotation; `Type`/`Kind`/`V` are strict case classes, so a cyclic term cannot be built), by
measurement (0 cycles in 984,400 marked walks), and by theorem (`follow_diverges` exhibits the
function Part B *described*; `escs_total_on_cyclic` shows the one that SHIPS returns on the same
input). S1b's `runsP_noAliasChain` adds that no cyclic binding is reachable on the loop's path.

**H3 (the walk is the victim): SURVIVES in its corrected, weaker half only** — `:648` is where
the sampler landed. Its proposed mechanism is refuted in both parts: the environment does not
grow (S0 §5.2, S1b `envTermSize_eq_len`), and the path does not diverge before `subsumeType`
(S1b `budgetSP_terminates`).

**And the thing that actually did not return was the PROPERTY.** This stage is the fix, and the
evidence that it is the fix is §2.1: same suite, same default `minSuccessfulTests`, same verdict,
1,282 s → 187 s.

---

## 6. What was proved

**Nothing. This stage proves nothing and adds no Lean.** `tracker/lean/` is untouched, so no
`lake build`, no `Audit.lean` count and no `#print axioms` is owed or offered. The theorems the
answer rests on are S1a's and S1b's, already built, audited and reviewed LAND; they are named in
§5.1 with their files. Per the common brief's rule that *a "terminates" claim is a theorem, not a
timing*, every termination claim in this report is a citation and every number is a measurement
with a log path.

---

## 7. Open questions, and what the next stage needs from this one

1. **No S3.** A budget bounds a computation that may not terminate; this one terminates, neither
   existing budget (`rowSound`, `solveBudget`) ever counted on this path (0 hits in every traced
   run), and budgeting `:648` would add a failure mode where none exists. S0 and its review both
   say so; this stage found nothing to change that. The programme's deliverable 1 is met and
   deliverable 2 is not owed.
2. **The `-Dermine.test.dateDiffReject` gate on `json-encode` can be lifted once this lands.**
   It was added (commit dd9e0316, GATE-POLICY.md, TICKET-editor-and-solver-followups item 12)
   because the B1 property looked like a hang. It is 187 s of ordinary suite now. Lifting it is
   a `json-encode` edit, not this branch's, and it should be done only after this stage is
   committed — named here so the orchestrator can ticket it.
3. **The id-base coverage that `rejects` removes has not been fully replaced.** A hundred
   re-checks of one program swept a hundred `Supply` id bases by accident; `TestRowRefusals`
   sweeps sixteen deliberately, over sixteen DIFFERENT programs. The experiment S0's reviewer
   named as the only one left that could still produce a divergence — the generator swept over
   id bases **in the FIXTURE environment**, which S0 never swept (it swept the CLI), plus one
   repeat at the `base-16` boot-time outlier of review §4.4 — is now cheap: the shared session
   makes a case 0.1 s, so a sweep of hundreds of cases is a one-minute job rather than a
   nine-second-per-case one. It is not done here and it is the natural next experiment.
4. **A harness rule worth keeping** (§2.3): a deadline pin that wraps `loadStatements` measures
   `ErmineFixture.literalLock` contention, not the check. Use `loadNamed`, or budget for the
   lock. Two of three runs of the first version went red at exactly the deadline with nothing
   wrong, which is exactly the false signal this programme exists to remove.
5. **`checkSkolemEscape` (`Subst.scala:365`), not `:648`, is where the cost is** — one
   whole-environment walk per ALTERNATIVE, 40,013 walks in one 12-property suite, and its
   elements are PRINTED, so S1a's verdict-only equivalences do not license touching it. S0's
   review puts it on the perf roadmap (P7 Step 1) behind a corrected cost figure. Not this
   programme's, and this stage did not touch it.
6. **A ticket, not a condition** (review F-3): move `failsMatching`/`failsAtLine`
   (`TestStage1Pins.scala:35-59`, 16 properties) into `ErmineFixture` and express them through
   `rejects`, so that "proved in one evaluation" and "and it died of THIS" are one facility
   rather than two. The reviewer explicitly did not make it a condition of this landing and I
   have not done it: converting the twenty fixed-program sites to a message-checking form is
   churn with a real risk of mis-transcribed expectations.
7. **For the reviewer.** The things worth disputing, in order: that `rejects` cannot weaken a
   refutation (the two `def`s side by side in §1.1, and the mutation in §2.4); that `TestScopes.scala:122`
   is the only site where `forAll` makes `no` right (re-grep); that the `(B1-bound)` and
   generator deadlines are wide enough to be non-flaky and narrow enough to be a pin (§2.3, and
   three green runs each); and that the corpus verdicts are unmoved (§4, the only two textual
   differences are absolute worktree paths).


---

## 8. Review fixes (`SUBSUME-STAGE2-REVIEW.md`, verdict FIX-THEN-LAND, 2026-09-16 evening)

All seven findings applied. The reviewer's own re-runs (B1 suite alone 189 s, 13/13 all proved;
`TestRowRefusals` 16 s; `lsp-smoke` 578; two mutations red and reverted; the 21-in-6 census
counted independently) are not repeated here — only what F-1 changed was re-run, which is what
the reviewer asked for in §5.

| # | finding | where it is fixed | evidence |
|---|---|---|---|
| **F-1** | FIX, the one code change: the generator asserted `startsWith("refused: ")` and never "refused by THIS check", so a machine-generated module that died for the wrong reason would have read green — and §2.4 claimed the strength the code did not have | `TestRowRefusals.scala`: new `rowRefusal` val (`:88`) and a second conjunct `bad.contains(rowRefusal)` (`:165`) with a comment naming the failure scenario and citing `failsMatching`; §2.4 rewritten to say plainly that the claim was true of the run and not of the code; §3.2's count 32 → **48 assertions (3 per case)** | compile green (`<s>/compile-f1.log`, `<s>/compile-f1-final.log`); `TestRowRefusals` alone **22 s, `Passed: Total 1`, `OK, proved property`** (`<s>/rr-f1.log`, `<s>/rr-f1-final.log`); **two** mutations, each red on its own conjunct and reverted byte-identically (`<s>/rr-mutA.log`, `<s>/rr-mutB.log`, §2.4) |
| **F-2** | "Nothing asserted that sweep" is FALSE — under `no` all hundred draws had to fail, so it was an assertion | §1.1's "What is lost" paragraph rewritten: the assertion is now made once per program instead of a hundred times, the S0 review's 2× `base-16` outlier is cited as why id-order sensitivity is measured rather than imagined, and the trade is stated as a trade; the same sentence in `TestErmine.scala`'s `rejects` docstring (`:239-247`) rewritten to match | — (documentation) |
| **F-3** | the in-tree precedent `failsMatching` is not cited, and "what does a cause check cost" is answered with silence | §1.1 gains a paragraph citing `TestStage1Pins.scala:35-47`, its 14 + 2 users, and the cost answer: the `Death` message is already in `Result.labels` (`sessionProof` builds `falsified :| e.getMessage`), so a cause check is near-free and a `rejectsWith(re)` would be four lines; the tidy is ticketed, not done (§7 item 6) | — |
| **F-4** | §5.1 states model theorems as if they were about `Subst.scala`, and drops `solveSeedP_terminates`'s `buildQueue` hypothesis | §5.1 items 1 and 2 now say **"in the MODEL"**, name `budgetSP_terminates_of_buildQueue`, carry **both** hypotheses of `solveSeedP_terminates` (`buildQueue` succeeded AND a nonzero effective budget), and add S1b §8's sentence verbatim in substance: the tie to the compiler is L2's measured differential (2,355,430 corpus solve segments, 0 mismatches), **not a proof** — plus that the budget theorem's existential fuel bounds steps and no wall clock | — |
| **F-5** | `loadNamed` drops `underZone`'s `literalLock` fence and says so only at one call site | `TestErmine.scala`'s `loadNamed` docstring now carries it: why dropping the lock is SOUND (`Session.depCache` is a `ConcurrentHashMap`, `:110`; a `Literal`'s identity is its module NAME, `:328-341`, minted uniquely here, so the shared `"Test"` key is never touched) and what it COSTS (a load can be in flight while `underZone` has the JVM default timezone changed — date VALUES can differ, a type-check verdict cannot, so **assert on verdicts, never on date values**) | — |
| **F-6** | §4.1 describes the two full runs in the wrong order | §4.1 now states the order the logs give: the AFTER run first (completes 18:47:49, 524 s), then the revert (`compile-before-full.log`, 18:50) and the BEFORE run (completes 19:19:07, 1,698 s), then the restore (`compile-restore.log`, 19:20) and §2.1's run 4 | the four timestamps are in the cited logs |
| **F-7** | two different numbers for the generator's cost (~20 s in the report, ~3 s in the source) | Both are now stated together wherever either appeared — §2.2, §3.2 and `TestRowRefusals.scala:56-70`: **~20 s of work = one 19.5 s library-closure read + ~0.1 s a case, so ~3 s is the sample itself**; standalone wall clock 16–29 s including sbt start-up | `<s>/rowrefusals-vacuity.log` (19,522 ms first case), `<s>/rr-f1-final.log` (22 s) |

Two of the reviewer's **non-findings** were worth writing down anyway and were: the `bounded`
docstring now records the one intended leak (a genuinely diverged check leaves a spinning daemon
thread for the life of a run that is already red, and no `interrupt()` is attempted because the
checker would not honour one), and F-5 covers the `literalLock` soundness argument the reviewer
verified at the source.

**Nothing else was touched.** No compiler source, no gate input, no theorem, no other suite: the
only file whose behaviour changed is `TestRowRefusals.scala`, and it was re-run alone, twice
green and twice deliberately red. `find core -name '*.ei'` = 0. No commits.

---

## Landing gates (orchestrator's gate run, 2026-09-17)

Run by the orchestrator on the tree being landed — `~/research/ermine/ermine-scala-wt-subsume-s2`
at **28e4761c** (branch `subsume-s2`, the S2 stage commit merged with `subsume-termination`, so
this is the first run that carries S0's `Subst.scala` instrumentation AND S2's harness changes
together). Logs are under `<g>` = `/home/dmitry/research/ermine/scratch-subsume/gates-s2/`.
Nothing was committed. `tracker/repl-classpath.txt` was regenerated from this worktree's
`target/ermine-classpath` before the smoke gates and restored with `git checkout` afterwards, per
GATE-POLICY's worktree rule; `git status` is clean apart from this section.

**Tier 1 is NOT triggered.** `git diff --stat ccaf3b45..HEAD -- core/src/main` is **empty** —
nothing under `core/src/main` has changed since the S0 landing commit (`ccaf3b45`), which ran
Tier 1 in full and was green. The whole S2 diff is test sources (`scalacheck-binding/src/main`),
an LSP test fixture (`tracker/lsp-tests/RowUnsat.e`), `tracker/tools/lsp-client.py` and tracker
documents.

| # | gate | command | result | log |
|---|---|---|---|---|
| a | compile (Tier 0) | `sbt core/compile core/copyResources core/Test/compile` | **rc=0**, three `[success]` (11 s / 0 s / 1 s, wall 15 s). **15 warnings, no new one**: the set is byte-identical (after stripping the worktree prefix) to the S0 tree's `scratch-subsume/s0/compile5.log` — all fifteen are the pre-existing `Subst.scala` deprecation/exhaustivity warnings | `<g>/compile.log` |
| b | model agreement (Tier 0) | `sbt -Dermine.looptrace=<wt-json-wrappers>/tracker/lean/.lake/build/bin/looptrace 'core/testOnly *TestLoopTrace'` | **720 solves / 720 segments / 720 agree**; `#summary segments=720 replayed=720 skipped=0 hashdiff=0 eqdiff=0 nonpart=0 rejected=36 fuel=0`; both negative controls firing (id base +1: **46 of 720**; `--flags=nongen`: **58 of 720**); `Passed: Total 3, Failed 0, Errors 0, Passed 3`, rc=0, 31 s. Identical to the S0 landing's line and to `GATE-POLICY.md:14` | `<g>/looptrace-test.log` |
| c | the B1 suite at the DEFAULT `minSuccessfulTests`, under a 10-minute deadline | `timeout 600 sbt 'core/testOnly com.clarifi.reporting.TestDateAndScan'` | **`Passed: Total 13, Failed 0, Errors 0, Passed 13`**, rc=0, and **every one of the 13 properties reports `OK, proved property`** (0 of 13 report `OK, passed N tests`). **329 s of sbt time, 5 min 33 s wall** — inside the deadline, which did not fire. Slower than the implementer's 181–195 s because it deliberately ran alongside three other JVMs (load average 6–9); it is a bound, not a timing for the tracker | `<g>/b1-dateandscan.log` |
| d | the generated row-refusal property | `sbt 'core/testOnly *TestRowRefusals'` | **1/1 proved**: `+ unsatisfiable row programs (S2).(rr) every unsatisfiable row program is refused, and its twin checks, in bounded time: OK, proved property`; `Passed: Total 1, Failed 0, Errors 0, Passed 1`, rc=0, 31 s sbt / 40 s wall | `<g>/rowrefusals.log` |
| e | corpus verdicts (Tier 0) | `tracker/tools/corpus-run.sh --batch <g>/corpus-s2` then `corpus-verdicts.py` | **89 LOADED / 79 REJECTED / 0 UNKNOWN over 168** — unmoved. 168 per-file outputs, one JVM, exit 0, 68 s | `<g>/corpus-s2.log`, `<g>/corpus-s2/`, `<g>/verdicts-s2.txt` |
| e′ | the same, diffed against S0's baseline dir `scratch-subsume/s0/corpus-base` | `corpus-verdicts.py <baseline> <g>/corpus-s2` (raw); then both single-dir listings with the worktree prefix normalised to `<TREE>` and `diff -u` (normalised) | **RAW: `2 of 168 files differ`, 0 of them a VERDICT change** — both are `MESSAGE`-only on `sk03`/`sk05`, and the only differing text is the absolute worktree prefix `…-subsume-s0` vs `…-subsume-s2` inside the embedded `…/classes/modules/Field.e:22:24` location. **NORMALISED: 0 diff lines** — the per-file verdict+message listing is byte-identical to S0's baseline | `<g>/verdicts-diff-raw.txt`, `<g>/verdicts-diff-normalised.txt` (empty), `<g>/verdicts-baseline.txt`, `<g>/verdicts-{baseline,s2}.norm.txt` |
| f | REPL smoke (Tier 0) | `tracker/tools/repl-smoke.sh` | **8 / 8 groups PASS, 66 checks, 0 FAIL** (aliasing 2, ffi 5, ffi-tolerant 9, pipedeof 12, relations 6, scoping 4, smoke 23, tauto 5), rc=0, 186 s | `<g>/repl-smoke.log` |
| f | LSP smoke (Tier 0) | `tracker/tools/lsp-smoke.sh` | **`PASS lsp (578 checks)`**, rc=0, 80 s — the expected 578, i.e. the recorded 573 plus this stage's five new `RowUnsat.e` checks | `<g>/lsp-smoke.log` |

`.ei` hygiene: `find core -name '*.ei'` is **0** after the run (it was 0 before it; the batch corpus
run and the smoke gates left none).

### Verdict

**GREEN. No gate deviates from its expected number.** Every figure the implementer reported in §4
re-measured identically on the merged tree: 720/720/720 with controls 46 and 58, 89/79/0 over 168
with a byte-identical normalised listing, 66 REPL checks in 8 groups, 578 LSP checks, 13/13 B1
properties all *proved*, 1/1 `(rr)` proved. The only numbers that differ from §4 are wall clocks
(this run was deliberately contended, four JVMs at once), and no wall clock is a gate here — the
B1 suite's only requirement was to finish inside the 10-minute deadline, which it did with four
and a half minutes to spare. Tier 1 was not run and is not owed: `core/src/main` is untouched
since `ccaf3b45`, which ran it.
