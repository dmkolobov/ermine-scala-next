# S4 — the projection fan-out cliff: mechanism, model reproduction, and guard vs budget

Stage S4 of `tracker/LOOP-MODEL-PLAN.md`, brief `tracker/loopmodel/briefs/brief-S4.md`, ticket
B5 of `tracker/TICKET-stdlib-findings.md`.  Branch `scala3-migration`, from `0740a7b` (S3 and F1
committed; `rowSound` ON, `dequeuePolicy=smallcanon`, `solveBudget=20000`).  **PART A ONLY** —
no Scala change, no commit.  Part B starts on the orchestrator's go.

Scratch: `/home/dmitry/.claude/jobs/880c725d/tmp/S4/`.

**Round 2, 2026-09-07** — corrected against `tracker/loopmodel/S4A-REVIEW.md` (verdict: ADVANCE
to Part B with changes).  Every correction is listed and dated in **§7**; the affected passages
below carry the corrected numbers, not the round-1 ones.

---

## 0. The finding, restated in one paragraph

`Record.(!) : t <- (r, s) => {..t} -> Field r a -> a` is a row PARTITION, not a lookup.  N reads
`p ! f_1 … p ! f_N` of one record parameter whose row `t` is a variable therefore hand the solver
N partitions with the SAME left-hand side, each with a one-label concrete part and its own fresh
remainder.  The solver closes them under `resolution`, which walks the whole subset lattice of the
N labels, and the number of resolution CALLS — which is the unit the adopted `solveBudget` counts —
is exactly `(5^N − 3·3^N + 2·2^N)/2`, five times bigger for each extra read.  At N = 7 that is
35,910 and a VALID program is rejected with the resource diagnostic.  Writing the row down costs
nothing at all — and a nine-line rewrite that writes it for the programmer takes the whole ladder
to **one draw at every N**, provably losing nothing.

---

## 1. (A1) The constraint system a projection generates — measured, not inferred

Seven probe modules, one body each, `N` reads of one unannotated parameter
(`/home/dmitry/.claude/jobs/880c725d/tmp/S4/probes/ProbeProj{2..8}.e`), traced with
`-Dermine.rowTrace`.  The `scon` block of the `inferImplicitBindingTypes` solve at `(1:1)` — the
solve that infers `projN`'s type — is, verbatim, for N = 3:

```
sin  inferImplicitBindingTypes  ProbeProj3.e(1:1)  suLo=303738  nCs=3  nRows=3
slbl 0 G 1 ProbeProj3 pAlpha   slbl 1 G 1 ProbeProj3 pBeta   slbl 2 G 1 ProbeProj3 pGamma
svar 303734 Free                       -- t, the parameter's row
svar 303735 303736 303737 Ambiguous(Free)   -- c_1 c_2 c_3, the three remainders
scon 0 part v303734|c0|v303737          -- t <- ({pAlpha}, c_1)
scon 1 part v303734|c1|v303736          -- t <- ({pBeta},  c_2)
scon 2 part v303734|c2|v303735          -- t <- ({pGamma}, c_3)
```

So the answer to the brief's question is **yes, exactly**: each read contributes
`Has t f = ∃c. t <- ((|f|), c)`, and the input to one solve of N reads is

>   `t <- ((|f_1|), c_1)`, …, `t <- ((|f_N|), c_N)`
>   — N **lone-abstract** premises at ONE left-hand side, with pairwise **incomparable**
>   (indeed pairwise disjoint singleton) concrete parts, and N pairwise distinct fresh
>   remainders.

Nothing else is in the solve: `nCs = nRows = N`, no class constraint, no concrete row.

### 1.1 The rule that fires at every draw

`Constraints.resolution` (`Constraints.scala:2231`), mirrored at
`tracker/lean/Rowpartition/Loop/Rules.lean:116`:

```
   v <- (x, C)        C \ D ≠ ∅
   v <- (y, D)        D \ C ≠ ∅        z fresh
  ------------------------------------------------
   v <- (z, C ∪ D)    x <- (z, D \ C)   y <- (z, C \ D)
```

Its premises are *precisely* the shape above: two lone-abstract partitions at one variable with
incomparable concrete parts (`L5-TERMINATION.md` §R7.3b).  Every input pair `(i, j)` matches, so
the rule fires at once, and its FIRST conclusion `t <- (z, {f_i, f_j})` is again lone-abstract at
`t` with a strictly bigger concrete part — so it matches again, against every premise whose
concrete part it neither contains nor is contained in.

**The draw is taken before every guard and before the applicability test.**  In `resolution`,

```scala
val z = fresh(...)          //  <-- the id
GenRules.countDraw()        //  <-- D1's budget unit, taken here
val int = concr1 & concr2
val tops = concr1 -- int ; val bots = concr2 -- int
if (tops.isEmpty || bots.isEmpty) Set()          // comparable pair: NOTHING derived, draw spent
else { ... resGuard / resRow / emptyRow lookups ... }   // reuse: NOTHING minted, draw spent
```

So **`drawn` counts pairs COMPARED, not names MINTED**.  That single fact is the whole cliff:
the three adopted keyed guards bound the names and none of them bounds the comparisons.

Measured on the model (`--depth`, §1.4): `nsplit = 0`, `nres = drawn` exactly,
for every N.  Every draw on this shape is a `Resolution` and there is not one split.

### 1.2 The mechanism, as a formula

Write `F = {f_1 … f_N}`.

**(a) The names.**  `resGuard`'s `resolvent(C ∪ D)` lookup asks "does the environment already
contain `t <- (w, C ∪ D)`?", and reuses `w` when it does.  On this shape it always eventually
does, so **the minted vocabulary is about one carrier per subset of F of size ≥ 2** — a name for
the row `t \ S`.  Unlike `nSat` and `D(N)` this one is NOT exact (S4A-REVIEW G-6): the count is
base-dependent and a few carriers appear at left-hand sides other than `t`.

| N | carriers minted (model `--mints`) | `2^N − N − 1` |
|---|---|---|
| 2 | 1 | 1 |
| 3 | 4 | 4 |
| 4 | 11 | 11 |
| 5 | 25 at `t` **+ 3 elsewhere = 28** | 26 |
| 6 | 56 at `t` **+ 2 elsewhere = 58** | 57 |

and the per-carrier-key mint count is **1 everywhere** (`cmax=1 cremint=0 max=0 remint=0` at every
N): `resGuard` is doing its job perfectly.  The pump shape of round 5 does not occur here at all.

**(b) The partitions.**  Consequently the saturated set is exactly the set of partitions
`v_S <- (v_T, T \ S)` for **strictly nested** pairs `S ⊊ T ⊆ F` (`v_∅ = t`, and `v_S` the carrier
of the row `t \ S`; `S = T` would be the self-partition `v_S <- (v_S)`, which is dropped).  The
number of strictly nested pairs is `3^N − 2^N`, and the compiler's own `nSat` column **is that
number, to the digit**:

| N | compiler `nSat` | `3^N − 2^N` |
|---|---|---|
| 2 | 5 | **5** |
| 3 | 19 | **19** |
| 4 | 65 | **65** |
| 5 | 211 | **211** |
| 6 | 665 | **665** |

**(c) The draws.**  A draw is spent on every pair of lone-abstract partitions with a common
left-hand side that the loop compares.  The partitions with left-hand side `v_S` are the `T ⊋ S`,
`2^{N−|S|} − 1` of them, so the number of same-lhs pairs the loop is offered is

```
    D(N)  =  Σ_{S ⊆ F} C( 2^{N−|S|} − 1 , 2 )
          =  ½ Σ_k C(N,k) ( 4^{N−k} − 3·2^{N−k} + 2 )
          =  ( 5^N − 3·3^N + 2·2^N ) / 2
```

**and that is the ladder, exactly.**  Against the compiler's own `-Dermine.rowTrace.draws`
counts for `Present/ProjectionCost.e`:

| N | compiler `drawn` | `D(N)` | growth |
|---|---|---|---|
| 2 | 3 | **3** | — |
| 3 | 30 | **30** | 10.0 |
| 4 | 207 | **207** | 6.9 |
| 5 | 1,230 | **1,230** | 5.94 |
| 6 | 6,783 | **6,783** | 5.51 |
| 7 | **35,910** (`-Dermine.solveBudget=60000`) | 35,910 | 5.29 |
| 8 | **185,727** (`-Dermine.solveBudget=300000`) | 185,727 | 5.17 |
| 9 | — | 947,550 | 5.10 |
| 10 | — | 4,795,263 | 5.06 |

**Seven of seven exact on the compiler** (round 1 treated N = 7 and 8 as formula-only and quoted
the MODEL's 35,958 and E4's 185,848 against them; the review re-ran both with the budget raised
and they are `D(N)` to the digit — S4A-REVIEW §1.4, reproduced here).  At the shipped defaults
N = 7 is rejected at 20,009 draws on a valid program.

**The MODEL, and only the model, draws a shade more, and the excess is id-BASE dependent**
(S4A-REVIEW G-5).  At base 1000 the ladder is 3 / 30 / 207 / 1,276 / 6,794 / 35,958; at base
100000 it is 3 / 30 / 210 / 1,230 / 6,914.  The spread is 0 to **+3.7 %**, not the "+0.13 %"
round 1 quoted from one base.  The mechanism is right — extra draws track extra dequeues, i.e.
pairs re-offered after a requeue — but the magnitude is a property of the base, and there is no
excess at all on the compiler.

**So the cost of one more read is a factor of five (`5^N` dominates), and the budget is a linear
resource.**  The `5` is `4 + 1`: for each of the `C(N,k)` subsets `S` there are about `4^{N−k}`
pairs of proper supersets of it, and `Σ_k C(N,k) 4^{N−k} = 5^N`.  The three terms of `D(N)` are
the three closed forms this shape produces — `5^N` the pairs, `3^N` the saturated set, `2^N` the
subset lattice — which is why no reordering and no dequeue policy changes it: they are counts of
a SET, not of a search.

### 1.3 What the keyed guards catch, and what they miss

| guard | what it needs here | fires? | effect on the ladder |
|---|---|---|---|
| `resGuard` (2026-09-02) | `t <- (w, C∪D)` already present at the EXACT key | yes, constantly | caps the vocabulary at one name per subset (`cmax=1`); **does not stop the draw** (taken first) and **does not stop the lattice from being enumerated** |
| `resRow` (Stage 5, 2026-09-03) | a CONCRETE row `t <- ((|F'|))` | **never** | `t` is an open parameter row: `conc=0` at every N |
| `emptyRow` (Stage 7, default OFF) | `t <- ((|C∪D|))` concrete AND an empty carrier | **never** | same reason |
| `splitConcrete` / `KeyedSplit` | a split | **never** | `nsplit = 0` at every N |

The keyed guards are guards on **minting**; the budget counts **comparisons**.  That gap is
exactly the cliff, and it is why "a name, never silence" already holds here (every subset does get
a name) and the program is still rejected.

**And the same gap explains why every L5 termination instrument reads clean on the cliff.**  The
mint CHAIN is shallow — `maxdepth` is 1, 1, 2, 2, 2, 3 for N = 2…7 at id base 1000 and 1, 1, 2,
2, 3, 3 on the compiler's own ids (it is base-dependent, S4A-REVIEW G-5), and
`Depth.terminates_of_chainRun`'s
`D` and `R` are both tiny — while `remint = cremint = 0` and `keys = 0` say the round-5 pump shape
and the `splitConcrete` key never occur at all.  The cascade is **WIDE, not DEEP**: 2^N − N − 1
names each minted exactly once, at depth ≤ 3, with `(5^N − 3·3^N + 2·2^N)/2` comparisons between
them.  Eight L5 rounds hunted for a shape that mints the SAME key forever; this one mints every
key exactly once and still exhausts a 20,000-draw budget.

This is also the clean explanation of why the PINNED form costs zero.  A written
`r <- ((|f_1..f_N|), o)` puts the top of the lattice in the environment as a HYPOTHESIS, so each
`p ! f_i` is discharged by entailment against it and no resolution is ever offered two
incomparable lone-abstract premises.  E5's reviewer confirmed independently that argument order
buys nothing (`showA` 1,230 vs `showB` 1,233) — because the ladder is a property of the constraint
SET, not of the order it arrives in.

### 1.4 The model reproduces the compiler's ladder BYTE for byte

`looptrace --replay` on the five probe segments (`N = 2…6`, the compiler's own ids and label
hashes):

```
#summary segments=5 replayed=5 skipped=0 hashdiff=0 eqdiff=0 nonpart=0 rejected=0 fuel=0
```

| N | model `drawn` | `steps` | `nsplit` | `nres` | `maxdkey` | `cmax` | `remint` | `keys` |
|---|---|---|---|---|---|---|---|---|
| 2 | 3 | 5 | 0 | 3 | 2 | 1 | 0 | 0 |
| 3 | 30 | 19 | 0 | 30 | 6 | 1 | 0 | 0 |
| 4 | 218 | 71 | 0 | 218 | 14 | 1 | 0 | 0 |
| 5 | 1,269 | 255 | 0 | 1,269 | 30 | 1 | 0 | 0 |
| 6 | 6,790 | 680 | 0 | 6,790 | 62 | 1 | 0 | 0 |

`maxdkey` — the largest number of draws at ONE dequeue key — is **`2^N − 2`**, the number of
non-empty PROPER subsets of `F`: the lattice is not an inference, it is in the instrument.
(Round 1 wrote `2·(2^N − 1)`, which its own table contradicts — S4A-REVIEW G-10 row 4.)
`keys = 0` says no `splitConcrete` key is touched at all, and `cmax = 1` that `resGuard` never
lets a carrier key be minted twice.

Off the CANONICAL seeds (`PROJ<N>.json`, labels renumbered) the same run gives
3 / 30 / 207 / 1,276 / 6,794 / 35,958; the differences from the compiler's own figures (218 vs
207, 1,269 vs 1,276) are the label hash order deciding which incomparable pair the queue offers
first, and are the same few-percent spread E4 (3/33/207/1,243/6,795), E5's `ProjectionCliff.slow`
(0/3/31/207/1,241/6,956) and E5's reviewer (1,230) each measured. **The compiler's own
`-Dermine.rowTrace.draws` figures**, which supersede all of those for `Present/ProjectionCost.e`
itself, are **3 / 30 / 207 / 1,230 / 6,783** for N = 2…6, with the budget reached at N = 7 in
`Present/shouldfail/proj01_seven_reads.e`.

**And the pinned half of the module, re-measured on the current bytes** (loaded as
`Present/Helpers.e` + `ProjectionCost.e` + `ValidationReport.e`, one JVM).  `ProjectionCost.e`
performs **442 solves**, spends **8,254 draws**, and **436 of the 442 draw nothing at all**.
The six that draw are the five unannotated `projN` (3 / 30 / 207 / 1,230 / 6,783 = 8,253) plus
one 1-draw `trySolveOn` at `(140:16)` — the two call sites together.  `proj5Pinned` and
`proj6Pinned` — same bodies, one line of signature — **draw zero**.  (Round 1 reported 8,256
and 3; those came from the whole-`Present` load, where the ambient environment moves the call
site.  `ValidationReport.e(214:14)` moves the same way: **209** loaded with `Helpers.e` alone,
**213** in the full group.  Both are the N = 4 rung — it reads five fields but only four of the
concrete parts are pairwise incomparable.)

The module's SHAPE claim survives the S2/S3/D1/A1 changes; its NUMBERS did not, and the same
sweep as `catalogueMarkdownPinned` fixed them — see §7.

---

## 2. (A2) Where the corpus stands

**The census.** All eighteen groups of `looptrace-corpus.sh`, one JVM per group,
`-Dermine.rowTrace` + `-Dermine.rowTrace.draws=true` (the compiler's own per-solve draw count),
**3,201,992 solve segments** — of which ~975,000 are the stdlib boot counted once per group
(each of the 18 group JVMs re-loads it), so the distinct-solve denominator is nearer 2.2 M
(S4A-REVIEW G-9).  Neither the hit count nor "none in the stdlib" is affected.  For each solve,
from the `scon` block alone: `P` = the largest number of
distinct concrete parts among the LONE-ABSTRACT input partitions at one left-hand side, and
`Pinc` = the largest pairwise-INCOMPARABLE such family, which is the cliff's actual trigger.

| `Pinc` | solves | | `Pinc` | solves |
|---|---|---|---|---|
| 0 | 3,175,577 | | 4 | 4 |
| 1 | 26,384 | | 5 | 4 |
| 2 | 18 | | 6 | 1 |
| 3 | 3 | | 7 | 1 |

**Thirty-one solves in 3.2 million have `Pinc ≥ 2`, and every one of them is in `Present/` or
`Lang/`.**  The stdlib boot (54,199 solves) has none; neither do `Ai/`, `Wide/`, `Time/`,
`Algebra/`, `top/`, `bugs/`, `guide/`, `shouldfail*/`, or `incomplete/` (1,905,368 solves).

**`Pinc` predicts the draws exactly** — this is the ladder read off real code rather than a probe:

| `Pinc` | solves | draws |
|---|---|---|
| 2 | 18 | thirteen 3s, two 4s, two 5s, one 32 |
| 3 | 3 | 30, 30, 30 |
| 4 | 4 | 207, 207, 207, 213 |
| 5 | 4 | 1,230 ×4 |
| 6 | 1 | 6,783 |
| 7 | 1 | budget (20,009) |

**Is N = 5…6 present outside the pinned examples?  N = 5 yes, three times; N = 6 no.**

```
Pinc=7  budget   Present/shouldfail/proj01_seven_reads.e(1:1)      (deliberate negative)
Pinc=6   6,783   Present/ProjectionCost.e(1:1)                     (deliberate example)
Pinc=5   1,230   Lang/RunningState.e(210:13)          <-- ORDINARY CODE
Pinc=5   1,230   Lang/TextTables.e(138:13)            <-- ORDINARY CODE
Pinc=5   1,230   Lang/TextTables.e(174:23)            <-- ORDINARY CODE
Pinc=5   1,230   Present/ProjectionCost.e(1:1)                     (deliberate example)
Pinc=4     213   Present/ValidationReport.e(214:14)   <-- ORDINARY CODE
Pinc=4     207   Lang/FreeReportDsl.e(153:17)         <-- ORDINARY CODE
Pinc=4     207   Lang/TextTables.e(188:9)             <-- ORDINARY CODE
Pinc=4     207   Present/ProjectionCost.e(1:1)                     (deliberate example)
Pinc=3      30   Present/VarianceStyling.e(321:23)    <-- ORDINARY CODE
Pinc=3      30   Lang/ForeignJdk.e(328:3)            <-- ORDINARY CODE
Pinc=3      30   Present/ProjectionCost.e(1:1)                     (deliberate example)
```

So the corpus's own high-water mark in code nobody wrote to demonstrate the cliff is **N = 5,
1,230 draws, 6.2 % of the budget** — and it is reached by three different bindings in two
modules whose subject is text rendering.  One more field in any of them costs 5.5×, two more
costs the module.

**`Lang/TextTables.e` in full, per source line** (the module the brief and `ProjectionCliff.slow`
both cite): 2,291 solves, 2,681 draws, 2,281 of them zero-draw.  The draws live at exactly three
lines — `catalogueMarkdown`'s cell lambda at **138: 1,230**, `catalogueAscii`'s `body` lambda at
**174: 1,233** (1,230 at `174:23` plus 3 at `174:18`), `catalogueCsv`'s at **188: 207** — three
unannotated cell lambdas at N = 5, 5, 4.
`catalogueMarkdownPinned` (lines 151–160), the same table with the lambda's argument annotated
at the concrete row, carries **zero** draws on the current bytes.  Same for
`RunningState.postingMarkdownPinned` (lines 216–223): **zero**, against `postingMarkdown`'s
**1,230** at `(210:13)` — and 1,230 is the same number as both `TextTables` sites, not "three
figures within 1 %": `D(5)` does not depend on what else is in the expression.  All of that is
now corrected in the modules themselves (§7).

**`Pinc`, not `P`, is the trigger.**  `Present/WriterOutputs.e(1:1)` has `P = 4` and `Pinc = 2`
(two of its four concrete parts are contained in others) and draws 32, not 207;
`Lang/ForeignJdk.e(325:19)` has `P = 3`, `Pinc = 1` and draws 33.  A guard keyed on `P` would
fire on shapes that do not have the problem.

**The budget headroom, restated.**  The largest draw count of ANY solve in the whole corpus is
now `Present/ProjectionCost.e(1:1)`'s **6,783 — 34 % of the adopted 20,000** — and the largest
that is not a projection cascade is `Wide/ClaimsExperience.e(207:3)`'s 385.  Per group:

```
Present 6,783 | Lang 1,230 | Wide 385 | incomplete 328 | Algebra 51 | Ai 47 | Time 24
top 10 | shouldfail 10 | shouldfail-controls 10 | Wide-sf 4 | Lang-sf 3 | Time-sf 3
Algebra-sf 1 | Present-sf 1 | boot 0 | bugs 0 | guide 0
```

`tracker/ROW-CONSTRAINT-STATE.md`'s "20,000 is 61× the largest draw count of any solve in the
corpus (328); it never fires anywhere in the corpus" is out of date on both halves and should
be re-stated as **2.9× the largest (6,783), and it fires on one deliberate negative**.

(Housekeeping found on the way: `core/examples/incomplete/.probeC.e` is a TRACKED dot-file that
is a byte-identical copy of `gu05_star_join_4dim_concrete_signature.e`'s solve — it doubles that
328-draw solve in every census.  Not S4's to fix.)

---

## 3. (A3) The three options

### 3.1 Option (i) — the WRITTEN-PARTITION normalisation.  **Recommended.**

**The rule.**  When one left-hand side `v` carries `k` lone-abstract premises
`v <- (c_i, F_i)` whose concrete parts are pairwise INCOMPARABLE and non-empty, replace all `k`
of them by

```
    v <- (c, F)             F = F_1 ∪ … ∪ F_k,  c fresh          (the written partition)
    c_i <- (c, F \ F_i)     for each i                            (the re-expressions)
```

which is the 0-draw form the user could have written, produced for them.  Two side conditions,
both found by measurement and not by taste (§3.1.3): **`k ≥ 3`**, and **`v` must have no
concrete row of its own**.

**Not a new branch inside `resolution` — a rewrite of the input.**  The `k` premises are all in
the solve's INPUT (§1), so the natural home is `PQueue.build` / the top of `Subst.solve`, and
that is where the model prototype puts it.  Two measurements decide this:

* Seeding the top WITHOUT deleting the premises changes **nothing** (`PROJ<N>S.json`, the same
  system plus `v <- (c, F)` and the `k` re-expressions): 30 / 207 / 1,237 / 6,789 against
  30 / 207 / 1,276 / 6,794.  `resolvent(C ∪ D)` is an EXACT-key lookup; it cannot see a
  partition at a bigger key, so the lattice forms anyway.  **"A name, never silence" is not
  enough here: the name has to be findable.**
* Deleting them is legitimate, because the replacement ENTAILS them (`read_of_top`, §3.1.2).

#### 3.1.1 The measured ladder under option (i)

Prototyped in the model behind `--topres` (`Rowpartition/Loop/Main.lean`, DEFAULT OFF, a
command-line switch rather than a `Flags` bit so that no existing proof changes shape while
Part A is still deciding).  `looptrace tracker/repro/satterm/seeds/PROJ<N>.json 1000 --depth`:

| N | draws OFF | draws ON | steps ON | `nres` ON | verdict |
|---|---|---|---|---|---|
| 2 | 3 | 3 (untouched, `k ≥ 3`) | 5 | 3 | SOLVED |
| 3 | 30 | **1** | 4 | 0 | SOLVED |
| 4 | 207 | **1** | 5 | 0 | SOLVED |
| 5 | 1,276 | **1** | 6 | 0 | SOLVED |
| 6 | 6,794 | **1** | 7 | 0 | SOLVED |
| 7 | 35,958 | **1** | 8 | 0 | SOLVED |
| 8 | (185,848) | **1** | 9 | 0 | SOLVED |

The single draw is the introduced carrier, and it is drawn before the loop (`drawn0 = 1`), so
the LOOP draws nothing at all: `nres = 0`, `maxdepth = 0` — **resolution never fires**.  That is
the same 0-work shape `proj5Pinned` reaches by having its row written down, reached without the
annotation.  The ladder is flat in N.

#### 3.1.2 Soundness — an EQUIVALENCE, and which kind

`tracker/loopmodel/S4Top.lean`, **eighteen declarations, all on the three standard axioms**
(`propext`, `Classical.choice`, `Quot.sound`; no `sorryAx`, no `nativeDecide`).  In
`Loop/Strict.lean`'s vocabulary:

* **`NoLoss` holds outright, with no freshness side condition** — `read_of_top`:
  `Sat rho (mk v {c} F) → Sat rho (mk x {c} (F \ C)) → C ⊆ F → Sat rho (mk v {x} C)`.
  Every deleted read is a semantic consequence of the two constraints that replace it.  This is
  the licence to DELETE, and `noloss_of_top` states it as `SEntails G (mk v {x} C)`.
* **`Conserv` holds over the OLD vocabulary, not over the new one**, and that is the honest
  answer to the brief's "entailed, or only satisfiability-equivalent?".  The introduced `c` is
  not free: `top_forced` proves `rho c = rho v \ F` in every model, exactly as
  `ResGuard.resolvent_unique` does for the shipped binary mint.  So the step is a
  **conservative (definitional) extension**, the same status the shipped `resolution` mint
  already has — the existentially closed form `∃c. v <- (c, F) ∧ ⋀_i c_i <- (c, F \ F_i)` IS
  entailed by the reads, but the un-closed form cannot be, because the old vocabulary has no
  name for `v \ F`.
* **Every model extends** — `top_sat` and `reexpr_sat` build the extension explicitly at
  `c := rho v \ F`.  **Round 2 (G-1): those are about the FAMILY, and Part B needs the SYSTEM.**
  Their freshness premises are only `c ≠ v` and `c ∉ {x_i}`, which say nothing about the rest of
  `G`, whereas the shipped mint's `Cut.ResApp` carries `fresh : z ∉ allVars G`.  With that
  premise the whole-system direction follows from the library's own `sModels_setVar`:

  ```
  ssat_rewrite_fwd :  c ∉ allVars G  →  fam ≠ []  →  (∀ p ∈ fam, mk v {p.1} p.2 ∈ G)  →
                      (∀ p ∈ fam, p.2 ⊆ F)  →  (∀ rho, SModels rho G → F ⊆ rho v)  →
                      SModels rho G  →
                        SModels (setVar rho c (rho v \ F)) G
                      ∧ Sat  (setVar rho c (rho v \ F)) (mk v {c} F)
                      ∧ ∀ p ∈ fam, Sat (setVar rho c (rho v \ F)) (mk p.1 {c} (F \ p.2))
  ```

  `F ⊆ rho v` is not an extra assumption (`F_subset_of_reads`).  The file now states everything
  in `setVar` rather than `Function.update` (`setVar_eq_update`), so `sModels_setVar` applies
  without a rewrite at each use.  Round 1 also cited a theorem `ssat_topRewrite_iff` that does
  not exist (G-8); the pair that does the work is `ssat_rewrite_fwd` forwards and
  `reads_of_rewrite` backwards.

* **Which `LoopStrict` constructor is it?  TWO steps, not one** (§5 of `S4Top.lean`) —
  the question the brief asks and round 1 did not answer:

  1. an **additive mint**, shaped exactly like `res : ResStep G G' → LoopStrict G G'`, whose
     application carries `fresh : c ∉ allVars G`.  Its `NoLoss` is free (`topAdd_noLoss`, it only
     inserts); its `SSat` obligation is `ssat_rewrite_fwd`;
  2. then **`drop`**, deleting the k reads, with the `NoLoss` premise discharged by
     `noloss_of_top` — `topDrop` builds the `LoopStrict.drop` application.

  It is **not** `requeue`: that demands `allVars G' ⊆ allVars G` and a genuinely fresh `c` breaks
  it by construction (`topAdd_escapes`).  It is never `weaken`, which `Loop/Strict.lean` exists
  to eliminate.

**No silent weakening**: the rewrite neither refuses a derivation nor accepts a system it
should not — it is model-set equality modulo one forced name.

#### 3.1.3 Termination, and the two side conditions

The rewrite REDUCES `drawn` from `≈ (5^N − 3^N)/2` to `1` on the ladder, and it terminates
trivially: it is a single pass over the input, one mint per left-hand side, before the loop
starts, so `Loop/Depth.lean`'s chain depth `D` and the per-key draw count `R` are both
unaffected (`maxdepth = 0`, `maxdkey = 0` under the flag).  Every existing termination theorem
applies unchanged to the loop that follows, because the loop is the same loop on a smaller
input.

The side conditions were found by running the whole seed suite both ways:

* **without `k ≥ 3`**: `NE6` 3 → **10** draws, `RR` 0 → 1, `W4` 0 → 1.  At `k = 2` the binary
  `resolution` already IS this rule — same two conclusions, same single mint — so firing here
  gains nothing and pre-empts the cheaper `cancellation` path.
* **without the "no concrete row" condition**: `RR` and `W4` are exactly the `resRow` /
  `emptyRow` shapes (Stages 5 and 7), which answer at 0 draws when the left-hand side has a
  concrete row; minting a redundant carrier for `v \ F` costs a draw they do not spend.

**Round 2 correction (G-13): the two conditions' evidence was entangled.**  `RR` and `W4` both
carry a concrete row at the lhs in question AND have only `k = 2` there, so either condition
alone excludes them; the reported "without `k ≥ 3`: RR 0→1, W4 0→1" is only reachable with the
concrete-row condition also off.  **The evidence for `k ≥ 3` is `NE6` alone** (two incomparable
lone-abstract premises at an lhs with no concrete row: 3 → 10 draws without the condition), and
the "no concrete row" condition had NO witness at `k ≥ 3` until the review built one.  That seed
is now tracked as `tracker/repro/satterm/seeds/GROW.json` — three pairwise-incomparable reads at
`t` PLUS `t <- ((|f0,f1,f2,f3|))` — and it draws **0 both ways**: the shipped `resRow` answers it
for free and the rewrite correctly stands aside.

**The seed differential.**  All **27** non-`PROJ` seed files (19 top-level + 7 `unsat/` +
`slow/GU05MIN`) come back identical ON and OFF (round 1 said 26, and `slow/GU05` was not run at
all — G-7).  **Two of those are vacuous**: `--depth` runs `depthRun` UNBUDGETED, so `GU05` and
`GU05MIN` produce no verdict in either mode and their "same" compares two empty strings.  Part B
must run the slow seeds through a budgeted path.  The review added five adversarial
projection-shaped seeds (`GU3`/`GU4`/`GU5`/`GS1`/`GU6`) and re-ran this report's
`PROJ3U1`/`PROJ4U2`/`PROJ3S1`: **eight projection-shaped verdict checks, all preserved**.

**The blast radius on the corpus is 19 solves, not 13 — and the difference is the rule's key**
(G-2).  Re-measured with the PROTOTYPE's own trigger (k counted in PARTITIONS at one lhs,
`pairwiseInc` passing EQUAL parts) against Part B's intended trigger (k counted in DISTINCT
concrete parts):

| trigger | solves that fire |
|---|---|
| k ≥ 3 **partitions** (the Part A prototype) | **19** |
| k ≥ 3 **distinct concrete parts** (Part B's rule) | **13** |

The six extra are duplicate-part shapes the `Pinc` census cannot see —
`Lang/RunningState.e(174:35)` and `(181:41)` (5 draws each), `Lang/DoNotation.e(329:35)` and
`(335:39)` (4), `Lang/TextTables.e(243:19)` and `Present/FulcrumPanel.e(1:1)` (2) — and firing
there is sound but pointless: it spends a draw and deletes three premises on a solve that draws
2.  **Part B keys on the distinct set**, so the blast radius is **13**, every one of them a
genuine projection fan.  (Round 1 quoted 13 in one place and 9 in another; 9 was simply wrong.)
Measured: NONE of the 31 `Pinc ≥ 2` solves has a concrete row at the left-hand side in question,
so the second side condition never excludes a corpus hit — it exists purely to keep out of
`resRow`/`emptyRow`'s way.

#### 3.1.4 Differential consequence (what Part B owes)

A new rule needs a model mirror and a trace record.  Concretely: a `Provenance` /
`Inference` tag (the prototype reuses `.resolution`, which Part B must not); a `GenRules` flag
and its `toString` token so the `--verdict` fingerprint still matches; the mirror moved out of
`Main.lean` into `Loop/Json.lean`'s `buildQueue` (or `Seed.lean`) so `--replay` reproduces it;
and `RowTrace` records for the rewrite so the L2 differential stays byte-exact.

**The `.ei` gate, stated the right way round (G-4).**  Round 1 said the published residual
"changes shape … from `k` separate `Has` constraints to one partition plus `k`
re-expressions".  It is **already** one partition:

```
>> :type proj5
forall (a: rho). (exists (b: rho). a <- ((|pEpsilon, pBeta, pDelta, pAlpha, pGamma|), b))
             => Record a -> String
```

`mkSimplified` collapses the whole 211-partition closure to the single top partition — so the
rewrite does not replace `k` constraints with one; it produces **in one draw the form the
compiler already reaches in 1,230**.  That is an argument FOR option (i) that round 1 did not
make.  The real `.ei` risk is the opposite: whether the `k` re-expressions `c_i <- (c, F \ F_i)`
— pure existentials — survive `mkSimplified` and ADD noise to a residual that is currently one
clean line.  S3 already drops permuted duplicates and the `a <- (a)` tautology; Part B must
measure whether it drops these too, and gate `.ei` ON vs OFF with A1's tooling.

**Three risks Part B must gate, found while prototyping.**
1. **The early per-label refutation reads the INPUT.**  `Constraints.checkLabel` /
   `labelCheckEarly` unit-propagates over the input partitions, and it is INCOMPLETE, so a
   rewrite that is a semantic equivalence can still change what it can see.  Measured on three
   purpose-built projection-shaped seeds (`PROJ3U1`, `PROJ4U2` unsat, `PROJ3S1` sat) the verdict
   is unchanged in all three, but the general fact needs a gate: run the rewrite AFTER the early
   check, or re-run the check on the rewritten set, or prove `checkLabel` invariant under it.
2. **A rejection now costs one id.**  `PROJ3U1`/`PROJ4U2` go `drawn = 0 → 1`: the rewrite spends
   its carrier before the refutation fires.  Harmless, but it shows in every differential.
3. **Blame location.**  The deleted premises carry the `Loc` the user's `p ! f` was written at;
   the replacements must carry them, or the row-constraint blame machinery
   (`tracker/ROW-CONSTRAINT-STATE.md`, the `cut`/`labelCheck` blame-location work) loses the
   site.
4. **The multi-left-hand-side semantics are undefined (G-11).**  `topNormalise` computes the
   candidate left-hand sides ONCE from the original queue and folds over it, rebuilding the
   queue at each step.  Today the introduced `c_i <- (c, F \ F_i)` land at variables that were
   rhs-only, so they are never revisited — but nothing in the code says so, and if a `c_i` were
   itself a later candidate the second rewrite would see a family the input did not have and the
   answer would depend on the fold order.  **Part B defines it as ONE pass over the ORIGINAL
   input families** (never a fixpoint), and Scala and model must agree exactly or the L2
   differential will not be byte-exact.
5. **The key is the DISTINCT concrete parts, not the partition count** (G-2): the prototype's
   `fam.length` counts partitions and its `pairwiseInc` passes equal parts, which fires on six
   corpus solves that draw 2–5 and gain nothing.

### 3.2 Option (ii) — raise the budget.  **Rejected, with the numbers.**

Measured on the compiler (`bin/ermine`, `-Dermine.solveBudget=<n>`, one JVM, `-Xmx2g`):

| N | draws needed | budget that admits it | compiler wall clock |
|---|---|---|---|
| 6 | 6,783 | 20,000 (shipped) | 0.73 s |
| 7 | 35,910 | 60,000 | **2.59 s** |
| 8 | 185,727 | 300,000 | **14.46 s** |
| 9 | 947,550 | 2,000,000 | **99.74 s** |
| 10 | 4,795,263 | 10,000,000 | **843.90 s** (14 min) |

The Lean statement option (ii) would make true is the one already proved and needs no new work:
`Budget.budget_never_accepts` and `runBud_rejects_unsat` hold for EVERY budget value, so raising
it is sound by construction and buys nothing but headroom.

It is rejected on arithmetic FIRST and on wall clock SECOND: **each extra read costs a factor of five**
(§1.2), so a budget chosen to admit N admits N and never N+1.  20,000 admits 6; 100,000 admits
7; 500,000 admits 8; 2.5 M admits 9.  A limit whose purpose is to be a floor under divergence
cannot also be set at five times the largest legitimate solve when "largest legitimate solve"
grows by 5× per field a programmer types.  (Two honest corrections to the brief.  First, the wall clock is NOT the obstacle at N = 7–8:
the compiler does N = 8, 185,848 draws, in **14.46 s** — the brief's "D1 measured ~56 s at
20,000" was a Lean-model figure and a differently shaped solve, and the compiler is far faster
than that here.  The wall arrives at N = 9: **99.74 s for one binding**, and N = 10 takes **843.90 s** — fourteen
minutes, and an 8.5× step for one extra field, i.e. the wall clock is growing FASTER than the
draws (5.06×) because the state grows with them.  At N = 10 the compiler is spending a quarter
of an hour deriving `3^10 - 2^10 = 58,025` partitions and closing 4,795,263 pairs about a lambda
that reads ten fields.  Second, what the budget is protecting against is the divergence the eight L5
rounds actually found; the projection cliff is the one known shape where that protection
rejects a valid program, and moving the limit does not stop it being that shape.)

### 3.2b The cheapest counter-proposal: move `countDraw()` past the applicability test.  **Rejected, with numbers.**

Round 1 did not evaluate it and it is the first thing any reader will suggest: `fresh` must stay
where it is (the comment at `Constraints.scala:2168-2170` requires that, to keep the `Supply`
sequence identical between modes), but `countDraw()` could move below
`if (tops.isEmpty || bots.isEmpty)`.  The budget would then count only the same-lhs pairs whose
concrete parts are INCOMPARABLE.  Subtracting the comparable ones (`3^n − 2·2^n + 1` at each
`v_S`, `n = N − |S|`):

```
    A(N) = D(N) − (4^N − 2·3^N + 2^N) = ( 5^N − 2·4^N + 3^N ) / 2
```

| N | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 10 |
|---|---|---|---|---|---|---|---|---|
| today `D(N)` | 3 | 30 | 207 | 1,230 | 6,783 | 35,910 | 185,727 | 4,795,263 |
| after the move `A(N)` | 1 | 12 | 97 | 660 | 4,081 | **23,772** | 133,057 | 3,863,761 |
| applicable share | 33 % | 40 % | 47 % | 54 % | 60 % | 66 % | 72 % | 81 % |

**It buys ZERO extra reads**: N = 7 is still 23,772 against a 20,000 budget, so the rejected
program stays rejected — and the saving SHRINKS with N (`A/D → 1`, because `5^N` dominates
both), which is the wrong direction for a cliff.  Moving `countDraw()` past all three GUARDS
instead would count mints only, `2^N − N − 1` (120 at N = 7), so the budget would never fire on
this shape — but it would then count exactly what `resGuard` already bounds and stop bounding
the loop's WORK, which at N = 9 is 99.74 s and at N = 10 is 843.90 s.  That trades a false
rejection for an unbounded wall clock, which is §3.3's objection to option (iii).
(S4A-REVIEW §2.1, brute-forced against the poset enumeration for N = 2…8.)

### 3.3 Option (iii) — a per-record cap on resolution partners.  **Rejected.**

Cap the number of lone-abstract partitions at one left-hand side that may participate in
`resolution`.  The Lean statement it would make true is a bound —
`terminates_of_drawsAtMost` instantiated at `k·(k−1)/2` per left-hand side — but the statement
it would make FALSE is the one that matters: `Loop/Strict.lean`'s `NoLoss`, proved for every
`LoopStrict` step as `LoopStrict.no_loss` (`Loop/StrictStep.lean`).  Refusing an applicable
`resolution` is exactly `LoopRel.weaken`, the arbitrary deletion `Loop/Strict.lean` was written
to eliminate, and the system that comes out no longer entails what it entered with.  Either the
cap raises a diagnostic — in which case it is the budget again, with a worse unit, because it
fires on shapes whose closure is cheap — or it does not, and a well-typed program is silently
accepted with an under-derived residual.  That is the "no silent weakening" rule.

### 3.4 Recommendation

**Option (i), behind a flag, default OFF, with the two side conditions of §3.1.3.**  It is the
only one of the three that removes the cliff rather than moving it; the ladder under it is flat
(1 draw at every N, §3.1.1); its soundness is an equivalence with a machine-checked proof on
standard axioms (§3.1.2); its blast radius on the corpus is 13 solves, none of them in the
stdlib (§2, §3.1.3); and it produces, mechanically, the text `Helpers.e` tells people to
write by hand.  Keep the budget exactly where it is: with option (i) in, the corpus's largest
solve stops being a projection cascade and 20,000 goes back to being ~50× the largest.

---

## 4. Build and audit figures

* `tracker/lean`: `lake build` clean before and after; `lake build looptrace` with the
  `--topres` prototype **succeeds, 1,670 jobs**, no error, warnings unchanged (style-linter
  only).  The prototype is confined to `Rowpartition/Loop/Main.lean`; no `Flags` field, no
  change to `Rules.lean` / `Step.lean`, so **no existing proof was touched or repaired**.
* `tracker/loopmodel/S4Top.lean`: `lake env lean ../loopmodel/S4Top.lean` — 11 declarations,
  **11/11 on `[propext, Classical.choice, Quot.sound]`, 0 non-standard axioms, 0 `sorryAx`**
  (`/home/dmitry/.claude/jobs/880c725d/tmp/S4/s4top-axioms.log`).
* Corpus: 18 groups, 3,201,992 solves, one JVM per group,
  `ERMINE_JAVA_OPTS="-Xmx2g -XX:ActiveProcessorCount=2"`, 17 group JVMs at 16–27 s plus
  `incomplete/` per-file at 627 s.  All `.ei` deleted before and after.
* Seed differential: 26 seeds × {OFF, ON}, all `same`.

---

## 5. Reproduction

```
# the ladder on the compiler (7 and 8 hit the budget at the defaults)
bin/ermine /home/dmitry/.claude/jobs/880c725d/tmp/S4/probes/ProbeProj{2..8}.e
# the seeds, transcoded from the scon blocks
tracker/repro/satterm/seeds/PROJ{2..8}.json
#   NOTE: the 1000 is the id BASE, not the fuel -- fuel is the THIRD positional.  The model's
#   draw count is base-dependent (0 .. +3.7 % over D(N)); the compiler's is not.
tracker/lean/.lake/build/bin/looptrace tracker/repro/satterm/seeds/PROJ6.json 1000 --depth
# option (i) prototype
tracker/lean/.lake/build/bin/looptrace tracker/repro/satterm/seeds/PROJ6.json 1000 --depth --topres
# the soundness proof
cd tracker/lean && lake env lean ../loopmodel/S4Top.lean
# the corpus census
/home/dmitry/.claude/jobs/880c725d/tmp/S4/corpus-trace.sh
python3 /home/dmitry/.claude/jobs/880c725d/tmp/S4/census.py <traces>/*.in.tsv.gz
```

---

## 6. State on disk, and what Part A did NOT do

**Uncommitted, in the working tree** (nothing was committed, as the brief requires):

```
 M tracker/lean/Rowpartition/Loop/Main.lean      the --topres prototype, DEFAULT OFF
?? tracker/loopmodel/S4-DESIGN.md                this file
?? tracker/loopmodel/S4Top.lean                  the soundness proof (11 decls, standard axioms)
?? tracker/repro/satterm/seeds/PROJ{2..8}.json   the transcoded ladder seeds
```

**No Scala file was touched.**  All `.ei` produced by the corpus run were deleted
(`find core/examples -name '*.ei' | wc -l` = 0).

**Not done, and why.**

* **The `--topres` prototype lives in `Main.lean`, not in `Loop/Json.lean`'s `buildQueue`.**
  That is deliberate — it keeps the flag out of `Flags` and out of `Rules.lean`/`Step.lean`, so
  no existing proof needed repair while Part A was still deciding.  The consequence is that
  `looptrace --replay` does NOT apply it, so there is no ON-mode corpus differential yet; the
  three measurement paths (`--depth`, `--cycle`, `--mints`) do.  Moving it is Part B's first
  step.
* **The prototype tags its conclusions `.resolution`.**  A real rule needs its own provenance;
  Part B must add one, and a `RowTrace` record.
* **No compiler-side measurement of the ladder UNDER option (i)** — that is Part B by
  definition (no Scala edits in Part A).  The model figure is 1 draw at every N.
* **The plain (`--topres` OFF) model run of `PROJ8.json` did not finish** in ~30 minutes of CPU
  and was killed; N = 8's OFF figure in §3.1.1 is E4's independently measured 185,848, which the
  formula predicts to 0.07 %.  The model is much slower than the compiler on this shape (the
  compiler does N = 8 in 14.46 s), so a full-ladder model run is not the right instrument past
  N = 7.
* **No `core/test`, `perf-bench` or corpus-verdict gate was run**, because nothing shipped
  changed.  Those belong to Part B.

**Part A's outcome: (A-done).**  Mechanism and formula in §1, corpus census in §2,
recommendation **option (i)** in §3.4, with a working model prototype whose ladder is flat.
Awaiting the orchestrator's go for Part B.

---

## 7. Corrections after the Part A review (2026-09-07)

`tracker/loopmodel/S4A-REVIEW.md`, verdict **ADVANCE to Part B with changes**.  Everything the
review found is either fixed above or listed here with where it went.  Nothing in §1's mechanism
or §3.4's recommendation changed; the review's own re-derivation made both stronger.

### 7.1 In this document

| finding | what round 1 said | corrected to |
|---|---|---|
| **G-1** | `top_sat`/`reexpr_sat`/`models_rewrite` are the direction Part B needs | they are about the FAMILY; the SYSTEM direction needs `c ∉ allVars G`, and is now `ssat_rewrite_fwd` (§3.1.2), from the library's `sModels_setVar`.  The file is now stated in `setVar`, and §5 of `S4Top.lean` answers "which `LoopStrict` constructor" — **two steps**: an additive `ResStep`-shaped mint, then `drop` via `noloss_of_top`.  `requeue` is ruled out by `topAdd_escapes` |
| **G-2** | blast radius 13 (§3.1.3) / 9 (§3.1.4) | **19** with the prototype's partition key, **13** with Part B's distinct-part key; the six extra are duplicate-part shapes and Part B does not fire on them (§3.1.3).  The "9" was simply wrong |
| **G-4** | the `.ei` risk is `k` `Has` constraints becoming one partition | backwards: `:type proj5` already prints the single top partition.  The real risk is the `k` re-expressions ADDING noise to a residual that is one clean line (§3.1.4) — and the fact that the compiler already knows the answer is the top partition is an argument FOR option (i) |
| **G-5** | the model's excess over `D(N)` is "+0.13 %" | it is id-BASE dependent, **0 to +3.7 %**, and there is **no excess at all on the compiler** (§1.2).  `maxdepth` is base-dependent too (§1.3).  The reproduction block now says the `1000` is the id BASE, not the fuel (§5) |
| **G-6** | the carrier count is "exactly `2^N − N − 1`" | it is **approximate**: 28 and 58 measured at N = 5, 6 against 26 and 57, some of them at other left-hand sides (§1.2a).  `nSat = 3^N − 2^N` and `D(N)` ARE exact |
| **G-7** | "all 26 seeds identical" | **27** files, and **two of them are vacuous** — `--depth` is unbudgeted, so `GU05`/`GU05MIN` reach no verdict either way (§3.1.3).  Part B runs the slow seeds through a budgeted path |
| **G-8** | cites `ssat_topRewrite_iff` | no such declaration; the pair is `ssat_rewrite_fwd` / `reads_of_rewrite` (§3.1.2) |
| **G-9** | "3,201,992 solves" | 3,201,992 SEGMENTS, of which ~975 k are the stdlib boot counted once per group (§2) |
| **G-10** | `maxdkey = 2·(2^N − 1)`; ProjectionCost 8,256 draws, `(140:16)` 3; TextTables line 174 = 1,231 | `maxdkey = 2^N − 2` (§1.4); **8,254** and **1** loaded with `Helpers.e` alone (§1.4); line 174 totals **1,233** (§2) |
| **G-11** | "prototype detail, not a risk" | the multi-lhs semantics are undefined and fold-order dependent; Part B defines **one pass over the ORIGINAL input families** and mirrors it (§3.1.4, risk 4) |
| **G-13** | `NE6`, `RR`, `W4` are evidence for `k ≥ 3` | only `NE6` is; `RR`/`W4` are excluded by the concrete-row condition whatever `k` is.  The concrete-row condition had no witness at `k ≥ 3` until `GROW.json`, now tracked (§3.1.3) |
| **review §1.4** | N = 7 / N = 8 formula-only | **exact on the compiler**: 35,910 at `-Dermine.solveBudget=60000` and 185,727 at `300000`.  Seven of seven, not five of five (§1.2c) |
| **review §2.1** | not evaluated | the cheapest counter-proposal — move `countDraw()` past the applicability test — is now §3.2b: `A(N) = (5^N − 2·4^N + 3^N)/2`, **23,772 at N = 7**, still over budget, and the saving shrinks with N.  Rejected |
| **review §6.1** | — | the fan does NOT need the reads in one expression: six un-annotated let-bound reads and six un-annotated one-line helpers both draw 6,783, and seven of either is rejected.  Folded into the Part B wild-code gate |

### 7.2 In the tree (one-token corrections, all measured with `-Dermine.rowTrace.draws=true`)

The round-1 figures in the example modules were MODEL runs at one id base and read a few per
cent high; the compiler's own counter says otherwise, and the closed forms say why.

| file | was | now |
|---|---|---|
| `core/examples/Present/ProjectionCost.e` | ladder `3 / 30 / 212 / 1,232 / 6,804`, "steps" column, "roughly SIX TIMES" | `3 / 30 / 207 / 1,230 / 6,783`, a "saturated set" column `3^N − 2^N`, `D(N)` written out, "tends to FIVE times" |
| same, `ValidationReport` note | "222 draws … costs 218 rather than 1,243" | **213** in-group / 209 alone, "rather than 1,230", and it is the N = 4 rung because only four parts are incomparable |
| same, `viaInference`/`viaSignature` | "draw 1 and 3" | together they draw **1** |
| same, three inline comments | "Thirty-three", "one thousand two hundred and forty-three", "six thousand seven hundred and ninety-five" | thirty, 1,230, 6,783 |
| same, the remedy line | "turns 1,232 draws into 0" | 1,230 |
| `core/examples/Present/Helpers.e` | "about six times … 3 / 33 / 207 / 1,243 / 6,795" | "FIVE times … 3 / 30 / 207 / 1,230 / 6,783", with `D(N)` |
| `core/examples/Present/README.md` (×2) | `3 / 30 / 212 / 1,232 / 6,804` | `3 / 30 / 207 / 1,230 / 6,783` |
| `core/examples/Lang/TextTables.e` | "1,241 draws"; `catalogueMarkdownPinned` "**one draw**" ×2 | **1,230**, the same number as the other two five-read sites; the pinned form draws **zero** |
| `core/examples/Lang/RunningState.e` | "1,233 draws, beside … 1,241 and 1,230 … within 1 %"; pinned "one draw" ×2 | **1,230, the same number three times** — `D(5)` does not care what else is in the expression; pinned draws **zero** |
| `core/examples/Lang/README.md` | ladder row `31 / 1,241 / 6,956`, "1,241 / 1,233 / 1,230 … order is not stable" | `30 / 1,230 / 6,783`; the three are equal, and the reorder line no longer quotes a number |
| `core/examples/Lang/ProjectionCliff.slow` | ladder `31 / 1,241 / 6,956`, "steady ~6x", "1,241 draws, 27 per-key mints" | compiler ladder with both closed forms, "tends to 5x", 1,230, N = 7 measured at 35,910 |
| `tracker/ROW-CONSTRAINT-STATE.md` (×3) | "61x the largest draw count in the corpus (328); it never fires anywhere" | re-measured table: largest is **6,783** (2.95x headroom), largest non-projection 385, stdlib 0, and **it does fire**, on a valid program; the "give the diagnostic a code" follow-up is upgraded from cosmetic |

`core/examples/incomplete/.probeC.e` is a TRACKED dot-file that differs from
`gu05_star_join_4dim_concrete_signature.e` only in its `module` line, so it doubles that
328-draw solve in every census.  **Noted, not deleted** — it is somebody's committed probe.

### 7.3 Carried into Part B

`GROW.json` is now `tracker/repro/satterm/seeds/GROW.json` (the first seed exercising the
"no concrete row" condition at `k ≥ 3`).  The review's five adversarial projection seeds and its
three wild-code probes are reproduced in Part B's gates.  The placement question (G-3) is
answered in `tracker/loopmodel/S4-CHANGE.md` §1.
