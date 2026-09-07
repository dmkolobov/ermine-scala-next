# S4 Part A — review

Reviewer pass over `tracker/loopmodel/S4-DESIGN.md` (Part A of brief `briefs/brief-S4.md`),
branch `scala3-migration`, HEAD `4a9ed4b`, working tree as the report leaves it.  Everything
below was **re-run**, not read off the report; where a number of mine differs it is said so and
the input is named.  Scratch: `/home/dmitry/.claude/jobs/880c725d/tmp/review-S4/`.  No file in
the tree was edited; the only `.ei` this review produced (five, under the S4 probe directory)
were deleted, and `find core/examples -name '*.ei'` is 0.

## VERDICT — **ADVANCE to Part B, with changes**

The mechanism is right, the formula is right and is in fact stronger than the report claims, the
corpus census reproduces exactly, and option (i) is the right recommendation: the ladder under it
is flat at 1 draw, its `NoLoss` half is proved outright, and the two side conditions are the right
two.  Options (ii) and (iii) are rightly rejected, and the cheaper alternative the report does not
evaluate — moving the draw past the applicability test — is measured below and **buys nothing**
(N = 7 still exceeds the budget), which strengthens the recommendation rather than weakening it.

What must change before or during Part B is in **§7**.  The two that gate the design rather than
the prose are **G-1** (the Lean proves the extension for the FAMILY, not for the SYSTEM — the
freshness premise the shipped mint carries is missing) and **G-3** (the rewrite's placement
collides with `rowSoundDecide`, DEFAULT ON since 2026-09-06, which the report does not name at
all, and with `solve_accepted_faithful`'s own premises).

---

## 1. The mechanism (claim 1) — CONFIRMED, and re-derived

### 1.1 The constraint system.  CONFIRMED on my own probe trace, verbatim

`ProbeProj3.e` under `-Dermine.rowTrace=<file> -Dermine.rowTrace.draws=true`, the
`inferImplicitBindingTypes` segment at `(1:1)`:

```
sin  inferImplicitBindingTypes  ProbeProj3.e(1:1)  suLo=303176 ... nCs=3 nRows=3
slbl 0 G 1 ProbeProj3 pAlpha    slbl 1 ... pBeta    slbl 2 ... pGamma
svar 303172 Free                 svar 303175/303174/303173 Ambiguous(Free)
scon 0  part v303172|c0|v303175
scon 1  part v303172|c1|v303174
scon 2  part v303172|c2|v303173
sdraw inferImplicitBindingTypes  -  30
```

Exactly N lone-abstract premises at one lhs, pairwise-disjoint singleton concrete parts, distinct
fresh remainders, `nCs = nRows = N`, nothing else.  ✔

### 1.2 The draw is taken first.  CONFIRMED by reading the code

`Constraints.scala:2231` `def resolution`: the `RHS(Single(x), …), RHS(Single(y), …)` pattern is
the only pre-test; inside it

```scala
val z = fresh(...)              // 2236
GenRules.countDraw()            // 2237  <-- the budget unit
val int = concr1 & concr2 ; val tops = ... ; val bots = ...
if (tops.isEmpty || bots.isEmpty) Set()          // applicability test, AFTER the draw
else { resolvent(all) / concRow(all) / emptyRow(all) ... }   // all three guards, AFTER the draw
```

So `drawn` counts **same-lhs lone-abstract PAIRS COMPARED**, not names minted.  ✔
The model draws at the same point — `Loop/Rules.lean:120` `let (z, su) := su.fresh` sits above
both `if tops.isEmpty || bots.isEmpty` and the three guard matches.  ✔
Pairs are enumerated once each: `learnPartitions` (`Constraints.scala:1920-1926`) folds the
dequeued partition over `proc`, so an unordered pair is compared when its second member is
dequeued.

### 1.3 The draws formula, re-derived

At left-hand side `v_S` the saturated set holds one partition per `T ⊋ S`, i.e. `2^{N-|S|} - 1`
of them, so the loop is offered `C(2^{N-|S|} - 1, 2)` same-lhs pairs there.  With `m = 2^{N-k}`
and `C(m-1,2) = (m^2 - 3m + 2)/2`:

```
D(N) = Σ_{S ⊆ F} C(2^{N-|S|} - 1, 2)
     = ½ Σ_k C(N,k) (4^{N-k} - 3·2^{N-k} + 2)
     = ½ [ (1+4)^N - 3(1+2)^N + 2(1+1)^N ]
     = ( 5^N - 3·3^N + 2·2^N ) / 2
```

Independently brute-forced by enumerating the poset for N = 2…8 (scratch): 3, 30, 207, 1230,
6783, 35910, 185727 — identical to the closed form.  ✔

### 1.4 Against the compiler — **7 of 7 exact, not 5 of 5**

Measured myself, one JVM, `ERMINE_JAVA_OPTS="-Xmx2g -XX:ActiveProcessorCount=2"`:

| N | compiler `sdraw` | `D(N)` | compiler `nSat` (solve record col 6) | `3^N − 2^N` |
|---|---|---|---|---|
| 2 | 3 | 3 | 5 | 5 |
| 3 | 30 | 30 | 19 | 19 |
| 4 | 207 | 207 | 65 | 65 |
| 5 | 1,230 | 1,230 | 211 | 211 |
| 6 | 6,783 | 6,783 | 665 | 665 |
| 7 | **35,910** (`-Dermine.solveBudget=60000`) | 35,910 | — | — |
| 8 | **185,727** (`-Dermine.solveBudget=300000`) | 185,727 | — | — |

The report treats N = 7 and N = 8 as formula-only and quotes the MODEL's 35,958 / E4's 185,848
against them.  On the compiler they are **exact**.  The formula is therefore exact on the
compiler for the whole measured ladder, N = 2…8, and the report understates its own result.

At the shipped defaults N = 7 is rejected at **20,009** draws with the resource diagnostic, on a
valid program.  ✔

The carriers and the saturated-set forms are also confirmed: `nSat` is `3^N − 2^N` to the digit
on the compiler's own solve record; carriers are discussed in **G-6**.

### 1.5 The "+0.1 % excess" — see **G-5**.  It is a MODEL artefact and it is not 0.1 %.

---

## 2. The guards (claim 2) — CONFIRMED, plus the cheaper-alternative measurement

`looptrace tracker/repro/satterm/seeds/PROJ5.json 1000 --mints` (note: the `1000` is the id
**base**, not the fuel — see G-5):

```
mints  SOLVED  steps=227  drawn=1276  max=0  remint=0  cmax=1  cremint=0  keys=0
cycle  SOLVED  ...  conc=0  maxmint=28
depth  SOLVED  ...  nsplit=0  nres=1276  maxdkey=30
```

* `cmax=1`, `cremint=0` — `resGuard` never lets a carrier key be minted twice: the vocabulary is
  capped and the draws are not.  ✔
* `conc=0` — no concrete row anywhere, so `resRow` and `emptyRow` cannot fire.  ✔  (The compiler's
  `solve` record shows `conc=true`, but that column tests whether any concrete part is non-empty,
  not whether the lhs has a concrete row; the two instruments are not the same and the report's
  "`conc=0` at every N" is the model's.)
* `nsplit=0`, `keys=0` — no split, no `splitConcrete` key touched.  ✔
* Effective flags on this path, from `--verdict`:
  `cut+label-early+resguard+splitkey+splitrow+resrow+rsbare+rssat+rsdecide+pol:smallcanon+budget:20000`.

### 2.1 The cheaper alternative the report does not evaluate — MEASURED

**Would moving `countDraw()` past the applicability test change the budget accounting, and by
how much?**  `fresh` can stay where it is (the code comment at 2168-2170 already requires that,
to keep the `Supply` sequence identical), so this is a one-line, semantics-free change.  The
budget would then count the same-lhs pairs whose concrete parts are INCOMPARABLE.  Counting the
comparable ones at `v_S` (strictly nested `T_1 ⊊ T_2`, both `⊋ S`) gives `3^n − 2·2^n + 1` with
`n = N−|S|`, and summing:

```
A(N) = D(N) − (4^N − 2·3^N + 2^N) = ( 5^N − 2·4^N + 3^N ) / 2
```

Brute-forced against enumeration for N = 2…8:

| N | draws today `D(N)` | draws after the move `A(N)` | applicable share |
|---|---|---|---|
| 2 | 3 | 1 | 33 % |
| 3 | 30 | 12 | 40 % |
| 4 | 207 | 97 | 47 % |
| 5 | 1,230 | 660 | 54 % |
| 6 | 6,783 | 4,081 | 60 % |
| 7 | 35,910 | **23,772** | 66 % |
| 8 | 185,727 | 133,057 | 72 % |
| 10 | 4,795,263 | 3,863,761 | 81 % |

**It buys ZERO extra reads.**  N = 7 is still 23,772 against a 20,000 budget, so the rejected
program stays rejected; and the saving SHRINKS with N (`A/D → 1`, because `5^N` dominates both),
which is the wrong direction for a cliff.  Both series still grow ×5 per read.

Moving `countDraw()` past all three guards instead — counting MINTS only — gives `2^N − N − 1`
(120 at N = 7, 247 at N = 8, 1,013 at N = 10), so the budget would never fire on this shape.  But
it would then be counting exactly what `resGuard` already bounds (`cmax=1`) and would stop
bounding the loop's WORK: my N = 9 run spends **108 s** minting ~502 names, and the report's
N = 10 spends 844 s minting ~1,013.  That trades a false rejection for an unbounded wall clock,
which is the same objection §3.3 raises against option (iii).

**Both rejected.  The report's option (i) survives the comparison, and the comparison is worth
adding to §3 — it is the cheapest thing anyone will propose in review and it does not work.**

---

## 3. The corpus census (claim 3) — CONFIRMED, re-run from the saved traces

I re-ran `census.py` over all 18 `*.in.tsv.gz` in `tmp/S4/corpus/traces/`:

* **3,201,992 solve segments** ✔
* Pinc histogram **0: 3,175,577 / 1: 26,384 / 2: 18 / 3: 3 / 4: 4 / 5: 4 / 6: 1 / 7: 1** ✔ —
  31 solves with `Pinc ≥ 2`, every one in `Present/` or `Lang/` ✔
* The three N = 5 sites outside the pinned examples, at 1,230 each ✔ —
  `Lang/RunningState.e(210:13)`, `Lang/TextTables.e(138:13)`, `Lang/TextTables.e(174:23)` — and I
  re-measured them on the compiler directly (Helpers + TextTables + RunningState, one JVM):
  1230 / 1230 / 1230, plus `TextTables.e(188:9)` at 207.  ✔
* Corpus max draws **6,783** at `Present/ProjectionCost.e(1:1)`; largest non-projection
  `Wide/ClaimsExperience.e(207:3)` at **385**.  ✔
* `catalogueMarkdownPinned` (TextTables 150-160): **0 draws**, against the module's own
  "1 draw" at line 68.  ✔ Correction stands.
* `core/examples/incomplete/.probeC.e` is TRACKED (`git ls-files`) and differs from
  `gu05_star_join_4dim_concrete_signature.e` only in the `module` line, so it doubles that
  328-draw solve in every census.  ✔ Correction stands.
* `ROW-CONSTRAINT-STATE.md:202-203` ("20,000 is 61x the largest draw count of any solve in the
  corpus (328); it never fires anywhere in the corpus") is stale on both halves.  ✔ It is 2.95×
  6,783, and it fires on `Present/shouldfail/proj01_seven_reads.e`.
* `Present/ProjectionCost.e`: **442 solves, 436 zero-draw**, ladder 3/30/207/1230/6783.  ✔
  (My total is 8,254 not 8,256 — see G-10.)

---

## 4. Option (i) — the normalisation (claim 4)

### 4.1 The prototype and its ladder — CONFIRMED

`looptrace PROJ<N>.json 1000 --depth [--topres]`:

| N | OFF | ON | steps ON | `nres` ON | verdict |
|---|---|---|---|---|---|
| 2 | 3 | 3 (untouched, `k ≥ 3`) | 5 | 3 | SOLVED |
| 3 | 30 | **1** | 4 | 0 | SOLVED |
| 4 | 207 | **1** | 5 | 0 | SOLVED |
| 5 | 1,276 | **1** | 6 | 0 | SOLVED |
| 6 | 6,794 | **1** | 7 | 0 | SOLVED |
| 7 | 35,958 (report) | **1** | 8 | 0 | SOLVED |
| 8 | (185,848, E4) | **1** | 9 | 0 | SOLVED |

Identical to §3.1.1.  `drawn0 = 1` and `maxdepth = 0` at every N ≥ 3: the loop itself draws
nothing.  ✔

### 4.2 "The name must be findable" — CONFIRMED, and the reason is in the code

`findResolvent` (`Constraints.scala:1833-1836`) matches `case Partition(u, RHS(Single(w), con), _)
if u == v && con == k` — an EXACT equality on the concrete part.  A partition at a bigger key is
invisible to it, so seeding the top without deleting the reads cannot suppress the lattice.
Measured on `PROJ<N>S.json`: **30 / 207 / 1,237 / 6,789** against 30 / 207 / 1,276 / 6,794.  ✔
The report's conclusion is right and its reason is the right reason.

### 4.3 The side conditions

* **`k ≥ 3`.**  I read the seeds.  `NE6` has exactly two pairwise-incomparable lone-abstract
  premises at lhs 0 (`[0,[1],[2,3,4]]` and `[0,[4],[1,4]]`; the other three at lhs 0 are
  multi-abstract) and no concrete row there, so dropping `k ≥ 3` would fire on it — the reported
  3 → 10 is consistent with the seed's contents.  PLAUSIBLE, not independently re-run (turning
  the condition off needs a model rebuild, which is outside a review's remit here).
* **`RR` and `W4` are NOT evidence for `k ≥ 3`.**  Both carry `[0,[],[1,2,3]]` — a concrete row
  at the same lhs — so the second side condition excludes them whatever `k` is; and both have
  only `k = 2` at that lhs.  The report's "without `k ≥ 3`: RR 0→1, W4 0→1" can only have been
  measured with the concrete-row condition ALSO off, i.e. the two experiments are not independent.
  See **G-13**.
* **"no concrete row" was untested at `k ≥ 3`** — no seed in the suite has three pairwise-
  incomparable lone-abstract premises AND a concrete row at the same lhs.  I built one
  (`review-S4/seeds/GROW.json`).  Result: **0 draws OFF, 0 draws ON** — the shipped `resRow`
  answers it for free and the rewrite correctly stands aside.  The condition is right; it now has
  a witness.  Hand `GROW.json` to Part B.

### 4.4 The 26-seed differential — CONFIRMED with one caveat

I re-ran **all 28 non-PROJ seed files** (19 top-level + `slow/GU05` + `slow/GU05MIN` + 7
`unsat/`) ON vs OFF through `--depth`, 300 s per side: **28 SAME, 0 DIFF**.  ✔  Two notes:
* the report's suite is 27 files, not 26 (`slow/GU05` excluded) — **G-7**;
* **`GU05` and `GU05MIN` both come back EMPTY on both sides** in my run, and `GU05MIN` is empty
  on both sides in the report's own `topres2.log` too.  The `--depth` path runs UNBUDGETED
  (`depthRun fuel st0`, fuel defaulting to 100,000 steps and no `solveBudget`), so the two slow
  seeds produce no verdict at all in either mode and their "same" is a comparison of two empty
  strings.  The slow seeds tested nothing.

I added five adversarial projection-shaped seeds of my own
(`review-S4/seeds/GU3,GU4,GU5,GS1,GU6.json`: reads plus a contradictory re-expression, a
contradictory link, a consistent double re-expression, a SAT control, and a k = 5 unsat).
**Verdicts preserved in all five**; draws 3→4, 6→2, 208→4, 32→2, 3→2.  Together with the
report's `PROJ3U1`/`PROJ4U2`/`PROJ3S1` (which I also re-ran: REJECTED/REJECTED/SOLVED both ways,
`drawn` 0→1, 0→1, 3→1) that is eight projection-shaped verdict checks, all clean.

### 4.5 The Lean — elaborates clean, but proves less than Part B needs

`cd tracker/lean && lake env lean ../loopmodel/S4Top.lean`: **11/11 declarations on
`[propext, Classical.choice, Quot.sound]`**, no `sorryAx`, no error.  ✔
`lake build looptrace`: **Build completed successfully (1,670 jobs)**, style-linter warnings only,
prototype confined to `Main.lean`.  ✔

**Are they the right statements?**

* `read_of_top` — `Sat rho (mk v {c} F) → Sat rho (mk x {c} (F \ C)) → C ⊆ F → Sat rho (mk v {x} C)`.
  Yes: this is exactly `NoLoss`'s obligation for the deleted premises, with `C = F_i ⊆ F = ⋃F_j`
  discharged by construction, and `noloss_of_top` lifts it to `SEntails G`.  It is the licence to
  delete and it is proved with no side condition.  ✔
* `top_forced` — `rho c = rho v \ F`.  Yes: it is `ResGuard.resolvent_unique`'s k-ary analogue,
  and it is what makes the introduction definitional rather than arbitrary.  ✔
* `top_sat` / `reexpr_sat` / `models_rewrite` — these are the direction Part B actually needs, and
  they are stated about the FAMILY, not the SYSTEM.  See **G-1**.  The freshness premises are
  `c ≠ v` and `c ≠ x_i` only; the shipped mint's `ResApp` (`Cut.lean:874`) carries
  `fresh : z ∉ allVars G`.  Without that, `SSat G → SSat G'` does not follow, and that is the
  obligation `LoopStrict.sat` discharges for every existing constructor.

**Which `LoopStrict` constructor is it?**  The report does not answer the brief's question; the
answer is **two steps, not one**:

1. an ADDITIVE mint step, shaped exactly like `res : ResStep G G' → LoopStrict G G'` — a new
   constructor with a `TopResApp` carrying `fresh : c ∉ allVars G`; its `no_loss` is
   `NoLoss.of_subset` (it only inserts), its `sat` is the lemma G-1 asks for;
2. then `drop : G' ⊆ G → NoLoss G G' → LoopStrict G G'` deleting the k reads, with the `NoLoss`
   premise discharged by `noloss_of_top`.

`requeue` will **not** do — it demands `allVars G' ⊆ allVars G`, which a fresh `c` breaks by
construction (`ResStep.escapes` is the same observation) — and `weaken` is precisely what
`Loop/Strict.lean` exists to eliminate.  Stating it as two steps is what keeps
`LoopStrict.no_loss` and `LoopStrict.sat` mechanical.

**What `Conserv` "over the old vocabulary only" costs the S2 chain.**  `solve_accepted_faithful`
(`Loop/NoFalseAccept.lean:1025`) is stated with ONE `q`, from `buildQueue cs su0 = .ok (q, su1)`,
and that same `q` appears in `hearly` (`labelClash ns q.elems`), in `hbud`
(`labelDecide (q.elems ++ envFacts) …`) and in `initState q su1 …`.  So:

* if the rewrite happens inside `buildQueue` (the report's stated plan, and where the model mirror
  must live for `--replay`), `q` becomes the REWRITTEN queue and the theorem's conclusion is about
  a system with a name the user's program does not have.  Repairing it needs BOTH directions over
  the whole system: rewritten-`SSat` → original-`SSat` is `reads_of_rewrite`/`read_of_top` and is
  already there; original-`SSat` → rewritten-`SSat` is the missing G-1 lemma.
* if the rewrite happens AFTER `decideLabels()` and before `q.expand`, the theorem's subject stays
  the user's own input and nothing in the S2 chain changes — but then the model mirror is no
  longer in `buildQueue` and `--replay` needs it at the matching point.

These two pull in opposite directions; **Part B must choose explicitly and gate the choice**
(see G-3).

---

## 5. Options (ii) and (iii) (claim 5) — AGREE

Reproduced on the compiler, no trace, `-Xmx2g -XX:ActiveProcessorCount=2`, baselined against the
same JVM at N = 2 (14.97 s total wall, of which ~14 s is the Prelude load):

| N | budget | total wall | incremental | report |
|---|---|---|---|---|
| 6 | 20,000 | 15.46 s | +0.49 s | 0.73 s |
| 7 | 60,000 | 17.02 s | +2.05 s | 2.59 s |
| 8 | 300,000 | 27.62 s | +12.65 s | 14.46 s |
| 9 | 2,000,000 | 124.5 s (module import **108.4 s**) | — | 99.74 s |

Same magnitudes throughout; mine are ~15-20 % lower because I ran without `-Dermine.rowTrace`
(the report's runs wrote 26+ MB traces).  I did not run N = 10 (14 min).

**AGREE that a budget raise cannot keep pace**, and the arithmetic reason is the one that matters:
`D(N+1)/D(N) → 5`, so a budget chosen to admit N admits N and never N+1.  20,000 admits 6;
60,000 admits 7; 300,000 admits 8; 2 M admits 9.  The report's honest correction to the brief —
that the wall clock is NOT the obstacle at N = 7-8 and only arrives at N = 9 — is confirmed.

**AGREE that a cap breaks `NoLoss`.**  Refusing an applicable `resolution` is `LoopRel.weaken`
verbatim, and `Loop/Strict.lean:594` (`∃ G G', LoopRel G G' ∧ ¬ NoLoss G G'`) is the theorem that
says so.  Nothing to add.

---

## 6. Part B risks (claim 6)

The report names three (plus a prototype detail).  Risks 2 and 3 are confirmed as stated:
`PROJ3U1`/`PROJ4U2` do go `drawn = 0 → 1`, and the blame `Loc`s do have to move onto the
replacements.  Risk 1 is **incomplete** (G-3) and the `.ei` risk is stated **backwards** (G-4).
Two more the report misses are G-3 and G-11.  The `--replay` point the brief raises is
acknowledged by the report itself (§6) and is correct: `replayMain` never reaches the positional
parsing, so `--topres` is invisible to it and there is no ON-mode corpus differential yet.

### 6.1 The wild-code gate the user added to the brief — ALREADY ANSWERED, on the compiler

The user's Part B addition asks whether an un-annotated CHAIN over a wide input produces the fan.
Two probes (`review-S4/probes/`), one JVM each:

| probe | shape | draws |
|---|---|---|
| `ProbeWildLet.e` | six un-annotated **let-bound** reads of one parameter, used together | **6,783** |
| `ProbeWildChain.e` | six un-annotated **top-level one-line helpers**, all applied at one use site | **6,783** |
| `ProbeWildChain7.e` | the same with a **seventh** helper | **REJECTED at 20,009** |

Both wild shapes are `D(6)` exactly — the same cliff, from the same fan.  **The reads do not have
to be in one expression**: six generalised one-line helpers over a shared row reach the cliff and
seven break the module at the shipped defaults.  That answers the user's question before Part B
starts; the 25-column relation chain is still worth building as a realistic gate, but the answer
is already "yes, it produces the fan".

---

## 7. Findings, ranked

### G-1 — CONFIRMED, blocks Part B's Lean.  The proof is about the family, not the system.

`S4Top.lean`'s `models_rewrite`/`top_sat`/`reexpr_sat` require only `c ≠ v` and `c ≠ x_i`.  The
shipped mint's `ResApp` carries `fresh : z ∉ allVars G`.  Without it, `SSat G → SSat G'` — the
obligation `LoopStrict.sat` needs for a new constructor, and the direction
`solve_noFalseAccept`'s completeness half needs — does not follow: `Function.update rho c …`
can break any constraint of `G` that mentions `c`.

**Closeable cheaply, and I closed it.**  `review-S4/GapCheck.lean` states and proves
`ssat_rewrite_fwd` — whole system, premise `c ∉ allVars G`, using the library's own
`sModels_setVar` (`Divergence.lean:227`) for the untouched part and S4Top's two halves for the
new constraints.  `lake env lean` accepts it: `[propext, Classical.choice, Quot.sound]`, 0
non-standard axioms.  Also proved there: `setVar_eq_update`, because S4Top writes the extension
with `Function.update` while the whole library uses `setVar` — Part B should switch to `setVar`
so `sModels_setVar` applies without a rewrite at every use.

### G-2 — CONFIRMED.  The blast radius is **19 solves, not 13** (and §3.1.4 says 9).

The prototype's `fam` counts PARTITIONS at `v` (`ps.filter isFam`, then `fam.length < 3`), and
its `pairwiseInc` passes equal parts (`c.eqv d || !(c.subsetOf d)`).  The census counts DISTINCT
concrete parts.  Running the prototype's own trigger over the 18 saved corpus traces (k ≥ 3
partitions at one lhs, all pairwise incomparable-or-equal, no concrete row at that lhs):

```
19 solves.  The 13 with Pinc >= 3, PLUS six duplicate-part shapes the census does not see:
   k=3 draws=5  Lang/RunningState.e(174:35)      k=3 draws=5  Lang/RunningState.e(181:41)
   k=3 draws=4  Lang/DoNotation.e(329:35)        k=3 draws=4  Lang/DoNotation.e(335:39)
   k=3 draws=2  Lang/TextTables.e(243:19)        k=3 draws=2  Present/FulcrumPanel.e(1:1)
```

The last two are not even in the report's `Pinc ≥ 2` list.  `Present/ValidationReport.e(214:14)`
is `k = 5` for the prototype and `Pinc = 4` for the census, for the same reason.  Firing there is
sound (equal parts give equal re-expressions, both denoting `v \ F_i`) but it spends a draw and
deletes three premises on a solve that draws 2.  The report calls this "prototype detail, not a
risk in itself"; it moves the measured blast radius by 46 %.  Part B must key on the distinct set
(as the report itself says) **and re-measure** — and the report's own two figures, 13 in §3.1.3
and 9 in §3.1.4, should be reconciled.

### G-3 — CONFIRMED, and MISSED by the report.  Three input-reading checks, not one; two of them DEFAULT ON since 2026-09-06.

`Subst.scala:1301-1305`, in order:

```scala
if (GenRules.labelCheckEarly) checkLabels(q.toList.map(_.tup))   // unit propagation, incomplete
if (GenRules.rowSoundDecide)  decideLabels()                     // COMPLETE per-label decision,
                                                                 //   liveInput = q + env facts,
                                                                 //   budgeted, no-verdict escape
var ps = q.expand.toList
if (GenRules.rowSoundSat)     checkSaturated(ps.map(_.tup))      // unit propagation on the CLOSURE
```

`rowSoundDecide` and `rowSoundSat` are both DEFAULT ON (`Subst.scala:1191`; confirmed live in the
`--verdict` fingerprint: `+rsbare+rssat+rsdecide`).  The report's risk 1 names only the first.

* `decideLabels` is the S2 no-false-acceptance layer.  Under the rewrite it would decide a system
  with one more variable, `k+1` constraints instead of `k`, and one large concrete part instead of
  `k` singletons.  Its escape on budget exhaustion is a **no-verdict**, i.e. a silently missed
  refutation (the code says so at 1271-1281).  A rewrite that makes the decision more expensive
  can therefore turn a refutation into an acceptance without any theorem lapsing.
* `checkSaturated` reads the CLOSURE, which the rewrite shrinks from `3^N − 2^N` partitions to
  `k + 1`.  Empirically it finds nothing extra on the corpora today, but the argument has to be
  made, not assumed.

**Part B constraint.**  Either (a) apply the rewrite AFTER `decideLabels()` and before
`q.expand` — then S2's subject stays the user's own input, `solve_accepted_faithful` is untouched,
and the MODEL mirror must go at the corresponding point (after the `labelClash` gate), not in
`buildQueue`; or (b) keep it in `buildQueue`, where `--replay` needs it, and carry both directions
of the equivalence over the whole system into the S2 chain (`read_of_top` gives one, G-1's lemma
the other).  Whichever is chosen, gate `rowSound` verdicts ON/OFF over the corpus and over the
`unsat/` seeds, not just `labelCheck`.

### G-4 — CONFIRMED.  The `.ei` risk is stated backwards.

§3.1.4: "The published residual also changes shape on those 9 solves — from `k` separate `Has`
constraints to one partition plus `k` re-expressions."  Measured:

```
>> :type proj5
forall (a: rho). (exists (b: rho). a <- ((|pEpsilon, pBeta, pDelta, pAlpha, pGamma|), b))
             => Record a -> String
```

The published residual is **already the single top partition** — `mkSimplified` collapses the
whole closure to it.  (`ProjectionCost.e:64` records the same for `WriterOutputs`' `reportFor`.)
So the rewrite does not replace `k` `Has` constraints with a partition; it produces in one draw
the form the compiler already reaches in 1,230.  The real `.ei` risk is the opposite: whether the
`k` re-expressions `c_i <- (c, F \ F_i)` — pure existentials — survive `mkSimplified` and ADD
noise to a residual that is currently one clean line.  S3 already drops permuted duplicates and
the `a <- (a)` tautology; Part B should measure whether it drops these too.  **This is also an
argument FOR option (i) that the report does not make: the compiler already knows the answer is
the top partition and spends the whole lattice re-deriving it.**

### G-5 — CONFIRMED.  The excess is a model-only artefact, base-dependent, and not 0.1 %.

* On the **compiler** there is no excess at all: N = 2…8 are exactly `D(N)` (§1.4).  The report's
  framing of `D(N)` as "a lower bound that the runs sit within a tenth of a percent of" applies to
  the MODEL only.
* On the model the excess depends on the id **base**.  The report's reproduction line is
  `looptrace tracker/repro/satterm/seeds/PROJ6.json 1000 --depth`, and the `1000` is the **base**,
  not the fuel: `Main.lean:498-499` parses `path :: baseS :: rest` and takes fuel from the THIRD
  positional (default 100000).  At base 1000 the ladder is 3 / 30 / 207 / 1,276 / 6,794 (the
  report's figures, reproduced exactly); at base 100000 it is 3 / 30 / **210** / **1,230** /
  **6,914**.  So the excess ranges 0 to +3.7 %, not "+0.13 %".
* The requeue EXPLANATION is supported: extra draws track extra dequeues (N = 5 base 1000 has
  227 steps / 1,276 draws against 211 / 1,230), so re-offered pairs after a requeue is the right
  mechanism.  Only the magnitude is wrong.
* Say `base=1000` in §5's reproduction block, or a reader reproducing the report gets different
  numbers, as I did.
* Same cause: §1.3's "`maxdepth` is 1, 1, 2, 2, 3, 3 for N = 2…7" is base-dependent (base 1000
  gives 1, 1, 2, 2, 2 for N = 2…6).

### G-6 — CONFIRMED.  The carrier closed form is not exact.

§1.2(a): "the minted vocabulary is exactly one carrier per subset of F of size ≥ 2".  Measured
(`--mints`, `grep -c '^carrier'`, base 1000):

| N | 2 | 3 | 4 | 5 | 6 |
|---|---|---|---|---|---|
| carriers | 1 | 4 | 11 | **28** | **58** |
| `2^N − N − 1` | 1 | 4 | 11 | 26 | 57 |

At N = 5 there are **25** distinct carrier keys at `t` (not 26) plus 3 at other left-hand sides
(`carrier 5 1002 [2,3]`, `carrier 108 1222 [1,2]`, `carrier 120 1219 [3,2]`).  The report's own
table discloses "25 (+3 at other lhs)" but the prose around it asserts exactness.  `nSat` and
`D(N)` are exact; this one is not, and should be stated as "≈".

### G-7 — CONFIRMED, minor.  "26 seeds" is 27, and two of them are vacuous.

19 top-level + 7 `unsat/` + `slow/GU05MIN` = 27 files as the report's own `topres2.log` lists
them; `slow/GU05.json` is excluded entirely.  `GU05MIN`'s row in that log has EMPTY verdict
columns on both sides, and my re-run reproduces that for BOTH `GU05` and `GU05MIN` — the
`--depth` path is unbudgeted, so neither slow seed reaches a verdict in either mode.  "All 26
seeds are byte-identical, verdict and draw count" therefore overstates the gate by two seeds and
mis-counts it by one.  My five extra adversarial seeds (§4.4) plus `GROW` (§4.3) partly make up
for it; Part B should run the slow seeds through a BUDGETED path (`--verdict`, which the
prototype does not currently reach — another reason to move the mirror out of the driver).

### G-8 — CONFIRMED, minor.  A theorem that does not exist.

`S4-DESIGN.md` §3.1.2 and `S4Top.lean`'s own header both cite **`ssat_topRewrite_iff`**.  There is
no such declaration in the file (the `#print axioms` block lists all eleven).  The nearest pair is
`models_rewrite` + `reads_of_rewrite`.

### G-9 — CONFIRMED, minor.  The 3.2 M denominator is inflated.

Every one of the 18 groups re-loads the stdlib boot, whose 54,199 segments therefore appear 18
times: ~975 k of the 3,201,992 "solves" are the same boot solves counted over and over.  The
conclusion (31 hits, none in the stdlib) is unaffected; the denominator is not what it looks like.

### G-10 — numbers of mine that differ (all minor, all disclosed)

| the report | mine | note |
|---|---|---|
| ProjectionCost total 8,256 draws; sixth solve `(140:16)` draws **3** | **8,254**; `(140:16)` draws **1** | I loaded Helpers + ProjectionCost only, the report's census loaded the whole Present group; the ladder itself is identical |
| `Pinc=2` draws "3 (14 of them), 4, 5, 5, 32" | thirteen 3s, **two** 4s, two 5s, one 32 | 18 solves both ways |
| TextTables "174: 1,231" | line 174 totals **1,233** (1,230 at 174:23 + 3 at 174:18) | the `Pinc` table's 1,230 is right |
| §1.4 "`maxdkey` is `2·(2^N − 1)` exactly" | measured 2, 6, 14, 30, 62 = **`2^N − 2`** | the report's own table contradicts its formula |
| §1.4 "the module's own header claim survives intact" | the SHAPE survives; the NUMBERS do not | `ProjectionCost.e`'s header ladder reads 3/30/**212**/**1232**/**6804** (E4 model figures) against the compiler's 3/30/207/1230/6783; `TextTables.e:54` says catalogueMarkdown is **1,241** (it is 1,230); `ProjectionCost.e:70` says ValidationReport(214:14) costs **222** ("218 rather than 1,243") against the measured **213**.  Three more one-token corrections for the same sweep as `catalogueMarkdownPinned`. |

### G-11 — CONFIRMED, medium.  The prototype's multi-lhs semantics are order-dependent and undefined.

`topNormalise` computes `lhss` ONCE from the ORIGINAL queue and folds `topNormaliseAt` over it,
rebuilding the queue at each step.  The introduced `c_i <- (c, F \ F_i)` land at left-hand sides
that were rhs-only before, so today they are never revisited — but nothing in the code says that,
and if a `c_i` were also an lhs carrying a family LATER in `lhss`, the second rewrite would see a
family the input did not have and the result would depend on the fold order.  The Scala mirror and
the model mirror must agree on this exactly or the L2 differential will not be byte-exact.  Part B
should define it (one pass over the ORIGINAL input families, or a fixpoint) and say which.

### G-12 — see G-10 row 4 (`maxdkey`).

### G-13 — CONFIRMED, minor.  The side conditions' evidence is entangled.

`RR` and `W4` both carry a concrete row at the lhs in question (`[0,[],[1,2,3]]`) and both have
`k = 2` there, so each side condition alone excludes them.  The reported "without `k ≥ 3`: RR 0→1,
W4 0→1" is only reachable with the concrete-row condition also off.  The real evidence for
`k ≥ 3` is `NE6` alone (which does have `k = 2` incomparable premises at an lhs with no concrete
row) — and the "no concrete row" condition had NO witness at `k ≥ 3` until `GROW.json` (§4.3).

---

## 8. Part B constraints (the list the verdict is conditional on)

1. **Resolve the placement conflict (G-3).**  `buildQueue` is where the model mirror must live for
   `--replay`; `after decideLabels()` is where the Scala must live for `solve_accepted_faithful` to
   keep the user's own input as its subject.  Choose one, say why, and gate `rowSound` verdicts
   (corpus + `unsat/` seeds) ON and OFF, not just `labelCheck`.
2. **Close the freshness gap (G-1).**  Add `fresh : c ∉ allVars G` and state the whole-system
   direction; `sModels_setVar` does it (`review-S4/GapCheck.lean` compiles, 0 non-standard axioms).
   Switch `Function.update` → `setVar` in `S4Top.lean` while doing it.
3. **State the rule as TWO `LoopStrict` steps** — an additive `ResStep`-shaped mint constructor,
   then `drop` with `noloss_of_top`.  Not `requeue` (it forbids new variables), never `weaken`.
4. **Key on the DISTINCT concrete parts and re-measure the blast radius** (G-2: 19 today, and the
   report's own two figures are 13 and 9).
5. **Define and mirror the multi-lhs semantics** (G-11).
6. **State the `.ei` gate the right way round** (G-4): does the rewrite ADD `k` re-expressions to a
   residual that is already one partition, and does `mkSimplified` drop them?
7. Own provenance tag (not `.resolution`), a `GenRules` flag and its `toString` token so the
   `--verdict` fingerprint still matches, `RowTrace` records for the new rule, and the deleted
   premises' blame `Loc`s carried onto the replacements.
8. **The wild-code gate is already half-answered** (§6.1): `ProbeWildLet.e` and `ProbeWildChain.e`
   both draw 6,783 at six reads and `ProbeWildChain7.e` is rejected at 20,009 — the fan does not
   need the reads in one expression.  The 25-column relation chain is still worth building as the
   realistic case, but the mechanism question is settled.
9. Add §2.1's cheaper-alternative measurement to `S4-DESIGN.md` §3 — it is the first counter-
   proposal any reader will make and the numbers say it buys nothing.
10. The one-token corrections of G-10 row 5 (three stale example-module headers) belong in the same
    sweep as the `catalogueMarkdownPinned` fix the report already found.

---

## 9. Reproduction

```
# compiler ladder and nSat (one JVM each)
ERMINE_JAVA_OPTS="-XX:ActiveProcessorCount=2 -Xmx2g -Dermine.useInterface=false \
  -Dermine.loadInSeries=true -Dermine.rowTrace.draws=true -Dermine.rowTrace=<f>" \
  bin/ermine tmp/S4/probes/ProbeProj{2..6}.e </dev/null
# N=7/N=8 with the budget raised
... -Dermine.solveBudget=60000  ... ProbeProj7.e     # 35,910
... -Dermine.solveBudget=300000 ... ProbeProj8.e     # 185,727
# model ladder -- note the 1000 is the id BASE, fuel is the THIRD positional
tracker/lean/.lake/build/bin/looptrace tracker/repro/satterm/seeds/PROJ6.json 1000 --depth [--topres]
# the census, re-run from the report's saved traces
python3 -c "import sys;sys.path.insert(0,'tmp/S4');import census,glob;..."   # see review-S4/
# the Lean
cd tracker/lean && lake env lean ../loopmodel/S4Top.lean
cd tracker/lean && lake env lean <review-S4>/GapCheck.lean      # the closed G-1 gap
cd tracker/lean && lake build looptrace                          # 1,670 jobs, clean
# my extra seeds and probes
<review-S4>/seeds/{GU3,GU4,GU5,GS1,GU6,GROW}.json
<review-S4>/probes/{ProbeWildLet,ProbeWildChain,ProbeWildChain7}.e
```

State on disk: nothing in the tree was edited by this review; `core/examples` holds 0 `.ei`.
