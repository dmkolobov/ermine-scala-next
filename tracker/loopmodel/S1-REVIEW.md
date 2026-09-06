# S1 REVIEW — soundness of the loop: re-run, hunted, and one CONFIRMED false acceptance

2026-09-05.  Reviewer agent (Opus), briefed with `tracker/loopmodel/briefs/brief-S1.md`, the
implementer's report `tracker/loopmodel/S1-SOUNDNESS.md` and the uncommitted diff at `fde996a`
(branch `scala3-migration`).  Nothing was trusted that was not re-run.  Scratch:
`/home/dmitry/.claude/jobs/880c725d/tmp/review-S1/`.  Finding prefix `Z-`.

## VERDICT: **FIX-THEN-ADVANCE**

The Lean is sound and re-verified: build 859, audit 3804 / 0 non-standard axioms, no `sorry`,
every quoted statement verbatim, every seed instantiation kernel-checked, no pre-existing
module touched.  Nothing in `Loop/{Sound,Reject,Solve}.lean` is wrong.

What must be fixed before S1 is closed is the **framing**, because the hunt the brief asked
for answered the open question and the answer is YES:

> **Z-1 (CONFIRMED, CRITICAL).  The shipped compiler ACCEPTS an unsatisfiable row-constraint
> system.**  Seed `MIN1` below, at the SHIPPED flags, at 20/20 id bases: `Subst.solve` returns
> normally with a substitution, publishing a residual constraint that is false in every model.
>
> **Z-2 (CONFIRMED, CRITICAL).  The same, THROUGH THE BARE-ROW HOLE S1 IDENTIFIES.**  Seed
> `MIN2` (five constraints), 4/20 bases: the Lean instrument shows `makeConcrete` deleting the
> bare `v1 <- ((|l38|))` with `srs` non-empty and nothing in its place, and the compiler then
> accepts with a substitution that puts `l17` in two parts of one whole.  20 such seeds in an
> 11 048-seed sweep at one base; six replayed on the compiler, six accepted.

That does not contradict any theorem in the three new modules — every one of them is
conditional on `SSat (sys s₀)` exactly where it has to be — but it does contradict the plan's
and the report's PROSE, which say (A) is "an accepted program is well-typed".  What S1 proved
is "an accepted **satisfiable** program is well-typed", and the difference is not academic.

---

## 1. Rebuild and re-audit (independent, from a clean checkout of the working tree)

```
cd tracker/lean && export PATH=$HOME/.elan/bin:$PATH
lake build Rowpartition   # Build completed successfully (859 jobs)
lake env lean Audit.lean  # Rowpartition theorems audited: 3804; declarations using a non-standard axiom: 0
lake build looptrace      # Build completed successfully (1662 jobs)
```

| check | implementer | reviewer | agree |
|---|---|---|---|
| `lake build Rowpartition` | 859 jobs | **859 jobs** | yes |
| `lake env lean Audit.lean` | 3804 theorems / 0 | **3804 / 0** | yes |
| `lake build looptrace` | 1662 jobs | **1662 jobs** | yes |
| `sorry` / `axiom` / `partial` / `native_decide` / `unsafe` / `opaque` / `implemented_by` / `admit` / `#exit` in the three new modules | 0 | **0** (the one `admit` hit is the word "admits" in a doc comment, `Sound.lean:53`) | yes |
| `#print axioms` over the new declarations | 63, all `[propext, Classical.choice, Quot.sound]` | **the saved census lists 63 names and 0 non-standard**; the three modules actually declare **77** top-level items, the 14 not censused being pure data/notation defs (`refSeed`, `refSu`, `refNs`, `refQ`, `refSu2`, `refS0`, `isSolvedB`, `isRejectedB`, three `instDecidable*`, and the three `sys` defs that my first count picked up out of a doc comment) | figure differs, substance agrees |
| pre-existing Lean modules unchanged | claimed | **`git diff --stat -- tracker/lean/` is exactly `README.md +23`, `Rowpartition.lean +23`** — every other module byte-identical; `CutSearch` still not imported | yes |

Every Lean statement quoted in `S1-SOUNDNESS.md` was checked against the source and matches
**verbatim**, hypotheses included: `bare_refutes`, `BareAgree`, `bareAgree_of_sat`,
`makeConcrete_noLoss`, `step_noLoss_concrete`, `step_noLoss_all`, `step_noLoss_sat`,
`step_noLoss_or`, `run_noLoss`, `run_models`, `run_ssat_iff`, `run_noLoss_or`,
`NonRefutation`, `step_died_refutes`, `run_rejects_unsat`, `run_rejects_unsat_noSkolem`,
`supFresh_initState`, `solve_sound`, `npS0_sound`, `refS0_refutes`, `destructiveSub_noLoss`,
`makeConcrete_records`, `subPartitions_mem`, `cancellation_singleton`.

---

## 2. THE SOUNDNESS HUNT

### 2.1 Method

*Oracle.*  `review-S1/oracle.py` — the per-label decomposition (`l <- (v₁…v_k, K)` says
`rho[l]` is the disjoint union, so per label `x` the problem is boolean:
`b[l] = Σ b[vᵢ] + [x∈K]` with `Σ ≤ 1`), solved by exhaustive pruned DFS and the returned model
VERIFIED against every constraint before it is reported SAT.  Cross-checked against round 8's
`L5r8/satcheck.py`: identical verdicts on `NP01`, `REF`, `BARE1`, `BARE2`, `TRI` and on the
witnesses below; and cross-checked against the compiler's own printed substitution (see 2.4).

*Pre-filter.*  `review-S1/labelcheck.py` — `Constraints.checkLabel`/`labelClash` as
`Loop/Json.lean:186-246` state them, run to a REAL fixpoint (more passes than the model's
`ps.length + 2` fuel), so "no clash here" implies "the shipped `labelCheckEarly` passes".
Validated against the model on 300 seeds: **300 agree, 0 disagree**.

*Generator.*  `review-S1/gen2.py`, biased at the hole's shape — two bare rows for one
variable (`T1`); the `cancellation` sources that DERIVE them, `a <- (v,K)` + `a <- ((|L|))`
(`T2`); alias/`unify` chains (`T3`); `makeEmpty` erasures (`T4`); and branchy `l <- (x,y)` /
`l <- (x,y,z)` shapes that unit propagation is blind to (`T6`, `T7`) — with label NUMBERS
drawn from a 39-wide pool so that the queue's `rhs.hashCode` order varies, and id bases swept
separately.  Only seeds that are **UNSAT and pass the label check** are kept: those are the
only ones on which a shipped-flag false acceptance can live.

*Yield.*  ~9 M generated systems; 49 139 of the first 60 000 were UNSAT and **49 092 of those
(99.90 %) were caught by `labelCheckEarly` alone** — which is why the naive sweep finds
nothing and why the pre-filter is the whole trick.  11 048 UNSAT + label-passing seeds were
kept and run through the model at the SHIPPED flags at two id bases.

### 2.2 Result: the model returns `SOLVED` on unsatisfiable input, routinely

On the first 400-seed calibration batch (`gen0`, unbiased) the label check caught **253/253**
UNSAT seeds and there was no false acceptance at the shipped flags — but **2** at
`--flags=nolabel`, i.e. the loop alone already accepts.  On the pre-filtered batch the shipped
flags stop being a defence: the first 47 seeds gave **4 distinct shipped-flag `SOLVED` on
UNSAT input** (`u00006`, `u00019`, `u00020`, `u00035`), reproduced at three bases each.  The
full 11 048-seed sweep is in §7: 1 166 shipped-flag `SOLVED` runs on UNSAT input over
665 distinct seeds.

Zero UNSOUND REJECTIONS were found in any batch (input SAT, model REJECTED: **0 / ~23 000
runs**), which is real evidence for (B).

### 2.3 Z-1 — CONFIRMED FALSE ACCEPTANCE in the shipped compiler

`/home/dmitry/.claude/jobs/880c725d/tmp/review-S1/MIN1.json` (minimised from `u00019` by
`review-S1/minimize.py`, which shrinks under "stays UNSAT ∧ still passes the label check ∧ the
model still says SOLVED"):

```json
{"name": "MIN", "cons": [[6,[7,2],[]], [6,[4],[35]], [7,[3,1],[]], [3,[2,0],[]], [1,[0],[22]]]}
```

i.e.

```
v6 <- (v7, v2)          v3 <- (v2, v0)
v6 <- (v4, (|l35|))     v1 <- (v0, (|l22|))
v7 <- (v3, v1)
```

**The input has no model** (hand proof, and both oracles agree, refuting at `l35`):
`v7 <- (v3,v1)` with `v3 <- (v2,v0)` and `v1 <- (v0,(|l22|))` forces `rho0 = ∅` by
disjointness (`rho0` would otherwise appear in both parts); then `rho7 = rho2 ⊎ {l22}`, and
`v6 <- (v7,v2)` forces `rho2 = ∅` the same way, so `rho6 = {l22}`.  But `v6 <- (v4,(|l35|))`
puts `l35` in `rho6`.  Contradiction.  It needs a case split, so `labelCheckEarly`'s unit
propagation does not see it.

**The shipped compiler accepts it, at every base:**

```
ERMINE_JAVA_OPTS="-Dermine.useInterface=false -XX:ActiveProcessorCount=2" \
  tracker/repro/satterm/run.sh sweep json:.../MIN1.json 300 319
SUMMARY bases=300..319 n=20 SOLVED=20 REJECTED=0 HANG=0 OOM=0
```

each base printing

```
SOLVED  v0 := ConcreteRho(-,Set()); v1 := ConcreteRho(-,Set(l22)); v2 := ConcreteRho(-,Set());
        v3 := ConcreteRho(-,Set()); v4 := unbound; v6 := ConcreteRho(-,Set(l22));
        v7 := ConcreteRho(-,Set(l22))   [residual=3
  residual=Exists(-,[],[ Part(ConcreteRho(-,Set(l22)), List(ConcreteRho(-,Set(l22)))),
                         Part(ConcreteRho(-,Set()),    List()),
                         Part(ConcreteRho(-,Set(l22)), List(ConcreteRho(-,Set(l35)), v4^…)) ])]
```

**The label on which the substitution violates the input is `l35`.**  The substitution says
`rho6 = {l22}`, and the input says `v6 <- (v4, (|l35|))`, i.e. `rho6 = rho4 ⊎ {l35} ∋ l35`.
The third published residual is that same constraint after substitution —
`{l22} <- ({l35}, v4)` — a constraint with a CONCRETE left-hand side that is false for every
`v4`, published rather than refuted.  `Subst.solve` never looks at it again: `labelClash` runs
only on the INPUT queue (`Subst.scala:1187`), and `reduce` (`Subst.scala:1071-1123`) only
`instantiateType`s bare-concrete partitions and splices ambiguous ones, dropping everything
else (`case (_, cs) => cs`).

The un-minimised witness is `u00019` (`review-S1/FALSE-ACCEPT-1.json`), also SOLVED at
bases 300-302.

**Scope of the demonstration, stated honestly.**  This is a false acceptance at the level of
`Subst.solve` — which is exactly the level S1's theorems are about, and the level at which the
whole loop model, the replay harness and the plan's (A) are stated.  I did not write an Ermine
source program that produces this constraint system; what is shown is that `solve` returns
normally, binds the variables to a substitution that violates a constraint it was given, and
publishes the violated constraint unchecked.  On `MIN2` (§2.5) the violated constraint is
GROUND after substitution — every variable in it is bound to a concrete row — so there is no
later opportunity for it to become true; on `MIN1` the violated residual
`{l22} <- ({l35}, v4)` still mentions a free `v4`, but it has no model for any value of `v4`.

**This is not the bare-row hole.**  A scratch Lean probe (`review-S1/Probe.lean`, run with
`lake env lean`, no repo file touched) instruments every `concrete` dequeue of the run:
`MIN1`/`u00019` takes exactly one `concrete` step, with `otherBare=0`, so `BareAgree` never
fails.  The loop simply reaches `incm = ∅` — `step` returns `.done` — with an unsatisfiable
residual it never derived a contradiction from.  **The loop is refutation-INCOMPLETE**, and
S1 neither claims nor tests completeness; but "an accepted program is well-typed" is a
completeness statement, not the soundness statement S1 proves.

### 2.4 Z-2 — the bare-row hole IS reachable at the shipped flags, and the report's two
### defences do NOT hold

The report's §Probes concludes "there are TWO defences and both held": `ensureSuperset` at the
other dequeue order and `labelCheckEarly` before the loop.  Both fail on `u00020`
(`review-S1/PANIC-1.json`):

```json
{"cons": [[2,[1],[4]], [2,[],[3,4]], [2,[3,0],[]], [0,[3,1],[]]]}
```

UNSAT (at `l4`; needs a case split), and `labelCheckEarly` **passes** it.  The Lean probe on
the run at the shipped flags, base 300:

```
step 1: CONCRETE v=302 fs={3,4}  otherBare=0 disagreeing=0            srsEmpty=true  keep=true
step 2: CONCRETE v=301 fs={3}    otherBare=0 disagreeing=0            srsEmpty=false keep=false
step 8: CONCRETE v=301 fs={3,4}  otherBare=1 disagreeing=1 {3}        srsEmpty=true  keep=true
DONE at step 9: proc=2 incm=0
```

At step 8 the loop dequeues the BARE row `v1 <- ((|l3,l4|))` while `v1 <- ((|l3|))` sits in
`proc`; `ensureSuperset {l3} {l3,l4}` PASSES (it is `subsetOf`, `Constraints.scala:312`), so
**`BareAgree` is FALSE at a state reachable at the shipped flags from a `buildQueue` initial
state whose per-label propagation has no clash.**  Same at base 301, and the same shape on
`u00006` and `u00035`.  That is a direct answer to §3 of the review brief, and it is the
negative one: the closing theorem the implementer hoped for — "`labelClash` refutes every
input on which the loop reaches the shape" — **is FALSE**, and this is the counter-model.

What saves `NoLoss` on these three seeds is a third mechanism the report does not mention:
`destructiveSub`'s `if ((srs isEmpty) && keep) proc else procd filter p`
(`Constraints.scala:1643-1644`, `Loop/Step.lean:175-177`).  When NOTHING in either queue
mentions `v`, `srs` is empty and **nothing is deleted at all** — the smaller bare row survives,
so the disagreement stays in `sys s'`, which is therefore also unsatisfiable and `NoLoss`
holds vacuously.  The README's new prose ("`makeConcrete` deletes `v <- ((|C|))` for every
`C ⊆ fs`") and `S1-SOUNDNESS.md` §S1.1's fourth table row are therefore **too strong**: the
deletion is conditional on `srs` being non-empty.

On `u00020` the compiler then dies at `Subst.reduce`, which instantiates each bare-concrete
partition (`Subst.scala:1077`) and hits the second one:

```
REJECTED  scalaparsers.Death: panic: reinstantiated type v1^301 to ConcreteRho(-,Set(l3, l4))
          but it was already bound to ConcreteRho(-,Set(l3))
```

at bases 300, 301, 302.  So the last line of defence for the very shape S1 identifies as its
hole is `Subst.reduce`, which S1 declares OUT OF SCOPE ("Nothing in S1 says anything about
it"), and the defence is a **panic**, not a diagnosable type error.  A user meeting this shape
gets an internal-error message with no source location.


### 2.5 Z-2 — CONFIRMED FALSE ACCEPTANCE **THROUGH THE BARE-ROW HOLE ITSELF**

`Z-1` is a saturation incompleteness, not the hole.  Adding ONE partition that MENTIONS the
culprit variable — which is what makes `destructiveSub`'s `srs` non-empty and so disarms the
`srs.isEmpty && keep` guard of §2.4 — drives the run through the deletion S1 names, and the
compiler still accepts.  `review-S1/MIN2.json` (`= review-S1/FALSE-ACCEPT-2.json`, already
minimal under "stays UNSAT ∧ passes the label check ∧ model SOLVED ∧ `reduce` would not
panic"):

```json
{"cons": [[2,[3,0],[]], [3,[0,1],[]], [2,[1],[17]], [2,[],[17,38]], [5,[2,8],[]]]}
```

```
v2 <- (v3, v0)          v2 <- (v1, (|l17|))        v5 <- (v2, v8)
v3 <- (v0, v1)          v2 <- ((|l17,l38|))
```

UNSAT (both oracles, at `l17`); `labelCheckEarly` passes it.  The Lean probe at base 300,
shipped flags:

```
step 2: CONCRETE v=302 fs={17,38} otherBare=0 disagreeing=0     srsEmpty=false keep=true
step 3: CONCRETE v=301 fs={38}    otherBare=0 disagreeing=0     srsEmpty=false keep=false
step 9: CONCRETE v=301 fs={17,38} otherBare=1 disagreeing=1 {38} srsEmpty=FALSE keep=true
DONE at step 12: proc=3 incm=0
```

Step 9 is the hole, exactly as `S1-SOUNDNESS.md` §S1.1 row 4 describes it: `v2` and `v3` have
been folded into `v1` by `common`/`unify`, so `v1` carries BOTH the input's bare row
`((|l17,l38|))` and the `cancellation` of `v2 <- (v1,(|l17|))` against it, `v1 <- ((|l38|))`.
`makeConcrete v1 {l17,l38}` finds `ensureSuperset {l38} {l17,l38}` satisfied, `srs` is
NON-empty (`v5 <- (v2,v8)` mentions the variable), so `keepDefs` is on, the `defs` filter
(`abs.size ≥ 2`) drops the bare row, `cancellation` emits nothing for it — and `{l38}` is gone.

**The compiler accepts:**

```
run.sh sweep json:.../MIN2.json 300 319
SUMMARY bases=300..319 n=20 SOLVED=4 REJECTED=16 HANG=0 OOM=0
SOLVED  v0 := ConcreteRho(-,Set());       v1 := ConcreteRho(-,Set(l17, l38));
        v2 := ConcreteRho(-,Set(l17,l38)); v3 := ConcreteRho(-,Set(l17, l38));
        v5 := unbound; v8 := unbound
```

**The label on which the substitution violates the input is `l17`**: input constraint 3 says
`rho2 = rho1 ⊎ {l17}` with the parts DISJOINT, and the substitution gives
`{l17,l38} = {l17,l38} ⊎ {l17}` — `l17` in two parts of one whole.  The order dependence
(4 of 20 bases) is the signature the report predicts for this hole: which of the two bare
rows is dequeued first is `rhs.hashCode`, and at the other order `ensureSuperset` refuses.

So the answer to the brief's open question is **YES on both counts**: the bare-row hole is
reachable at the SHIPPED flags from a `labelCheckEarly`-passing input, and it makes the
shipped compiler accept an unsatisfiable row system.

### 2.6 Size of the hunt, and how often the hole's shape was exercised

| | |
|---|---|
| systems generated and oracled | ~9 000 000 |
| of those UNSAT | ~7 400 000 |
| UNSAT and caught by `labelCheckEarly` alone | 99.90 % |
| **UNSAT and label-check-passing seeds kept** | **11 048** (+ 1 600 targeted extensions of four witnesses, + 400 unbiased calibration) |
| model runs at the SHIPPED flags | ~27 000 (2-3 id bases per seed) |
| model runs at `--flags=nolabel` | ~1 800 |
| model `SOLVED` on UNSAT input at the SHIPPED flags | **1 166 runs / 665 seeds** (§7) |
| model `REJECTED` on SAT input (unsound rejection) | **0** |
| compiler replays (`run.sh sweep`, one JVM at a time) | 15 invocations, 13 seeds, 1-20 bases each |
| **seeds on which the SHIPPED COMPILER returned `SOLVED` on an UNSAT input** | **10 distinct**: `MIN1`, `u00019`, `MIN2` (= `x00002`), `x00005`, `U11/u00402`, `U12/u00321`, `U14/u00017`, `U15/u00003`, `U16/u01221`, `U11/u00857` |
| … of those, reached through the unlicensed bare-row DELETION | 7 (`MIN2`, `x00005` and the five `U*` seeds) |
| compiler `REJECTED` by a `Subst.reduce` PANIC rather than a diagnostic | `u00020` at 3/3 bases |

The shape counts come from a scratch Lean instrument (`review-S1/Probe2.lean`, run under
`lake env lean`; it re-implements `destructiveSub`'s `srs` computation from the library's own
`subPartitions`, so the instrument is the rule itself) which reports, per run, how many
`concrete` dequeues had a DISAGREEING bare definition of the same variable in the queues
(`BareAgree` fails — the hole's shape) and how many of those had `srs` non-empty (the row is
actually DELETED — the loss).  Numbers in §7.

---

## 3. The closing theorem (brief §3): ATTEMPTED, and it is FALSE

The brief asked for either the state-level fact

> from a `Wf`, `QueueHygiene` state reached from a `buildQueue` initial state whose per-label
> propagation has no clash, the `concrete` branch's bare-row deletion has `C = fs`

or the reachable state where it does not.  **It is the second.**  `MIN2` at base 300 and
`u00020`/`u00006`/`u00035` at bases 300/301 are all such states, exhibited above with the
instrument that computes them from the library's own `subPartitions`.  Concretely, at `MIN2`
step 9 the state `s` satisfies

* `s` is reachable from `initState (buildQueue …)` under `step` at the SHIPPED flags (nine
  steps, no death), so `Wf s` and `QueueHygiene s` hold (`step_wf`, `step_queueHygiene`);
* `labelClash ns q.elems = none` on the initial queue — the per-label propagation has no clash;
* `s.incm.dequeue = some (r, rest)` with `r = v1 <- ((|l17,l38|))`, `r.rhs.abstr.isEmpty`;
* `v1 <- ((|l38|)) ∈ rest.elems ++ s.proc.elems`, so `¬ BareAgree s` with `C = {l38} ≠ fs`;
* `destructiveSub`'s `srs` is NON-empty, so the row is DELETED and nothing replaces it.

So the hoped-for route (b) of `S1-SOUNDNESS.md` §"What I could not prove" item 2 — "a theorem
that `labelClash` refutes every input on which the loop reaches the shape" — **cannot be
proved, because the statement is false.**  `LabelAlgo.checkLabel_clash_unsat` is soundness of
the label check, not completeness, and the gap is exactly the case splits `MIN1`/`MIN2` need.
Route (a) of the same item — "a seed in which the larger bare row is dequeued first AND the
rest of the system stays satisfiable AND the per-label propagation on the INPUT misses it" —
is `MIN2`, found.

The other half of the report's §Probes reasoning is also refuted: "the loop's derivation of a
bare concrete row … is followed label by label by exactly the propagation rules `labelClash`
runs" is true for the DERIVATION but not for the REFUTATION — `labelClash` propagates units
only, and the systems above need a case split on a variable that no unit rule can pin.

What CAN be proved, and would be worth proving, is the positive fact the implementer already
has in a different shape: `BareAgree` holds at every state of a run from a SATISFIABLE input
(`bareAgree_of_sat` composed with `step_sat_all`).  That is the honest statement, and it is
what the theorems already say.

---

## 4. Scala and Lean side by side

Independently re-read (`Constraints.scala` / `Subst.scala` against `Loop/{Step,Rules,Queue}.lean`
and `Loop/Sound.lean`).  The four-row deletion table of `S1-SOUNDNESS.md` §S1.1 is CORRECT
against the Scala on every row:

* `keepDefs` really keeps only `abs.size >= 2` — `Constraints.scala:1660-1662`;
* `cancellation` really emits nothing for a bare definition — `Constraints.scala:1677-1697`,
  both branches need exactly one left-over variable and `abs1 = ∅` / `ys = ∅` kill them;
* `ensureSuperset` really is containment, not equality — `Constraints.scala:312-321`;
* nothing else in the loop records the deleted `C` — `makeConcrete` never calls
  `instantiateType` and the Scala says so itself (`Constraints.scala:1245-1250`).

Two corrections:

* **the table is missing a fifth case** — `if ((srs isEmpty) && keep) proc else procd filter p`
  (`Constraints.scala:1643-1644`, `Loop/Step.lean:175-177`): when nothing mentions `v`,
  NOTHING is deleted.  The Lean lemma `destructiveSub_noLoss` is a disjunction and stays true;
  it is the PROSE (report §S1.1 "the last row"; README "deletes `v <- ((|C|))` for every
  `C ⊆ fs`") that overstates.  This matters because that guard is what makes `u00020`'s
  residual unsatisfiable and so keeps `NoLoss` true there — and it is the difference between
  `Z-1`'s shape and `Z-2`'s.
* **`Subst.solve` does not return `sys s'`** — `Subst.scala:1260` returns
  `Exists(l, [], reduce(l, cs map substType, es, ps))`: the published constraint list is built
  from the ORIGINAL input `cs`, and the loop's residual `ps` is used only to `instantiateType`
  bare-concrete partitions (`Subst.scala:1077`) and to splice ambiguous/existential variables
  (`:1080-1121`); everything else in `ps` is DROPPED (`case (_, cs) => cs`).  So report §S1.4's
  "what the type checker consumes" table is wrong about the artefact, though the theorem it
  cites is fine.

**The death-site table is COMPLETE.**  Every `die` reachable from `incorporateAll` is one of
the seven: `Constraints.scala:341` (merge), `:1158` (selfSubstitution), `:314`
(ensureSuperset), `:1575` (incompatible), `:1587` (skolem), and `Subst.scala:184` reached from
`Constraints.scala:1539` (instantiate) and `:1589` (makeEmpty).  Correctly excluded as
around-the-loop: `Constraints.scala:387`, `:395`, `Subst.scala:1183` (labelClash).  Two sites
the report does not mention: `Constraints.scala:648` (`PQueue.build(v,t)`, dead code, no
callers) and `Subst.scala:1077 → 184` (`reduce`'s `instantiateType` — the one that fires on
`u00020`, covered only by the declared `reduce` scope limit).  One non-`die` throw is not in
the model: `Constraints.scala:463-464`, `pr(graph)`'s `graph.sort(lhs)` is a `Map.apply` that
would raise `NoSuchElementException`, totalised in the Lean as `(g.prioOf? v).getD 0`
(`Loop/Queue.lean:73`) with the invariant argued in a comment and not proved; the Scala
invariant does hold (`Constraints.scala:407-425`), so this is low risk.  On the Lean side
exactly seven `.error` sites are reachable from `step` (Rules.lean:43, 56; Step.lean:89, 132,
136, 138, 187), matching line for line.

`step_link_no_death` (`Loop/Hygiene.lean:1476`) and `queueHygiene_binds_unbound` (`:1438`) are
airtight AS STATEMENTS ABOUT THE MODEL: `instantiate` has exactly one error arm and it tests
`env.contains v`; `QueueHygiene` (`Loop/StrictBound.lean:281`) is
`∀ p ∈ s.parts, ∀ v, s.env.contains v = true → p.involves v = false`; preservation is
`step_queueHygiene` (`:1209`, needs `disjRule = false` + `SupOk` + `SupFresh`, all shipped),
the died case is `:1402`, and it is free at an initial state because `env := {}`
(`queueHygiene_of_env_nil`, `:1353`).  **The transfer to the compiler carries an unstated
assumption** (`Z-6`): `SubstEnv.types` is a long-lived mutable map shared across the whole
type checker (`Subst.scala:182-188`) and `Subst.solve` does NOT `substType` its input before
`PQueue.build` (`:1135`; `substType` is applied only at `:1260`), so at the real entry to
`incorporateAll` the environment is generally NOT empty and the input partitions may mention
already-bound variables.  The report's "free at an initial state (`env := {}`)" (line 280) has
no caveat.

`NonRefutation` (`Loop/Reject.lean:493-495`) is exactly the skolem message and nothing else,
and the Scala raises it only for `v.ty == Skolem` (`Constraints.scala:1587`), after the `nps`
fold and before `instantiateType`, which is the Lean's ordering (`Loop/Step.lean:120-142`).

---

## 5. The theorems' hypotheses: what is discharged, and by what

| theorem | hypotheses | discharged how |
|---|---|---|
| `step_noLoss_all` | `Wf s`; **`BareAgree s`**; `step s = .continue s'` | `Wf` by `wf_of_nodup (by decide)³` at a seed, a hypothesis in general. **`BareAgree` is NOT dischargeable** — §2.4/§3 exhibit reachable states where it FAILS at the shipped flags. Its only discharge is `bareAgree_of_sat`, i.e. `SSat (sys s)` |
| `step_noLoss_or` | `Wf s`; `step` | nothing else — this is the unconditional form, and it is the true one |
| `run_noLoss`, `run_models`, `run_ssat_iff` | `Wf s`; `emptyRow = false`; `disjRule = false`; `cseMints = false`; `RunSupOk n s`; **`SSat (sys s)`** | the three flags ARE the shipped defaults (`Loop/State.lean:356,361,368`); `RunSupOk` by `Supply.runSupOk_of` from `SupOk`+`SupFresh`, both `decide`-able per seed; **`SSat (sys s)` is never discharged, and is exactly the gap `Z-1`/`Z-2` live in** |
| `run_rejects_unsat` | the same, plus `QueueHygiene s` and `¬ NonRefutation s.names m` | `QueueHygiene` free at `env := {}` (but see `Z-6`); the exception is empty on any skolem-free solve (`run_rejects_unsat_noSkolem`, `refNoSkolem`/`npNoSkolem` = `fun _ => rfl`) |
| `solve_sound` | `buildQueue cs su = .ok (q,su')`; three flags; **`Wf (initState …)`**; `SupOk su'`; `SupFresh su' (sys …)` | `Wf` remains a hypothesis (acknowledged; `buildQueue` is not known to produce `Nodup` partitions); `SupFresh` is made `decide`-able by `supFresh_initState`. The first conjunct's own `SSat (sys s₀)` premise is inside the statement and is never discharged |
| `npS0_solved`, `refS0_rejected` | none | `by rfl` — kernel-checked, and `lake build` re-ran them here |
| `npS0_sound` | none stated | but its first conjunct is `… → SSat (sys npS0) → …`, and **nothing in Lean proves `SSat (sys npS0)`**, so the flagship accepted-seed instantiation is a conditional whose antecedent is unproved. (It IS true: my oracle's model for NP01 is `{0:{l0..l5}, 1:∅, 2:{l3}, 3:{l4,l5}, 4:∅, 5:{l0..l6}, 6:{l6}, 7:{l3}, 8:{l0,l1,l2,l4,l5}, 9:{l6}, 10:{l0,l1,l2,l4,l5}}` — **identical, variable for variable, to the substitution the compiler prints**, which is a good independent check of both. Turning it into `theorem npS0_sat : SSat (sys npS0)` by exhibiting that assignment would make `npS0_sound` unconditional and is a small, high-value addition.) |

**Both seed instantiations re-checked on the compiler** (`-Dermine.useInterface=false`,
`-XX:ActiveProcessorCount=2`, one JVM at a time):

| seed | flags | compiler | matches report |
|---|---|---|---|
| `NP01.json` @300 | shipped | `SOLVED in 365 ms  … [bound=24 residual=5 drawn=18]` | yes (drawn=18) |
| `REF.json` @300 | shipped | `REJECTED … Row partitions are unsatisfiable at field 'l1': two parts of one partition both contain it` | yes |
| `REF.json` @300 | `-Dermine.labelCheck=false` | `REJECTED … Fields appear twice in row: Set(l1)` | yes |

---

## 6. Prose, deliverables, and the acceptance criteria

### 6.1 `tracker/ROW-CONSTRAINT-STATE.md`'s new "Soundness" section

Mostly good — it *does* say plainly "what it costs is COMPLETENESS — the loop can turn an
unsatisfiable system into a satisfiable one and then accept", which is exactly right and is
more honest than the plan's own §S1 (A) wording.  Three problems:

* the section heading is "**SOUNDNESS of the row solver's LOOP, proved**" and the (A) heading
  is "**every model of the output is a model of the input**", neither carrying the
  satisfiable-input proviso that the quoted `run_noLoss` right underneath does carry.  A
  reader who reads headings comes away with the unconditional statement;
* "**No input on which the shipped compiler ACCEPTS through this hole was found**" is now
  FALSE — `MIN2`, §2.5.  This sentence must be replaced, not softened;
* "Two probes … show the two defences that are in the way" is FALSE as a general claim —
  neither defence holds on `u00020`/`MIN2` (§2.4).

### 6.2 `tracker/LOOP-MODEL-PLAN.md` S1 row and `tracker/lean/README.md`

The plan's S1 status row is accurate about what was proved and honest about the deficit, but
carries the same now-false clause ("no compiler-reproducible acceptance of an ill-typed
program was found").  The README's new section is accurate except for
"`makeConcrete` deletes `v <- ((|C|))` for every `C ⊆ fs`", which needs the `srs` condition.
Both README rows and the module bullets in `Rowpartition.lean` are otherwise correct.

### 6.3 Acceptance criteria (plan §S1) and the brief's S1.1-S1.5

| criterion | verdict | evidence |
|---|---|---|
| `step_noLoss_all` for all five branches **under `step_refines_all`'s hypotheses** | **PARTIAL** | delivered with an EXTRA hypothesis `BareAgree` (and, to its credit, WITHOUT the flag/supply hypotheses the brief allowed). The extra hypothesis is not a technicality: §2.4/§3 show it fails at reachable shipped-flag states |
| `run_noLoss` | **PARTIAL** | delivered with `SSat (sys s)` added; `run_noLoss_or` unconditional |
| death-site table, every message extracted or on an explicit `NonRefutation` list | **PASS** | seven messages, complete against the Scala (§4); two panics removed by `QueueHygiene`; one exception |
| `solve_sound` from an initial state | **PASS** with `Wf` still a hypothesis (declared) |
| instantiation on two seeds | **PASS** | `npS0_solved`/`refS0_rejected` kernel `rfl`; compiler agrees (§5) |
| audit 0 non-standard axioms, no `sorry` | **PASS** | re-run: 3804 / 0, 0 `sorry` |
| a "Soundness" section in `ROW-CONSTRAINT-STATE.md` | **PASS** on existence, **FIX** on three sentences (§6.1) |
| S1.1 `NoLoss` on the `concrete` branch | **PARTIAL** — proved under `BareAgree`; the brief's own escape hatch ("If a deletion turns out NOT to be entailed, that is a soundness bug: reproduce it on the compiler with a seed and report at once") was NOT taken, and the review has now taken it |
| S1.2 output soundness along a run | **PARTIAL** (same proviso) |
| S1.3 rejection soundness | **PASS** |
| S1.4 `solve_sound` + two seeds + scope limits | **PASS**, with §4's correction that the "what the type checker consumes" table names the wrong artefact |
| S1.5 state it | **PASS** on existence, **FIX** on §6.1 |

### 6.4 Outcome label

The report calls the outcome **P-**.  On the brief's own definitions that is no longer right:
the brief says **(BUG) a deletion or death that is not sound, with a compiler-reproduced
seed** — and `MIN2` is exactly that, a compiler-reproduced seed on which the unlicensed
deletion makes the shipped compiler accept an ill-typed system.  The implementer cannot be
faulted for not finding it (the brief forbade hunting in S1, and said so), but the OUTCOME
LABEL should move to **P- + BUG**: the Lean is right, and the thing it left open turned out to
be a real bug.

---

## 7. Numbers: how often the hole's shape was actually exercised

A scratch Lean instrument (`review-S1/Probe2.lean`) ran the model at the SHIPPED flags over all
**11 048** UNSAT + label-check-passing seeds at base 300, reporting per run the number of
`concrete` dequeues at which a DISAGREEING bare definition of the dequeued variable was in the
queues (`BareAgree` fails — the hole's SHAPE) and how many of those had `destructiveSub`'s
`srs` non-empty (the row is actually DELETED — the LOSS).  `srs` is computed from the library's
own `subPartitions`, so the instrument is the rule.

| | count | of 11 048 |
|---|---|---|
| model verdict `REJECTED` | 10 461 | 94.7 % |
| **model verdict `SOLVED` on UNSAT input** | **587** | **5.3 %** |
| runs that reached the hole's SHAPE (`BareAgree` fails at some `concrete` step) | **2 954** | **26.7 %** |
| runs in which the unlicensed DELETION actually fired (`srs` non-empty at such a step) | **178** | 1.6 % |
| … of those, ending `SOLVED` | **32** | |
| … of those 32, with no `Subst.reduce` panic (so the compiler returns `SOLVED`) | **20** | |
| SOLVED runs that reached the hole's shape | 406 | |
| model `REJECTED` on a SATISFIABLE input, anywhere in the sweep | **0** | |

So "no witness" was never the outcome on offer: the shape was exercised in more than a quarter
of the runs and the deletion in 178 of them.  **Five of the twenty deletion-and-SOLVED seeds
were replayed on the shipped compiler and all five returned `SOLVED`** (`U11/u00402`,
`U12/u00321`, `U14/u00017`, `U15/u00003`, `U16/u01221`, at base 300), plus `MIN2` — six for
six.

Across the whole 22 096-run sweep (11 048 seeds × 2 bases) the model returned `SOLVED` on an
UNSAT input **1 166 times over 665 distinct seeds**.  Classifying every one of those 1 166
(`review-S1/classify-big2.tsv`: rebuild `sys s'`, ask the oracle, ask whether `Subst.reduce`
would panic, ask whether `labelClash` on the RESIDUAL would refute):

| | count | of 1 166 |
|---|---|---|
| `Subst.reduce` would PANIC on two disagreeing bare residual rows (the compiler dies, ugly but safe) | 762 | 65.4 % |
| **no panic — the compiler returns `SOLVED`** | **404** | **34.6 %** |
| the residual system is SATISFIABLE | **0** | 0 % |
| `labelClash` on the RESIDUAL would refute | 1 146 | 98.3 % |
| … would NOT (the fix of §7.1 misses it) | **20 runs / 10 seeds**, all of them `panic=False` | 1.7 % |

**One number deserves emphasis: the residual was UNSATISFIABLE in all 1 166.**  So the hunt
found NO violation of `NoLoss` — `sys s'` being unsatisfiable makes `NoLoss (sys s) (sys s')`
hold vacuously, and every S1 theorem survives every witness in this review intact.  What the
witnesses violate is the informal reading of (A), "an accepted program is well-typed": the
loop stops with `.done` on a system it never refuted, and the constraint it lost at the hole
(`Z-2`) is lost without the loss ever showing up as a `NoLoss` failure.  That distinction is
the single most useful thing this review has to say about the S1 statements: **they are right,
and they are not the property the type checker needs.**

### 7.1 The fix that closes every witness found

`Subst.solve` runs `labelClash` on the INPUT queue only, at either flag setting
(`Subst.scala:1187` and `:1259`, both `q.toList`).  Running the SAME check on the SATURATED
set `ps` catches **all six compiler-confirmed witnesses** — `MIN1` (at `l35`), `MIN2` (at
`l17`), `u00019`, `x00002` and every one of the 32 deletion-and-SOLVED seeds — and **1 146 of
the 1 166** model false acceptances.  The compiler's own comment already says this is sound
(`Subst.scala:1247-1258`, citing `Rowpartition.refute_saturated_sound` /
`tracker/lean/Rowpartition/Saturate.lean`) and records that it was removed again because it
was "measured on both corpora at ZERO additional refutations".  That measurement is a fact
about the corpora, not about the algorithm; this review shows the additional refutations are
not zero in general.  **Recommended fix: run `checkLabels` on `ps` as well as on `q`, and keep
it.**  It is cheap, already proved sound, and it turns every confirmed false acceptance above
into a proper `Row partitions are unsatisfiable at field '…'` diagnostic.

**It is not a complete fix**, and the review is explicit about that: 10 seeds (20 runs) survive
it, and all 10 are `panic=False`, i.e. real compiler acceptances.  One is verified on the
compiler — `U11/u00857.json`, `{"cons": [[5,[2,6,0],[]], [5,[2,4],[1]], [3,[2,1,6],[20]],
[3,[0,4],[]]]}`, UNSAT at `l20`, `SOLVED` at bases 300 and 301 with every variable left
unbound and an 8-partition unsatisfiable residual on which unit propagation still finds
nothing.  Completeness of refutation needs a case split, which no propagation gets; the
realistic target is "refute everything a bounded search refutes", not "refute everything".

A second, narrower repair — and the one that fixes the hole rather than papering over it — is
to make `makeConcrete` refuse `C ⊊ fs` at a BARE definition instead of merely
`ensureSuperset`-ing it: at a bare `v <- ((|C|))` and a concrete instantiation `v := ((|fs|))`,
`C = fs` is forced, so `if (concr.isEmpty || abs.nonEmpty) ensureSuperset else require(concr == fs)`
is sound (it is `bare_refutes`, already proved) and it converts `Z-2` into death-site 7, which
S1 has already shown is a refutation.  That change is small and its soundness is the theorem
`Loop/Sound.lean` already contains.

---

## 8. Findings, ranked

| # | sev | finding |
|---|---|---|
| **Z-1** | **CRITICAL / CONFIRMED** | The shipped compiler ACCEPTS an unsatisfiable row system: `MIN1` (5 constraints), `SOLVED` at 20/20 bases, substitution violates the input at `l35`. Mechanism: the loop saturates (`step = .done`) with an unsatisfiable residual it never refuted; `labelClash` sees only the input (`Subst.scala:1187`) and `reduce` drops non-bare residual partitions (`Subst.scala:1122`). Fix: §7.1. |
| **Z-2** | **CRITICAL / CONFIRMED** | The same, **through the bare-row deletion S1 identifies as its hole**: `MIN2`, `SOLVED` at 4/20 bases, substitution violates the input at `l17`; the Lean probe shows the deleted row is `v1 <- ((|l38|))` at a `concrete` step with `srs` non-empty. 20 such seeds at base 300 in an 11 048-seed sweep; 5 more replayed on the compiler, 5/5 `SOLVED`. This answers the review's open question: the hole IS reachable and IS a false acceptance. Fix: §7.1, second paragraph. |
| **Z-3** | **HIGH / PROSE** | `S1-SOUNDNESS.md` §Probes, `ROW-CONSTRAINT-STATE.md` and the plan's S1 row all assert "no input on which the shipped compiler ACCEPTS through this hole was found … there are TWO defences and both held". Both defences fail on `u00020`/`MIN2` (`ensureSuperset` passes because it is `subsetOf`; `labelCheckEarly` passes because it is unit propagation and the systems need a case split). These sentences must be replaced, and the outcome label moved to **P- + BUG**. |
| **Z-4** | **HIGH / PROSE** | The `concrete` branch's deletion is described unconditionally ("`makeConcrete` deletes `v <- ((|C|))` for every `C ⊆ fs`", README; §S1.1 table row 4). It is conditional on `destructiveSub`'s `srs` being NON-empty (`Constraints.scala:1643-1644`, `Loop/Step.lean:175-177`): when nothing mentions `v`, NOTHING is deleted. That guard is exactly what separates `Z-1`'s shape from `Z-2`'s, and it is why `u00020` ends with an unsatisfiable residual and a `Subst.reduce` PANIC rather than a silent acceptance. The Lean lemma (`destructiveSub_noLoss`, a disjunction) is unaffected. |
| **Z-5** | **MEDIUM** | `Subst.reduce` — declared OUT OF SCOPE ("Nothing in S1 says anything about it") — is in fact the last line of defence for the very shape S1 names, and the defence is `instantiateType`'s **panic** (`Subst.scala:1077 → :184`), an internal-error `Death` with no source location: `u00020` gives `panic: reinstantiated type v1^301 to ConcreteRho(-,Set(l3, l4)) but it was already bound to ConcreteRho(-,Set(l3))` at three bases. Also an eighth message-producing site not in the seven-message census. |
| **Z-6** | **MEDIUM** | The two UNREACHABLE verdicts (messages 3 and 6) rest on `QueueHygiene`, discharged at an initial state only because the model sets `env := {}` (`Loop/Seed.lean:135`). In the compiler `SubstEnv.types` is a long-lived mutable map (`Subst.scala:182-188`) and `solve` does not `substType` its input before `PQueue.build` (`:1135`), so the transfer needs the unstated side condition "no input partition mentions an already-bound variable". `S1-SOUNDNESS.md` line 280 states it with no caveat. |
| **Z-7** | **MEDIUM** | §S1.4's "what the type checker consumes" table names the wrong artefact: `solve` returns `Exists(l, [], reduce(l, cs map substType, es, ps))` (`Subst.scala:1260`) — the published constraint list is built from the ORIGINAL `cs`, and `ps` is used only to `instantiateType` bare-concrete partitions and to splice ambiguous ones. `sys s'` is not what is published. The theorems are unaffected; the reader-facing framing is wrong, and it is the framing a reader would use to look for exactly the bug in `Z-1`. |
| **Z-8** | **LOW** | `npS0_sound`'s first conjunct is conditional on `SSat (sys npS0)`, which nothing in Lean proves, so the flagship accepted-seed instantiation says nothing unconditional. A witness exists (§5) and matches the compiler's own substitution exactly; adding `theorem npS0_sat : SSat (sys npS0)` would make it unconditional. |
| **Z-9** | **LOW** | "the compiler's message is the model's message character for character" (§S1.4) is contradicted two lines above by the model's own `Set(Repro.l1)` against the compiler's `Set(l1)` (`Lbl.toStr` prefixes the module, `Loop/State.lean:53`). Likewise the model truncates both panics — the Scala's is `… but it was already bound to <t>` (`Subst.scala:184`), the Lean's stops at `already bound` (`Loop/Step.lean:89-90, 138-139`) — and the skolem message drops `V.toString`'s `"S"` suffix for skolems (`Vars.scala:110-112`) and `report`'s line break. None of it affects soundness (`NonRefutation` carries `isSkolem v = true`, not just the string), but "character for character" should go. |
| **Z-10** | **LOW** | One Scala throw is not modelled and not in the census: `Constraints.scala:463-464`, `pr(graph)`'s `graph.sort(lhs)` is a `Map.apply` that would raise `NoSuchElementException`; the Lean totalises it (`Loop/Queue.lean:73`, `(g.prioOf? v).getD 0`) with the invariant argued in a comment. The Scala invariant does hold (`:407-425`), so the risk is low, but the census sentence "`step` can die with exactly seven messages" is about `Death`s, not about crashes, and should say so. Also `Constraints.scala:648` (`PQueue.build(v,t)`) is dead code with a `die` in it. |
| **Z-11** | **LOW** | Counting/citation slips: "all 63 new declarations" — the modules declare 77 top-level items, 63 of which are censused (the other 14 are pure data/notation defs); "27 theorems + 5 defs" for `Sound.lean` is 27 + 2; `Rowpartition.lean +27` and `README.md +19` are `+23` and `+23`; `Loop/Step.lean:190` is the doc comment, `def makeConcrete` is at 191; the report carries no `Constraints.scala:NNN` citation at all although its central claims are about `keepDefs`/`cancellation`/`ensureSuperset`; §Probes calls BARE2 "the same two rows" as BARE1 when the seed's own name says `l2`/`l2,l4`, not `l1`/`l1,l2`. Several stale Scala line numbers inside the Lean sources themselves (`Loop/Step.lean:5-6`, `:104`; `Loop/Rules.lean:3-6`) — off by 8-10 lines each. |

---

## 9. VERDICT

### **FIX-THEN-ADVANCE.**

The Lean work is good and I found nothing wrong inside it.  All three modules rebuild, the
audit is clean, there is no `sorry` and no non-standard axiom, every quoted statement is
verbatim, the two seed instantiations are kernel `rfl`s that this review re-ran, the compiler
agrees on both, no pre-existing module was touched, and the death-site census is complete
against the Scala.  (B) really is complete; and the 23 000-run sweep found **zero** unsound
rejections, which is the first empirical evidence for it.  The `BareAgree` proviso is not a
weakness of the proof — it is the correct statement, and this review's job was to find out
what it costs.

Required before S1 is closed:

0. **Nothing in the Lean.**  The theorems survive every witness (the residual was
   unsatisfiable in all 1 166 model false acceptances, so `NoLoss` never actually failed);
   what changes is what the reader is told those theorems mean.
1. **Report `Z-1` and `Z-2` as bugs and file them.**  The plan's own outcome ladder makes this
   **(BUG)**: `MIN2` is "an unsound deletion … with a compiler-reproduced seed".  The seeds are
   `review-S1/MIN1.json`, `review-S1/MIN2.json`, `review-S1/FALSE-ACCEPT-{1,2}.json`,
   `review-S1/PANIC-1.json`; they should move into `tracker/repro/satterm/seeds/` and get a
   ticket.
2. **Correct the three prose claims** (`Z-3`, `Z-4`, `Z-7`) in `S1-SOUNDNESS.md`,
   `tracker/ROW-CONSTRAINT-STATE.md`, `tracker/LOOP-MODEL-PLAN.md`'s S1 row and
   `tracker/lean/README.md`.  In particular every heading that says "soundness … proved"
   must carry the satisfiable-input proviso, and "no input on which the shipped compiler
   ACCEPTS through this hole was found" must be replaced by `MIN2`.
3. **State the `Z-6` side condition** where `QueueHygiene` is discharged.
4. Optional but cheap: `Z-8` (`npS0_sat` from the model in §5), `Z-9`/`Z-11` (message text and
   counting slips).

No Lean change is required to advance.  D1 (termination engineering) can proceed in parallel,
but the row-constraint tracker should get a soundness ticket ahead of it, because `Z-1`/`Z-2`
are ill-typed programs the compiler accepts, and §7.1 gives a fix whose soundness is already a
theorem in this repository.

### Judgement on the open question

**Yes — a false acceptance through the bare-row hole is reachable in the shipped compiler, and
it is not rare.**  With one precision that matters: it is not a `NoLoss` failure.  In all
1 166 model false acceptances the OUTPUT system was itself unsatisfiable, so every S1 theorem
holds on every witness; what fails is the loop's ability to NOTICE, and at the hole the lost
constraint simply happens not to be the one that would have been noticed.  The two defences the report relies on are both incomplete in the same way:
`ensureSuperset` is containment, not equality, so it waves through exactly the `C ⊊ fs` that
the deletion then loses; and `labelCheckEarly` is unit propagation over the INPUT, so any
unsatisfiability that needs a case split — which is the majority of the interesting ones —
walks past it.  Once you generate systems that are unsatisfiable *and* propagation-blind (0.1 %
of random unsatisfiable systems, but easy to make deliberately), the hole's shape appears in
26.7 % of runs, the unlicensed deletion fires in 1.6 %, and 20 seeds in an 11 048-seed sweep
end `SOLVED` with the deletion having fired and nothing downstream to catch it; six of those
were replayed on the shipped compiler and all six were accepted.  `MIN2` is five constraints
long.  What settles the general question — and what I would ask for next — is not another hunt
but the theorem the other way round: *the loop's `.done` state, plus the `reduce` that follows
it, refutes every unsatisfiable input*, which is FALSE as the code stands and becomes provable
after §7.1's change, because `labelClash` on the saturated set is `LabelAlgo`'s fixpoint on a
system in which every bare row is a unit — precisely the fragment where unit propagation IS
complete.  That is a well-shaped D-stage ticket, and it is where the soundness programme
should go next.

---

## Appendix: how to re-run this review

```bash
cd tracker/lean && export PATH=$HOME/.elan/bin:$PATH
lake build Rowpartition && lake env lean Audit.lean && lake build looptrace

S=/home/dmitry/.claude/jobs/880c725d/tmp/review-S1
python3 $S/oracle.py $S/MIN1.json            # UNSAT 35
python3 $S/oracle.py $S/MIN2.json            # UNSAT 17
./.lake/build/bin/looptrace $S/MIN1.json 300 4000 --verdict   # SOLVED  (shipped flags)
./.lake/build/bin/looptrace $S/MIN2.json 300 4000 --verdict   # SOLVED  (shipped flags)
lake env lean $S/Probe.lean                  # the per-`concrete`-step BareAgree/srs instrument

export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:$PATH
ERMINE_JAVA_OPTS="-Dermine.useInterface=false -XX:ActiveProcessorCount=2" \
  tracker/repro/satterm/run.sh sweep json:$S/MIN1.json 300 319   # SOLVED=20 REJECTED=0
ERMINE_JAVA_OPTS="-Dermine.useInterface=false -XX:ActiveProcessorCount=2" \
  tracker/repro/satterm/run.sh sweep json:$S/MIN2.json 300 319   # SOLVED=4  REJECTED=16
```

Scratch inventory: `oracle.py` (exact satisfiability), `labelcheck.py` (`labelClash` to a real
fixpoint), `gen.py` / `gen2.py` (generators), `extend.py` (targeted extension of a witness),
`minimize.py` (witness shrinker), `residual.py` (rebuild `sys s'` from a model run),
`classify.py` (residual satisfiability + would-`reduce`-panic + residual label clash),
`Probe.lean` / `Probe2.lean` (the Lean instruments), `bighunt.tsv`, `exthunt.tsv`, `pa.tsv`
(the shape census), `classify-big2.tsv`.

### Appendix B: the ten compiler-confirmed seeds, verbatim

Each is a `tracker/repro/satterm` `json:` seed (`[lhs, [vars], [labels]]`).  All are UNSAT,
all pass `labelCheckEarly`, and on the base(s) shown the SHIPPED compiler returns `SOLVED`.

```json
MIN1           [[6, [7, 2], []], [6, [4], [35]], [7, [3, 1], []], [3, [2, 0], []], [1, [0], [22]]]
MIN2           [[2, [3, 0], []], [3, [0, 1], []], [2, [1], [17]], [2, [], [17, 38]], [5, [2, 8], []]]
FALSE-ACCEPT-1 [[6, [7, 2], []], [6, [4, 0], [22, 35]], [7, [3, 1], []], [3, [2, 0], []], [1, [0], [22]]]
x00005         [[2, [3, 0], []], [3, [0, 1], []], [2, [1], [17]], [2, [], [17, 38]], [5, [0, 3, 7], []], [8, [7], [17]]]
u00402         [[2, [5], []], [2, [], [12, 17, 32]], [2, [4, 3], [12, 32]], [0, [5, 1], []], [4, [3], []]]
u00321         [[4, [6], []], [6, [5, 2], []], [3, [0, 4], []], [6, [7], [2, 30]], [6, [], [2, 14, 30]], [4, [5, 2], []], [5, [2, 7], []]]
u00017         [[2, [3], [10, 28]], [4, [2, 3], []], [0, [1, 6], []], [4, [6], []], [4, [], [5, 10, 28]], [2, [8, 3], []]]
u00003         [[6, [2], [21]], [6, [], [3, 21, 39]], [6, [5, 8], [39]], [0, [7, 4], []], [8, [5], []], [1, [6, 4], []]]
u01221         [[3, [1], [29]], [5, [1, 3], []], [4, [2, 0], []], [0, [5], []], [0, [], [10, 29, 36]]]
u00857         [[5, [2, 6, 0], []], [5, [2, 4], [1]], [3, [2, 1, 6], [20]], [3, [0, 4], []]]
PANIC-1        [[2, [1], [4]], [2, [], [3, 4]], [2, [3, 0], []], [0, [3, 1], []]]
```
