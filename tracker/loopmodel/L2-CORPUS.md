# L2 — trace equivalence of the Lean loop model against the compiler, over the WHOLE corpus

Stage L2 of `tracker/LOOP-MODEL-PLAN.md`. Implemented 2026-09-04.

**Result. At the shipped flags the Lean loop model reproduces the compiler's trace on EVERY
solve the compiler performs while it loads the corpus — the 110 example modules and the
129-module stdlib boot — and on 2,000 random systems from `rowclosure.py`'s generator: 0
mismatches, 0 skipped segments, compared BYTE for byte at the compiler's own ids.**

**Read the headline number carefully.** The sweep compares **2,355,430 solve segments**, but
that is a count of REPLAYS, not of distinct solves. Every group's JVM boots the stdlib, and
`incomplete/` runs one JVM per file, so the 54,199-segment boot is replayed **42 times** (7
groups + 35 files) — 2,276,358 of the 2,355,430, i.e. **96.6 %**. And **98.9 %** of all
segments are trivial: only **26,864** carry a row constraint at all (`sin`'s `nRows > 0`),
and only **12,310** of those belong to the group's own modules rather than to the boot.
So the honest headline is:

> **26,864 segments carrying a row constraint, of which 12,310 are not repeats of the bare
> stdlib boot (10,694 have a location under `core/examples` itself), plus 2,000 random
> systems — 0 mismatches, 0 skips.**

The 42 bases are real coverage rather than padding: replaying one module at many id bases is
what L1's base sweeps do, and it is exactly how **M3, the `Supply` block boundary, was found**
(two segments in one of the 42). But "2,355,430 solves" would overstate the distinct
population by about 190x, so both numbers are given here, in the plan's status row and in
`tracker/lean/README.md`. (Found by the L2 review, F1.)

Getting there took four record types added to `RowTrace`, three mismatch classes found and
fixed (§5), and one accepted abstraction behind a default-off flag (M4). Every number below
was run; §4f re-ran all of them on the final binary.

## The question

Does the L1 model (`tracker/lean/Rowpartition/Loop/`) reproduce the compiler's
`-Dermine.rowTrace` on EVERY `Subst.solve` the compiler performs on the 110-module example
corpus and the 129-module stdlib boot, and on 2,000 random systems from `rowclosure.py`'s
generator? Acceptance: 0 unexplained mismatches; every explained class either fixed in the
model or recorded here as a deliberate abstraction with its exact scope.

## 1. What had to be added before a corpus solve could be replayed at all

L1 ran the model on `json:` seeds built by `tracker/repro/satterm/SatTermRepro.scala`, where
the harness chooses every id, every flavour and every label. A corpus solve chooses none of
them, and the serialized trace did not carry them. Four record types now do
(`RowTrace.scala`'s FORMAT block documents each field; all four are inert unless
`-Dermine.rowTrace` is set, like every other record there):

| record | fields | why the model cannot do without it |
|---|---|---|
| `sin` | `suLo suHi nCs` | the `Supply`'s next id at the START of the solve. `V.hashCode` IS the id and the queue is ordered by `rhs.hashCode`, so a mint at the wrong id reorders the queue. It also OPENS a solve segment: it is written before the solve does anything, so a trace splits into solves at `sin` boundaries even when a solve DIES and writes no `solve` line. |
| `slbl` | `idx kind con module string` | the label table. `Name.hashCode` is `(2, module, string, fixity.con).hashCode` (`Name.scala:39`), which decides the `Set` iteration order and hence both the queue order and the printed rows. `toString` alone does NOT determine it: `Prefix`, `Infix` and `Postfix` all print `module.(string)` and two of them share a `con`. |
| `svar` | `id ty name` | every input variable's `VarType` and `V.name`. `Partition.toString` prints `'^' + ty.toString.toLowerCase + id`, and in real code `ty` is `Free`, `Skolem`, `Bound`, `Unspecified` or `Ambiguous(_)` with no relation to the id. **This is L1 review F7, L2's declared first blocker**, and it is now removed rather than worked around: `Names.tys` carries the real flavour and `Names.pvar` reads it. |
| `scon` | `i eqid hash kind payload` | the constraint list in the order `PQueue.build` receives it. `Exists.apply` puts that list through `p.toSet.toList` before `aux` sees it, so an element the solver never inspects — a class constraint, say — can still MOVE the ones it does. `eqid` (the index of the first element this one is `equals` to) and `hash` are exactly what that reordering reads. A `part` payload carries the lhs and each rhs term, with a `ConcreteRho`'s fields as label-table indices IN ITERATION ORDER — which `in` and `inpart` sort away and `Partition.toString` prints raw. |

`RowTrace.supplyBounds` reads the `Supply`'s private `lo`/`hi` reflectively rather than
widening their visibility; it is a READ that takes no id, so the compiler draws exactly the
ids it would have drawn with the property unset. `tracker/repro/satterm/SatTermRepro.scala`'s
`drawnOf` already reads `lo` the same way.

**Scala changed**: `RowTrace.scala` (+122 lines: the four record formats in the header, and
`supplyBounds` / `solveInput`) and ONE call line in `Subst.solve`, placed after
`unbindExists` and before `PQueue.build` because it must see the `Supply` before
`PQueue.build` draws from it and the constraint list before `Exists.apply` reorders it. The
brief allows record types in `RowTrace.scala`; the call site is unavoidable, since
`RowTrace` cannot see a solve's arguments on its own, and it is one statement whose whole
body is under `if (enabled)` with a by-name `loc`. Compiled ONCE (`sbt -batch core/compile`,
9 s, success).

## 2. What changed in the Lean model

| file | change |
|---|---|
| `Loop/State.lean` | `Lbl` is a `Name` — `(n, glob, mod, str, con)` — not a number. `toStr` and `hshOf` are `Name.toString` and `Name.hashCode` for both `Global` and `Local` and for every fixity. `Lbl.repro n` rebuilds L1's `Global("Repro", "l" ++ n)`. `Names` gains `tys`, and `pvar` reads it (F7). |
| `Loop/Json.lean` | `ITerm` gains `conT` (a `Con` in a row position, which `RHS.build` treats as a one-label concrete row, `Constraints.scala:394`) and `opaque` (anything else, carried so `Part.hashCode` stays exact). New `CsItem`: one element of the constraint list, either a `part` or an `other` reduced to its hash and `equals` class. `existsApply` is generic; `buildQueue` takes `List CsItem`. |
| `Loop/Trace.lean`, `Loop/Seed.lean` | the record `loc` (third column) is a parameter instead of the constant `-`. |
| `Loop/Replay.lean` (NEW) | the `sin`/`slbl`/`svar`/`scon` parser and the per-segment driver. Total: a record it cannot parse makes the SEGMENT unreplayable and is reported, never silently dropped. |
| `Loop/Main.lean` | `--replay <trace.tsv> [--flags=..] [--fuel=N] [--from=I] [--to=J]`: ONE process per corpus file, a `#seg` marker per solve, `#skip`/`#REJECTED`/`#FUEL`/`#hashdiff` diagnostics and a `#summary` line. |
| `Loop/Conformance.lean` | the four `Lbl` guards restated, plus **12 new ones** for the label forms a `json:` seed cannot produce (a qualified `Global`, a `Local`, a non-`Idfix` fixity, `Con.hashCode`) and for `pvar` reading the `svar` table. |
| `Loop/Bridge.lean` | `Lbl.n` is now the label's TABLE INDEX rather than the label itself, so it is injective on one solve's labels and not on the type. `toFinset_map_n_iff` and `LPart.eqv_iff_toConstraint` take that as an explicit hypothesis, `LblCoh`. |
| `tracker/tools/looptrace-diff.py` | `--segments` mode: split the compiler side at `sin`, the model side at `#seg`, pair by index, compare RAW (no id normalisation — a replay runs at the compiler's own ids), classify by the record type at which a pair first differs. |
| `tracker/tools/looptrace-corpus.sh` (NEW) | the sweep. |

## 3. What the corpus actually contains

Measured off the traces themselves, because it decides which of the model's branches are
under test and which are only under `#guard`:

| | |
|---|---|
| variable flavours the corpus uses | `Free`, `Ambiguous(Free)`, `Ambiguous(Ambiguous(Free))`, `Ambiguous(Bound)`, `Skolem` — five, of which L1's id rule got two right |
| label forms | every corpus label is a `Global` at `Idfix` (`con` 1). `Local`, `Prefix`/`Infix`/`Postfix` and `Con`-in-a-row-position are covered by `Conformance.lean` guards only |
| constraint-list elements | `part` and `AppT` (a class constraint) — no nested `Exists`, and no row term the model calls `opaque` |
| `Supply` block room at solve start (`Ai`) | 677 of 83 942 solves start with fewer than ten ids left in their 1024-id block |
| largest solve | `nSat = 39` (`core/examples/Ai/IncidentSeverity.e:69`), 140 dequeues |

**The population is the SERIALIZED loader's.** `-Dermine.loadInSeries=true` is not optional
here: the segmentation assumes one solve's records are contiguous, and the parallel loader
interleaves the records of solves running in different threads. That changes what is being
covered, and the difference is already documented: `tracker/satterm/KEYED-SPLIT-STAGE2.md`
§B5 measured that `gu05`'s expensive solve — the corpus's famous 1,372-partition,
436-fresh-id one, and the reason L1 §10 flagged performance as a risk — **does not happen at
all under the serialized loader**, where the same module reports `nSat = 83`. So this sweep
covers every solve the compiler performs when it loads the corpus module by module, and NOT
the larger solves the parallel loader's id interleaving produces. §8 runs the one module that
shows the difference both ways.

**Stated plainly, so it is not read past:**

* **The parallel loader's solves — including `gu05`'s 1,372-partition one — are OUTSIDE this
  population, and no number in this report covers them.** They are outside not because the
  model fails on them but because a `RowTrace` written by a parallel load cannot be segmented
  at all: `RowTrace.log` synchronises per LINE, so concurrent solves interleave their records
  (§8 measures it: 1,654 of `gu05`'s 54,235 parallel segments hold more than one `solve`
  record). Including them needs a THREAD ID on every trace record, which is a different
  instrumentation change and would break `keptdef-mints.py`'s format.
* **`-Dermine.disjunction=true` has no corpus sweep, on EITHER side.** The compiler did not
  finish the stdlib boot in 14 minutes; and the L2 review found that the MODEL does not finish
  that trace either — an abandoned `--flags=disj` replay of the 54,199-segment boot trace was
  still running after 92 minutes, against 888 ms at the shipped flags. `Disjunction` is
  therefore covered by seeds only (§4d).

## 4. Results

Every number below comes from ONE build of both sides — `sbt -batch core/compile` and
`lake build looptrace` after the last change — re-run from scratch. The compiler side is
`-Dermine.rowTrace` with `-Dermine.loadInSeries=true -Dermine.useInterface=false`, one JVM
per corpus directory (`incomplete/` per file, see §7); the model side is one
`looptrace --replay` per group; the comparison is `looptrace-diff.py --segments`, which pairs
segments by index and compares them RAW.

### 4a. The corpus at the shipped flags

| group | files | compiler | segments | model | AGREE | SKIP | mismatch |
|---|---|---|---|---|---|---|---|
| `boot` (stdlib only) | 0 | 17 s | 54,199 | 888 ms | 54,199 | 0 | — |
| `top` | 15 | 21 s | 92,673 | 1,744 ms | 92,673 | 0 | — |
| `Ai` | 11 | 21 s | 83,942 | 19,133 ms | 83,942 | 0 | — |
| `shouldfail` | 40 | 18 s | 56,032 | 1,068 ms | 56,032 | 0 | — |
| `bugs` | 2 | 17 s | 54,235 | 915 ms | 54,235 | 0 | — |
| `guide` | 2 | 17 s | 54,244 | 881 ms | 54,244 | 0 | — |
| `shouldfail-controls` | 5 | 17 s | 54,739 | 986 ms | 54,739 | 0 | — |
| `incomplete` | 35 | 590 s | 1,905,366 | 85,124 ms | 1,905,366 | 0 | — |
| **total** | **110** | | **2,355,430** | **110,739 ms** | **2,355,430** | **0** | **0** |

**0 mismatches, 0 skipped, 0 hash cross-check failures, 0 `equals`-class cross-check
failures.**

**What those 2,355,430 segments really are** (L2 review, F1; every figure below re-counted
from the traces off `sin`'s `nRows` field and `loc`):

| group | segments | with a row constraint | not a bare-boot repeat | `loc` under `core/examples` |
|---|---|---|---|---|
| `boot` | 54,199 | 383 | 383 | 0 |
| `top` | 92,673 | 5,424 | 5,424 | 4,999 |
| `Ai` | 83,942 | 4,494 | 4,494 | 4,069 |
| `shouldfail` | 56,032 | 647 | 647 | 264 |
| `bugs` | 54,235 | 383 | **0** | 0 |
| `guide` | 54,244 | 383 | **0** | 0 |
| `shouldfail-controls` | 54,739 | 447 | 64 | 64 |
| `incomplete` | 1,905,366 | 14,703 | 1,298 | 1,298 |
| **total** | **2,355,430** | **26,864** | **12,310** | **10,694** |

Two things follow, and neither is a defect.

* **96.6 % of the segments are the stdlib boot, replayed.** Every group's JVM boots the
  stdlib, and `incomplete/` runs one JVM per FILE, so the 54,199-segment boot appears 42 times
  (7 groups + 35 files) = 2,276,358 segments. `bugs` and `guide` contribute nothing of their
  own at all: their two modules each raise no row constraint the boot did not already raise.
* **98.9 % of the segments are trivial**: 2,328,566 of them have `nRows = 0`, so their whole
  compared content is one `solve` record with `rows=0` — the compiler and the model both do
  nothing, and agreeing about it is worth little.

**The 42 repeats ARE coverage, though.** Each run starts a fresh `Supply`, so the same module
is replayed at 42 different id bases — which is what L1's per-base sweeps do, and is exactly
how **M3, the `Supply` block boundary, was found**: it showed up in two segments of ONE of the
42, and a single-base sweep would have missed it. The point of F1 is only that "2,355,430
solves" overstates the distinct population by about 190x, so both numbers are given.

What is actually compared inside the non-trivial ones:

| | |
|---|---|
| segments with at least one dequeue | **26,405** |
| `step` records compared | **70,679** |
| `learn` records compared | **100,522** |
| `in` / `inpart` / `sat` / `solve` records compared | one `solve` per solved segment, plus the whole input and saturated populations |

Dispatch branches exercised (all five): `learn` 61,301, `concrete` 3,615, `empty` 2,079,
`unify` 1,898, `common` 1,786.

`Inference` tags exercised at the shipped flags (12 of 16): `CommonSubexpression` 53,217,
`Substitution` 36,436, `Cancellation` 28,789, `SplitConcrete` 3,181, `Resolution` 2,683,
`PartitionEmpty` 933, `DeDuplication` 496, `CommonPartition` 250, `SelfSubstitution` 174,
`SplitKeyed` 165, `ResolutionRow` 39, `SplitRow` 11. The other four are behind flags and are
covered in 4c.

### 4b. Random systems

2,000 seeds from `rowclosure.py`'s own generator, each run through
`tracker/repro/satterm/run.sh` at one id base (`base = index mod 40`, to spread the id space)
and replayed. The parameters are the `search` sub-command's DEFAULTS, which is the population
that sub-command searches: `--rng 1`, `k ∈ [3,7]` constraints, `m ∈ [2,4]` variables per row,
`n ∈ [2,6]` labels, `--p-empty 0.25 --p-dup 0.25 --p-self 0.04`, `--no-empty` off.

| | segments | AGREE | SKIP | of which REJECTED |
|---|---|---|---|---|
| 4 jobs × 500 seeds | 2,000 | **2,000** | 0 | 48 |

The 48 rejections are systems the compiler refutes; the model dies at the same record.

### 4c. Flag variants

L1 §10 item 3 asked for at least one flag-variant sweep, because `CommonSubexpressionMint`
and `Disjunction` cannot fire at the shipped defaults. `boot top Ai shouldfail` at each:

| variant | compiler flag | model flag | segments | AGREE | mismatch |
|---|---|---|---|---|---|
| empty row | `-Dermine.emptyRow=true` | `--flags=emptyrow` | 286,846 | 286,809 | **37** (class M4 below) |
| all generative rules | `-Dermine.genRules=all` | `--flags=all` | 286,846 | **286,846** | 0 |

The `emptyRow` variant fires `SplitEmpty` 180 times and `ResolutionEmpty` 161; `genRules=all`
fires `CommonSubexpressionMint` 8,241 times. With those two runs, **15 of the 16 `Inference`
tags are exercised by a corpus sweep**; the sixteenth, `Disjunction`, is covered by seeds
(4d), because `-Dermine.disjunction=true` does not finish a corpus sweep **on either side**:
the compiler's stdlib boot ran 14 minutes without completing and was still writing trace, and
the L2 review found that the MODEL does not finish that trace either — an abandoned
`--flags=disj` replay of the 54,199-segment boot trace was still running after 92 minutes,
against 888 ms for the same trace at the shipped flags.

### 4d. `Disjunction`, on seeds

`-Dermine.disjunction=true` against `--flags=disj`, the tracked and regression seeds at
bases 0-9 (`tracker/repro/satterm/run.sh trace` per base, `looptrace-diff.py` per pair).
| seeds | comparisons | `Disjunction` records in the compiler traces | result |
|---|---|---|---|
| `W2` bases 0-9, `H2` bases 0-9, `NE6` bases 0-8 | **29** | **16,683** (all on `NE6`; `W2` and `H2` never reach the rule) | **29 agree, 0 differ** |

The sweep was stopped there rather than extended to the remaining seeds: with the flag on,
one `NE6` base takes about a minute, and `Disjunction` was already firing 16,683 times. It
is the only `Inference` tag whose evidence is seeds rather than corpus.

### 4e. The L1 sweeps, re-run on this build

The brief requires the L1 evidence to survive every change. Regenerated on BOTH sides with
the final build:

| sweep | comparisons | result |
|---|---|---|
| `W2 H2 NE6 W3 W4 G7` × bases 0-29, shipped flags | 180 | agree |
| the same six × bases 0-9, `emptyRow` | 60 | agree |
| `RR RE CHAIN COLL LBL REF SUP` × bases 0-14, shipped | 105 | agree |
| `RE RR` × bases 0-14, `emptyRow` | 30 | agree |
| `D1`-`D4` × bases 0,3, `labelCheck` off | 8 | agree |
| **total** | **383** | **0 differing, and all 383 BYTE-identical** |

(Byte-identity checked separately with `diff` over the six record types, not only through the
normalising harness: 383 identical, 0 differing.)

`Conformance.lean`'s guards all pass — they are `#guard`s, so `lake build Rowpartition`
failing is the only way they could not.

### 4f. Everything re-verified on the FINAL binary

The last change to the model was a constructor rename (`ITerm.opaque` → `ITerm.otherT`, so
that a reviewer's `grep -w opaque` under `Loop/` returns only prose). Rather than argue that
a rename is behaviour-neutral, every saved trace was replayed and re-diffed with the binary
that shipped:

| | segments | AGREE | SKIP |
|---|---|---|---|
| corpus, shipped flags (8 groups) | 2,355,430 | 2,355,430 | 0 |
| `emptyRow` variant (4 groups) | 286,846 | 286,809 | 0 |
| `genRules=all` variant (4 groups) | 286,846 | 286,846 | 0 |
| random systems (4 jobs) | 2,000 | 2,000 | 0 |
| **total** | **2,931,122** | **2,931,085** | **0** |

The 37 are M4, and all of them are under `-Dermine.emptyRow`, which ships OFF.

**Totals for the acceptance criterion.** At the SHIPPED flags — the configuration the plan is
about — **0 mismatches and 0 skips** over 2,355,430 corpus segments (of which 26,864 carry a
row constraint and 12,310 are not bare-boot repeats; see §4a for why both numbers are given)
and 2,000 random systems. Across every configuration run, 2,931,122 segments and **37
mismatches, all in one explained class, all behind a default-off flag**.

## 5. Mismatch triage

Every class that appeared, in the order it was found. "Unexplained" is a failure of the
stage, so each row ends in a fix or in a scoped abstraction.

### M1 — the label table was indexed in reverse (harness bug, FIXED)

* **First differing record.** `top`, seg 54253, `core/examples/Accumulate.e(14:3)`:
  `lean : step … concrete ^free303202 <- (,Accumulate.nodeId Accumulate.name)` against
  `scala: step … concrete ^free303202 <- (,Accumulate.name Accumulate.nodeId)`.
* **Cause.** Mine, not the model's. `Loop/Replay.lean`'s `Segment` accumulated the `slbl`
  records by PREPENDING and reversed them in `finish` — but `parseTerm` indexes into that
  list while the `scon` records are still being read, so a `c0,1` payload picked up the
  labels in the wrong order (and, with three or more labels, the wrong labels entirely).
* **Effect.** 887 of `top`'s 92 673 segments, 818 of `Ai`'s 83 942, 39 of `shouldfail`'s
  56 032, and every one of the 231 `hashdiff` segments those runs reported — a `ConcreteRho`
  built from the wrong labels has the wrong `hashCode`, which is exactly what the `scon`
  cross-check is for.
* **Fix.** `Segment.labels` is built FORWARDS. `Loop/Replay.lean` says so where the field is
  declared, because it is the one of the four that cannot be reversed at the end.

### M2 — `makeEmpty`'s SKOLEM refusal (model gap, FIXED)

* **First differing record.** `shouldfail`, seg 55915,
  `core/examples/shouldfail/sk01_row_append_self.e(35:29)`: the model wrote
  `in … 0 r^350061 r^350038 | r^350038` where the compiler wrote nothing at all — the
  compiler had already died, and the model was still going.
* **Scala.** `Constraints.scala:1577`, inside `makeEmpty`:
  `if (v.ty == Skolem) tml.die(v.report("Cannot unify skolem variable with empty relation", …))`
  — the ONLY place in the whole loop that looks at a variable's flavour. The five
  `shouldfail/sk0*` modules each write a row append of a variable with itself
  (`r^350038 | r^350038`), which `RHS.build` turns into "both parts forced empty", and the
  variable is a SKOLEM.
* **Lean.** L1 listed this in `L1-MODEL.md` §7 as not modelled, correctly: a `json:` seed has
  no skolem, so no L1 seed could reach it. With `svar` carrying the real `VarType` there is
  nothing left to abstract, so it is now `Loop/Step.lean`'s `makeEmpty`, in the Scala's own
  position — AFTER the `nps` fold, so an "Incompatible instantiations" contradiction still
  wins, and BEFORE `instantiateType`, so the reinstantiation panic still comes after.
* **Effect.** 5 of `shouldfail`'s 56 032 segments; 0 after the fix.

### M3 — `Supply.fresh` crossing a BLOCK BOUNDARY (model gap, FIXED)

* **First differing records.** `Ai`, seg 60504, `core/examples/Ai/IncidentSeverity.e(69:15)`:
  the model minted `^ambiguous(free)336895` where the compiler minted `336896`. And `Ai`,
  seg 81326, `core/examples/Ai/SupplyChainInventory.e(71:70)`: the compiler's ids jump to
  `393216` while the model is still at `392186` — a gap of about a thousand.
* **Scala.** `parsers/src/main/scala/scalaparsers/Supply.scala:22`. A `Supply` owns a block
  of `blockSize = 1024` ids; `fresh` hands out `lo` and advances it, but when `lo == hi` it
  calls `getBlock`, which returns the GLOBAL counter `Supply.block` and advances that by
  1024. So the next id after a block runs out is not `hi + 1`: it is wherever that counter
  stands. `V.hashCode` IS the id and the queue is ordered by `rhs.hashCode`, so a mint at the
  wrong id reorders the queue and everything after it diverges.
* **Lean.** L1's supply was a single `Nat` — exact for a seed, because the repro harness
  builds `Supply(base, base + 100000)`. `Loop/State.lean` now has `Sup`, which is
  `scalaparsers.Supply` field for field, and `Sup.fresh` is `Supply.fresh` branch for branch;
  it is threaded through `splitConcrete`, `resolution`, `commonSubexpression`, `disjunction`,
  `PQueue.build` and `learnPartitions` in place of the `Nat`. The trace's `sin` record now
  carries `suLo`, `suHi`, the global counter and the block size.
* **Effect.** 677 of `Ai`'s 83 942 solves START with fewer than ten ids left in their block,
  and 2 of them actually cross while minting; 0 after the fix. `RowTrace.supplyBlock` reads
  `Supply.block` and `Supply.blockSize` reflectively — reading, never calling `getBlock`,
  which would consume a block and change the ids the compiler hands out.

### M4 — `envEmptyRow` reads the WHOLE inference's `SubstEnv` (accepted abstraction, `-Dermine.emptyRow` only)

* **First differing record.** `Ai`, seg 54341, `core/examples/Ai/ClinicalTrial.e(74:31)`,
  under `-Dermine.emptyRow=true`:
  `lean : learn … new SplitConcrete: ^ambiguous(free)305330 <- (^ambiguous(ambiguous(free))305325 ^ambiguous(free)305329,)`
  against `scala: learn … new SplitEmpty: ^ambiguous(ambiguous(free))305325 <- (,)`.
  The compiler REUSED an empty-row carrier where the model, finding none, MINTED.
* **Scala.** `Constraints.scala`'s `envEmptyRow`:
  `hm.types.collectFirst { case (z, ConcreteRho(_, fs)) if fs.isEmpty => z }`. `hm.types` is
  the `SubstEnv` of the WHOLE inference, not of this solve, so it holds empty-row bindings
  made by EARLIER solves and by unification outside `solve`. The Scala's own comment calls
  this out — "(i) `hm.types` holds the empties of the WHOLE inference, not of this solve's
  system, so unlike `concRows` this lookup is an UPPER bound on the Lean's `EmptyKnown G`".
* **Lean.** `Loop/Step.lean`'s `findEmptyRow` reads `Env`, which the model starts EMPTY at
  each solve — it can only see what this solve's own `makeEmpty` put there. In the segment
  above no `makeEmpty` has run yet when the branch fires, and no `u <- (||)` is in either
  queue, so the carrier can only have come from a previous solve.
* **Scope, exactly.** `-Dermine.emptyRow=true` ONLY, which ships OFF: **37 of 286,846**
  segments in the flag-variant sweep (2 in `top`, 35 in `Ai`), and **0 of 2,355,430** at the
  shipped flags, where the branch does not exist. Every one of the 37 is a
  `SplitEmpty`/`ResolutionEmpty` decision.
* **Why L3 does not depend on it.** The model is CONSERVATIVE here: where the compiler
  reuses, the model mints, so the model's run is a run of the same rule set with a mint the
  compiler avoided — a `K2MintApp` instead of a `K2RowApp`, both steps of the same relation
  (`Rowpartition/KeyedEmptyScala.lean`). It cannot make a diverging model run out of a
  terminating compiler run in the other direction, and at the shipped flags neither branch
  is reachable at all.
* **What would remove it.** One more record: the variables `hm.types` binds to
  `ConcreteRho(∅)` at solve start. That is a third `sbt` recompile for a default-OFF flag's
  37 segments, which is why it was not taken.

## 6. Accepted abstractions carried to L3

These are the places where the model deliberately does not follow the compiler. Each is
stated with the solves it affects and why an L3 theorem about `step` does not depend on it.

| abstraction | scope on the corpus | why L3 does not depend on it |
|---|---|---|
| `Subst.reduce` and its `concr`/`splice` records | runs AFTER `q.expand` returns and after the `solve` record is written; the diff keeps the six record types the LOOP writes and drops these two | L3's theorems are about `step` and its iteration. `reduce` is a separate pass over the SATURATED queue; it neither dequeues nor mints. L1-MODEL.md §7 quantifies its effect on the reported bindings exactly (the compiler binds one more variable per `concr` record). |
| `ensureSuperset`'s MESSAGE | `makeConcrete`'s superset check; the Scala renders a two-row `Document` with `displayFactoredRow`, the model a flat string | messages are not trace records: the `step`/`learn`/`inpart`/`sat`/`solve` records carry no message, and a death is compared by WHERE it happens, which is exact. L3 proves termination and refinement, not error text. |
| `Located` / `Loc` / `sourcePosition` and `labelClash`'s BLAME search | the location a refutation is reported at | the trace's `loc` column is the SOLVE's location, which the replay echoes from the `sin` record; the blame search picks a different location for the user's error message only. |
| CHAMP hash-COLLISION nodes | two elements whose `improve`d hashes agree in all 32 bits; the model keeps insertion order beyond seven 5-bit levels, a real trie makes a `HashCollisionSetNode` (which also keeps insertion order) | not reached: a disagreement would show as a set-order difference in a printed row, and there are none in 2.3 M solves. |
| `Map` ITERATION order (`edges`, `sort`, `resolvents`, `concRows`) and `hm.types` in `envEmptyRow` | only `get` and `+` are used on the first four; the empty-row branches do not print the carrier they find | the model uses association lists with the same `get`/`+`; nothing reads the order. |
| `RowTrace.clean`'s tab/newline escaping | a label or variable name containing a tab | no corpus name contains one; the model would print the raw character. |
| a nested `Exists` in the constraint list | `PQueue.build`'s `aux` would `unbindExists` it and DRAW IDS, and `Exists.apply` APPENDS its contents (`r ++ cs`) where the model's `existsApply` conses; `buildQueue` does neither | not reached: every `scon` in the corpus is `part` or `AppT` (a class constraint), never `exists`. **What would catch a first appearance is the `nRows` cross-check** — `replay` refuses a segment whose `cs.flatMap(_.rowConstraints).length` differs from its number of `part` items, and a nested `Exists` holding any `Part` raises `nRows`. It is NOT the `#summary`'s `nonpart` count: `CsItem.other` drops the kind string and `nonpart` lumps `exists` in with the thousands of `AppT`s. **An `Exists` carrying no row constraint at all would slip through both**, and would be mis-ordered. (L2 review, F2.) |
| the `hashCode` and `equals` CLASS of a non-`part` list element | taken from the trace (`scon`'s `hash` and `eqid`) rather than recomputed — the model does not represent an `AppT` | for a `part` item both ARE recomputed, from the model's own `IPart.hshOf` / `IPart.eqv`, and cross-checked against the recorded values (`#hashdiff` / `#eqdiff`, 0 in every run). For the thousands of `AppT` class constraints per group — which do move the `part` items through `Exists.apply`'s `p.toSet.toList` — the compiler's values are carried verbatim, so the corpus differential does not test the model's construction of the initial queue from a RAW constraint list. It does not weaken L3, whose theorems quantify over an initial `State`. (L2 review, F3.) |
| the `ex` records | `unbindExists`'s existential variables (`es`) are neither part of the replay input nor compared: `looptrace-diff.py`'s `KEEP` drops `ex`, as it drops `concr` and `splice` | harmless — `es` reaches only those records and `reduce`, and the ids it drew are already inside `sin`'s `suLo` (checked on `top` seg 84386: `ex` 375840/1/2, `suLo` 375843) — but it is a compiler record the model does not reproduce, and it was in neither this list nor L1-MODEL §7. (L2 review, F4.) |
| a row term that is neither `VarT` nor `ConcreteRho` nor `Con` | `RHS.build`'s last case dies with a rendered `Document`; the model dies with a flat message | not reached: every term in the corpus is `v` or `c`. |

## 7. The exact commands

```bash
export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH
export PATH=$HOME/.elan/bin:$PATH

# build
sbt -batch core/compile
cd tracker/lean && lake build Rowpartition && lake build looptrace && lake env lean Audit.lean

# the whole corpus: trace, replay, diff, per group
tracker/tools/looptrace-corpus.sh <outdir>

# a flag variant
LOOPTRACE_GROUPS="boot top Ai shouldfail" LOOPTRACE_JAVA=-Dermine.emptyRow=true   LOOPTRACE_FLAGS=--flags=emptyrow tracker/tools/looptrace-corpus.sh <outdir>

# one trace by hand
cd tracker/lean
lake exe looptrace --replay <trace.tsv> > model.out
python3 ../tools/looptrace-diff.py --segments --lean model.out --scala <trace.tsv> --show 6

# the 2,000 random systems: generate, trace one base each, replay, diff
python3 - <<'GEN'          # rowclosure.py's own generator, `search`'s defaults
import json, os, sys, types
sys.path.insert(0, "tracker/tools"); import rowclosure
args = types.SimpleNamespace(seeds=2000, rng=1, k_min=3, k_max=7, m_min=2, m_max=4,
                             n_min=2, n_max=6, p_empty=0.25, p_dup=0.25, p_self=0.04,
                             no_empty=False)
os.makedirs("SEEDS", exist_ok=True)
for i, obj in enumerate(rowclosure.random_seed_stream(args)):
    json.dump(obj, open("SEEDS/S%04d.json" % i, "w"))
GEN
for i in $(seq 0 1999); do f=$(printf SEEDS/S%04d.json $i); b=$((i % 40))
  ERMINE_JAVA_OPTS="-Dermine.rowTrace=rand.tsv" \
    tracker/repro/satterm/run.sh sweep "json:$f" $b $b 60 99 >/dev/null 2>&1
done
cd tracker/lean && lake exe looptrace --replay ../../rand.tsv > rand.out
python3 ../tools/looptrace-diff.py --segments --lean rand.out --scala ../../rand.tsv
```

The sweep script's knobs: `LOOPTRACE_GROUPS` (which directories),
`LOOPTRACE_PERFILE` (which of them run one JVM per FILE — `incomplete` by default),
`LOOPTRACE_FILE_TIMEOUT` (120 s) and `LOOPTRACE_FILE_CAP` (300 MB) for those,
`LOOPTRACE_JAVA` / `LOOPTRACE_FLAGS` (the two sides of a flag variant), `LOOPTRACE_XMX`.

## 8. The parallel loader, and the big solve

L1 §10 flagged performance as the risk, citing "the corpus's largest solve saturates 1,372
partitions". Under the SERIALIZED loader that solve does not exist: the largest saturated set
in the whole sweep is **97 partitions** (`core/examples/incomplete/.probeC.e(62:1)`), and the
largest in `Ai` is 39. `tracker/satterm/KEYED-SPLIT-STAGE2.md` §B5 already recorded why —
`gu05`'s expensive solve is a property of the PARALLEL loader — so `gu05` was run BOTH ways,
one module, one JVM each:

| loader | segments | largest `nSat` | model | AGREE | mismatch |
|---|---|---|---|---|---|
| serialized (`-Dermine.loadInSeries=true`) | 54,235 | 83 | 16.3 s | **54,235** | 0 |
| parallel (the default) | 54,235 | 458 | 618 s | 50,315 | 77 SKIP + 3,842 |

**The parallel run's disagreements are not the model's: that trace cannot be segmented.**
`RowTrace.log` synchronises per LINE, not per solve, so two threads solving at once interleave
their records — and the trace shows it directly: **1,654 of its 54,235 segments contain more
than one `solve` record**, and 1,659 draw records from more than one source location. The
mismatch classes the diff reports are exactly that signature (`length+` 1,778, `solve` 1,682,
`length-` 377). A replay of an interleaved segment is a replay of a system the compiler never
had.

So the population this stage covers is **every solve the compiler performs when it loads the
corpus module by module**, and NOT the larger solves the parallel loader's id interleaving
produces. Making the parallel loader replayable needs a thread id on every record — a
different instrumentation change, and one that would break `keptdef-mints.py`'s format.
(The 1,372 figure is also pre-`splitKey`: with the shipped flag on, the same solve saturates
458, which is what the parallel run above measured.)

## 9. Performance

Measured first, as the brief asks. The model's data structures were **not** changed, because
nothing crossed the bar the brief set ("more than a few seconds" for a solve):

| | |
|---|---|
| whole corpus, 2,355,430 solves | **110.7 s** in eight `looptrace --replay` processes |
| largest group (`incomplete`, 1,905,366 solves) | 85.1 s |
| slowest SINGLE solve at the shipped flags | **1.90 s** — `Ai/IncidentSeverity.e(69:15)`, 140 dequeues, `nSat` 39, extracted to its own file and timed alone |
| slowest single solve under `genRules=all` | 0.16 s — `Ai/SalesByRegion.e(72:6)`, 507 dequeues, `nSat` 338 |
| `Ai` under `genRules=all` (83,942 solves) | 270 s — spread over many solves, not one |
| trace PARSING alone (`--from` out of range) | 0.34 s for the 118 k-line boot trace, 0.71 s for `Ai` |
| the boot trace under `--flags=disj` | **does not finish**: >92 minutes, against 888 ms at the shipped flags (L2 review) |

The one change made for performance was to `--replay` itself, not to the model: it now
STREAMS the trace one segment at a time instead of `IO.FS.lines`-ing it whole. The
`incomplete` group's trace is 551 MB, which as an `Array String` is over a gigabyte of live
Lean strings; streaming holds one segment. The cost is that stripping the line terminator
without `String.trimRight` (whose result type moved in recent Lean) roughly doubles the parse
phase — boot 540 ms → 888 ms — which is the smaller half of a much smaller number.

The one configuration the model cannot get through is `--flags=disj`: `disjunction` is
applied inside a fold over `proc` for EVERY pair, so its cost is cubic in the partition count
where every other rule is quadratic, and the compiler is no better (§4c). That is a property
of the rule, not of the model's data structures.

**Where the time goes, for whoever needs it faster.** The 1.90 s solve has four labels and
long concrete parts; the 0.16 s one has two labels and mostly variables. `SSet.champSort`
computes `improve (SVal.hsh x)` for every element in each of 64 bucket scans per level, and
`SVal.hsh` for a label is two `javaStringHash`es plus a four-element Murmur. The
behaviour-preserving fix is to bucket on precomputed `(hash, element)` pairs — `champSort`'s
order is a function of that hash alone, and `SSet.champSort_perm` transfers to the pair list —
but it changes a definition `Bridge.lean` reasons about, so it is an L4 item, not an L2 one.

## 10. What is still open

1. **`Subst.reduce`** (L1 §10 item 1) stays outside the model, and the diff drops its `concr`
   and `splice` records. That is now a measured quantity rather than a guess: the corpus
   writes them after every solve and the model reproduces everything up to and including the
   `solve` line.
2. **The parallel loader** (§8). A `RowTrace` written by a parallel load cannot be segmented;
   1,654 of 54,235 `gu05` segments prove it. Fixing it means a thread id per record.
3. **`envEmptyRow`** (M4), if `-Dermine.emptyRow` is ever adopted.
4. **`champSort`'s hashing** (§9), if L4's ScalaCheck property wants the model faster.
5. **`Local` labels, non-`Idfix` fixities, `Con` in a row position, and a nested `Exists` in
   the constraint list** are modelled and `#guard`ed but NOT exercised by any corpus solve.
   A first appearance would be caught by the `nRows` cross-check, not by the `#summary`'s
   `nonpart` count — and an `Exists` carrying no row constraint would slip through both
   (§6, L2 review F2).
6. **`Bridge.lean` now has a FIFTH hypothesis.** `LPart.eqv_iff_toConstraint` needs `LblCoh`
   — the label-table index is injective on one solve's labels — as well as the four `Nodup`s
   that L1 review F6 already flagged as unconnected to `step`. It is true by construction of
   `RowTrace`'s label table (a `LinkedHashMap[Name, Int]` keyed by `Name.equals`) and
   trivially true of `ofConstraint`'s output, so it is not a defect — but **L3's acceptance
   (iv) in `tracker/LOOP-MODEL-PLAN.md` names only "the `Nodup` hypotheses" and must name
   `LblCoh` too** (L2 review, F5; the orchestrator is editing the plan). A related note for
   whoever writes L3: `LPart.ofConstraint` builds every label as `{ n := n }`, so all of them
   share one `Lbl.hshOf` — harmless for lemmas stated up to `toFinset`, but any future lemma
   reasoning through `ofConstraint` about `champSort` ORDER would be reasoning about a
   hash-degenerate special case.
7. **Two notes that are not defects** (L2 review, F7 and F8). `RowTrace.solveInput`'s `loc` is
   by-name, which is what stops `Loc.toString` running on the default path, but a by-name
   argument compiles to a `Function0` capturing `l`, so the default path allocates one small
   closure per `Subst.solve`; if that ever mattered the call would be guarded with
   `if (RowTrace.enabled)` at the call site, as the block twenty lines below already is. And
   `looptrace-diff.py --segments` computes its exit status from the mismatch classes only, so
   a segment whose records agree but whose `Part.hashCode` the model got wrong would be
   reported in the file and still exit 0 — it is caught by `looptrace --replay` itself, which
   exits non-zero when `hashdiff` or `eqdiff` is nonzero and whose `rc=` the sweep script
   prints (0 in every run here), but the two ought to agree.
8. **The `C` / `c` representation flag is defensive, not under test** (L2 review). `RowTrace`
   records whether a `ConcreteRho`'s field set is an `immutable.HashSet` or a `SetN` because
   the size does not determine it; the corpus has 10 four-element `C`s and no `C` of size 3 or
   less, and the reviewer flipped all six segments carrying one from `C` to `c` and still got
   6/6 AGREE. The distinction can only bite for a `HashSet` of size ≤ 3, which the corpus does
   not contain. Keep the field; do not read the sweep as evidence for it.

## 11. Files

| file | lines | what |
|---|---|---|
| `core/src/main/scala/com/clarifi/reporting/ermine/RowTrace.scala` | 220 (+154, −0) | the four replay record FORMATS in the header, `supplyBounds`, `supplyBlock`, `solveInput` |
| `core/src/main/scala/com/clarifi/reporting/ermine/Subst.scala` | +7 | one `RowTrace.solveInput` call in `solve`, with the comment that says why it is where it is |
| `tracker/lean/Rowpartition/Loop/Replay.lean` | 247 | NEW: the `sin`/`slbl`/`svar`/`scon` parser and the per-segment driver |
| `tracker/lean/Rowpartition/Loop/Main.lean` | 203 (+131, −7) | `--replay`, streaming, with `#seg` / `#skip` / `#hashdiff` / `#eqdiff` / `#summary` |
| `tracker/lean/Rowpartition/Loop/State.lean` | 387 (+122, −19) | `Lbl` is a `Name`; `Sup` is `scalaparsers.Supply`; `Names.tys`; `pvar`, `tyOf`, `isSkolem` |
| `tracker/lean/Rowpartition/Loop/Json.lean` | 251 (+68, −14) | `ITerm.conT` / `.otherT`, `CsItem`, generic `existsApply`, `buildQueue` over `CsItem` |
| `tracker/lean/Rowpartition/Loop/Step.lean` | 368 (+18, −9) | `makeEmpty`'s skolem refusal; `Sup` threaded through `learnPartitions` |
| `tracker/lean/Rowpartition/Loop/Rules.lean` | 224 (+12, −14) | `Sup.fresh` in place of `su + 1`, four rules |
| `tracker/lean/Rowpartition/Loop/Seed.lean` | 181 (+28, −17) | `loc` and `Sup` parameters; seeds build `CsItem.part`s |
| `tracker/lean/Rowpartition/Loop/Trace.lean` | 60 (+5, −3) | `popRecord` takes `loc` |
| `tracker/lean/Rowpartition/Loop/Conformance.lean` | 167 (+50, −4) | 12 new `#guard`s: `Global`/`Local`/fixity hashing and printing, `Con.hashCode`, `pvar` reading the `svar` table |
| `tracker/lean/Rowpartition/Loop/Bridge.lean` | 400 (+46, −19) | `LblCoh`, and the two lemmas that need it |
| `tracker/lean/Rowpartition/Loop.lean` | 51 (+4) | the umbrella line for `Loop.Replay` |
| `tracker/tools/looptrace-diff.py` | 318 (+155, −0) | `--segments` mode |
| `tracker/tools/looptrace-corpus.sh` | 101 | NEW: the sweep |
| `tracker/loopmodel/L2-CORPUS.md` | (this file; see `wc -l`) | this report |
| `tracker/lean/README.md` | +47, −1 | the "L2" subsection, the recounted headline figures, the `Replay.lean` table row |
| `tracker/LOOP-MODEL-PLAN.md` | +1 line | the L2 status row |

(`tracker/LOOP-MODEL-HANDOFF.md` also shows as modified; that edit is the orchestrator's,
made at 12:11 while this stage was compiling, and is not mine.)

Build at the end: `lake build Rowpartition` **833 jobs**, `lake env lean Audit.lean`
**"Rowpartition theorems audited: 2530; declarations using a non-standard axiom: 0"**,
`lake build looptrace` **24 jobs**. No `sorry`, `partial`, `Classical`, `axiom`,
`native_decide`, `unsafe`, `opaque` or `implemented_by` anywhere under `Rowpartition/Loop/`
(the three grep hits are prose saying so). Nothing was committed.
