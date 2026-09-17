# SUBSUME-2.11 — the `subsume-termination` programme ported to the Scala 2.11 line

Step P211 of the programme's closing sequence (brief `tracker/satterm/briefs/brief-P211-port.md` on
`scala3-migration`).  Source: `scala3-migration` at `d278c900` — the S0 instrumentation commit
`bef7e7a7` and the S2 harness commit `b69b13de`.  Targets: `backport-2.11` (worktree
`~/research/ermine/ermine-scala-wt-backport`, tip `572e3592`) and `json-encode-2.11` (worktree
`~/research/ermine/ermine-scala-wt-json211`, tip `d75dfb1f`).  **Nothing committed, nothing pushed**:
the changes are in both working trees and the explicit path lists are in §7.

**Review round applied (2026-09-16).**  The P211 review (`backport/SUBSUME-2.11-REVIEW.md`, verdict
FIX-THEN-LAND) found one code defect and five documentation errors; all six are fixed here, on both
worktrees, and the fixes are flagged in place: **F-1** the vacuous empty sample in
`TestRowRefusals.scala` (§2.4 item 7, the only code change), **F-2** the eager-`secure` mechanism was
misattributed — the real difference is `PropertySpecifier.update` by value vs by name (§0.1, and the
`no` / `rejects` / lazy-`secure` docstrings), **F-3** four gate cross-references pointed at §6 instead
of §4/§5, **F-4** "129 s before and after" had no before-log and is now stated as after-only (§0.1),
**F-5** "four wrapped call sites" is three (§2.1 and `Subst.scala`'s header comment), **F-6** §2.4
enumerated four changes to `TestRowRefusals.scala` where there are seven.  The review's extra gap —
`sbt211`'s silent `_ERM_ROOT` bug — is recorded in §3 and §8.  Post-fix gates are in §4 and §5.

Every log path below is relative to `<p>` = `/home/dmitry/research/ermine/scratch-subsume/p211/`.
Toolchain: `source backport/env-2.11.sh; sbt211 <task>` — JDK 8 (Temurin 8u504), sbt 0.13.5,
Scala 2.11.5, **scalacheck 1.11.3**.  The machine was shared throughout with the main checkout's full
`core/test` (400–520 % CPU) and 2 G of free memory, which the gate policy expects; no figure here is a
tracker-grade timing and none was taken alone.

---

## 0. Three findings, before the transcription

The port is not a transcription.  Three things are different on the 2.11 line and each of them
changes what the ported code says or does.

### 0.1 scalacheck 1.11.3 stores a property BY VALUE, so `rejects` buys STATUS here, not wall clock

On `scala3-migration` the whole point of `rejects` is wall clock: `no` left a refutation *passed*
rather than *proved*, ScalaCheck ran `minSuccessfulTests` = 100 complete re-checks of one fixed
program at ~9 s each, and the B1 property took 1,099 s (`SUBSUME-STAGE0.md` §0, `SUBSUME-STAGE2.md`
§2.1: 1,282 s → 187 s).

**That cost does not exist on this line, and the reason is NOT `Prop.secure`** (P211 review F-2;
the first version of this section said it was, and that was wrong).  `Prop.secure` is eager in BOTH
versions — `try pv(p) catch ..` — as this branch's own `TestRunner.scala:50-57` on
`json-encode-2.11` already records.  What differs is how `Properties` STORES a property, read with
`javap` from both shipped jars:

```
1.11.3 :  Properties$PropertySpecifier.update(String, org.scalacheck.Prop)                <- BY VALUE
1.15.4 :  Properties$PropertySpecifier.update(String, scala.Function0<org.scalacheck.Prop>)  <- BY NAME
```
(`~/.ivy2/cache/org.scalacheck/scalacheck_2.11/jars/scalacheck_2.11-1.11.3.jar` and
`~/.cache/coursier/.../org/scalacheck/scalacheck_3/1.15.4/scalacheck_3-1.15.4.jar`.)

So on this line the whole right-hand side of `property(..) = ..` is evaluated ONCE, where it is
written — in the suite object's static initialiser — and the stored `Prop` is a constant `Result`
that the other ninety-nine draws only re-wrap.  On `scala3-migration` the by-name `update`
re-evaluates that right-hand side per draw, and that is where the 1,099 s went.  MEASURED here: the
three converted suites take **129 s** after the conversion (§4; there is no before-run of those three
suites alone, so this is an after-only number and no saving is inferred from it — P211 review F-4),
and the full `core/test` is 193 s → 125 s, a difference that is recompilation and machine noise, not
ninety-nine skipped library boots.  The mechanism above does not depend on either measurement.

So on this line `rejects` is worth having for three reasons that are not wall clock, and the report
says so rather than claiming a saving it does not make:

1. **The two branches' harness is the same.**  A refutation reads `OK, proved property` on both, so a
   future diff of the suites is about the suites.
2. **It is already right for a lazy `secure`.**  `json-encode-2.11` carries a lazy `secure` shadow in
   three JSON suites (`TestRunner.scala:67`, `TestDoc.scala:141`, `TestWidgets.scala:50`), and the new
   `TestRowRefusals` needs one too (§0.2).  Any site that ever moves under such a shadow gets the
   Scala 3 saving the moment it does.
3. **It states the stronger claim at the call site** — "this refutation is deterministic, so one
   evaluation settles it" — which is reviewable, and which `no` does not state.

What is NOT true here, and the Scala 3 report's paragraph about it was edited rather than copied: the
"hundred different `Supply` id bases" that `rejects` gives up.  With a by-value `update` there was only
ever ONE evaluation at ONE id base, so `TestRowRefusals`' sixteen bases over sixteen generated
programs are a net gain on this branch, not a trade.

### 0.2 `bounded` + eager `secure` = a class-initialisation deadlock; the lazy `secure` shadow is mandatory

The first port of `TestRowRefusals` was a faithful transcription, and it **wedged**: every case timed
out at its 180 s deadline, the suite was still running after eleven minutes, and each timeout left one
abandoned daemon thread behind.  Diagnosed by thread dump (`<p>/rr-jstack1.txt`, `rr-jstack2.txt`,
`rr-n2-jstack.txt`), and it is not a checker problem at all:

```
"ermine-bounded-check" #68 daemon  java.lang.Thread.State: RUNNABLE
        at com.clarifi.reporting.TestRowRefusals$lambda$$x1$1.apply(TestRowRefusals.scala:175)   <- no frames below
        ...
"pool-4-thread-11"  java.lang.Thread.State: TIMED_WAITING (on object monitor)
        at java.lang.Thread.join(Thread.java:1265)
        at com.clarifi.reporting.ErmineFixture.bounded(TestErmine.scala:247)
        at com.clarifi.reporting.TestRowRefusals$.<init>(TestRowRefusals.scala:180)
        at com.clarifi.reporting.TestRowRefusals$.<clinit>(TestRowRefusals.scala)                <- the deadlock
```

Because 1.11.3's `update` takes the property BY VALUE (§0.1) and `Prop.secure` is eager, the whole
right-hand side — the property body — runs inside `TestRowRefusals$.<clinit>`.  `bounded`
starts a daemon thread whose body reads `getstatic TestRowRefusals$.MODULE$`, and the JVM makes a
thread that touches a class whose initialisation is in progress on ANOTHER thread wait for that
initialisation — while the initialising thread sits in `Thread.join`.  Neither can proceed; the join
expires at the deadline, sixteen times.

The fix is the idiom the JSON 2.11 programme already found and documented for exactly this
(`TestRunner.scala:55-68` on `json-encode-2.11`), copied into `TestRowRefusals` with its own
explanation:

```scala
  private def secure[P](p: => P)(implicit pv: P => Prop): Prop =
    Prop((prms: Gen.Parameters) => Prop.secure(p)(pv).apply(prms))
```

It also keeps the one-evaluation property the stage is about: the body answers `Prop.all(..)` over
`propBoolean` props and `propBoolean(true)` is `proved` in 1.11.3 (bytecode: `Prop.apply(boolean)`
returns `proved`/`falsified`), so an all-green run is `Proof` and ScalaCheck stops after one test.
Measured after the fix: `OK, proved property`, 56 s at the shipped n = 16 (§4).

A second, smaller correction came out of the same investigation and is kept: the shared session is
forced by `bootShared()` on the property's own thread, OUTSIDE any deadline.  `fx.mkEnv` is only
~300 ms here, so this is hygiene rather than the fix — the number is reported in the property's label
so a future reader can see it.

### 0.3 THE B1 PROGRAM IS NOT REFUSED ON THE 2.11 LINE — the F3 `dateDiff` signature was never back-ported

`TestRowRefusals` on `scala3-migration` builds every case as
`combine_Op (dateDiff_Op days (col_Op s) (col_Op e)) g r`.  On this line that program **type-checks**.
`Relation/Op.e:150-151` here is

```
--dateDiff : forall r r1 r2 .  AsOp op1 op2 => TimeUnit -> op1 r Date -> op2 r1 Date -> Op r2 Long
dateDiff u s e = dateDiff# u (asOp s) (asOp e)
```

— the signature is COMMENTED OUT (and would have left `r2` free anyway), so the result row is
unconstrained and a `combine` of a date difference over a relation carrying neither date is accepted.
That is the F3/B1 defect itself, fixed on `scala3-migration` by giving `dateDiff` `dateAdd'`'s
signature; the stdlib fix is not on this branch and porting it is a stdlib change with its own gates,
which this brief does not cover.

MEASURED, with the exact B1 program of `TestDateAndScan`: `Importing module 'B1' (0.25 seconds)` —
accepted (`<p>/probe/B1.e`, `<p>/probe-b1-good1.log`).

So the generator uses **`coalesce'`** instead, whose signature is byte-identical on the two branches
(`(RUnion2 r r1 r2, AsOp opc, AsOp opa) => opc r1 a -> opa r2 a -> Op r a`) and which puts BOTH
columns in the op's row — precisely the shape `combine`'s `r <- (s, o)` then refuses.  The refusal is
the same sentence from the same check:

```
Bad1.e:14:9: Row partitions are unsatisfiable at field 'Bad1.eB1': a part contains it but the whole does not
outB1 = combine_Op (coalesce'_Op (col_Op sB1) (col_Op eB1)) gB1 rB1
```

0.50 s, with the positive twin accepted in 0.69 s (`<p>/probe/Bad1.e`, `<p>/probe/Good1.e`).

**Consequences recorded for the orchestrator.**  (a) The `(B1-bound)` deadline pin is NOT ported
anywhere on the 2.11 line: `TestDateAndScan.scala` exists on neither branch
(`git cat-file -e json-encode-2.11:scalacheck-binding/src/main/scala/TestDateAndScan.scala` → does not
exist), so there is nothing to pin it to and no `-Dermine.test.dateDiffReject` gate to lift (no such
string anywhere on `json-encode-2.11`).  (b) The 2.11 line still accepts the B1 program at run-time
risk; that is a KNOWN, pre-existing gap of the back-port scope, not a regression of this port, and it
is the one thing a future 2.11 stdlib port would close.

---

## 1. The `no(` census on 2.11, before and after

Done by grep on each branch rather than by trusting the Scala 3 list (which is 21 live sites in 6
files; the 2.11 line has its own set and its own files).  "Live" means a call site that compiles.

### 1.1 `backport-2.11` (tip `572e3592`) — 19 live sites in 3 files, 18 converted, 1 kept

| file | BEFORE (line) | body | AFTER |
|---|---|---|---|
| `scalacheck-binding/src/main/scala/TestErmine.scala` | 194, 196, 197, 198, 253, 267, 271 | `sessionProof`, fixed program | **7 → `rejects`** |
| `scalacheck-binding/src/main/scala/TestScopes.scala` | 119, 122, 131, 134, 153 | `typeChecks`, fixed program | **5 → `rejects`** |
| `scalacheck-binding/src/main/scala/TestScopes.scala` | **116** | **`forAll(imported) { n => .. }`** | **KEPT as `no`** |
| `scalacheck-binding/src/main/scala/TestSigEntail.scala` | 55, 59, 62, 67, 76, 91 | `typeChecks`, fixed program | **6 → `rejects`** |
| `core/src/test/scala/com/clarifi/reporting/TestRelations.scala` | 122, 125, 126, 127, 128, 156, 161 | — | **DEAD, untouched** |

`TestRelations.scala` is one block comment from its first line to its last (`:1` is
`/*package com.clarifi.reporting`, `:215` is `}*/`), exactly as on `scala3-migration`; nothing in it
compiles, so converting it would buy no coverage and mislead the next reader.  **If it is ever
revived, those seven must be converted with it.**

The kept site is `TestScopes.scala:116`: its body is `forAll(imported) { n => no(sessionProof(..)) }`
and EVERY generated import name must fail — mapping the first draw to `Proof` would short-circuit the
generator and silently drop the other ninety-nine.  A comment above it now says so.

AFTER: **one** live `no(` call site on the branch (`TestScopes.scala:121`, the same one), plus the
`def no` definition and three doc mentions; every converted site reads `OK, proved property` in §4's
log and the kept one still reads `OK, passed 100 tests`.

### 1.2 `json-encode-2.11` (tip `d75dfb1f`) — 20 live sites in 4 files, 19 converted, 1 kept

The same 19 (the three suites are byte-identical to `backport-2.11`'s apart from `TestErmine.scala`'s
`literalLock`/`deleteTree` block, which is above the region this port touches), **plus one the JSON
programme added**:

| file | BEFORE (line) | body | AFTER |
|---|---|---|---|
| `scalacheck-binding/src/main/scala/TestErmine.scala` | 214, 216, 217, 218, 273, 287, 291 | `sessionProof`, fixed | **7 → `rejects`** |
| `scalacheck-binding/src/main/scala/TestScopes.scala` | 119, 122, 131, 134, 153 (+ 116 kept) | `typeChecks` / `forAll` | **5 → `rejects`**, 1 kept |
| `scalacheck-binding/src/main/scala/TestSigEntail.scala` | 55, 59, 62, 67, 76, 91 | `typeChecks`, fixed | **6 → `rejects`** |
| `scalacheck-binding/src/main/scala/TestNamedFields.scala` | **416** | `typeChecks`, fixed, first of three `&&` conjuncts | **1 → `rejects`** |
| `core/src/test/scala/com/clarifi/reporting/TestRelations.scala` | as above | — | **DEAD, untouched** |

`TestNamedFields.scala:416` is `no(typeChecks(src, "nfsecret", imps)) && typeChecks(..) &&
sessionProof(..)`: under `no` the conjunction was `True && Proof && Proof` = `True` (*passed*), and
`Result.&&` makes it `Proof` once the first conjunct is `rejects` — the one place on either branch
where the conversion changes a WHOLE property's status rather than a single site's.

**Not a site:** `TestDecode.scala:463-490`.  Its `no(..)` is a local `def no(t: String, text: String):
Decode.Error` inside a property — a different function with the same name.  Left alone.

---

## 2. What was ported, file by file

### 2.1 `core/src/main/scala/com/clarifi/reporting/ermine/Subst.scala` — from `bef7e7a7` (+171/−2)

Three call sites and one appended object, the same as on `scala3-migration` (where the file is
+157/−2; the extra fourteen lines here are the two BACK-PORT paragraphs in the object's header
comment, F-5 included).
Line numbers are this branch's:

* `:293-295` `checkSkolemEscape`'s whole-`hm.types` walk wrapped in `SubsumeTrace.cse(hm)(..)`
  (`:365` on `scala3-migration`);
* `:544-547` `subsumeType` opens with `val stid = SubsumeTrace.enter(hm, sig)`;
* `:582-584` `SubsumeTrace.atEscape(stid, sks, sts, hm)` and the escape check's two halves wrapped in
  `phaseFskvs` / `phaseKindVars` (`:648` on `scala3-migration`);
* `:2067-2222` the header comment and `object SubsumeTrace` (`:2115`).

**The one dialect change, and what it costs.**  Scala 3's `inline def f(inline body: A)` has no 2.11
equivalent.  Every entry point is an **`@inline def` with a by-name parameter**, guarded exactly as
before — `if (!enabled)` is the first act of each — so the records, the nanosecond accumulators and
the `bump` CAS loop are byte-identical.  What 2.11 cannot do is elide the thunk when the flag is OFF,
so each of the **three** wrapped call sites — `cse` (`:295`) and `phaseFskvs` / `phaseKindVars`
(`:583-584`) — allocates one `Function0` per call on a path that runs ~9,500 times per module load.
`enter` (`:547`) and `atEscape` (`:582`) take strict parameters and allocate nothing (P211 review
F-5; the first version of this section and of the file's header comment said four).  **That cost is
accepted and measured**: the flag-OFF full `core/test` is 125 s / 736 properties green (§4) and the
flag-OFF CLI run writes ZERO records (§4).  The
alternative — a `tick()`/`tock()` pair with no by-name — was rejected because it would have made the
three call sites structurally different from `scala3-migration`'s, and a future diff of the two
`Subst.scala`s is worth more than one allocation on a diagnostic path.

Everything else compiles as written on 2.11: `AtomicLong`, `System.nanoTime`, `lazy val` writer,
`GenRules.rowSoundBudgetHits` / `rowSoundNodes` / `solveBudgetHits`, `SigEntail.Site(kind, module,
binding, loc)`, `SubstEnv.types` / `kinds` / `fskvs` / `kindVars` — all present on this branch with
the same names.  The object's header comment carries a BACK-PORT paragraph naming the dialect change
and re-points the two "which line" references at this branch's line numbers.

### 2.2 `scalacheck-binding/src/main/scala/TestErmine.scala` — from `b69b13de` (+136/−7)

`ErmineFixture` gains `rejects`, `bounded(ms)`, `outcomeOf` and `loadNamed`, and `no` gains its
docstring; the seven call sites of §1 are converted.  No dialect change was needed in the code — 1.11.3
has `Prop.Proof`, `Result.copy(status =, labels =)`, `AtomicReference`, and `Session.Literal` /
`Session.depCache` / `Session.load(file, Some(name))` all exist here with the same shapes.

**Two docstrings were rewritten rather than copied, because the Scala 3 text is FALSE here.**

* `no` / `rejects`: the "hundred library-scale re-checks" argument (§0.1).  The new text states the
  eager-`secure` fact, cites the bytecode check, and says plainly that `rejects` buys status and
  branch-parity here rather than wall clock.
* `loadNamed`: `scala3-migration`'s version argues at length that dropping `ErmineFixture.literalLock`
  is sound, because there `loadStatements` takes that lock around a dep-cache eviction and
  `TestDateAndScan.underZone` holds it with the JVM default timezone changed.  **Neither is true on the
  2.11 line**: `loadStatements` here parses and calls `loadModule` directly, touching neither the lock
  nor the cache, and no suite here changes the default timezone.  `literalLock` does not exist on
  `backport-2.11` at all; on `json-encode-2.11` it exists and is taken by exactly one property
  (`TestNamedFields`' interface-cache case, which CLEARS the dep cache), and a `loadNamed` in flight
  during that clear can be made to re-read a dependency, never to reach a different verdict.  What
  survives is the data-structure half, restated for this branch: `Session.depCache` is a
  `HashMap with SynchronizedMap` (`Session.scala:101` on both branches), so the unlocked `-=` can
  neither corrupt it nor race another property's.

### 2.3 `TestScopes.scala` (+10/−5) and `TestSigEntail.scala` (+9/−9) — from `b69b13de`

Site conversions only, plus `TestSigEntail`'s three doc references to `no(typeChecks(...))` corrected
to `rejects(...)` as on `scala3-migration`, plus a five-line comment above `TestScopes.scala:116`
saying why that one site keeps `no`.

### 2.4 `scalacheck-binding/src/main/scala/TestRowRefusals.scala` — NEW, from `b69b13de` (+253)

The generator of unsatisfiable row programs and their positive twins.  **Seven** changes from the
Scala 3 file, each documented in the file itself (the first version of this section listed four and
the P211 review found two more, F-6; the seventh is the review's own F-1):

1. **`coalesce'` instead of `dateDiff`** (§0.3) — otherwise the "bad" programs are ACCEPTED here.
2. **`field g<sfx> : Date` instead of `: Int`** (`:150`) — a consequence of (1), not a choice:
   `coalesce'` over two `Date` columns returns `Date` where `dateDiff` returned `Int`, and `combine`'s
   `op s a -> Field c a` forces the combine target to the op's own element type.  Without it nothing
   type-checks.
3. **A lazy `secure` shadow** (§0.2) — otherwise the suite deadlocks against its own worker thread.
4. **`java.util.Random` seeding instead of `org.scalacheck.rng.Seed`.**  scalacheck 1.11.3 has NO
   `rng` package (`Seed` arrives in 1.13) and `pureApply` does not exist; `Gen.Parameters` carries a
   `scala.util.Random` and `Gen[T].apply(params): Option[T]` draws.  So the seed is a `Long`, the
   sample is `Gen.listOfN(n, pairGen).apply(Gen.Parameters.default.withRng(new Random(seed)))`, and a
   failure is reproducible with `-Dermine.test.rowRefusals.seed=<long>` exactly as there.
5. **`Gen.oneOf(List(a, b, c))` instead of `Gen.oneOf(a, b, c)`** (`:167`) — 1.11.3's `Seq[T]`
   overload; the varargs one would take the three lists as three `Gen`s' worth of values of the wrong
   type.
6. **`bootShared()`** forces the shared session outside any deadline and reports its cost in the
   property's label (~300 ms measured).
7. **An undrawable sample is LOUD** (`:209-222`, P211 review F-1, the one code fix of the review).
   `Gen[T].apply(params)` is an `Option` here, and the first port wrote `.getOrElse(Nil)` — whereupon
   an empty sample makes `checks` empty and `Prop.all` with an empty `Seq` answers **`proved`**
   (bytecode: `all(Seq)` = `if (ps.isEmpty) proved`), i.e. a GREEN property asserting nothing.  The
   Scala 3 original cannot reach that: `pureApply` retries and then throws `Gen.RetrievalError`.  The
   fix restores the throw — `.getOrElse(sys.error("rowRefusals: the generator produced no sample …"))`
   — which the lazy `secure` above turns into `Prop.exception`, a RED property naming the seed.
   **`sys.error` was chosen over the equivalent `cases.size ?= sample` conjunct** because it matches
   the Scala 3 behaviour it replaces and cannot be dropped by a later edit to `checks`.  It cannot
   fire today (`Gen.choose` and `Gen.oneOf` never fail); it is one `suchThat` away from being able to.

Unchanged: the sixteen cases (`-Dermine.test.rowRefusals.n`), the 180,000 ms deadline, the three
assertions per case (refused / refused BY THE ROW-LABEL CHECK / the twin checks), the one warm
session, the no-underscore rule for generated names, and the S2 review's F-1 cause conjunct.

### 2.5 `TestNamedFields.scala` — `json-encode-2.11` ONLY (+1/−1)

One site (§1.2).  This is the only edit that exists on `json-encode-2.11` and not on `backport-2.11`.

### 2.6 What was NOT ported, and why

* **The LSP smoke case** — `tracker/lsp-tests/RowUnsat.e` and the `lsp-client.py` block: there is no
  language server on the 2.11 line, as `BACKPORT.md` records.
* **The `(B1-bound)` deadline pin** — `TestDateAndScan.scala` exists on NEITHER 2.11 branch (§0.3),
  so there is nothing to pin; and there is no `-Dermine.test.dateDiffReject` gate on
  `json-encode-2.11` to lift (grep: no occurrence).
* **The Lean development and the tracker documents** — `backport-2.11` carries no `tracker/` tree
  (`BACKPORT.md`: "Not ported on purpose: … the tracker/ tree (design notes, the Lean development, the
  corpus tooling)").  The documents this port's code cites therefore live on `scala3-migration`, and
  the citations name that branch:
  `tracker/PROMPT-subsume-termination.md`, `tracker/satterm/SUBSUME-PLAN.md`,
  `tracker/satterm/SUBSUME-STAGE0.md` (+ `-REVIEW`), `SUBSUME-STAGE1A.md`, `SUBSUME-STAGE1B.md`,
  `SUBSUME-STAGE2.md` (+ `-REVIEW`), `tracker/satterm/briefs/brief-S0.md`, `brief-S2.md`,
  `brief-P211-port.md`, and the Lean sources `tracker/lean/Rowpartition/SubsumeEscape.lean`,
  `tracker/lean/Loop/RejectTerm.lean`, `tracker/lean/Loop/EnvBound.lean`.
  `json-encode-2.11` DOES carry a `tracker/` tree; nothing was copied into it either, so that the two
  2.11 branches stay identical outside the five ported files and the merge stays trivial.
* **`tracker/repl-classpath.txt`, `backport/.classpath`, anything under `target/`** — generated or
  pre-existing noise.  `backport/.classpath` was regenerated to run the CLI gates and must NOT be
  staged.

---

## 3. Toolchain notes worth keeping (two of them are small bugs someone will hit again)

`source backport/env-2.11.sh` then `sbt211 <task>`, as `BACKPORT.md` says.  Two things bit this port:

* **`backport/env-2.11.sh` has TWO unbound-variable bugs, and the second is worse than the first.**
  The script ends with `unset _ERM_BP _ERM_ROOT`, but both functions still read those variables.
  `ermine211` reads `local cp="$_ERM_BP/.classpath"`, so it resolves to `/.classpath` and answers
  `no /.classpath; run: sbt211 'export core/runtime:fullClasspath' | tail -1 > /.classpath` — loud,
  and it is why the CLI gates below run the equivalent invocation by hand.  **`sbt211` has the same
  bug and is SILENT about it** (P211 review, §4.2 there): its body is `( cd "$_ERM_ROOT" && … )`, and
  `cd ""` is a no-op, so it builds whatever tree the caller happens to be in — correct only because
  every invocation in this port was already `cd`-ed into the right worktree — and under `set -u` it
  dies outright (`env-2.11.sh: line 46: _ERM_ROOT: unbound variable`, which the reviewer hit).  Both
  fixes are one line.  NOT FIXED here (`env-2.11.sh` is outside this port's brief, and the review
  agrees); recorded in §8 for whoever owns that file.  The hand invocation used for the CLI gates:
  ```
  java -Xss16m -Dermine.typeCheck=true -Dermine.useInterface=false \
       -cp "$(tr -d '\n' < backport/.classpath)" com.clarifi.reporting.ermine.session.Console <file>
  ```
  The one-line fix for each is to capture the variable inside the function, or to keep both exported.
* **`sbt 0.13.5`'s JUnit XML listener races the build's own `System.setProperty`.**  One run in about
  a dozen died before any test with
  `java.util.ConcurrentModificationException at java.util.Hashtable$Enumerator.next` /
  `sbt.JUnitXmlTestsListener.<init>(JUnitXmlTestsListener.scala:28)` — the listener enumerates the
  system properties while `computeRevision` / `enableTypeCheck` are setting them.  A plain retry is
  green (the failing log was overwritten by that retry, so the stack above is the record).
  Pre-existing, unrelated to this port.

---

## 4. Gates on `backport-2.11`

| gate | result | log |
|---|---|---|
| baseline compile (before any edit) | rc 0, 2 m 27 s cold | `<p>/bp-compile-baseline.log` |
| **compile** `core/compile core/test:compile` | **rc 0**, 36 s + 8 s; 5 test sources; no new warning attributable to the ported files (21 warnings, all pre-existing in the 10 recompiled core sources; the only new-ish one is the long-standing `SynchronizedMap is deprecated` at `Session.scala:101`) | `<p>/bp-compile-ported.log` |
| **the converted suites alone** (`TestErmine`, `TestScopes`, `TestSigEntail`) | **69 / 69 green, 129 s.** All 18 converted sites read `OK, proved property`; the kept `forAll` site reads `OK, passed 100 tests`. 44 proved / 25 passed-100 over the three suites | `<p>/bp-converted-suites.log` |
| **`TestRowRefusals` alone** | **`OK, proved property`, 56 s** at the shipped n = 16 (48 assertions: 16 refusals, 16 causes, 16 twins); 48 s at n = 2 | `<p>/bp-rowrefusals.log`, `<p>/bp-rowrefusals-n2.log` |
| `TestRowRefusals` MUTATION (`rowRefusal` → a string no refusal contains) | **RED, on the right conjunct**: `case 1 missing {s,e} with 2 payload column(s): refused, but not by the row-label check (43515 ms): refused: RowUnsatBad1<dynamic>:14:9: Row partitions are unsatisfiable at field 'RowUnsatBad1.eB1': the whole contains it but no part does`; mutation reverted, file restored byte-identical | `<p>/bp-rowrefusals-mutation.log` |
| **flag OFF, zero records** | `-Dermine.subsumeTrace.out=<file>` with the flag UNSET: **the file is never created** — zero records — and the module is refused in 0.14 s (37.0 s wall incl. the 129-module boot) | `<p>/bp-cli-flag-gate.log`, `<p>/trace-off.tsv` (absent) |
| flag ON, control | 19,030 records: **9,515 `enter` and 9,515 `escape` — equal, so every `subsumeType` returned**; final record `types=13 kinds=0 fskvsNs=2.887e9 kvNs=7.717e9 cseCalls=2224 cseNs=0.560e9`, i.e. the escape check is 10.6 s of a 38.0 s CLI run (28 %) and `checkSkolemEscape`'s walk 0.56 s over 2,224 calls | `<p>/bp-cli-flag-gate.log`, `<p>/trace-on.tsv.gz` |
| **post-review re-runs** (after the F-1 code fix) | `core/compile core/test:compile` **rc 0**; `TestRowRefusals` alone **`OK, proved property`**; mutation A (`kept` → `List("s","e")`, i.e. the bad case made satisfiable) **RED on the "refused" conjunct**, then reverted byte-identically (`cmp` clean against the pre-mutation copy AND against the `json-encode-2.11` copy) | `<p>/fix-bp-compile.log`, `<p>/fix-bp-rowrefusals.log`, `<p>/fix-bp-rr-mutA.log` |
| **full `core/test` BEFORE** (ported files reverted, `TestRowRefusals` moved aside) | **735 / 735 green, 193 s** (includes recompiling the reverted sources) | `<p>/bp-full-core-test-before.log` |
| **full `core/test` AFTER** | **736 / 736 green, 125 s** — 735 + the one new `TestRowRefusals` property | `<p>/bp-full-core-test-after.log` |

The before/after pair was taken on the same tree, twenty minutes apart, with the main checkout's full
test running throughout; the before run also pays a recompile.  **No wall-clock saving is claimed from
it** — §0.1 explains why there is none to claim on this line — and the numbers are here so that the
reviewer can see the property count go 735 → 736 and nothing go red.  The documented baseline for this
branch is 735/735 (`BACKPORT.md`, 2026-09-12); it reproduced exactly.

`.ei` hygiene: the fixture runs with `-Dermine.useInterface=false` and every CLI gate passed the same
flag, so no interface file was written; `find core/examples core/src -name '*.ei'` is empty on both
branches.

---

## 5. Gates on `json-encode-2.11`

The changes there are **byte-identical** to `backport-2.11`'s (§7.3), plus the one
`TestNamedFields.scala` site, so the merge the orchestrator will do is trivial.

| gate | result | log |
|---|---|---|
| **compile** `core/compile core/test:compile core/copyResources` | **rc 0**, 58 s + 9 s; 6 test sources; 21 warnings, all pre-existing | `<p>/j211-compile-ported.log` |
| **the converted suites alone** (`TestErmine`, `TestScopes`, `TestSigEntail`, `TestNamedFields`) | **83 / 83 green, 123 s**; 48 proved / 35 passed-100. `Ermine named constructor fields.an existential field gets no selector, a sibling still does: OK, proved property` — the property whose status the conversion flips (§1.2); the kept `forAll` site still `OK, passed 100 tests` | `<p>/j211-converted-suites.log` |
| **`TestRowRefusals` alone** | **`OK, proved property`, 47 s** at n = 16 | `<p>/j211-rowrefusals.log` |
| **full `core/test`** | **859 / 859 green, 354 s** — the documented baseline 858 (at `d75dfb1f`) plus the one new property; nothing red, nothing quarantined | `<p>/j211-full-core-test-after.log` |
| **flag OFF, zero records** | `-Dermine.subsumeTrace.out=<file>` with the flag UNSET: **the file is never created** — zero records — and the same program is refused in **0.12 s** with `Row partitions are unsatisfiable at field 'Bad1.eB1'` | `<p>/j211-cli-off.log`, `<p>/j211-trace-off.tsv` (absent) |
| flag ON, control | **19,030 records, 9,515 `enter` and 9,515 `escape`** — equal, and identical to `backport-2.11`'s counts | `<p>/j211-cli-on.log`, `<p>/j211-trace-on.tsv.gz` |

**Line endings, and one gate that was re-run because of them.**  The older suites on this branch are
CRLF (the whole `backport-2.11` lineage is, and `BACKPORT.md` says to keep it that way), but the files
the JSON programme added are LF — `TestNamedFields.scala` among them.  The first patch of it rewrote
the whole file to CRLF (a 536/536 diff for a one-line change); it was reverted and re-patched
BYTE-WISE, so the diff is now `1 / 1` and the file is still LF.  The converted-suites gate above was
re-run on that final tree (123 s, same 83/83, same statuses).  The full `core/test` below ran six
minutes before that whitespace-only rewrite; the compiled substitution is identical, and the
converted-suites re-run covers the file.  `TestRowRefusals.scala` is CRLF on BOTH branches, matching
its `scalacheck-binding` neighbours and keeping the two copies byte-identical.

**Post-review re-runs (after the F-1 code fix):** `core/compile core/test:compile core/copyResources`
**rc 0** (`<p>/fix-j211-compile.log`) and `TestRowRefusals` alone **`OK, proved property`**
(`<p>/fix-j211-rowrefusals.log`).  The full `core/test` above and the converted-suites gate predate
the fix; the fix touches one expression inside `TestRowRefusals`' property and two docstrings, and
`TestRowRefusals` was re-run alone on both branches afterwards.

No BEFORE full run was taken on this branch: `d75dfb1f`'s 858/858 is the documented baseline, the
after-count is 859 = 858 + `TestRowRefusals`, and §0.1 says why a same-day wall-clock pair would be
measuring the machine rather than the change.

---

## 6. What the port says about the programme's title question on this line

*Does the checker terminate on a refused row program?*  This step proves nothing new — the theorems
are S1a's (`runV_steps`) and S1b's (`budgetSP_terminates`, `solveSeedP_terminates`,
`runsP_noAliasChain`), and they are about a model, on the other branch.  What it adds is **the same
answer, measured on the 2.11 engine**:

* an unsatisfiable row program is REFUSED here in **0.14–0.50 s** (`<p>/trace-off.tsv` run,
  `<p>/probe/Bad1.e`), its positive twin accepted in 0.69 s;
* the instrumented run records **9,515 `enter` and 9,515 `escape`** — equal, so no `subsumeType` call
  failed to return — against `scala3-migration`'s 9,531 for the same kind of module
  (`SUBSUME-STAGE0.md` §0.1).  The two engines agree to 0.2 % on how much escape-checking one library
  boot plus one refusal costs;
* the escape check is **10.6 s of a 38.0 s CLI run (28 %)**, split 2.89 s `fskvs` / 7.72 s
  `kindVars`, with `checkSkolemEscape`'s walk at 0.56 s over 2,224 calls.  That is the same
  performance item S0 ticketed on `scala3-migration` (45.4 s of 184 s, 24.7 %) and it is **not** a
  termination problem on either branch;
* **32 generated unsatisfiable programs and their twins** (16 cases × 2, at 16 fresh `Supply` id
  bases) are all refused by the row-label check, and all their twins check, inside a 180 s deadline,
  on both branches.

One thing this line does NOT have and the Scala 3 line does: the F3 `dateDiff` signature (§0.3).  The
B1 program of the original report is still ACCEPTED here.  That is a stdlib gap of the back-port's
scope, it is now measured and written down, and it is the single most useful thing a future 2.11 port
could close.

---

## 7. The explicit path list to commit

Nothing is committed and nothing is pushed.  Both working trees hold the changes.

### 7.1 `backport-2.11` (worktree `~/research/ermine/ermine-scala-wt-backport`)

```
core/src/main/scala/com/clarifi/reporting/ermine/Subst.scala          (modified, +171/-2)
scalacheck-binding/src/main/scala/TestErmine.scala                    (modified, +136/-7)
scalacheck-binding/src/main/scala/TestScopes.scala                    (modified, +10/-5)
scalacheck-binding/src/main/scala/TestSigEntail.scala                 (modified, +9/-9)
scalacheck-binding/src/main/scala/TestRowRefusals.scala               (NEW, 253 lines)
backport/SUBSUME-2.11.md                                              (this report)
backport/SUBSUME-2.11-REVIEW.md                                       (the P211 review)
```

### 7.2 `json-encode-2.11` (worktree `~/research/ermine/ermine-scala-wt-json211`)

The same six, plus the one site this branch alone has:

```
core/src/main/scala/com/clarifi/reporting/ermine/Subst.scala          (modified, +171/-2)
scalacheck-binding/src/main/scala/TestErmine.scala                    (modified, +136/-7)
scalacheck-binding/src/main/scala/TestScopes.scala                    (modified, +10/-5)
scalacheck-binding/src/main/scala/TestSigEntail.scala                 (modified, +9/-9)
scalacheck-binding/src/main/scala/TestRowRefusals.scala               (NEW, 253 lines)
scalacheck-binding/src/main/scala/TestNamedFields.scala               (modified, +1/-1)  <- json-encode-2.11 ONLY
backport/SUBSUME-2.11.md                                              (this report)
```

`backport/SUBSUME-2.11-REVIEW.md` exists only in the `backport-2.11` worktree and reaches
`json-encode-2.11` through the merge; it was deliberately not copied across, so that the merge stays
the only path by which it arrives.

### 7.3 DO NOT STAGE, on either branch

`backport/.classpath` (a tracked, generated classpath cache), anything under `core/target/`,
`scalacheck-binding/target/` or any other `target/` tree.  It was regenerated on both branches to run
the CLI gates: on `backport-2.11` the regenerated content is identical to the committed one (`git
status` clean for that path), and on `json-encode-2.11` it was restored with `git checkout --
backport/.classpath` afterwards, so it is clean there too.  Both branches show a large pre-existing
`git status` of deleted/modified tracked class files under `core/target/` and
`scalacheck-binding/target/` — that noise predates this port and the earlier back-port reports already
recorded it.  After this port, the ONLY non-`target/` entries in `git status` on each branch are the
paths listed in §7.1 / §7.2 plus `project/project/` — sbt 0.13's meta-build output directory, generated
and untracked, present on `json-encode-2.11` since 2026-09-14 and created on `backport-2.11` by this
port's first `sbt211` invocation.  Do not stage it either.  (The empty `.ermine_history` each CLI gate
drops in the worktree root was deleted.)

### 7.4 The merge `backport-2.11` → `json-encode-2.11` will be trivial, and here is the evidence

For each of the four modified files, the ADDED and REMOVED lines of the two working trees' diffs were
compared by checksum and are **identical**:

```
Subst.scala          backport=ca681d5dd9421094a099e22f32aa8090  json211=ca681d5dd9421094a099e22f32aa8090
TestErmine.scala     backport=36b6e09ab18aa65ede4118dad2d79aae  json211=36b6e09ab18aa65ede4118dad2d79aae
TestScopes.scala     backport=0565659f9e7fddd45ae8e74659c474b6  json211=0565659f9e7fddd45ae8e74659c474b6
TestSigEntail.scala  backport=11e109ac5571dc3259096e5d785fba7f  json211=11e109ac5571dc3259096e5d785fba7f
```
(`git diff -U0 -- <file> | grep '^[+-][^+-]' | md5sum` in each worktree.)

`TestRowRefusals.scala` is byte-identical on the two branches (`cmp` clean).  `TestScopes.scala` and
`TestSigEntail.scala` are byte-identical as whole files.  The two files that still differ between the
branches differ ONLY by what already differed before this port: `TestErmine.scala` by
`json-encode-2.11`'s 20-line `literalLock` / `deleteTree` block (above the region touched here), and
`Subst.scala` by the JSON branch's five `DataStatement(..., sels)` arity hunks (far from the three
touched sites, and the appended `object SubsumeTrace` is identical at both file ends).  So the
orchestrator should commit `backport-2.11` first, then `git merge backport-2.11` into
`json-encode-2.11`; the only file that can need attention is `TestNamedFields.scala`, which exists on
one side only and therefore cannot conflict.

---

## 8. Open items for the orchestrator / the reviewer

1. **`backport/env-2.11.sh` has TWO unbound-variable bugs** (§3).  `ermine211` fails loudly
   (`_ERM_BP` unset ⇒ it looks for `/.classpath`).  **`sbt211` has the same bug and fails silently**:
   `( cd "$_ERM_ROOT" && … )` with `_ERM_ROOT` unset is `cd ""`, a no-op, so it builds whatever tree
   the caller is in — and under `set -u` it dies outright (the P211 reviewer hit exactly that).  One
   line each; left alone because the file is outside this brief and the review agrees it should be.
2. **The 2.11 line still accepts the B1 program** (§0.3): `Relation/Op.e`'s `dateDiff` has no
   signature here.  Porting the F3 stdlib fix is a separate job with its own gates (the example
   corpus and the `.ei` interface key would both move).
3. **`TestRelations.scala`'s seven dead `no(` sites** (§1.1) must be converted if that file is ever
   revived, on both 2.11 branches and on `scala3-migration`.
4. **No LSP, no Lean, no `tracker/` copy** (§2.6).  `json-encode-2.11` does carry a `tracker/` tree;
   nothing was copied into it, deliberately, so that the two branches stay identical outside the five
   ported files.
5. **If the F3 `dateDiff` stdlib fix is ever back-ported**, switch `TestRowRefusals`' generator back
   to `dateDiff` (or add a `dateDiff` case) so that the pin covers B1 itself; as it stands the suite
   pins the row-label refusal through `coalesce'` and does NOT pin F3/B1 (P211 review §4.1).
6. The reviewer's cheapest re-check is `sbt211 'core/testOnly com.clarifi.reporting.TestErmine
   com.clarifi.reporting.TestScopes com.clarifi.reporting.TestSigEntail'` and
   `sbt211 'core/testOnly com.clarifi.reporting.TestRowRefusals'` on each branch (plus
   `com.clarifi.reporting.TestNamedFields` on `json-encode-2.11`), and reading
   `<p>/bp-full-core-test-after.log` and `<p>/j211-full-core-test-after.log`.
