# L2 review — trust nothing you have not re-run

Reviewer agent, 2026-09-04. **Verdict: FIX-THEN-ADVANCE** — no correctness defect found;
six prose corrections required, none needing a re-run or a code change.

**Summary.** I rebuilt and re-audited, re-ran `core/test` once and first, re-ran the corpus
sweep on four groups, the 2,000 random systems, the 383 L1 comparisons and the `emptyRow`
variant, and every number reproduced to the digit. Then I ran what the implementer did not:
two more flag variants (`splitKey=false`, `resGuard=false`) with bite checks, `genRules=all`
and `disjunction`, five random systems of my own at three id bases, two hand-built replay
inputs, and **five negative controls** that each disable one modelled mechanism and confirm the
model then diverges — so M2 and M3 are load-bearing, not cosmetic. **920,611 segments compared
at matched flags; the only 37 mismatches anywhere are M4, under a flag that ships off.** The
findings are all documentation, presentation or scope.

Stage L2 of `tracker/LOOP-MODEL-PLAN.md`. Implementer's report `tracker/loopmodel/L2-CORPUS.md`;
brief `tracker/loopmodel/briefs/brief-L2.md`. Baseline: HEAD `c8484d0` (Stage 7 + L1); everything
`git status` lists is L2's. Scratch: `/home/dmitry/.claude/jobs/880c725d/tmp/review-L2/`.

## Step 1 — rebuild and re-audit (DONE, all three figures reproduce)

```
cd tracker/lean && export PATH=$HOME/.elan/bin:$PATH
lake build Rowpartition   -> Build completed successfully (833 jobs).                        exit 0
lake env lean Audit.lean  -> Rowpartition theorems audited: 2530; declarations using a
                             non-standard axiom: 0                                           exit 0
lake build looptrace      -> Build completed successfully (24 jobs).                         exit 0
```

Greps over `Rowpartition/Loop/` + `Rowpartition/Loop.lean` for `sorry`, `Classical`, `partial`,
`axiom`, `unsafe`, `native_decide`, `opaque`, `implemented_by`, `extern`, `panic!`, `dbg_trace`,
`lcProof`, `unsafeCast`, `set_option maxRecDepth`: **three hits, all prose** (`Step.lean:11`,
`Step.lean:359`, `Main.lean:63`). The replay's fuel is explicit (`Main.lean:67`, default
2 000 000) and exhaustion is a distinguishable `#FUEL` answer counted in `#summary`.
CONFIRMED as reported.

## Step 2 — the Scala change, and `core/test`

**Inertness.** `RowTrace.solveInput(loc: => String, cs: List[Type], su: Supply): Unit =
if (enabled) { … }` with `enabled` a `val` off `System.getProperty` and `out` a `lazy val`.
The call site is `Subst.solve:1134`, `RowTrace.solveInput(l.toString, cs, su)`; `loc` is
**by-name**, so `Loc.toString` is not rendered, and `cs`/`su` are values already in scope.
On the default path the added cost is one static boolean read (plus the by-name thunk the
call site must construct, which is a small escape-analysable allocation, not I/O or
reflection). **No reflection on the default path**: `supplyBounds`/`supplyBlock` are called
inside the `if (enabled)` body. CONFIRMED inert.

`supplyBlock()` reads `scalaparsers.Supply$`'s `block` and `blockSize` with `getInt(null)`.
That is only correct if those fields are STATIC; I checked the bytecode rather than assume:
`javap -p parsers/target/scala-3.3.8/classes/scalaparsers/Supply$.class` shows
`private static int block;` and `private static final int blockSize;`. Correct, and the
traces confirm it — **0 of 83 942 `Ai` `sin` records carry the `(-1,-1)` reflection-refused
sentinel**.

**`core/test`, run ONCE and FIRST** (`sbt -batch -J-Xmx3g core/test`, 274 s):

```
[info] ! Constraints.disjunction sound: Gave up after only 0 passed tests. 501 tests were discarded.
[info] Failed: Total 911, Failed 1, Errors 0, Passed 910
```

**910/911 — exactly the known `disjunction sound` starvation, and nothing else.** The
instrumentation does not disturb the suite.

## Step 3 — re-running the implementer's evidence

### 3a. The corpus sweep, four groups, with the implementer's own script

`tracker/tools/looptrace-corpus.sh` on `boot`, `top`, `Ai`, `shouldfail` (the brief's `boot`
and `top` plus `Ai`, which holds M3 and M4, and `shouldfail`, which holds M2):

```
boot         files=0  ermine=17s(rc=0,timeouts=0,dropped=0) segments=54199  model=888ms   agree=54199  skip=0
top          files=15 ermine=21s(rc=0,timeouts=0,dropped=0) segments=92673  model=1738ms  agree=92673  skip=0
Ai           files=11 ermine=20s(rc=0,timeouts=0,dropped=0) segments=83942  model=18698ms agree=83942  skip=0
shouldfail   files=40 ermine=19s(rc=0,timeouts=0,dropped=0) segments=56032  model=1105ms  agree=56032  skip=0
```

**Every segment count, agree count, skip count and model time reproduces the report's §4a to
the digit** (model times within 3 %). 0 hashdiff, 0 eqdiff segments in all four.


### 3b. The 2,000 random systems

The implementer's `gen-seeds.py` (its own copy, under `.../tmp/L2/`) re-run into MY scratch:
`S0000.json` is byte-identical to the implementer's, so the generator is deterministic and the
population is the same one. Its own `randsweep.sh`, re-pathed, 4 jobs x 500 seeds, base =
index mod 40, `tracker/repro/satterm/run.sh sweep`:

```
job 0: segments 500  AGREE 500  SKIP 0  hashdiff 0  eqdiff 0  rejected 15
job 1: segments 500  AGREE 500  SKIP 0  hashdiff 0  eqdiff 0  rejected 11
job 2: segments 500  AGREE 500  SKIP 0  hashdiff 0  eqdiff 0  rejected 10
job 3: segments 500  AGREE 500  SKIP 0  hashdiff 0  eqdiff 0  rejected 12
```

**2,000/2,000 agree, 0 skipped, 48 rejected** — the report's §4b to the digit, rejections
included.

### 3c. M2 and M3 re-verified, each with a POSITIVE CONTROL the implementer did not run

Reproducing a mismatch class's *fix* is not the same as showing the fix is load-bearing. For
both model gaps I extracted the exact corpus segments, replayed them, and then replayed a
DOCTORED copy of the same trace in which the fixed mechanism is disabled — if the fix were
cosmetic the doctored run would still agree.

**M3 (`Supply.fresh` across a 1024-id block).** I found the low-room solves myself:
`zcat Ai.tsv.gz | awk '$1=="sin" && $5-$4 < 10'` gives **677**, the report's number, and **0**
of the 83,942 `sin` records carry the `(-1,-1)` reflection-refused sentinel. Six segments
extracted (`room` = `suHi - suLo`): `Relation.e(232:92)` room 1, `Tree.e(98:29)` room 2,
`Layout/Report.e(748:60)` room 0, `Ai/ClinicalTrial.e(48:3)` room 1,
`Ai/IncidentSeverity.e(69:15)` room 3, `Ai/SupplyChainInventory.e(71:70)` room 0.

| run | result |
|---|---|
| as traced | **6/6 AGREE**, 0 hashdiff, 0 eqdiff |
| same trace with `suHi := suLo + 100000` on every `sin` (model can no longer cross a block) | **4 agree, 2 DIFFER** |

The two that differ are exactly the two the report names, with exactly the records it quotes:

```
[learn] seg 4  core/examples/Ai/IncidentSeverity.e(69:15)
    lean : … SplitConcrete: ^ambiguous(free)336895 <- (…)
    scala: … SplitConcrete: ^ambiguous(free)336896 <- (…)
[step]  seg 5  core/examples/Ai/SupplyChainInventory.e(71:70)
    lean : step … ^free392186 <- (…)
    scala: step … ^ambiguous(free)393216 <- (…)
```

**M3 CONFIRMED real, correctly fixed, and load-bearing.** `Sup.fresh` is
`scalaparsers.Supply.fresh` branch for branch (`parsers/.../Supply.scala:22-31`), and
`Supply$`'s `block`/`blockSize` really are static fields, so `getInt(null)` is legitimate.

**M2 (`makeEmpty`'s skolem refusal).** Exactly five segments in `shouldfail` carry a `Skolem`
`svar` — `sk01`…`sk05`, the same five the report names.

| run | result |
|---|---|
| as traced | **5/5 AGREE**; the model answers `#REJECTED … Cannot unify skolem variable with empty relation r^350038` etc. |
| same trace with every `svar` `Skolem` rewritten to `Free` | **0 agree, 5 DIFFER** |

The comparison is not vacuous: the compiler writes TWO `step` records before it dies on
`sk01` (`empty ^free350061`, then `empty ^skolem350038`) and the model writes both, byte for
byte, before rejecting. The doctored run diverges at the printed flavour (`^free350038` vs
`^skolem350038`) — which independently confirms that L1 review's **F7** (`V.ty` inferred from
the id) was a real defect and that `Names.tys` closes it. **M2 CONFIRMED, and F7 CLOSED.**

### 3d. Flag variants

| variant | groups | segments | AGREE | mismatch |
|---|---|---|---|---|
| `-Dermine.emptyRow=true` / `--flags=emptyrow` | boot | 54,199 | 54,199 | 0 |
| | top | 92,673 | 92,671 | **2** (M4) |
| | Ai | 83,942 | 83,907 | **35** (M4) |

`2 + 35 = 37`, the report's §4c figure, in the same two groups. Every one is the M4 signature —
the model MINTS (`SplitConcrete` / a fresh id) where the compiler REUSES (`SplitEmpty` /
`ResolutionEmpty`), i.e. the model is the CONSERVATIVE side, never the other way round:

```
[learn] seg 84386  core/examples/GridExample.e(109:3)
    lean : learn … new SplitConcrete: ^ambiguous(free)375846 <- (^ambiguous(ambiguous(free))375841 ^ambiguous(free)375845,)
    scala: learn … new SplitEmpty:    ^ambiguous(ambiguous(free))375841 <- (,)
```

I checked that segment's whole record stream myself: when the compiler's `SplitEmpty` fires
(`proc=10`) no partition of the form `u <- ()` is in either queue and the solve's FIRST
`step … empty` has not yet run, so the carrier can only have come from `hm.types` of an
earlier solve. That is exactly the report's §5-M4 analysis, independently reproduced. Reading
`Constraints.scala`'s `envEmptyRow` (`hm.types.collectFirst{…fs.isEmpty}`) against
`Loop/Step.lean:246`'s `findEmptyRow` (`env.binds.find? (·.2 == EnvVal.emptyRow)`) confirms
the model's carrier set is a SUBSET of the compiler's on every solve, so the direction is
forced, not observed. And both call sites use the result as `case Some(_)` — the carrier is
never printed — so §5's "which one it is cannot reach the output" holds.


### 3e. Two flag variants the implementer did NOT run, plus negative controls for both

`looptrace` supports `--flags=nosplitkey` / `--flags=noresguard`
(`Loop/Main.lean:applyFlag`), matching `-Dermine.splitKey=false` /
`-Dermine.resGuard=false` (`Constraints.scala:887, 807`). The replay records carry enough:
these flags change how the model computes its LOOKUPS, not the input, so the same `sin` /
`slbl` / `svar` / `scon` stream drives both.

| variant | group | segments | AGREE | mismatch |
|---|---|---|---|---|
| `-Dermine.splitKey=false` / `--flags=nosplitkey` | Ai | 83,942 | **83,942** | 0 |
| `-Dermine.resGuard=false` / `--flags=noresguard` | top | 92,673 | **92,673** | 0 |

**The flag has to be shown to BITE, or the variant is vacuous.** For `splitKey` it does: the
shipped `Ai` trace has 160 `SplitKeyed` occurrences and the variant trace has **0**, and the
two traces differ. Negative control — the SHIPPED-flag model replayed against the
`splitKey=false` trace: **83,901 agree, 41 differ**, first difference
`lean: SplitKeyed: … / scala: Cancellation: …` at `Ai/ClinicalTrial.e(73:6)`. So the model
really implements the branch and really honours the flag.

For `resGuard` on `top` it does NOT bite: the `resGuard=false` trace is **byte-identical** to
the shipped one (same md5), so that variant proved nothing. `Constraints.scala:806` says why
— "`resolution` fires on 18 example modules (and zero stdlib ones)". Re-run on `Ai`: see
below.

Re-run on `Ai`, where it does bite (the variant trace is 245,257 lines against the shipped
243,551, different md5):

| variant | group | segments | AGREE | mismatch |
|---|---|---|---|---|
| `-Dermine.resGuard=false` / `--flags=noresguard` | Ai | 83,942 | **83,942** | 0 |

Negative control — SHIPPED-flag model against the `resGuard=false` trace: **83,927 agree, 15
differ**, first difference `lean: Resolution: … / scala: ResolutionRow: …` at
`Ai/ClinicalTrial.e(67:24)`. Both new variants therefore agree at matched flags AND are shown
to be non-vacuous.

### 3f. A branch no seed can reach, on a hand-built replay input

The brief asks for a hand-built seed reaching `makeEmpty`'s skolem refusal. **The `json:`
seed format cannot express it**: `tracker/repro/nameloss/Replay.scala:22` builds every seed
variable as `V(…, Free, rho)`, so no `json:` seed has a skolem — which is exactly why L1 could
not find M2. The REPLAY format can, so I wrote a segment by hand:

```
sin	handbuilt	SKOLEM.e(1:1)	1000	2000	1	100000	1024	1
svar	handbuilt	SKOLEM.e(1:1)	100	Free	r
svar	handbuilt	SKOLEM.e(1:1)	101	Skolem	s
scon	handbuilt	SKOLEM.e(1:1)	0	0	12345	part	v100|v101|v101
```

The model dispatches `empty` twice and rejects with `Cannot unify skolem variable with empty
relation s^101`; with `Skolem` changed to `Free` the same input SOLVES and prints its `in` /
`inpart` / `solve` records. (The invented `hashCode` produces `#hashdiff 1`, reported rather
than swallowed; with `nCs = 1` `existsApply` is the identity, so it cannot affect the run.)

I also probed the one thing the Lean docstring asserts and no corpus solve tests — that
`Ambiguous(Skolem)` is NOT `Skolem`, because the Scala compares the case object. Rewriting the
five `sk0*` segments' `svar` from `Skolem` to `Ambiguous(Skolem)`: the model **solves all
five** instead of rejecting. `Names.isSkolem` is therefore exact, not a substring test.

### 3g. Where the block-boundary branch could NOT be tested by a seed

`supplyAt` builds `Supply(lo, lo + 100000)` (`tracker/repro/nameloss/Replay.scala:16-20`) and
`Sup.ofSeed` mirrors it, so **no `json:` seed at any id base can cross a 1024-id block**. M3
is testable only on corpus segments, which is what §3c does, plus the doctored-trace control.
Worth recording as a permanent limit of the seed harness.

## Step 4 — reading the two sides side by side

### 4a. `Replay.lean`'s reconstruction against what `Subst.solve` actually passes

`Subst.solve:1125-1135`:

```scala
val (es, cs) = unbindExists(Ambiguous(Free), csz)
RowTrace.solveInput(l.toString, cs, su)            // <- the one added line
val (q, esp) = PQueue.build(Exists(l, List(), cs))
```

**Nothing in the loop's input is dropped or reordered by the instrumentation.** `cs` is
recorded element by element in the list's own order, BEFORE `Exists.apply` touches it, and
`su` is read (not drawn from) at that instant. I checked the placement is forced and correct:
in `top` seg 84386 the `ex` records name 375840/1/2 and `sin` says `suLo = 375843`, i.e.
`unbindExists` had already drawn its ids when `solveInput` ran — which is exactly what the
model needs.

The model then reproduces the two reorderings itself rather than reading them off the trace:

| Scala | Lean | verdict |
|---|---|---|
| `Exists.apply(l, Nil, q)` — `q.length == 1` returns `q.head`; otherwise the fold CONSES each non-`Exists` (so the list is REVERSED) and then `p.toSet.toList` (`Type.scala:295-302`) | `existsApply` (`Json.lean:130`) | **exact** |
| `.nf` inside `PQueue.build(t)` → `Exists.nfWith` → `Exists.mk(loc, xs, constraints.map(_.nf))` → `Exists.apply` again (`Type.scala:262, 311`) | the SECOND `existsApply` in `buildQueue` | **exact**, and I checked the two things that make it exact: `Exists.mk`'s `nxs` is empty when `xs` is (no nested `Exists` in the corpus), and **`Part` does not override `nfWith`**, so `Part.nf = this` and `constraints.map(_.nf)` cannot rewrite a term under the model's feet |
| `RHS.build` (`Constraints.scala:382-397`) | `rhsBuild` (`Json.lean:136`) | **exact**, arm for arm, including the duplicate-variable removal and the "Fields appear twice" message |
| `aux`'s `Part(loc, VarT(v), _)` / non-variable-lhs mint / `case _ => (Nil, Nil)` (`Constraints.scala:653-668`) | `partToPartitions` / `buildQueue`'s `.other` arm | **exact** |
| `Supply.fresh` (`parsers/…/Supply.scala:22-31`) | `Sup.fresh` (`State.lean`) | **exact, branch for branch** (§3c) |
| `makeEmpty`'s `if (v.ty == Skolem) tml.die(…)` AFTER the `nps` fold and BEFORE `instantiateType` (`Constraints.scala:1577`) | `Step.lean:130`, in the same position relative to the `Incompatible instantiations` error and the reinstantiation panic | **exact** (§3c, §3f) |
| `envEmptyRow = hm.types.collectFirst{… fs.isEmpty}` (`Constraints.scala:1456`) | `findEmptyRow`'s `env.binds.find?` (`Step.lean:246`) | **abstracted, one-directional** — M4 (§3d) |

**Are `hashCode` / `equals` taken from the trace?** For `part` items, NO: `IPart.hshOf` and
`IPart.eqv` are computed by the model and CROSS-CHECKED against the trace's `hash` and `eqid`
on every segment (`Replay.lean:235-242`). Across everything I ran — 918,191 corpus segments
over six flag configurations, 2,000 random systems, and every hand-extracted segment — **0
hashdiff and 0 eqdiff**, and
`looptrace --replay` exits non-zero if either is nonzero (`Main.lean:157`), which
`looptrace-corpus.sh` prints as `rc=`; it was 0 in every run. That is a strong, genuinely
independent check on `Part.hashCode`, `ConcreteRho.hashCode`, `Con.hashCode`,
`Murmur.seqHash`, `Name.hashCode` and `SSet.hsh` at real qualified `Global` names.

For NON-`part` items, YES: `CsItem.other h eqid` carries the compiler's own `hashCode` and
`equals`-class verbatim, and `CsItem.hshOf`/`eqv` return them (`Json.lean:107-114`). These are
real and common — every corpus group has thousands (`AppT` class constraints: boot 1,251, top
2,095, Ai 2,242, shouldfail 1,291) — and they MOVE the `part` items through `p.toSet.toList`.
**This is a faithfulness gap in the corpus differential, though not in the model, and not one
that affects L3**: the model has no `AppT`, so the sweep cannot test the model's ability to
build the initial queue from a raw constraint list, only from one whose non-row elements the
instrumentation has already reduced to `(hash, eq-class)`. L3's theorems quantify over an
initial `State`, however it arose, so nothing there depends on it. It belongs in §6's
accepted-abstraction table, where it is not currently listed (finding F3).

### 4b. The corpus's own shape, measured off my traces

Everything the report's §3 says about the population reproduces:

| | measured by me |
|---|---|
| `VarType`s in the input (boot+top+Ai+shouldfail) | `Free` 23,241, `Ambiguous(Ambiguous(Free))` 3,400, `Ambiguous(Free)` 1,152, `Ambiguous(Bound)` 81, **`Skolem` 5** — five flavours, of which L1's id rule got two right |
| label forms | **10,842 `slbl` records, every one `G` at `con` 1** — a `Global` at `Idfix`. `Local`, `Prefix`/`Infix`/`Postfix` and `Con`-in-a-row-position are covered by `#guard` only, as the report says |
| `scon` kinds | **only `part` and `other`, every `other` an `AppT`** — no `exists`, so §6's nested-`Exists` row is genuinely unreached |
| `sin` records with `(-1,-1)` (reflection refused) | **0 of 83,942** in `Ai` |
| solves starting with <10 ids left in their block | **677** in `Ai` |
| mint flavour | all six `fresh(` sites in `Constraints.scala` (662, 1337, 1764, 1851, 1880, 1889) are `fresh(_, none, Ambiguous(Free), _)`, so `pvar`'s "not in the table ⇒ `Ambiguous(Free)`, no name" fallback is exact for every mint the loop can make |

### 4c. Record types the diff drops

`looptrace-diff.py`'s `KEEP` is `step, learn, in, inpart, sat, solve`. A `top` trace also
contains `concr` 1,304 and `splice` 293 (`Subst.reduce`, declared out of scope in L1 §7 and
L2 §6 — I confirmed they are written AFTER the `solve` line) and **`ex` 797**, the
existential variables `unbindExists` produced. `es` is not replayed and `ex` is not compared.
That is harmless — `es` is used in `solve` only for those records and for `reduce`, and the
ids it drew are already inside `sin`'s `suLo` — but it is a compiler record the model does not
reproduce and it is in NEITHER §6 nor L1-MODEL §7 (finding F4).

### 4d. `Bridge.lean`, and what L3 now inherits

`LPart.eqv_iff_toConstraint` gained a FIFTH hypothesis, `LblCoh` (label-table index is
injective on the labels of one solve), on top of the four `Nodup`s that L1 review's F6 already
flagged as unconnected to `step`. `LblCoh` is true of `RowTrace`'s tables by construction
(`LinkedHashMap[Name, Int]` keyed by `Name.equals`) and true of `ofConstraint`'s output
trivially, so this is not a defect — but L3 (iv) in the plan names only "`Nodup` hypotheses"
and should name `LblCoh` too (finding F5).

One consequence worth writing down before L3 starts: `LPart.ofConstraint` now builds labels as
`{ n := n }`, i.e. with `glob = true, mod = "", str = "", con = 1` for every `n`, so **every
label it produces has the same `Lbl.hshOf`**. Bridge lemmas stated up to `toFinset` are
unaffected, and it happens to make the `hashed := decide (4 < length)` SSets it builds
CONSISTENT (all-equal hashes make `champSort` the identity on a sorted list, which L1's
`⟨n⟩` labels did not) — but any future lemma reasoning through `ofConstraint` about
`champSort` ORDER would be reasoning about a hash-degenerate special case.

## Step 5 — the segmentation assumption, and what the agreement does NOT cover

`-Dermine.loadInSeries=true` is not a detail; it decides the population. I re-ran `gu05` under
the default (PARALLEL) loader myself, one module, one JVM:

```
par  rc=0  segments=54235  maxSat=458
     segments with >1 `solve` record = 1575     drawing records from >1 source location = 2058
```

**§8's claim is CONFIRMED**: a rowTrace written by a parallel load cannot be segmented, because
`RowTrace.log` synchronises per LINE and two threads solving at once interleave their records —
1,575 of 54,235 segments hold more than one `solve` line. (The report's figures were 1,654 and
1,659; the difference is a thread race and is expected to move run to run. The direction and
magnitude reproduce.) A replay of an interleaved segment is a replay of a system the compiler
never had, so the parallel run's 3,842 "mismatches" are not the model's, and the report is right
not to count them.

**What that means for the plan.** The compiler as SHIPPED loads in parallel. The solves this
stage covers are therefore the ones the compiler performs when it loads module by module, and
NOT the larger solves the parallel loader's id interleaving produces — including `gu05`'s
famous one, which reaches `nSat = 458` under the parallel loader (I measured it) against 83
serialized. Those are precisely the solves where termination is most at risk, which is what L3
is about. My judgement: this is **acceptable L2 scope but a gap the plan must record
explicitly**, not a footnote in the report. It is already in the report's §8 and §10.2 and in
the plan's L2 status row; it should also appear in L3's scope, because "the model agrees with
the compiler on the corpus" will otherwise be read as covering the compiler's hardest solves,
and it does not. Making it coverable needs a thread id on every record — one more
instrumentation change, and one that breaks `keptdef-mints.py`'s format.

I also checked the segmentation is sound where the sweep DOES run, over my own 286,846
serialized segments: **no segment holds two `solve` records, and every `in`/`inpart`/`sat`/
`solve` record in a segment carries the same location as its `sin`.**

```
boot: >1 solve=0  loc mismatch=0     Ai:         >1 solve=0  loc mismatch=0
top:  >1 solve=0  loc mismatch=0     shouldfail: >1 solve=0  loc mismatch=0
gu05 serialized: 54,235 segments, >1 solve=0, loc mismatch=0, maxSat=83
gu05 parallel:   54,235 segments, >1 solve=1575, loc mismatch=1660, maxSat=458
```

So `Subst.solve` is never re-entered during a solve either — which the segmentation silently
assumes and nothing states.

## Step 6 — the L1 evidence, and evidence of my own

| sweep | comparisons | result |
|---|---|---|
| the implementer's `l1sweep.sh`, re-pathed and re-run from scratch on BOTH sides: `W2 H2 NE6 W3 W4 G7` x bases 0-29 shipped (180), the same six x 0-9 under `emptyRow` (60), `RR RE CHAIN COLL LBL REF SUP` x 0-14 (105), `RE RR` x 0-14 under `emptyRow` (30), `D1`-`D4` x bases 0,3 with `labelCheck` off (8) | **383** | **383 agree, 0 differ** — §4e reproduced exactly |
| **five random systems of MY OWN** (`rowclosure.py`'s generator, rng **20260904**, so a population the implementer never touched) x bases **0, 7, 41** | **15** | **15 agree, and all 15 BYTE-IDENTICAL** to the compiler file grepped to the six record types |

## Findings

No correctness defect in the model or the harness was found. Everything below is
documentation, presentation or scope.

### F1 — MEDIUM (presentation). The headline "2,355,430 solves" is 96.6 % repeated stdlib boot and 98.9 % trivial

CONFIRMED by measurement on my own traces and the implementer's.

* Of the 2,355,430 segments, **26,864 have any row constraint at all** (`sin`'s `nRows > 0`).
  The other 2,328,566 are solves whose whole compared content is one `solve` record with
  `rows=0`. (The report does give "26,405 segments with at least one dequeue" in §4a, so the
  fact is present — but the number that travels, into the plan's status row and
  `tracker/lean/README.md`, is 2,355,430.)
* Every group boots the stdlib, and `incomplete` runs **one JVM per FILE** — 35 of them — so it
  boots the stdlib 35 times. **1,905,366 of the 2,355,430 segments are the `incomplete`
  group, and only 8,401 of those are the `incomplete/` modules' own**; the other 1,896,965 are
  35 repeats of the 54,199-segment boot. Across all eight groups the boot is replayed **42
  times** (7 groups + 35 files), i.e. 2,276,358 of the 2,355,430 segments. The report says
  "re-traced in each of the eight runs"; it does not say 42.
* DISTINCT non-trivial solves in the entire sweep:

  | group | non-trivial (`nRows>0`) | of which the group's OWN modules |
  |---|---|---|
  | boot | 383 | 383 |
  | top | 5,424 | 5,424 |
  | Ai | 4,494 | 4,494 |
  | shouldfail | 647 | 647 |
  | bugs | 383 | **0** |
  | guide | 383 | **0** |
  | shouldfail-controls | 447 | 64 |
  | incomplete | 14,703 | 1,298 |
  | **total** | **26,864** | **12,310** |

**This is not a defect.** Replaying the same module at 42 different id bases is real coverage —
it is exactly what L1's base sweeps do, and it is where M3 (the block boundary) was found. But
"2,355,430 solves" overstates the distinct population by ~190x, and `bugs` and `guide`
contribute literally nothing of their own. **Fix:** in §4a, in the plan's status row and in
`tracker/lean/README.md`, give both numbers — e.g. "2,355,430 solve segments, of which 26,864
carry a row constraint and 12,310 are distinct solves; the 129-module stdlib boot is replayed
42 times at different id bases". Nothing needs re-running.

### F2 — LOW. §6's "the replay reports the kind … so this cannot go unnoticed" is not true as written

`Replay.addRecord` turns every non-`part` `scon` into `CsItem.other h eqid`, **dropping the
kind string**, and `Main.lean`'s `nonpart` counts SEGMENTS holding any non-`part` item — of
which every group has thousands (`AppT`: boot 1,251, top 2,095, Ai 2,242, shouldfail 1,291;
`nonpart=1436` on my `top` replay). A nested `Exists` would be lumped in with them and
invisible.

What actually catches it is a different check: `replay` refuses a segment whose `nRows`
(`cs.flatMap(_.rowConstraints).length`) differs from the number of `part` items, and a nested
`Exists` holding any `Part` raises `nRows`. **An `Exists` with no row constraints would slip
through, and would be MIS-ORDERED**: `Exists.apply` appends a nested `Exists`'s contents to the
END of the accumulator (`r ++ cs`, dropping the element itself when its list is empty) where
`existsApply` CONSES it (`t :: r`). CONFIRMED unreached — I counted the `scon` kind field over
four groups and it is only ever `part` or `other`, and every `other` payload is `AppT`. **Fix:**
either keep the kind in `CsItem.other` and count `exists` separately in `#summary`, or restate
§6 and §10.5 as "caught by the `nRows` cross-check, except an `Exists` with no row constraints".

### F3 — LOW. The `hashCode` / `equals` of non-`part` constraint-list elements come from the trace, and §6 does not say so

See §4a. For `part` items both are recomputed and cross-checked (0 hashdiff / 0 eqdiff
everywhere). For `AppT` class constraints — thousands per group, and they DO move the `part`
items through `p.toSet.toList` — both are the compiler's own values, carried verbatim. That is
the right engineering choice and it does not weaken L3 (whose theorems quantify over an initial
`State`), but it means the corpus differential does not test the model's construction of the
initial queue from a RAW constraint list. **Fix:** one row in §6's accepted-abstraction table.

### F4 — LOW. The `ex` records are neither replayed nor compared, and no list says so

`unbindExists`'s existential variables are logged as `ex` records (797 in a `top` trace) and
`looptrace-diff.py`'s `KEEP` drops them; `es` is not in the replay input. Harmless — `es`
reaches only the `ex` records and `reduce`, and the ids it drew are already in `sin`'s `suLo`,
which I verified on `top` seg 84386 (`ex` 375840/1/2, `suLo` 375843). But it is a compiler
record the model does not reproduce and it appears in neither §6 nor L1-MODEL §7. **Fix:** one
line in §6.

### F5 — LOW (input to L3). `Bridge.lean` grew a fifth hypothesis; the plan's L3 (iv) names only the `Nodup`s

`LPart.eqv_iff_toConstraint` now needs `LblCoh` as well as the four `Nodup`s. True by
construction of `RowTrace`'s label table, so not a defect — but L3 (iv) says "the state
invariants the bridge assumes (`Loop/Bridge.lean`'s `Nodup` hypotheses, L1 review F6)" and
should say "`Nodup` and `LblCoh`". See §4d for the `ofConstraint` hash-degeneracy note that
goes with it.

### F6 — LOW (documentation). `tracker/lean/README.md`'s L2 block quotes a stale audit figure

README line 54 says `Rowpartition theorems audited: 2527`. The correct figure — in the
implementer's own report, and re-run by me — is **2530**. **Fix:** one digit.

### F7 — INFO, not a defect. One thunk allocation per solve on the default path

`RowTrace.solveInput(l.toString, cs, su)` passes `loc` by name, which is right (it prevents
`Loc.toString`), but a by-name argument compiles to a `Function0` capturing `l`, so the default
path constructs one small closure per `Subst.solve`. It is escape-analysable and the
`core/test` timing shows nothing, so this is a note, not a request. If it ever mattered, the
call would be `if (RowTrace.enabled) RowTrace.solveInput(…)` at the call site, as the `if
(RowTrace.enabled)` block twenty lines below already does.

### F8 — INFO. `looptrace-diff.py`'s exit status ignores `hashdiff` / `eqdiff`

`segments_main` computes `bad` from `classes` only, so a segment whose records agree but whose
`Part.hashCode` the model got wrong would be printed in the report file and counted as AGREE,
and the diff would exit 0. It is caught elsewhere — `looptrace --replay` itself exits non-zero
when either count is nonzero (`Main.lean:157`) and `looptrace-corpus.sh` prints that as `rc=`
(0 in every run of mine) — so nothing was missed. Worth folding into `bad` anyway.

## Step 7 — the L2 acceptance criteria, one by one

The plan's L2 paragraph is the contract. Each clause, with the evidence I ran.

| criterion | verdict | evidence |
|---|---|---|
| "A harness … (or a `rowTrace` extension that records the input system and base)" | **PASS** | `RowTrace`'s four replay records + `lake exe looptrace --replay` + `looptrace-diff.py --segments` + `looptrace-corpus.sh`. I re-ran all four end to end. The one solver line added is inert without `-Dermine.rowTrace` (bytecode-checked reflection target; §2) and `core/test` is 910/911, the known starvation. |
| "runs the Lean model on EVERY solve segment of the 110-module example corpus and the 129-module stdlib boot" | **PASS, with a scope caveat the report already states** | Every `Subst.solve` gets a `sin`, so segmentation is total, and 0 segments were skipped in any run. The caveat is `-Dermine.loadInSeries=true`: the SHIPPED (parallel) loader's solves are a different, larger population and are not covered — I confirmed the reason myself (§5). |
| "diffs against the compiler's trace, and classifies mismatches" | **PASS** | `--segments` pairs by index and classifies by the record type at which a pair first differs. I exercised the classifier with five deliberately broken runs (§3c, §3e) and it reported each one at the right record. |
| "Batch mode makes the compiler side minutes" | **PASS** | my re-run: boot 17 s, top 21 s, Ai 20 s, shouldfail 19 s; the implementer's `incomplete` 590 s. Whole corpus ≈ 12 minutes of compiler and 111 s of model. |
| "0 unexplained mismatches over both corpora" | **PASS** | At the shipped flags, **0** over the 286,846 segments I re-ran and over the implementer's full 2,355,430. The only mismatches anywhere are the 37 M4 ones, all under `-Dermine.emptyRow`, which ships OFF — I reproduced all 37, in the same two groups, and independently verified the cause on one of them. |
| "every explained class either fixed in the model or recorded as a deliberate abstraction with its scope" | **PASS** | M1 harness bug fixed; M2 and M3 fixed IN THE MODEL and shown by me to be load-bearing with doctored-trace controls; M4 recorded with its exact scope, its direction (model conservative) forced by a subset argument I checked in the source, and its irrelevance to L3 argued. |
| "Random systems from `rowclosure.py`'s generator at 2,000 seeds, same criterion" | **PASS** | re-generated (`S0000.json` byte-identical, so the same population) and re-run: **2,000/2,000 agree, 0 skipped, 48 rejected** — the report's figures exactly. |

## Totals, all re-run by me

| what | segments / comparisons | result |
|---|---|---|
| corpus, shipped flags, `boot top Ai shouldfail` | 286,846 | **286,846 agree, 0 skip, 0 hashdiff, 0 eqdiff** |
| `-Dermine.emptyRow=true`, same four groups | 286,846 | 286,809 agree, **37 differ** — all M4, all `SplitEmpty`/`ResolutionEmpty` |
| `-Dermine.splitKey=false`, `Ai` (NEW) | 83,942 | **all agree** |
| `-Dermine.resGuard=false`, `top` (NEW; flag does not bite there) | 92,673 | all agree |
| `-Dermine.resGuard=false`, `Ai` (NEW; flag bites) | 83,942 | **all agree** |
| 2,000 random systems | 2,000 | **all agree**, 48 rejected |
| L1 regression (`l1sweep.sh` re-run from scratch) | 383 | **all agree** |
| five random systems of my own x three bases (NEW) | 15 | **all agree, all byte-identical** |
| M3 block-boundary segments | 6 | all agree |
| M2 skolem segments | 5 | all agree |
| hand-built replay segments (NEW) | 2 | behave as the Scala specifies |
| `-Dermine.genRules=all`, `Ai` (NEW) | 83,942 | **all agree**; model 270.7 s; 12,200 `CommonSubexpressionMint` |
| `-Dermine.disjunction=true`, NE6 bases 0-2 (NEW) | 3 | **all agree**; base 1 fires `Disjunction` 4 times |
| **grand total compared at matched flags** | **920,611** | **37 differ, all M4, all behind `-Dermine.emptyRow`, which ships OFF** |
| **NEGATIVE CONTROLS** (each should differ, and does) | | |
| M3 with `suHi` raised so no block is crossed | 6 | **2 differ**, at the two segments the report names |
| M2 with `Skolem` rewritten to `Free` | 5 | **5 differ** |
| M2 with `Skolem` rewritten to `Ambiguous(Skolem)` | 5 | model SOLVES all five — `isSkolem` is exact |
| shipped-flag model vs `splitKey=false` trace | 83,942 | **41 differ** |
| shipped-flag model vs `resGuard=false` trace | 83,942 | **15 differ** |
| `C`/`c` representation flag flipped on the six segments carrying a size-4 `HashSet` | 6 | still agree — so that flag is defensive, not exercised (see below) |

## What I did NOT re-run, plainly

* The four corpus groups `bugs`, `guide`, `shouldfail-controls` and `incomplete` at the shipped
  flags. I read the implementer's saved traces for those (to measure the population in F1) but
  did not re-trace them. `incomplete` is 590 s of compiler and 85 s of model; the other three
  contribute 64 non-trivial solves between them and 0 of their own from `bugs` and `guide`.
* The `Disjunction` seed sweep of §4d (29 comparisons) — I ran three of its NE6 bases instead
  (below), not all 29.
* The full 2,355,430-segment re-verification of §4f. I ran 286,846 at the shipped flags plus
  the variants; the segment-count and agree-count arithmetic of the four groups I did run
  matches §4a to the digit, which is the part §4f re-checks.
* The parallel-loader `gu05` MODEL replay (618 s). I re-ran the compiler side both ways and
  measured the interleaving directly (§5), which is what the claim rests on.

**Housekeeping note, not a finding against the work.** A `looptrace --replay … --flags=disj`
process from the implementer's abandoned disjunction corpus attempt (PID 1041991, started
13:39) was still running when I reviewed, 92 minutes in, writing to a file in a directory that
has since been deleted. It self-terminates on its own `timeout 7200`. Two consequences worth
recording: it was burning a core during my timings (so my model times are if anything
pessimistic), and it is evidence that under `-Dermine.disjunction` the MODEL side, not only the
compiler side, fails to finish the 54,199-segment boot trace — where at the shipped flags the
same trace takes 888 ms. The report's §4d attributes the abandonment to the compiler ("the
stdlib boot alone ran 14 minutes without completing"); §9 should record that the model is at
least as far from finishing.

## Two things worth recording that neither report states

**(a) The strongest evidence in the stage is the queue order at real qualified names.** `Lbl`
became a `Name` in L2, and `Lbl.hshOf` feeds `RHS.hsh` -> `Partition.hashCode` -> the
priority-search queue's key, so the DEQUEUE ORDER of every corpus solve is a function of
`Name.hashCode` and `MurmurHash3` over 10,842 real `Global(module, string)` names. Byte-equal
`step` and `learn` streams across 286,846 segments is a much sharper test of that than the
twelve new `#guard`s, most of which restate `hshOf`'s own definition rather than pinning a
JVM-probed constant (only the `Global("Repro","l1")` guard does that). Related: **197 corpus
`ConcreteRho`s really are CHAMP `immutable.HashSet`s**, up to 13 labels wide, so the model's
`champSort` is exercised on real names — which is exactly what L1's review said its fuzz could
not reach ("`gen_random` was given at most five labels").

**(b) The `C` / `c` representation flag is defensive, not exercised.** `RowTrace` records
whether a `ConcreteRho`'s field set is an `immutable.HashSet` (`C`) or a `SetN` (`c`) because
"the size does not determine that". The corpus has **10** four-element `C`s (against 234
four-element `c`s) and **no `C` of size 3 or less**. I flipped all six segments carrying one
from `C` to `c` and replayed: **still 6/6 AGREE**. That is expected on reflection — the model is
fed the recorded ITERATION order, so a size-4 `SetN` reproduces it trivially, and `SSet.incl`
re-champs at size 5 either way — so the distinction can only bite for a `HashSet` of size <= 3,
which the corpus does not contain. Keep the field (it costs nothing and the next corpus may
have one), but the report should not imply it is under test.

## Spot checks on the report's other numbers

Everything I could cheaply verify, verified:

| report claim | my measurement |
|---|---|
| `Ai` 677 solves start with <10 ids left in their block | **677** |
| largest solve `nSat = 39`, `Ai/IncidentSeverity.e(69:15)`, 140 dequeues | **39, 140 `step` records** |
| largest saturated set in the sweep = 97, `incomplete/.probeC.e(62:1)` | **97, same file** |
| `gu05` serialized `nSat = 83`, parallel much larger | **83 serialized, 458 parallel** |
| corpus label forms all `Global`/`Idfix` | **10,842 `slbl`, all `G` con 1** |
| §11's file/line table and the `git diff --numstat` | every line count and every `+n/-m` matches, except the report's own line count (443 vs 475 now) |
| build 833 / audit 2530-0 / looptrace 24 | all three reproduce |

(Aside, pre-existing and not L2's doing: one of the "110 example modules" is
`core/examples/incomplete/.probeC.e`, a hidden probe file from an earlier stage, and it is the
one with the largest saturated set. The corpus is 109 modules plus that probe.)

## Two more variants, closing the `Inference`-tag coverage

| variant | group / seeds | segments | AGREE | note |
|---|---|---|---|---|
| `-Dermine.genRules=all` / `--flags=all` | Ai | 83,942 | **83,942** | model 270.7 s, matching §9's "270 s" exactly; the trace carries **12,200** `CommonSubexpressionMint` occurrences, so the minting branch really fires |
| `-Dermine.disjunction=true` / `--flags=disj` | NE6 bases 0, 1, 2 | 3 | **3** | base 1 fires the `Disjunction` rule 4 times; bases 0 and 2 do not reach it |

So I have personally seen both flag-gated rules (`CommonSubexpressionMint` and `Disjunction`)
firing with the model agreeing, which is the coverage §4c and §4d claim.

## VERDICT: FIX-THEN-ADVANCE

**The technical work is sound and I found no correctness defect.** Every headline figure I
re-ran reproduced — build 833, audit 2530/0, `looptrace` 24, `core/test` 910/911, four corpus
groups segment for segment, the 2,000 random systems including the 48 rejections, the 383 L1
comparisons, the 37 M4 mismatches in the same two groups. The two model gaps L2 found (M2's
skolem refusal, M3's `Supply` block boundary) are fixed correctly and, by my own doctored-trace
controls, are LOAD-BEARING rather than cosmetic; the accepted abstraction (M4) is real, scoped
to a default-off flag, and conservative in a direction I verified from the source rather than
from the sample. I added two flag variants, five random systems at three bases, two hand-built
replay inputs and five negative controls, and everything agreed at matched flags and diverged
where it should.

The fix list is **documentation only — no code change, no Lean change, and nothing to re-run.**
I list it as FIX-THEN-ADVANCE rather than ADVANCE because the plan's own protocol says a stage
advances when the reviewer's list is empty *or every remaining item is recorded in the report as
accepted scope*, and five of these are facts that are currently recorded nowhere.

**Required before advancing (all edits to prose):**

1. **F6** — `tracker/lean/README.md:54`: `2527` -> **`2530`**. Also §11's line count for
   `L2-CORPUS.md` itself (443 -> 475).
2. **F1** — wherever `2,355,430` appears (report §4a and the headline, `tracker/LOOP-MODEL-PLAN.md`'s
   L2 status row, `tracker/lean/README.md`), give the shape of it too: **26,864 of those
   segments carry a row constraint, 12,310 are distinct solves, and the 129-module stdlib boot
   is replayed 42 times** (7 groups + 35 `incomplete` files) accounting for 2,276,358 of them.
   `bugs` and `guide` contribute 0 non-trivial solves of their own.
3. **F2** — restate §6's nested-`Exists` row and §10.5: the kind is NOT carried past
   `addRecord` and `nonpart` lumps `exists` with the thousands of `AppT`s; what actually
   catches a nested `Exists` is the `nRows` cross-check, which misses one with no row
   constraints (and would then mis-order it, `r ++ cs` vs `t :: r`).
4. **F3** — add to §6: the `hashCode` and `equals` class of NON-`part` constraint-list elements
   are taken from the trace, not modelled; scope = every `AppT` class constraint (thousands per
   group); why L3 does not depend on it = its theorems quantify over an initial `State`.
5. **F4** — add to §6: the `ex` records (`unbindExists`'s existentials) are neither replayed
   nor compared; scope = 797 records in a `top` trace; harmless because `es` reaches only those
   records and `reduce`, and its ids are already inside `sin`'s `suLo`.
6. **F5** — `tracker/LOOP-MODEL-PLAN.md`'s L3 (iv) should read "`Nodup` and `LblCoh`
   hypotheses", and L3's scope should state that the PARALLEL loader's solves — the compiler's
   largest, `gu05` at `nSat = 458` against 83 serialized — are outside the population L2
   validated.

**Recommended, not required:** F7 (the by-name thunk per solve, if anyone ever profiles it),
F8 (fold `hashdiff`/`eqdiff` into `looptrace-diff.py`'s `bad`), a §9 sentence that the model
side also fails to finish a corpus sweep under `-Dermine.disjunction`, and one sentence that
the `C`/`c` representation flag is defensive rather than exercised.

## Commands (all of mine)

```bash
export PATH=$HOME/.elan/bin:$PATH
cd tracker/lean && lake build Rowpartition && lake env lean Audit.lean && lake build looptrace

export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH
sbt -batch -J-Xmx3g core/test                                          # ONCE, first, 274 s

R=/home/dmitry/.claude/jobs/880c725d/tmp/review-L2
LOOPTRACE_GROUPS="boot top Ai shouldfail" tracker/tools/looptrace-corpus.sh $R/corpus
LOOPTRACE_GROUPS="boot top Ai shouldfail" LOOPTRACE_JAVA=-Dermine.emptyRow=true \
  LOOPTRACE_FLAGS=--flags=emptyrow      tracker/tools/looptrace-corpus.sh $R/var-emptyrow
LOOPTRACE_GROUPS="Ai"  LOOPTRACE_JAVA=-Dermine.splitKey=false  LOOPTRACE_FLAGS=--flags=nosplitkey  ... $R/var-nosplitkey
LOOPTRACE_GROUPS="top" LOOPTRACE_JAVA=-Dermine.resGuard=false  LOOPTRACE_FLAGS=--flags=noresguard  ... $R/var-noresguard
LOOPTRACE_GROUPS="Ai"  LOOPTRACE_JAVA=-Dermine.resGuard=false  LOOPTRACE_FLAGS=--flags=noresguard  ... $R/var-noresguard-Ai
LOOPTRACE_GROUPS="Ai"  LOOPTRACE_JAVA=-Dermine.genRules=all    LOOPTRACE_FLAGS=--flags=all         ... $R/var-all

python3 $R/../L2/gen-seeds.py $R/seeds  2000 1           # the implementer's population
python3 $R/../L2/gen-seeds.py $R/myseeds   5 20260904    # mine
$R/randsweep.sh 2000 4        # 2,000 systems, 4 jobs
$R/l1sweep.sh                 # the 383 L1 comparisons, both sides regenerated
$R/myseeds.sh                 # my five seeds x bases 0, 7, 41
$R/gu05.sh                    # parallel vs serialized segmentation
$R/extra.sh                   # genRules=all on Ai, disjunction on NE6 0-2
$R/segx.py <trace.gz> <out> <comma-separated segment indices>     # segment extractor
```

Scratch (306 MB, traces gzipped): `/home/dmitry/.claude/jobs/880c725d/tmp/review-L2/`.
No `.ei` files left under `core/examples` (checked, 0). Nothing committed; nothing outside my
scratch directory and this file was written.
