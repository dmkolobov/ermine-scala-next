# Review of P211 — the `subsume-termination` programme ported to the Scala 2.11 line

Reviewer: Opus, 2026-09-16, ~1.4 h.  I did not write the port.  Subject: the UNCOMMITTED changes on
`backport-2.11` (worktree `~/research/ermine/ermine-scala-wt-backport`) and `json-encode-2.11`
(worktree `~/research/ermine/ermine-scala-wt-json211`), and the porter's report
`backport/SUBSUME-2.11.md`.  Sources re-read on `scala3-migration` (main checkout, READ-ONLY):
`bef7e7a7` (S0), `b69b13de` (S2), `SUBSUME-STAGE0.md` §3, `SUBSUME-STAGE2.md` §1–§3,
`briefs/brief-P211-port.md`, `brief-S-common.md`, `brief-review.md`.

Every log path below is under `<r>` = `/home/dmitry/research/ermine/scratch-subsume/review-p211/`;
the porter's are under `<p>` = `/home/dmitry/research/ermine/scratch-subsume/p211/`.

---

## VERDICT: **FIX-THEN-LAND**

One code fix (F-1, one line, a vacuity hole the 2.11 dialect change opened) and five documentation
corrections (F-2 … F-6).  Nothing in the port changes shipped behaviour, the instrumentation is
default OFF and demonstrably silent, the harness conversion is faithful, both trees are green, and
the two worktrees are byte-identical where they must be.  None of F-2 … F-6 needs a re-run.

---

## 1. Findings

### F-1 (CODE, blocking) — `TestRowRefusals.scala:209`: a generator failure would make the property GREEN

```scala
val cases = Gen.listOfN(sample, pairGen).apply(params).getOrElse(Nil)
```

`Gen[T].apply(params)` is `Option[T]` in scalacheck 1.11.3, and `getOrElse(Nil)` turns "the sample
could not be drawn" into "there is no sample".  With no cases, `checks` is empty and the property is
`Prop.all()` — and `Prop.all` in 1.11.3 is `if (ps.isEmpty) proved` (verified in the shipped jar:
`javap -c 'org.scalacheck.Prop$'`, `all(Seq)` → `Seq.isEmpty` → `proved`).  **An empty sample is
therefore reported as `OK, proved property` while asserting nothing at all.**

The Scala 3 original cannot do this: `pureApply(params, seed)` retries and then THROWS
(`Gen.RetrievalError`), which makes the property red.  So the dialect change silently converted a
loud failure into a vacuous pass — the exact class of defect the S2 review's F-1 closed in this very
file.

Failure scenario: any future edit that makes `pairGen` failable — a `suchThat`, a `retryUntil`, a
filter on the generated field names (the no-underscore rule is one such rule away from being
expressed as a filter) — leaves the suite permanently green and silent.  It cannot fire today
(`Gen.choose` + `Gen.oneOf` never fail), which is why this is the only code finding rather than a
REWORK.

Fix (one line, no re-run beyond the suite itself):

```scala
val cases = Gen.listOfN(sample, pairGen).apply(params)
              .getOrElse(sys.error("rowRefusals: the generator produced no sample at seed " + seed))
```

or, equivalently, add `(cases.size ?= sample)` as a conjunct of the property.

### F-2 (DOC) — the eager-`secure` mechanism is misattributed, and contradicts a docstring on the same branch

`TestErmine.scala:183-186` (the `no` docstring), repeated at `:214` (the `rejects` docstring) and in
the report §0.1: *"scalacheck 1.11.3's `Prop.secure` is EAGER: it evaluates its argument once, at
property-construction time … so on this branch the check runs ONCE however many tests ScalaCheck asks
for"*.

The first clause is true and I verified it (`javap -c 'org.scalacheck.Prop$'` on
`scalacheck_2.11-1.11.3.jar`: `secure` is `Function0.apply` then the view function, no `Prop.apply`
wrapper).  **The second does not follow from it**, because `Prop.secure` is eager in 1.15.4 as well —
the branch's own `TestRunner.scala:50-57` on `json-encode-2.11` says so in as many words ("`Prop.secure`
is `try pv(p) catch ..` in BOTH scalacheck 1.11.3 and 1.15.4").  What actually differs is
`Properties.PropertySpecifier.update`, which I checked in both jars:

```
1.11.3 : update(java.lang.String, org.scalacheck.Prop)                       <- BY VALUE
1.15.4 : update(java.lang.String, scala.Function0<org.scalacheck.Prop>)      <- BY NAME
```

So on this line `property(..) = secure { .. }` stores a CONSTANT `Result` and the other ninety-nine
draws re-wrap it; on `scala3-migration` the by-name `update` re-evaluates the body per draw, which is
where the 1,099 s went.  **The port's CONCLUSION is correct and independently confirmed here** — on
2.11 `rejects` buys status and branch-parity, not wall clock — only its stated cause is incomplete,
and as written it contradicts a neighbouring in-tree docstring.  One sentence in each of the two
docstrings and in report §0.1.

### F-3 (DOC) — the report's gate cross-references point at the wrong section

`SUBSUME-2.11.md` §0.1 cites "(§6.1)", §0.2 "(§6.2)", §2.1 "(§6.4)" and "(§6.3)".  The gate tables
are **§4** (backport-2.11) and **§5** (json-encode-2.11); §6 is "what the port says about the title
question".  Four references, `sed`-able.

### F-4 (DOC) — one number in the report has no log

§0.1: *"the three converted suites take **129 s before and after** the conversion"*.  `<p>/` holds
`bp-converted-suites.log` (the AFTER) and no BEFORE run of those three suites; §4's table cites only
the after.  The programme's rule is that every measured claim carries a log path.  Either cite the
log or drop the number — the CLAIM survives without it, because F-2's bytecode evidence settles the
mechanism, and my own after-run is 100 s on a quieter machine (`<r>/rv-bp-converted-suites.log`).

### F-5 (DOC) — `Subst.scala:2079`: "four wrapped call sites" is three

The header comment says the by-name port makes "each of the four wrapped call sites allocate one
`Function0` per call".  Only three entry points take a by-name argument — `cse` (`:293`),
`phaseFskvs` and `phaseKindVars` (`:582-584`).  `enter` (`:544`) and `atEscape` (`:582`) have strict
parameters and allocate nothing.  The accepted cost is 3 thunks per `subsumeType`-with-escape-check,
not 4.

### F-6 (DOC) — report §2.4 enumerates four changes to `TestRowRefusals.scala`; there are six

Two more, both correct and both consequences of the `coalesce'` substitution, neither named:

* `TestRowRefusals.scala:150` — the generated combine target changes from `field g : Int` to
  `field g : Date`, because `coalesce'` over two `Date` columns returns `Date` where `dateDiff`
  returned `Long`/`Int`.  Without it nothing would type-check, so it is not optional.
* `TestRowRefusals.scala:167` — `Gen.oneOf(a, b, c)` becomes `Gen.oneOf(List(a, b, c))` (the
  `Seq[T]` overload), a 1.11.3 dialect adjustment.

A reader diffing the two files will find them; the report claims to enumerate the differences, so it
should name them.

### Not findings (checked and clean)

* The `@inline def` + by-name dialect change is semantically identical to Scala 3's `inline def` at
  the three wrapped sites: `body` is evaluated exactly once, inside the call, in the same order, in
  both the enabled and the disabled branch; the `++` in `subsumeType` infers the same element types
  (the generic `A` is the argument's static type), which the 736/736 run confirms.  `@inline` without
  `-optimise` is a no-op — that is the accepted allocation, and it is stated.
* Everything else in `object SubsumeTrace` is byte-identical to `bef7e7a7`'s, comments aside:
  I diffed both hunks.  `rejects`, `bounded`, `outcomeOf` and `loadNamed` are byte-identical to
  `b69b13de`'s bodies; only the docstrings differ, deliberately.
* The rewritten `loadNamed` docstring is TRUE on this line, each clause checked: `literalLock` has no
  definition on `backport-2.11` (grep: three doc mentions, no `val`); `loadStatements`
  (`TestErmine.scala`) parses and calls `loadModule` and touches neither a lock nor `Session.depCache`;
  no suite on either 2.11 branch calls `TimeZone.setDefault` (grep: zero hits); `Session.depCache` is
  `new HashMap[...] with SynchronizedMap[...]` at `Session.scala:101` on both branches; `Literal`'s
  `hashCode`/`equals` key off the module name at `Session.scala:295-308`.  On `json-encode-2.11`
  `literalLock` is taken by exactly one property (`TestNamedFields.scala:520`), which does
  `Session.depCache.clear()` three times inside it — a concurrent `loadNamed` can be made to re-read a
  dependency there and nothing worse, and that hazard predates this port (2.11's `loadStatements`
  never took the lock either).
* The lazy `secure` shadow (`TestRowRefusals.scala:94`) is character-for-character the JSON 2.11
  programme's documented idiom (`TestRunner.scala:67`, `TestDoc.scala`, `TestWidgets.scala`), and the
  deadlock diagnosis in its comment matches the jstacks in `<p>/rr-jstack{1,2}.txt`, `rr-n2-jstack.txt`.
  It preserves the one-evaluation property: the body answers `Prop.all` over `propBoolean` props, so
  an all-green run is `Proof` and ScalaCheck stops after one test — which my re-runs show
  (`OK, proved property`, one evaluation, 55 s).
* `TestScopes.scala` and `TestSigEntail.scala`: site-for-site conversions, nothing else touched; the
  kept site carries the comment that explains why.
* `backport/.classpath` is tracked and currently byte-identical to `HEAD` (`git status` clean for it);
  nothing is staged on either branch; no `.ei` anywhere under `core/src` or `core/examples` on either
  branch (the only `.ei` are `json-encode-2.11`'s pre-existing ones under `core/target/`, dated
  Sep 14).  I deleted the one artefact I caused: an empty `.ermine_history` in the backport worktree,
  written by my CLI probe.

---

## 2. My re-runs (all commands from the worktree they belong to, JDK 8 + sbt 0.13.5 per `env-2.11.sh`)

### 2.1 `backport-2.11`

| gate | my result | the report's | log |
|---|---|---|---|
| `core/compile core/test:compile` | **rc 0** (up to date, 1 s — the porter's build was current) | rc 0, 36 s + 8 s | `<r>/rv-bp-compile.log` |
| the converted suites alone (`TestErmine`, `TestScopes`, `TestSigEntail`) | **69 / 69 green, 100 s**; **44 `OK, proved property` / 25 `OK, passed 100 tests`** | 69/69, 129 s, 44/25 | `<r>/rv-bp-converted-suites.log` |
| `TestRowRefusals` alone | **`OK, proved property`, 55 s** (58.6 s wall), 1/1 | proved, 56 s | `<r>/rv-bp-rowrefusals.log` |
| flag OFF with `-Dermine.subsumeTrace.out=<file>` set, CLI on `Bad1.e` | **the file is never created — ZERO records**; module refused in **0.11 s**, 30.5 s wall | same | `<r>/rv-bp-cli-bad1.log` |
| mutation A — make the bad case satisfiable (`kept` → `List("s","e")`) | **RED on the "refused" conjunct**: `case 1 missing {s,e} with 2 payload column(s): the bad program was not refused (32884 ms): accepted`; label `seed -3255771913022341523, 16 cases, session boot 233 ms` | (S2's mutation; not re-run on 2.11 by the porter) | `<r>/rv-bp-rr-mutA.log` |
| mutation B — `rowRefusal` → a string no refusal contains | **RED on the cause conjunct**: `case 1 missing {e} with 0 payload column(s): refused, but not by the row-label check (32530 ms): refused: RowUnsatBad1<dynamic>:13:9: Row partitions are unsatisfiable at field 'RowUnsatBad1.eB1': …` | same | `<r>/rv-bp-rr-mutB.log` |
| revert after the mutations | **byte-identical** (`md5sum -c` OK; `cmp` against the pre-mutation copy AND against the `json-encode-2.11` copy both clean); `core/test:compile` rc 0 afterwards | — | `<r>/rv-mutations.log`, `<r>/rv-bp-recompile-final.log` |

The mutation cycle also served as a genuine from-source compile of the ported suite on 2.11 (the file
was rewritten and recompiled three times, the last time back to the shipped bytes, rc 0).

### 2.2 `json-encode-2.11`

| gate | my result | log |
|---|---|---|
| `core/compile core/test:compile core/copyResources` | **rc 0** (up to date, 7 s) | `<r>/rv-j211-compile.log` |
| `TestRowRefusals` alone | **`OK, proved property`, 58 s**, 1/1 | `<r>/rv-j211-rowrefusals.log` |
| `TestNamedFields` alone (the one property whose STATUS the conversion flips) | **14 / 14 green, 26 s**; `Ermine named constructor fields.an existential field gets no selector, a sibling still does: OK, proved property` — the flip is real: under `no` that conjunction was `True && Proof && Proof` = *passed* | `<r>/rv-j211-namedfields.log` |

### 2.3 The three findings of the report's §0

**(a) `Prop.secure` is eager in 1.11.3 — CONFIRMED, with a correction to the mechanism.**  Verified
from the shipped jar rather than from the report: `javap -c 'org.scalacheck.Prop$'` on
`~/.ivy2/cache/org.scalacheck/scalacheck_2.11/jars/scalacheck_2.11-1.11.3.jar` shows
`secure(Function0, Function1)` = `Function0.apply` → view → `checkcast Prop`, with an exception
handler and no `Prop.apply` wrapper.  The load-bearing difference from the Scala 3 line is
`Properties.PropertySpecifier.update` (by value at 1.11.3, `Function0` at 1.15.4) — see F-2.  The
conclusion stands: **on 2.11 `rejects` buys STATUS PARITY, not wall clock.**  The report's own
measurement of that (129 s before and after) lacks a before-log (F-4); the mechanism does not depend
on it.

**(b) The class-initialisation deadlock and the lazy `secure` shadow — CONFIRMED.**  The fix is the
JSON 2.11 programme's documented pattern, character-for-character (`TestRunner.scala:67`), and its
docstring in `TestRowRefusals.scala:71-93` states the diagnosis correctly (eager `update` ⇒ the body
runs in `<clinit>`; `bounded`'s daemon thread touches `TestRowRefusals$.MODULE$`; the JVM blocks it on
the in-progress initialisation while the initialising thread sits in `Thread.join`).  The jstacks in
`<p>/rr-jstack{1,2}.txt` and `<p>/rr-n2-jstack.txt` show exactly those two frames.  Post-fix the suite
is one evaluation and 55–58 s on both branches (my logs above).

**(c) The 2.11 line ACCEPTS the B1 program — CONFIRMED, reproduced, and it is a PRE-EXISTING GAP.**
I loaded the exact B1 program (`<p>/probe/B1.e`) through the 2.11 CLI on `backport-2.11`:

```
Importing module 'B1' (0.11 seconds)          <- ACCEPTED, no refusal          <r>/rv-bp-cli-probe.log
```

and the cause is where the report says: `core/src/main/resources/modules/Relation/Op.e:150-151` on
this branch is

```
--dateDiff : forall r r1 r2 .  AsOp op1 op2 => TimeUnit -> op1 r Date -> op2 r1 Date -> Op r2 Long
dateDiff u s e = dateDiff# u (asOp s) (asOp e)
```

— signature commented out, result row unconstrained — against `scala3-migration`'s `Op.e:151-162`,
which carries the F3 fix (`RUnion2 t r1 r2`) and a ten-line comment explaining it.  The generator's
substitute operator is sound: `coalesce'` is byte-identical on the two branches (`Op.e:56-60` on
both), and it yields the row-label refusal here:

```
Bad1.e:14:9: Row partitions are unsatisfiable at field 'Bad1.eB1': a part contains it but the whole does not
Unable to load module (0.11 seconds)                                              <r>/rv-bp-cli-bad1.log
```

**Stated plainly: this is a pre-existing gap of the back-port's scope, not a defect of this port, and
it is not this port's to fix.**  See §4.1 for what the user should be told.

### 2.4 Census — verified by grep on both branches

`backport-2.11` BEFORE (`git grep` at `HEAD`): **19 live `no(` sites in 3 files** —
`TestErmine.scala` 194, 196, 197, 198, 253, 267, 271 (7); `TestScopes.scala` 116, 119, 122, 131, 134,
153 (6); `TestSigEntail.scala` 55, 59, 62, 67, 76, 91 (6).  No other file on the branch has one.
AFTER: **exactly one live call site** (`TestScopes.scala:121`, the `forAll(imported)`-bodied one) plus
the `def no` definition; `rejects(` counts are TestErmine 8 (1 def + 7 sites), TestScopes 5,
TestSigEntail 9 (6 sites + 3 doc references) — **18 converted, 1 kept**, exactly as reported.
`core/src/test/.../TestRelations.scala`'s 7 are inside the file-wide block comment (`:1`
`/*package …`, `:215` `}*/`) and are untouched, correctly.

`json-encode-2.11`: the same 19 plus `TestNamedFields.scala:416` = **20, 19 converted, 1 kept**.
`TestDecode.scala:463-490` is a different local `def no(t: String, text: String): Decode.Error` — not
a site, correctly left alone.

### 2.5 Byte-identity of the two worktrees (the orchestrator's merge)

`cmp` over the six shared files:

```
TestRowRefusals.scala   IDENTICAL      TestScopes.scala   IDENTICAL
TestSigEntail.scala     IDENTICAL      SUBSUME-2.11.md    IDENTICAL
TestErmine.scala        differs by 20 lines   <- exactly the pre-existing HEAD..HEAD delta
Subst.scala             differs by 10 lines   <- exactly the pre-existing HEAD..HEAD delta
```

I checked the two that differ twice over: the inter-branch diff of the WORKING trees (20 and 10
lines) equals the inter-branch diff at `HEAD` (20 and 10 lines), and the normalised port hunks
(`git diff` with hunk headers stripped) are **byte-identical on the two branches** for both files
(`<r>/bp-*.patch` vs `<r>/j-*.patch`, `cmp` clean).  So the merge of `backport-2.11` into
`json-encode-2.11` cannot conflict on any ported hunk, and `TestNamedFields.scala` exists on one side
only.  Line endings are right: `TestRowRefusals.scala` is CRLF on both (234/234 lines), and
`TestNamedFields.scala` is still LF (0 CRLF in 536 lines) with a 1/1 diff.

### 2.6 The porter's full runs, read not re-run (as the brief requires)

* `<p>/bp-full-core-test-after.log`: `Passed: Total 736, Failed 0, Errors 0, Passed 736`,
  `Total time: 125 s` — and **zero `!` lines** in the file.  The before run
  (`<p>/bp-full-core-test-before.log`) reads `Passed: Total 735 … Total time: 193 s`: the documented
  735/735 baseline reproduced, +1 for the new suite.
* `<p>/j211-full-core-test-after.log`: `Passed: Total 859, Failed 0, Errors 0, Passed 859`,
  `Total time: 354 s`, zero `!` lines — the documented 858 baseline +1.
* The flag-ON control: `zcat <p>/trace-on.tsv.gz | awk -F'\t' '{print $3}' | sort | uniq -c` gives
  **9515 `enter`, 9515 `escape`** — equal, so no `subsumeType` failed to return — and the final
  record is the one quoted in §4 of the report (`types=13 kinds=0 fskvsNs=2887046605 kvNs=7717335053
  cseCalls=2224`).  Both numbers are as claimed.

---

## 3. Does the port's answer follow from what it measured?

Yes, and it claims no more than that.  P211 proves nothing new — the theorems are S1a's and S1b's, on
the other branch — and what it adds is the same behaviour measured on the 2.11 engine: an
unsatisfiable row program refused in 0.11 s (mine) / 0.14–0.50 s (the porter's), `enter` = `escape` =
9,515 on an instrumented library boot, 32 generated programs and twins refused-and-accepted inside a
180 s deadline, and both full suites green.  The one honest subtraction the report makes itself and I
confirm: **the 2.11 harness conversion buys status parity, not the Scala 3 wall clock**, because this
scalacheck stores the property by value.

---

## 4. Pre-existing 2.11 gaps the user should be told about

1. **The B1 program still type-checks on the 2.11 line** (§2.3(c)).  `Relation/Op.e`'s `dateDiff` has
   no signature on either 2.11 branch, so a `combine` of a date difference over a relation carrying
   neither date is ACCEPTED and fails later at header computation — the F3/B1 defect, fixed on
   `scala3-migration` and never back-ported.  Porting it is a stdlib change with its own gates (the
   example corpus and the `.ei` interface key both move).  **Consequence for this port:**
   `TestRowRefusals` on 2.11 pins the row-label refusal through `coalesce'`, and therefore does NOT
   pin F3/B1; if the stdlib fix is ever back-ported, switch the generator back to `dateDiff` (or add a
   `dateDiff` case) so that the pin covers it.
2. **`backport/env-2.11.sh` has TWO unbound-variable bugs, not one.**  The porter reports
   `ermine211` (broken: `_ERM_BP` is unset at the end of the script, so it looks for `/.classpath`).
   `sbt211` has the same bug — `( cd "$_ERM_ROOT" && … )` with `_ERM_ROOT` unset — and it is worse
   because it appears to work: `cd ""` is a no-op, so `sbt211` silently builds whatever tree the
   caller happens to be in, and under `set -u` it dies outright (it did, in my first mutation run:
   `env-2.11.sh: line 46: _ERM_ROOT: unbound variable`, `<r>/rv-mutations.log` first attempt).  Both
   fixes are one line: keep the two variables, or capture them inside the functions.  Outside this
   port's brief, as the porter says — but it should not stay unrecorded.
3. **sbt 0.13.5's `JUnitXmlTestsListener` races the build's own `System.setProperty`** and kills about
   one run in a dozen with a `ConcurrentModificationException` before any test starts (porter's §3).
   Pre-existing; a plain retry is green.  I did not hit it in seven runs.
4. **`TestRelations.scala`'s seven dead `no(` sites** must be converted with it if that file is ever
   revived — on both 2.11 branches and on `scala3-migration`.
5. **No `(B1-bound)` pin exists on the 2.11 line**, and correctly so: `TestDateAndScan.scala` is
   absent from BOTH 2.11 branches (`git cat-file -e` fails on each) and there is no
   `-Dermine.test.dateDiffReject` gate anywhere on `json-encode-2.11` to lift.  Verified.
6. **No LSP smoke case and no Lean/tracker copy on `backport-2.11`** — deliberate (no language server
   there, no `tracker/` tree).  `json-encode-2.11` has a `tracker/` tree and nothing was copied into
   it, which is what keeps the two branches identical outside the ported files.  Endorsed.

---

## 5. What to commit (unchanged from the report's §7, re-verified)

`backport-2.11`: `core/src/main/scala/com/clarifi/reporting/ermine/Subst.scala`,
`scalacheck-binding/src/main/scala/{TestErmine,TestScopes,TestSigEntail}.scala`,
`scalacheck-binding/src/main/scala/TestRowRefusals.scala` (new), `backport/SUBSUME-2.11.md`, and this
review.  `json-encode-2.11`: the same six plus
`scalacheck-binding/src/main/scala/TestNamedFields.scala`.  Nothing under `target/`, nothing under
`backport/.classpath` (tracked, currently identical to `HEAD`), nothing in `project/project/` — all
pre-existing noise.  Nothing is staged on either branch; I committed nothing and pushed nothing.

---

## 6. Re-check, 2026-09-16 (after the porter applied all six findings) — **VERDICT: LAND**

Scope: the six findings only, plus a confirmation that nothing else moved.  Logs added under `<r>`.

### 6.1 The findings

| # | applied? | what I checked |
|---|---|---|
| **F-1** | **YES, and well** | `TestRowRefusals.scala:209-222` is now `.apply(params).getOrElse(sys.error("rowRefusals: the generator produced no sample of " + sample + " cases at seed " + seed))` under a 14-line comment that states the mechanism (`Prop.all` of an empty `Seq` = `proved`), the Scala 3 behaviour it restores, and why. **The `sys.error` choice is the right one**: the throw happens inside the lazy `secure` shadow, whose `Prop.secure` catches `Throwable` and yields `Prop.exception` — a RED property carrying the seed in its message — so the loud failure is delivered, not leaked; and unlike a `cases.size ?= sample` conjunct it cannot be dropped by a later edit to `checks`. The comment says all of this, including that it cannot fire today. |
| **F-2** | YES, in all three docstrings and the report | `TestErmine.scala` `no` (`:183-200`) and `rejects` (`:216-226`), and `TestRowRefusals.scala:75-91`, now say the mechanism is `Properties.PropertySpecifier.update` — `update(String, Prop)` by value at 1.11.3 against `update(String, Function0[Prop])` at 1.15.4, both read with `javap` — and state explicitly that `Prop.secure` is eager in BOTH, citing `TestRunner.scala:50-57`. That is exactly what I measured. The report's §0.1 is retitled "scalacheck 1.11.3 stores a property BY VALUE …" and carries the same two signatures and the correction of its own earlier text. |
| **F-3** | YES | `grep '§6\.'` over the report: **no hits**; the gate references now read §4/§5. |
| **F-4** | YES | §0.1 now says "**129 s** after the conversion (§4; there is no before-run of those three suites alone, so this is an after-only number and no saving is inferred from it)". |
| **F-5** | YES, with exact line numbers | `Subst.scala:2079-2082` now says **three** wrapped call sites — `cse` (`:295`), `phaseFskvs`/`phaseKindVars` (`:583-584`) — and that `enter` (`:547`) and `atEscape` (`:582`) take strict parameters and allocate nothing. I checked every one of those five line numbers against the file: all exact. |
| **F-6** | YES, and it went further | Report §2.4 now enumerates **seven** changes, including `field g<sfx> : Date` (`:150`) with the type-level reason, the `Gen.oneOf(Seq)` overload (`:167`), and F-1 itself as the seventh. |
| extra | YES | The `sbt211` `_ERM_ROOT` gap I reported is recorded in the report's §3 and §8 alongside `ermine211`'s. |

### 6.2 My re-run and the diffs

* `TestRowRefusals` alone on `backport-2.11`: **`OK, proved property`, 1/1, 36 s** — `<r>/rv2-bp-rowrefusals.log`. (This run also recompiled the edited suite from source, so it is a compile gate too.)
* `git status` on both worktrees: the same file sets as before, **nothing staged**, nothing new outside `target/`, `project/project/` and `backport/.classpath` (the last still byte-identical to `HEAD`). The only untracked addition is this review, on `backport-2.11`.
* `git diff --stat`: `Subst.scala` 170 → **173** (+3, the F-5 comment), `TestErmine.scala` 134 → **143** (+9, the F-2 docstrings); `TestScopes.scala` (15), `TestSigEntail.scala` (18) and `TestNamedFields.scala` (2) **unchanged**. Diffing `TestRowRefusals.scala` against my pre-fix copy: 31 lines, of which exactly four are code — the F-1 `getOrElse` and its three continuation lines — and the rest comment.
* `cmp` across the worktrees: `TestRowRefusals.scala`, `TestScopes.scala`, `TestSigEntail.scala` and `SUBSUME-2.11.md` **IDENTICAL**; `TestErmine.scala` and `Subst.scala` still differ by exactly the pre-existing 20- and 10-line branch deltas, and their normalised port hunks are **byte-identical on the two branches** (`<r>/r2-*.patch`, `cmp` clean). The merge stays trivial.
* The porter's post-fix logs read as claimed: `<p>/fix-bp-rowrefusals.log` and `<p>/fix-j211-rowrefusals.log` both `OK, proved property` (1/1); `<p>/fix-bp-rr-mutA.log` red on the right conjunct (`case 1 missing {e} with 1 payload column(s): the bad program was not refused (31808 ms): accepted`, label `seed 1748119841232603689, 2 cases, session boot 208 ms`); `<p>/fix-bp-compile.log`, `fix-bp-recompile.log`, `fix-j211-compile.log` rc 0.

### 6.3 Residual

**None blocking.** Two notes, neither a condition of landing:

1. This review file lives only on `backport-2.11` (the report `SUBSUME-2.11.md` is on both, `cmp`-identical). If the orchestrator wants the review on both branches it will arrive with the merge.
2. The pre-existing 2.11 gaps of §4 are unchanged by the fixes and still stand — above all that **the B1 program still type-checks on the 2.11 line** (`Relation/Op.e`'s unsignatured `dateDiff`), which is the one thing a future 2.11 stdlib port should close, and at which point `TestRowRefusals` should move back from `coalesce'` to `dateDiff`.
