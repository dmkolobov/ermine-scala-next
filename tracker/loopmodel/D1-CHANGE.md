# D1 Part B — the flagged change to `Constraints.scala`

Worktree `~/research/ermine/ermine-scala-wt-d1`, branch `dequeue-policy`, base `3991a58`
(Part A is `93e9454` on `scala3-migration`).  **Both flags DEFAULT OFF.  No commits.**
Design: `tracker/loopmodel/D1-DESIGN.md`; review: `D1-REVIEW.md` (ADVANCE, T-1…T-14).

## 1. What changed

### 1a `Constraints.GenRules` — the two properties, the counter, the warning

```scala
val solveBudget: Int      = ... System.getProperty("ermine.solveBudget", "0") ...      // 0 = off
val dequeuePolicy: String = System.getProperty("ermine.dequeuePolicy", "shipped")      // shipped = off
val solveBudgetHits       = new java.util.concurrent.atomic.AtomicLong(0L)
val drawCountActive: Boolean = solveBudget > 0 || RowTrace.enabled
```

* **T-1, the review's most serious finding, is built in.**  The counter is a `ThreadLocal[Int]`
  and it is saved/reset/restored at the LOOP's own entry — `PQueue.expand` and `combine`, the only
  two callers of `incorporateAll` that are not its own tail recursion — by `GenRules.withLoopDraws`.
  Not at `RowTrace.withSite`, which is a no-op unless `-Dermine.rowTrace` is set: a reset there
  would never fire in a normal compile and the budget would trip on whichever solve pushed the
  MODULE's cumulative draw count past the limit.  Save/restore because solves NEST; `ThreadLocal`
  because the shipped loader solves on several threads.
* **T-13, the footgun, is a loud warning**: `solveBudget > 0 && dequeuePolicy == "shipped"` prints
  a `System.err` line naming the reason (under the shipped order a solve's draw count depends on
  the id base, so the budget can accept a program at one base and reject it at another).
* With both flags off `drawCountActive` is false and the loop pays nothing: no counter is read,
  no branch is taken.

### 1b Where the draws are counted, and where the budget is checked

Counting: the loop's **two** minting sites and only those — `splitConcrete`'s `fresh`
(`Constraints.scala:1441` in the base) and `resolution`'s (`:1887`).  `PQueue.build`'s mint is
excluded *by construction*, because it is a third call site and is not wrapped.  There is no
`Supply`-side baseline to read (review T-10: `scalaparsers.Supply` has no `drawn`, only private
`lo`/`hi`, and `lo` is not a draw count across block boundaries).

Checking: **once per dequeue, at the top of `incorporateAll`, before the dequeue** — which is
exactly where `Loop/Budget.lean`'s `stepBud` checks it.  This is a deliberate change from
`D1-DESIGN.md` §1, which had the compiler checking *at the draw* and the model one dequeue
coarser, i.e. a deliberate mismatch.  Checking in the same place on both sides buys two things:
the model and the compiler stop on the **same dequeue**, so the L2 differential can be run with
the budget ON; and the `Death` is raised where a `Located` is in scope, so it carries a source
position.  The overshoot is the same one the model has and `Draws.learnPartitions_drawn` bounds:
at most `1 + proc.size` draws past the limit.

### 1c The diagnostic (review T-9)

```
Row solver resource limit reached (this is NOT a type error): the row constraint solver drew
<n> fresh row variables at this signature, past the -Dermine.solveBudget=<b> limit, so it was
stopped rather than left to run.  Raise the limit with -Dermine.solveBudget=<n>, simplify the
row constraints at this signature, or report it.
```

`Death` renders as a located error at the signature (`Locations.scala:126` → `Console.scala:220`
/ `TolerantCheck.scala:137`), so the wording carries the distinction the rendering cannot: it
says up front that it is a resource limit and not a verdict about the program, and it says what
to do.

### 1d `Q.pop` and the `smallcanon` order (review T-2)

`pop` now dispatches: `dequeuePolicy == "shipped"` runs `popShipped`, the existing body verbatim;
anything else runs `popSmallCanon`.  Both of T-2's constraints are honoured:

* **the tree keeps its `(rhs.hashCode, lhs.hashCode)` order.**  `popSmallCanon` chooses a
  different ELEMENT and rebuilds with `removeOne`, which splits at the chosen partition's own key
  block, drops the first element of that block equal to it, and rejoins `less <++> kept <++>
  greater`.  The measure `PSQK` and the reducer `pr` are NOT touched, so `PQueue.findRHS`,
  `PQueue.contains` and `Q.insert`'s `sandwich` — all finger-tree RANGE SPLITS on that key —
  keep working;
* **the measure-or-scan decision: SCAN.**  `smallcanon`'s primary key is the partition's ARITY,
  which `PSQK` does not carry; extending the measure would only help the first of three keys
  (the topological index and the canonical key are not in it either).  `popSmallCanon` is one
  `foldRight` over the queue, O(n) per dequeue, paid only when the policy is on.  §3 has the
  measurement.

`TypeVarGraph` gains a `lazy val canonSort`: `reverseTopSort` recomputed over ID-ORDERED nodes
and id-ordered children.  The existing `sort` is built from `Set` iteration orders, and a
`TypeVar`'s hash IS its id, so `sort` moves wholesale when the id base does; `canonSort` depends
on the graph alone.

### 1e The canonical label key — the Part A defect this stage found

`Loop/Policy.lean`'s `canonKey` ordered a right-hand side's concrete part by `Lbl.n`, the
label's index in the solve's `slbl` table — and `slbl` is a TRACE artefact built by
`RowTrace.solveInput`.  The compiler at solve time has no such table, so that key is **not
implementable in `Constraints.scala` at all**.  Both sides now order labels by the `Name`:
`(kind, module, string, fixity.con)` with `1` for a `Local` and `2` for a `Global` — the tags
`Name.hashCode` itself uses (`Name.scala:23,39`) — which needs no table and is base-independent
for the same reason an id order is.

**Measured, not assumed:** the model was re-run under the new key and **no row moved** — the
`smallcanon` corpus census is byte-identical over all **2,301,195** segments, the 190 tracked-seed
runs are identical, and `GU05` is still 414 dequeues / 306 loop draws at every base.

### 1f The Lean mirror (done ahead of the gates; main tree, on `93e9454`)

* `Loop/Replay.lean`: `Segment` gains `policy` and `budget`, read from `sin`'s two new columns.
  A trace that predates them keeps the defaults, so every existing corpus trace still parses.
* `Loop/PolicyReplay.lean` (NEW): the record printer under a policy.  `stepSP` is
  `Loop/Decide.lean`'s `stepS` with the dequeue call replaced, and `stepSP_shipped` is `rfl`;
  `runSP` threads the policy's auxiliary state AND the draw budget, tested BEFORE the dequeue --
  the same place `Loop/Budget.lean`'s `stepBud` and now `incorporateAll` test it, which is what
  makes "the two sides stop on the same dequeue" a checkable claim rather than a hope;
  `solveSeedP` and `replayP` are `Seed.solveSeed` and `Replay.replay` with those substituted.
  It could not go in `Loop/Seed.lean`: `Seed` is imported by `Replay` while `Policy` sits on the
  `Depth`/`VocFix` branch, and this module is where the two branches meet.
* `Loop/Main.lean`: `--trace` forces the RECORD path when `--policy=`/`--budget=` are given
  (they otherwise select the `pol` census), and with no `--policy=` the policy is taken from the
  trace's own `sin` record.
* `TestLoopTrace`: `d1Opts` forwards `-Dermine.dequeuePolicy` and `-Dermine.solveBudget` to the
  model as `--policy=` / `--budget=` / `--trace`.  They are deliberately NOT `--flags` tokens:
  both are read by the loop DRIVER, not by any rule, and neither is a field of `GenRules` or of
  the model's `Flags`.  Forwarded for the reason S2 review V-3 forwarded the numeric flags --
  otherwise the compiler would run under the policy and the model under the shipped order, and
  the property would fail for a reason that is not a bug.

**And the second half of that forwarding, which is what actually made the test pass.**
`TestLoopTrace` runs the compiler in a CHILD JVM and hands it a command line; the child inherited
`setFlags ++ setNumeric` but not the two D1 properties, so with `-Dermine.dequeuePolicy` set on
the outer JVM the model ran under the policy while the compiler ran SHIPPED, and 419 of 714
segments disagreed.  `setD1` now goes on the child's command line beside them.  The failure mode
is worth naming because it is silent in the other direction too: a property that forwards a flag
to one side only does not fail loudly, it fails as a plausible-looking mismatch.

*(The Lean mirror was built after D1-T finished in the main tree: `lake build Rowpartition` 867
jobs, `Audit.lean` 4,112 theorems / 0 non-standard axioms, `lake build looptrace` relinked.  The
build was deliberately deferred while corpus differentials were running, because it relinks the
`looptrace` binary they are using.)*

### 1g The trace records

The `sin` record gains two trailing columns, the policy and the budget, before `RowTrace.log`'s
thread-id column.  `Loop/Replay.lean` parses `sin` positionally with a trailing wildcard, so old
traces keep parsing; the Lean mirror reads them so that `looptrace --replay` can reproduce a
policy-on or budget-on trace.

## 2. Gates

### 2a Flags OFF — nothing may change

| # | gate | result |
|---|---|---|
| 1 | `core/test` | **914 total, 913 passed, 1 failed** — `com.clarifi.reporting.TestConstraints`, the known failure, and the same line S2's baseline log prints (`tmp/S2/coretest-off.log`: `Failed: Total 914, Failed 1, Errors 0, Passed 913`).  **PASS** |
| 2 | `TestLoopTrace` | **714 solves, 714 segments, 714 agree**, `hashdiff=0 eqdiff=0 skipped=0`, both controls still detect (id base +1: 53 of 714 disagree; `--flags=nongen`: 65 of 714).  **PASS** (run with `-Dermine.looptrace` pointed at the main tree's model binary — the worktree has no `.lake` build) |
| 3 | L2 corpus differential, eight groups | **PASS — 2,355,430 segments, 2,355,430 AGREE, 0 skip**, every group `timeouts=0 dropped=0 threads=1` (`boot` 54,199, `top` 92,673, `Ai` 83,942, `shouldfail` 56,032, `bugs` 54,235, `guide` 54,244, `shouldfail-controls` 54,739, `incomplete` 1,905,366 over 35 files).  The same population S2 gated on |
| 4 | `.ei`: worktree OFF vs the main checkout | **181 interfaces on both sides, 181 of 181 IDENTICAL, 0 differing, none published on one side only** (normalised by `tmp/D1/einorm2.py`; three snapshots were taken: A worktree OFF, B the main checkout, C worktree with the policy ON — A vs B is this gate, A vs C is review T-14.1).  A raw BYTE comparison says 180/1, and that one byte difference is churn, not the change: see FINDING 1.  **PASS** |

### 2b Flags ON

#### The gate this stage exists for: `GU05` at 25 id bases ON THE COMPILER

`tracker/repro/satterm/run.sh sweep`, 600 s cap, one JVM at a time, `-XX:ActiveProcessorCount=2`.
The shipped control is run in the SAME harness so the comparison is like for like rather than
against `L5-TERMINATION.md` §R8.0a's older passes.

| | draws | wall clock |
|---|---|---|
| `shipped`, base 0 | **47,317** | 128,354 ms |
| `shipped`, base 1 | 1,091 | 1,399 ms |
| `shipped`, base 2 | 743 | 1,304 ms |
| **`smallcanon`, every one of bases 0…24** | **306 at all 25** (`min=median=max=306`) | ~1.0 s per base |

**306 is the model's figure too** — the compiler and the model agree exactly, which is what the
differential under the policy now holds them to.  `GU05MIN`, 25 bases: **SOLVED at all 25, 256
draws at every one**, a seed the model finishes for no policy inside 900 s.

**Spread 1.00× against ≥ 63.7× in draws and ≥ 98× in wall clock over just the three shipped
bases** — and ≥ 110× over the 25 from §R8.0a.  The worst base drops from 47,317 draws / 128 s to
**306 draws / ~1.0 s**, a 155× cut.  This is the compiler, not the model.



#### The rest

| gate | result |
|---|---|
| `gu05` module load time, OFF vs ON, 3 reps | OFF 16.07 / 17.29 / 16.19 s; ON 16.21 / 15.49 / 17.45 s — **no measurable difference**, the O(n) scan is invisible at this scale |
| S2 environment-fact gate (`run.sh env`, nine cases) | `cases=9 differ=4` **both ON and OFF** — the shipped baseline S2 recorded, unmoved |
| the corpus at `-Dermine.solveBudget=20000` with the policy | re-run after the key fix: `bugs` **54,235 of 54,235 agree**, `guide` **54,244 of 54,244 agree**, `rc=0`, `limit-hits=0` — a budget far above what any of these solves draws is INERT, record for record |
| a budget that FIRES, on `incomplete/gu05` under the policy | **PASS, both directions** — see "A budget of 20 DOES fire" below |
| `TestLoopTrace`, policy ON and policy+budget ON | **714/714 at all three settings**, 3 of 3 properties, both controls still detect — see below |
| `repl-smoke` | **PASS** — aliasing (2), relations (6), scoping (4), smoke (23 checks) |
| `lsp-smoke` | **PASS** — lsp (98 checks) |
| `perf-bench.sh batch`, OFF vs ON, alternated twice | OFF **13.63 / 13.68 s** cold median, ON **13.42 / 13.55 s** — a 1.2 % gap, which is INSIDE the noise and is NOT a speed-up claim (per-run spread 0.45-0.78 s; the reviewer's independent runs give OFF 11.45/11.56 and ON 11.34/11.57 on a quieter host, and puts the resolution at ~5 %).  **The finding is: no measurable cost**; see §7c for the load caveat |
| `.ei` gate 4 (worktree OFF vs main checkout) | **181 of 181 identical**, 0 differing (`einorm2.py`) — see FINDING 1 for why the byte comparison's 180/1 is not a failure |
| `.ei` T-14.1 (OFF vs policy ON), **re-measured with `-Dermine.loadInSeries=true` and `einorm3.py`** | floor **152 of 152 identical, BYTE-identical, twice at each setting**; OFF vs ON **151 of 152 identical, 1 differing** (`GridExample`, two bindings, one vacuous kind binder) — FINDING 2, restated |
| the two flags are COUPLED in code (D1B review) | `-Dermine.solveBudget` at the shipped order: the module LOADS, the budget does not fire, one `is IGNORED` warning, and the model agrees — `incomplete/gu05` at `-Dermine.solveBudget=20` under `shipped`: `limit-hits=0`, `imported=1`, differential **54,235 of 54,235 agree, `rejected=0`** |
| the configuration fingerprint (`GenRules.toString`) | defaults `cut+label-early+resguard+splitkey+splitrow+resrow` — **byte-identical to S2's**; policy on adds `+pol:smallcanon`; policy+budget adds `+budget:20000`; **a budget alone adds NOTHING**, because the string records the EFFECTIVE configuration |
| `TestLoopTrace` after the post-review code changes, three settings | **714/714, 3 of 3, at all three**; controls detect (53/65 at the defaults, 46/58 under the policy) |
| L2 differential regression after the post-review code changes (`boot`+`top`) | flags OFF **146,872 of 146,872 agree**; under the policy **146,872 of 146,872 agree** |

#### FINDING 1 — `.ei` is not byte-stable at a FIXED configuration

*(Corrected 2026-09-06 after the D1B review, U-1/U-3.  The finding stands; the CONTROL under it
did not.  Old text and new numbers in §8.)*

Gate 4 compares two trees at the SAME setting and one interface differed byte for byte:
`Relation_Predicate.ei`, same length, 831 differing bytes, carrying **the same constraint set in
a different order** with two binders swapped.  Published constraint lists, concrete rows and
existential binder lists all print in `Set` iteration order, which is a hash order, which is an
id order.  **So an `.ei` byte comparison is not a valid gate** -- it fails on churn.

Two things were wrong with the way this stage then calibrated the comparison, and the reviewer
found both.

* **The sweep was NONDETERMINISTIC.**  It ran `bin/ermine` at the defaults, i.e. under the
  shipped PARALLEL module loader, and `session/Session.scala:558-560` says in its own comment
  what that means: *"parallel makes give thread-timing-dependent Supply order, which reaches
  interface bytes through the constraint solver's id-hash queue"*.  The "zero noise floor" was
  therefore ONE repetition of a nondeterministic experiment; the reviewer's ten repetitions at
  the flags OFF gave eight distinct md5s and 1 of 152 interfaces differing in all nine
  comparisons — and that one was `Relation.lookbackJoin`, one of "the five" this document
  attributed to the policy.  **Fix: `-Dermine.loadInSeries=true` on both sides.**  Re-measured
  here, that floor really is zero and is zero at the BYTE level: two sweeps at the flags OFF
  give the same md5 (`52b0cefc554d`, 152 interfaces, `diff -rq` empty), and two sweeps under the
  policy likewise (`546b42fde523`).
* **The normaliser reported alpha-variants as differences.**  `tmp/D1/einorm2.py` sorted each
  constraint group BEFORE anonymising the binder names, so the sort key was the order-dependent
  names and two renamings of the same set sorted differently (D1B review U-3).
  `tmp/D1/einorm3.py` anonymises FIRST and then sorts.  On this stage's own snapshots that alone
  takes the policy comparison from 5 differing to **2**.

#### FINDING 2 — the policy moves published TEXT in one interface, and every difference is a renaming or a VACUOUS binder

*(Corrected 2026-09-06 after the D1B review, U-1/U-2/U-3.  The old table and its wording are in
§8; this is the measurement that replaces it.)*

With the loader made deterministic (`-Dermine.loadInSeries=true`, the reviewer's two-chunk
scope, 152 interfaces) and the normaliser fixed (`einorm3.py`):

| comparison | result |
|---|---|
| **floor**, flags OFF twice | **152 of 152 identical — and byte-identical**, same md5, `diff -rq` empty |
| **floor**, policy ON twice | **152 of 152 identical — and byte-identical** |
| **OFF vs ON** | **151 of 152 identical, 1 DIFFERING**: `GridExample.ei`, in two bindings, `stackedBarChart` and `stackedAreaChart` |
| OFF vs ON, raw bytes | 7 of 152 files differ — the other six are renamings, which is exactly what FINDING 1 says a byte diff cannot tell you |
| OFF vs ON with the OLD `einorm2.py` | 150 of 152 — it adds `Relation.lookbackJoin`, a tool artefact (U-3) |

**What the one difference IS.**  Both bindings publish the same body and the same residual; they
differ in ONE implicit KIND binder:

```
OFF: stackedBarChart : forall {_ _ _ _}   … (_: rho) sa     (_: rho -> * -> *) …
ON : stackedBarChart : forall {_ _ _ _ _} … (_: rho) (_: _) (_: rho -> * -> *) …
```

A BARE binder means kind `*` (`Pretty.ppTypeVarBinder`, `Pretty.scala:259-266`: `case Star(_) =>
d`), and both bodies contain `s sr sa` with `s : rho -> * -> *`, which pins that kind to `*`
either way — **so the extra quantifier is vacuous and the type is the same type.**  The
reviewer checked every differing residual in both snapshot sets by a backtracking isomorphism
search (`tmp/review-D1B/alpha2.py`, `forall`-bound variables and qualified names held fixed,
`x <- (a, b, c)` treated as the unordered set `Constraints.RHS` makes it) and found them
**alpha-equivalent in every case**; three of the original five were textually identical outside
the existential names, i.e. the same type outright.

**Where the residue comes from, since the theorems forbid a different derived set.**
`runP_ssat_iff`, `runP_noLoss` and `runP_models` say the derived system is equivalent, and it is.
What moves is downstream of the loop and unmodelled: the existential NAMES come from
`Subst.reduce`'s generalisation over a `Set` whose iteration order is an id order, and the kind
binder from whether a kind meta-variable is still a variable at generalisation.

**What this means for adoption.**  Not "five signatures change".  **One published interface's
text moves, in two bindings, by a vacuous kind quantifier; no published TYPE changes.**  A
consumer that diffed interface bytes to decide what to rebuild would still see a change there —
and would also see one at a FIXED configuration under the parallel loader, which is the more
important thing to know.  A mixed-policy tree loads (the reviewer's gate 16, both directions,
`rc=0`).

**Is this unsoundness?  No, and the theorems say why.**  `runP_noLoss` and `runP_models`
(`Loop/PolicyStep.lean`) say an accepted solve under ANY policy loses nothing and that every
model of its output is a model of its input; two dequeue orders derive different but equivalent
saturated sets, and `Subst.reduce` publishes from whichever it is given.  What the theorems do
NOT say -- and what nothing in the development says -- is that the two publications are the same
TEXT.  For five of 181, they are not.

**What that means for adoption, plainly.**  Every module in the corpus still loads (2,355,430
solve segments agree, zero verdict changes, `core/test` unmoved), so nothing breaks downstream
here.  But `.ei` is a published artefact: a consumer that recorded a signature's exact shape, or
a build that diffs interfaces to decide what to rebuild, would see a change at these five.
**Turning `ermine.dequeuePolicy` on is therefore an interface-affecting change, not a pure
performance one**, and those five names are the list to look at before adopting.  This is exactly
the gate the review added (T-14.1) and the reason it added it.

#### FINDING 3 (U-0, the D1B review's, and the one that decides adoption) — under the policy the solver stops REFUTING two known-unsatisfiable witnesses

*(Added 2026-09-06.  This stage did not measure it; the reviewer did, and I reproduced it here
digit for digit.)*

`tracker/repro/satterm/seeds/unsat/` holds the seven curated witnesses of the row solver's
KNOWN incompleteness — the inputs S1's review found the shipped solver ACCEPTS although they are
unsatisfiable, and the reason stage S2 exists.  `SOLVED` on one of them is a FALSE ACCEPTANCE.
On the COMPILER, ten id bases, both dequeue orders, with and without S2's `-Dermine.rowSound`
(`tmp/D1/u0-unsat.sh`, `u0-unsat.tsv`; `SOLVED` counts out of 10):

| seed | `shipped`, rowSound OFF | `smallcanon`, rowSound OFF | `shipped`, rowSound ON | `smallcanon`, rowSound ON |
|---|---|---|---|---|
| `MIN1` | SOLVED 10/10 | SOLVED 10/10 | **REJECTED 10/10** | **REJECTED 10/10** |
| `FALSE-ACCEPT-1` | SOLVED 10/10 | SOLVED 10/10 | **REJECTED 10/10** | **REJECTED 10/10** |
| **`MIN2`** | SOLVED **2**/10 | SOLVED **10**/10 | **REJECTED 10/10** | **REJECTED 10/10** |
| **`FALSE-ACCEPT-2`** | SOLVED **2**/10 | SOLVED **10**/10 | **REJECTED 10/10** | **REJECTED 10/10** |
| `SURV1` | SOLVED 10/10 | SOLVED 10/10 | **REJECTED 10/10** | **REJECTED 10/10** |
| `ENV-LINK` | SOLVED 10/10 | SOLVED 10/10 | **REJECTED 10/10** | **REJECTED 10/10** |
| `PANIC-1` | REJECTED 10/10 | REJECTED 10/10 | REJECTED 10/10 | REJECTED 10/10 |

**What it says.**  At the shipped `rowSound` default the policy turns 8 rejections in 20 into 0:
`MIN2` and `FALSE-ACCEPT-2` are refuted at 8 of 10 bases under the shipped order and at NONE
under `smallcanon`.  It is the ORDER and not a compiler bug — the MODEL agrees, and the fixed
`bindcmp.sh` (below) reproduces the same flip on the model at the same eight bases.

**It contradicts no theorem, and that is the point.**  `runP_rejects_unsat` says a rejection is
SOUND; nothing anywhere says an unsatisfiable input WILL be rejected.  The shipped loop's
refutation is incomplete and, as this shows, order-dependent — two dequeue orders derive
different but equivalent saturated sets, and only one of them happens to trip a check.  What
changed is not correctness but a behaviour users have today.

**And S2 removes the loss completely.**  With `-Dermine.rowSound=true` all seven witnesses are
refuted at all ten bases under BOTH orders: S2's layer (iii) is a COMPLETE per-label decision run
BEFORE the loop (which is exactly the shape of `solveP_noFalseAccept`), so it does not care which
partition the loop would have dequeued.

**And the PAIR loads the corpus.**  Nothing had gated the two flags together, so it is gated
here: the 15 top-level examples and the `Ai` group, loaded at four settings — flags OFF, the
policy alone, `rowSound` alone, and **the pair** — give the SAME three pre-existing failures in
`top` (`Interp.e`, `Sample.e`, `Yahoo.e`, identical module for module, not merely the same count)
and none in `Ai`, at every setting (`tmp/D1/adopt-pair.sh`).  Adopting the pair does not reject
anything the shipped compiler accepts here.

**THE ADOPTION CONSEQUENCE, plainly: the policy must not ship without `-Dermine.rowSound`.**
Adopt `rowSound` first or with it, never the policy alone.  This also qualifies this document's
"zero verdict changes in 2,301,195 solves": that population is the CORPUS, which contains no
known unsatisfiable input of this shape — the corpus could not have caught it, and the gate that
would have (`bindcmp.sh`) was broken and unrun (U-8, fixed below).

#### THE 1,093-vs-306 GAP: localised by the differential, and CLOSED

**Answer first: the compiler now draws 306 on `GU05` at every base — exactly the model's 306.**
Two things were wrong, and the second was hiding the first.

**The order difference.**  The L2 differential under the policy over `boot`/`top`/`bugs` pinned it
to **six segments of `top`**, all of the same shape.  At `Accumulate.e(32:3)` the two sides had
the same dequeued left-hand side and two candidates of **equal arity 1**:

```
lean : step  trySolveOn  unify:304419  ^ambiguous(free)304425 <- (^ambiguous(free)304419,)
scala: step  trySolveOn  common:304419 ^ambiguous(free)304425 <- (,Accumulate.name Accumulate.nodeId Accumulate.parentId)
```

one with a lone variable and no labels (`|abstr| = 1`, `conc` empty), one with labels and no
variables (`|abstr| = 0`, `conc` nonempty).  Arity ties at 1, the left-hand sides are the same so
the topological index ties, and the decision falls to `canonKey` — which is exactly where the two
implementations disagreed: `Loop/Policy.lean` concatenates the components with a SENTINEL
(`canonSep`, larger than any id, code point or `Fixity.con`), so at the position where the empty
abstract list ends the comparison sees `canonSep` against `304419` and the variable candidate
wins; `Constraints.scala`'s first version compared `(abstrIds, labelKeys, lhs)` component by
component with Scala's list ordering, where the empty list is a PREFIX and therefore wins.  Six
segments of 92,673, and all six of this one shape.

**And the reason the first fix looked ineffective**: the recompile that was supposed to pick it up
**failed** — the new `List[Int]`-valued `lblKey` collided with the tuple-valued one it was meant
to replace (`Conflicting definitions … have matching parameter types`), `core/compile` returned
`[error]`, and the driver went on to run the 25-base sweep and the differential against the
PREVIOUS classes.  That is why the "post-fix" sweep still said 1,093.  With the stale overload
removed and the compile green, `GU05` under `-Dermine.dequeuePolicy=smallcanon` gives
**306 draws at bases 0, 1 and 2**, ~1.0 s each — the model's figure, on the compiler.  The full
25-base sweep then gave 306 at ALL 25 bases and the eight-group differential came back
2,355,430 of 2,355,430 agreeing, both against that corrected binary; those are the figures the
tables above report, and no figure in this document comes from the stale classes.

*The lesson, recorded because it nearly shipped a wrong number: a driver that runs gates after a
build step must FAIL on a non-zero build, not carry on.*

#### The two questions the coordinator asked, answered precisely

* **What does "arity" count?**  `|abstr| + (conc.isEmpty ? 0 : 1)` — abstract parts, plus ONE for
  a nonempty concrete part however many labels it holds.  `Loop/Policy.lean`'s
  `preKey .smallRhs` and `Constraints.scala`'s `arityOf` were identical throughout; arity was
  never the difference, and the six diverging segments are ties at arity 1 that prove it.
* **Does `removeOne`'s rebuild reorder the survivors?**  No.  It splits the finger tree at the
  CHOSEN partition's own `(rhs.hashCode, lhs.hashCode)` block, drops the first element of that
  block that is `==` to it, and rejoins `less <++> kept <++> greater`; every survivor keeps its
  position in the key order, which is what the model's `elems.eraseIdx i` does.  Had it not, the
  differential would have failed on far more than six segments of one group, and on the shipped
  order too — where `removeOne` is not used at all, since `popShipped` is the original body.

#### The L2 differential UNDER THE POLICY

`looptrace-corpus.sh` with `-Dermine.dequeuePolicy=smallcanon` on the compiler; the model takes
the policy from the trace's own `sin` record and prints records through `PolicyReplay.replayP`.

| group | segments | agree | skip |
|---|---|---|---|
| `boot` | 54,199 | **54,199** | 0 |
| `top` | 92,673 | **92,673** | 0 |
| `Ai` | 83,942 | **83,942** | 0 |
| `shouldfail` | 56,032 | **56,032** | 0 |
| `bugs` | 54,235 | **54,235** | 0 |
| `guide` | 54,244 | **54,244** | 0 |
| `shouldfail-controls` | 54,739 | **54,739** | 0 |
| `incomplete` | 1,905,366 | **1,905,366** | 0 |

**All eight groups: 2,355,430 segments, 2,355,430 AGREE, 0 skip, 0 hashdiff, 0 eqdiff** — the
same population the flags-OFF differential covers.  The compiler under
`-Dermine.dequeuePolicy=smallcanon` and the model under the policy it reads off the `sin` record
produce the same row trace, record for record, over the whole corpus.

#### Per-solve draw equality — the gate that ties the budget's unit to the model's

`-Dermine.rowTrace.draws=true` emits one `sdraw` record per solve carrying
`GenRules.drawnThisSolve`; the model's figure is `drawn - drawn0`.  Over `boot`, under the
policy: **54,199 solves, 54,199 sdraw records, IDENTICAL** — the compiler's counted draws equal
the model's, per solve, with no exception.  Nothing gated that before; the budget is defined in
draws and this is what makes the two definitions the same one.

#### The five `incomplete/` modules that publish an interface only under the policy

The reviewer asked whether that is a rejection, a batch-sweep cap, or a real completion.  It is a
real completion, and the chunk log says so in one line.  `ei-diff`-style sweeps load ten files
per JVM with interfaces ENABLED, so a module is solved in the context the ones before it left —
which is exactly where an id-order blow-up bites.  In the chunk holding `incomplete/`:

| | shipped order | `smallcanon` |
|---|---|---|
| `Incomplete.Gu01` | 0.22 s | 0.25 s |
| `Incomplete.Gu04` | 0.13 s | 0.15 s |
| **`Incomplete.Gu05`** | **never completes — the chunk is killed at the 900 s cap** | **2.08 s** |
| `Incomplete.Gu06` | never reached | 0.07 s |
| `Incomplete.Gu08` | never reached | 0.15 s |
| `Incomplete.Gu10` | never reached | 0.07 s |
| `Incomplete.Np01` | never reached | 0.41 s |

So: `Gu05` **times out** under the shipped order and the four after it are **never reached**;
under the policy `Gu05` takes 2.08 s and the rest follow in under half a second each.  That is
the six extra interfaces, and it is the id-order blow-up reproduced **on a real module in a
normal multi-file compile** — not on a seed, not on a transcode.

And the per-file control that makes the reading precise: loaded ALONE, with
`-Dermine.useInterface=false` and nothing before it, `gu05` completes under BOTH settings —
17,338 ms OFF against 15,962 ms ON, and `gu06`/`gu08`/`gu10` likewise within noise
(15,562/15,500, 16,547/16,115, 16,416/…).  The module is not intrinsically slow; it is slow **at
the id base a preceding load happens to give it**, which is the whole thesis of §0 and which the
policy removes.

#### A budget of 20 DOES fire — on a module that actually draws

The first firing-budget differential was run on groups whose solves draw almost nothing (the
corpus draws 1,845 ids over 2.3 M solves), so `-Dermine.solveBudget=20` never fired and the run
proved only that the flag is inert when it does not.  The targeted run is
`core/examples/incomplete/gu05_star_join_4dim_concrete_signature.e`, which draws 328 under the
policy, loaded alone with `-Dermine.useInterface=false -Dermine.loadInSeries=true
-Dermine.dequeuePolicy=smallcanon`, at two budgets, each traced and replayed:

| budget | compiler | differential |
|---|---|---|
| `0` (off) | `Importing module 'Incomplete.Gu05' (0.41 seconds)`, `limit-hits=0` | 54,235 segments, **54,235 AGREE**, 0 skip, `hashdiff=0 eqdiff=0`, `rejected=0` |
| `20` | the module is REJECTED at `gu05…e:62:1` with the §1c diagnostic, `limit-hits=1` | 54,235 segments, **54,235 AGREE**, 0 skip, `hashdiff=0 eqdiff=0`, `rejected=1` |

The diagnostic, verbatim from `bud20.out`:

```
core/examples/incomplete/gu05_star_join_4dim_concrete_signature.e:62:1: Row solver resource
limit reached (this is NOT a type error): the row constraint solver drew 21 fresh row variables
at this signature, past the -Dermine.solveBudget=20 limit, so it was stopped rather than left to
run.  Raise the limit with -Dermine.solveBudget=<n>, simplify the row constraints at this
signature, or report it.
```

Two things are gated here at once.  The budget **fires**: it stops a solve that would have gone
on, at the draw the model's `stepBud` stops at (`d0 + b < drawn` with `b = 20` and a 21st draw).
And the model **agrees about the firing**: the replay's `rejected` count moves from 0 to 1 and
every one of the 54,235 segments still matches, so the compiler's budget death and the model's
`budgetMsg` death are the same event on the same dequeue, not merely two runs that both stopped.
That is what makes `runBud_rejects_unsat`'s hypothesis — a budget death is a `BudgetDeath`, never
a refutation — a statement about this compiler.

## 4. Soundness: the theorems transported to the flagged driver

The user's question for this commit was *"are we sure we are not introducing unsoundness"*, and
the answer is `Rowpartition/Loop/FlaggedSound.lean` (267 lines, new) for the budget and, after
stage D1-T, `Loop/PolicyStep.lean` + `Loop/PolicyTerm.lean` for the policy (§6).  At the time
this section was written: build **865**, audit **3,969 theorems / 0 non-standard axioms**,
`looptrace` 1,670; no `sorry`; `#print axioms` over all 19 new declarations in
`tmp/D1/print-axioms-B.out`, standard axioms only.  With D1-T's two modules in the tree the same
figures are build **867**, audit **4,112 theorems / 0 non-standard axioms**.

### 4a Which step the replay actually runs

`PolicyReplay.solveSeedP` → `runSP pol d0 bud` → **`stepSP pol a s`**.  Three equations pin it to
the loop S1 and S2 are about, and they are the reason nothing is at risk with the flags off:

```lean
theorem stepSP_shipped (a : Aux) (s : State) : stepSP .shipped a s = stepS s := rfl

theorem stepSP_of_rowSound_off {pol : Policy} {a : Aux} {s : State}
    (h : s.flags.rowSoundBare = false) : stepSP pol a s = stepP pol a s

theorem stepP_shipped (a : Aux) (s : State) : stepP .shipped a s = step s := rfl
```

### 4b The BUDGET — transported completely

```lean
theorem runBud_outOfFuel {d0 b : Nat} : ∀ (n : Nat) {s s' : State},
    runBud d0 b s n = .outOfFuel s' → run s n = .outOfFuel s'

theorem runBud_noLoss {d0 b : Nat} (n : Nat) {s : State} (hw : Wf s)
    (hem : s.flags.emptyRow = false) (hdj : s.flags.disjRule = false)
    (hcse : s.flags.cseMints = false) (hb : RunSupOk n s) (hsat : SSat (sys s))
    (s' : State) (hres : runBud d0 b s n = .solved s' ∨ runBud d0 b s n = .outOfFuel s') :
    NoLoss (sys s) (sys s')

theorem runBud_sat_all {d0 b : Nat} (n : Nat) {s : State} (hw : Wf s)
    (hem : s.flags.emptyRow = false) (hdj : s.flags.disjRule = false)
    (hcse : s.flags.cseMints = false) (hb : RunSupOk n s) (hsat : SSat (sys s))
    (s' : State) (hres : runBud d0 b s n = .solved s' ∨ runBud d0 b s n = .outOfFuel s') :
    SSat (sys s')

theorem runBud_models {d0 b : Nat} {n : Nat} {s : State} (hw : Wf s)
    (hem : s.flags.emptyRow = false) (hdj : s.flags.disjRule = false)
    (hcse : s.flags.cseMints = false) (hb : RunSupOk n s) (hsat : SSat (sys s))
    {s' : State} (hres : runBud d0 b s n = .solved s' ∨ runBud d0 b s n = .outOfFuel s') :
    ∀ rho, SModels rho (sys s') → SModels rho (sys s)

theorem runBud_rejects_unsat {d0 b : Nat} : ∀ (n : Nat) {s : State}, Wf s →
    s.flags.emptyRow = false → s.flags.disjRule = false → s.flags.cseMints = false →
    RunSupOk n s → QueueHygiene s →
    ∀ (m : String) (s' : State), runBud d0 b s n = .rejected m s' →
      ¬ NonRefutationB s.names m → ¬ SSat (sys s)

theorem runBud_not_rejected {d0 b : Nat} (n : Nat) {s : State}
    (h : ∀ m s', runBud d0 b s n ≠ .rejected m s') : ∀ m s', run s n ≠ .rejected m s'
```

with the budget's death added to the exception list beside the skolem refusal —

```lean
def BudgetDeath (m : String) : Prop :=
  ∃ (site : String) (d0 b n : Nat), m = budgetMsg site d0 b n

def NonRefutationB (ns : Names) (m : String) : Prop :=
  NonRefutation ns m ∨ BudgetDeath m
```

— which is precisely the unsoundness the question was about: without it, *"the loop rejected"*
would license *"the input has no model"*, and budget exhaustion licenses nothing of the sort.
`runBud_not_rejected` is what carries S2's `solve_noFalseAccept` and `solve_accepted_faithful`
across, since both are conditional on the run not rejecting.

### 4c The POLICY — the acceptance branch, which is the one that could be unsound on its own

```lean
theorem stepP_done_dequeue {pol : Policy} {a : Aux} {s s' : State}
    (h : stepP pol a s = .done s') : s.incm.elems = []

theorem stepSP_done_dequeue {pol : Policy} {a : Aux} {s s' : State}
    (h : stepSP pol a s = .done s') : s.incm.elems = []
```

This is what `dequeuePol_none` is for, and it is the flagged `run`'s `.solved` case that uses
it: a `pop` answering `none` on a non-empty queue would make `incorporateAll` return `proc` and
the solve accept **without saturating**.  Ruled out for every policy.

### 4d FINDING (CLOSED by §6 on 2026-09-06) — the rest of S1 was not transported to a non-default policy

Reported rather than papered over.  It is not that the theorems are false; it is that they are
written against `s.incm.dequeue = some (r, rest)` and would have to be re-run against
`DequeueShape s.incm r rest`.

**Every FACT the re-run needs is already proved** — `dequeuePol_shape`, `shape_mem`,
`shape_mem_or`, `shape_length_lt`, `shape_kdist`, `dequeuePol_unique`, `dequeuePol_none`.  What
is missing is the mechanical re-run: the dispatch is unfolded in **22 theorems across 11
modules, 1,221 proof lines** (`step_supFresh` 190, `step_queueHygiene` 132,
`step_refines_learn` 119, `step_refines` 118, `step_drawn_le` 104, `step_died_refutes` 95,
`step_qok` 70, `step_envNodup`+`step_su` 118, `step_refines_nonlearn` 54, `step_noLoss_*` 68,
`step_noLoss`/`step_strict`/`step_learn_env` 78, the rest 75).  Each begins
`simp only [step, State.log] at h; split at h` and then uses the dequeue only through those
facts, so the transport is a copy with two substitutions and needs no new mathematics — but it
is 1,221 lines, and it was not done here.

**This was the state of play when §4 was written, and §6 closes it.**  `Loop/PolicyStep.lean`
now proves `stepP_refines_all`, `runP_sat_all`, `runP_noLoss`, `runP_rejects_unsat` and S2's
chain for an arbitrary policy, and `Loop/PolicyTerm.lean` proves `budgetP_terminates` for one.
So the sentence that used to end this section — "the rest is EVIDENCE, not theorem" — is
retracted: it is now theorem, and the 0 verdict differences in 2,301,195 corpus solves and 950
seed runs are corroboration rather than the whole case.  `ermine.dequeuePolicy` still ships OFF,
because adoption is the user's decision and not this stage's.

## 5. TRANSPORT SPEC — for the follow-up agent that closes §4d

Everything below is measured on `93e9454` + this branch's Lean.  The goal: the four S1 results
and the S2 chain, for `stepP pol` with `pol` arbitrary, as theorems with `#print axioms` clean.

### 5a Recommended shape

A NEW module `Rowpartition/Loop/PolicyStep.lean`, importing `Rowpartition.Loop.FlaggedSound`.
**Leave every original untouched** — that is what kept Part A's L2 differential meaningful and
it is what lets a reviewer diff old against new.  For each theorem in §5b write a
`stepP`-parameterised copy: same statement with `step s = .continue s'` replaced by
`stepP pol a s = .continue s'` (and `∀ pol a` bound at the front), same proof, with the opening
and the dequeue facts substituted as in §5c.  Then the run level, and the final theorems:

```
theorem stepP_refines_all  (pol) (a) … (h : stepP pol a s = .continue s') : LoopRun (sys s) (sys s')
theorem runP_sat_all       …  -- over `runSP pol d0 0` (or a bare `runP pol`), SSat preserved
theorem runP_noLoss        …  -- NoLoss on .solved ∨ .outOfFuel, satisfiable input
theorem runP_rejects_unsat …  -- with `NonRefutationB` (FlaggedSound §SS2), not `NonRefutation`
```

and S2's chain for the driver the replay actually runs: `runSP_noFalseAccept` and
`runSP_accepted_faithful`, obtained the way `FlaggedSound.runBud_not_rejected` obtains them —
"does not reject" is the only hypothesis they need, so a policy version of that lemma is enough.
`stepSP` reduces to `stepP` by `stepSP_of_rowSound_off` (already proved), so the S2 layer-(i)
case is the only extra one and it can only turn a continuation into a death (S2's
`stepS_continue` is the pattern).

### 5b The 22 theorems, with what each uses of the dequeue

Line ranges are on `93e9454`.  `dequeue_length_lt`, `dequeue_sub` and `kdist_dequeue` do **not**
appear in any of them — they are used by the termination fragments, which are order-blind
already (`D1-DESIGN.md` §5f) — so the only facts to substitute are the three in the last column.

| module | theorem | lines | n | dequeue facts used |
|---|---|---|---|---|
| `Loop/Supply.lean` | `step_supFresh` | 545–734 | 190 | `PQueue.dequeue_mem` |
| `Loop/Hygiene.lean` | `step_queueHygiene` | 1210–1341 | 132 | `PQueue.dequeue_mem` |
| `Loop/RefineLearn.lean` | `step_refines_learn` | 1353–1471 | 119 | `PQueue.dequeue_mem`, `dequeue_mem_or`, `dequeue_unique` |
| `Loop/Refine.lean` | `step_refines` | 1146–1263 | 118 | `PQueue.dequeue_mem` |
| `Loop/Mints.lean` | `step_drawn_le` | 287–390 | 104 | — (unfolds `step` only) |
| `Loop/Reject.lean` | `step_died_refutes` | 517–611 | 95 | `PQueue.dequeue_mem` |
| `Loop/Wf.lean` | `step_qok` | 943–1012 | 70 | — |
| `Loop/StrictBound.lean` | `step_envNodup` | 150–209 | 60 | — |
| `Loop/StrictBound.lean` | `step_su` | 34–91 | 58 | — |
| `Loop/RefineConcrete.lean` | `step_refines_nonlearn` | 650–703 | 54 | `PQueue.dequeue_mem`, `dequeue_unique` |
| `Loop/Sound.lean` | `step_noLoss_concrete` | 914–958 | 45 | `PQueue.dequeue_mem`, `dequeue_mem_or` |
| `Loop/StrictStep.lean` | `step_noLoss` | 1805–1838 | 34 | — |
| `Loop/StrictStep.lean` | `step_strict` | 1604–1626 | 23 | — |
| `Loop/Sound.lean` | `step_noLoss_all` | 959–981 | 23 | — (dispatches to the two above) |
| `Loop/StrictStep.lean` | `step_learn_env` | 1757–1777 | 21 | — |
| `Loop/Reject.lean` | `step_names` | 500–516 | 17 | — |
| `Loop/RefineLearn.lean` | `step_sat_all` | 1489–1503 | 15 | — (corollary of `step_refines_all`) |
| `Loop/Refine.lean` | `step_died_sys` | 1424–1434 | 11 | — |
| `Loop/RefineLearn.lean` | `step_refines_all` | 1479–1488 | 10 | — (dispatches to nonlearn/learn) |
| `Loop/Wf.lean` | `step_done` | 1061–1069 | 9 | — (use `stepP_done`, already proved) |
| `Loop/RefineLearn.lean` | `step_flags` | 1472–1478 | 7 | — |
| `Loop/Hygiene.lean` | `step_died_parts` | 1396–1401 | 6 | — |

**1,221 lines.**  The five with a fact in the last column are the only ones where anything but
the opening changes; the other seventeen are the opening and nothing else.

### 5c The substitutions

1. **The opening.**  `simp only [step, State.log] at h; split at h` becomes
   `simp only [stepP, State.log] at h; split at h`.  `split` behaves identically — it splits on
   `dequeuePol pol a s.incm` instead of `s.incm.dequeue` and `rename_i r rest hdq` gives
   `hdq : dequeuePol pol a s.incm = some (r, rest)`.  Everything after the split is unchanged,
   because `stepP`'s body after the dequeue is `step`'s body character for character
   (`stepP_shipped` is `rfl`, which is the machine-checked form of that claim).
2. **The facts.**  `PQueue.dequeue_mem hdq` becomes `shape_mem (dequeuePol_shape hdq)`;
   `dequeue_mem_or hdq` becomes `shape_mem_or (dequeuePol_shape hdq)`; `dequeue_unique h1 h2`
   becomes `(dequeuePol_unique h1 h2).1` (the policy version returns the pair, so take `.1`).
   `stuck`/`.done` reasoning uses `stepP_done` and `stepP_done_dequeue` (`FlaggedSound` §SS4).
3. **`Aux`.**  No soundness statement mentions `a`, so bind `∀ pol a` at the front and let it
   ride.  At the run level the induction threads `a.next pol s'`, exactly as `runSP` does; the
   step lemmas are `∀ a`, so the particular `a` never matters.

### 5d Traps hit while writing `Policy.lean` / `FlaggedSound.lean` — do not rediscover them

* **Alpha-equivalent `match`es are NOT interchangeable.**  Lean compiles each `match` to its own
  auxiliary constant, so a helper lemma written with a separately-typed `match` will not unify
  with the code's `match` even when the two printed types differ only in a bound-variable name
  (`some v` vs `some w`).  This cost an hour on `pickStep_cases`; the fix is to prove such goals
  **inline with a tactic script** rather than through a standalone lemma.
* **Elaboration order for higher-order lemmas.**  `foldl_pick_lt` had to be stated over the
  fold's BODY (`g : Option (Nat × β) → (α × Nat) → Option (Nat × β)`) rather than over its key,
  because the two argmin folds have different key types; and its `hg` argument must be passed as
  `?_` **after** the fold hypothesis, so that `g` is fixed by unification against the real term
  before the side goal is stated.
* **`Nat.min` is not `min`.**  `omega` does not see through `Nat.min a (f y)` with `f y` opaque,
  and `Nat.min_def`/`min_eq_left` are stated for `min`.  Use `Nat.min_eq_left` / `Nat.min_eq_right`.
* **`push_neg` is deprecated** in this toolchain; `push Not at h` is the replacement.
* **Do not `lake build` while a corpus differential is running** — it relinks `looptrace` and the
  in-flight sweep gets `rc=127` for whatever group is running (three groups were lost that way in
  Part A; the reviewer's T-8 records it).
* Scala side, for whoever touches `Constraints.scala`: the name `Ordering` is `scalaz.Ordering`
  there (`import Scalaz._`), so `implicitly[Ordering[…]]` does not resolve — spell comparisons
  out, which is in any case what makes the correspondence with the model's `natListLt` checkable.

## 6. Transport — DONE (stage D1-T, 2026-09-06)

*Written by the transport agent as `D1-TRANSPORT.md` while this document still lived in the
Part-B worktree, and folded in here verbatim from its "Outcome" line on.  `D1-TRANSPORT.md` is
now a pointer to this section, so the spec (§5) and its closure sit together and cannot drift.*

**Outcome: T-DONE.**  All 22 theorems of §5b are transported, together with the 19 further
`step`-unfolding lemmas their proofs depend on that §5b did not list (see "What §5b missed"),
the run level, the acceptance fact and S2's chain.  **No theorem resisted.**  No policy broke
any of them, so there is no FINDING to report against `concFirst`, `smallRhs`, `fifo`, `canon`
or `smallCanon`: everything S1 and S2 prove about the shipped loop is now a theorem about
`stepP pol` for an arbitrary `pol`.

| | |
|---|---|
| new module | `tracker/lean/Rowpartition/Loop/PolicyStep.lean`, **2,373 lines**, 84 declarations |
| files edited | `tracker/lean/Rowpartition.lean` — ONE import line appended to the `Loop` block |
| originals touched | **none** |
| `sorry` | 0 |
| `#print axioms` | 84 declarations, all `[propext, Classical.choice, Quot.sound]` or fewer (`tmp/D1T/print-axioms-T.out`) |
| build | `lake build Rowpartition` **866 jobs** (was 865), no warnings from the new module; **867** with §6k's module |
| audit | `lake env lean Audit.lean` — **4,059 theorems / 0 non-standard axioms** (was 3,969 / 0); **4,112 / 0** with §6k's module |

## 6a What the transport is, and why it is a copy and not a weakening

Every proof in the development consumes `pop` through the SHAPE of a dequeue and never through
the ORDER it chose in.  `Loop/Policy.lean` §5–§6 proved that shape for all six policies; this
module re-runs the proofs against it.  The two substitutions of §5c are the whole change:

1. the opening `simp only [step, State.log] at h` becomes `simp only [stepP, State.log] at h`
   (and `cases hdq : s.incm.dequeue` becomes `cases hdq : dequeuePol pol aux s.incm`);
2. `PQueue.dequeue_mem hdq` becomes `shape_mem (dequeuePol_shape hdq)`, `dequeue_mem_or hdq`
   becomes `shape_mem_or (dequeuePol_shape hdq)`, `dequeue_unique h1 h2` becomes
   `(dequeuePol_unique h1 h2).1`, `QOk.dequeue h hdq` becomes
   `QOk.shape h (dequeuePol_shape hdq)`.

§5c was right about the traps: `dequeue_length_lt`, `dequeue_sub` and `kdist_dequeue` appear in
none of the transported proofs, `split` behaves identically on `dequeuePol pol aux s.incm`, and
everything after the split is unchanged because `stepP`'s body after the dequeue is `step`'s
body character for character.  The MATCHER-CONSTANT trap did not bite: `Order.step_empty_branch`
and its two siblings state a `match` in the theorem itself and close it with `rfl` against the
code's `match`, and the transported copies do the same — the two matcher constants are
definitionally equal even though they are different constants.

**No silent weakening, machine-checked.**  A script re-derived each transported statement from
its original by applying exactly the substitutions above and compared it to what is in the file:
**41 statements compared, 0 differences** (`tmp/D1T/stmt-diff.txt`; the three entries it prints
are its own double-suffixing of the renamed lemmas, not statement differences).  In addition
§7 of the module proves the originals BACK from the transported ones, in the kernel, by
instantiating at `pol := .shipped` and feeding them a hypothesis about `step` with no bridging
lemma in between (`stepP_qok_recovers`, `stepP_supFresh_recovers`,
`stepP_queueHygiene_recovers`, `stepP_refines_all_recovers`, `stepP_noLoss_all_recovers`,
`stepP_died_refutes_recovers`, `stepP_drawn_le_recovers`, `runP_sat_all_recovers`,
`runP_noLoss_recovers`, `runP_rejects_unsat_recovers`).

## 6b What §5b missed, and it matters

§5b listed 22 theorems / 1,221 lines.  That is the set of theorems whose OWN proof unfolds the
dispatch, and it is right as far as it goes; but four of the 22 (`step_refines_all`,
`step_noLoss_all`, `step_strict`, `step_noLoss`) dispatch to BRANCH lemmas which also take
`hdq : s.incm.dequeue = some (r, rest)` alongside `h : step s = .continue s'`, and those cannot
be reused: the hypothesis is about `Q.pop`'s partition, not the policy's.  The transitive
closure is **41 declarations / 1,657 source lines**, not 22 / 1,221.  The extra nineteen are

`step_wf`, `step_sat`, `step_sat_nonlearn`, `step_empty_branch`, `step_unify_branch`,
`step_common_branch`, `step_learn_shape`, `common_self_drops`, `queueHygiene_binds_unbound`,
`step_link_no_death`, `common_eq_sys`, `step_strict_common_eq`, `step_strict_empty`,
`step_strict_common`, `step_strict_unify`, `step_learn_sys_mono`, `step_learn_noLoss`,
`bareAgree_of_sat`, and `QOk.dequeue` (as `QOk.shape`).

Four DEFINITIONS also quantify over the dequeue and therefore need policy forms — they are
about the partition the policy picked, and using the shipped ones would have been exactly the
silent weakening the brief forbids:

```lean
def LinkOrEmptyStepP (pol : Policy) (aux : Aux) (s : State) : Prop :=
  ∀ r rest, dequeuePol pol aux s.incm = some (r, rest) →
    (s.proc.findRHS r.rhs).isSome = true ∨ r.rhs.isEmpty = true ∨ (r.rhs.single?).isSome = true

def NonLearnStepP (pol : Policy) (aux : Aux) (s : State) : Prop := …
def NonConcreteStepP (pol : Policy) (aux : Aux) (s : State) : Prop := …
def IsLearnStepP (pol : Policy) (aux : Aux) (s : State) : Prop := …

def BareAgreeP (pol : Policy) (aux : Aux) (s : State) : Prop :=
  ∀ r rest, dequeuePol pol aux s.incm = some (r, rest) → r.rhs.abstr.isEmpty = true →
    ∀ x ∈ rest.elems ++ s.proc.elems, x.lhs = r.lhs → x.rhs.abstr.isEmpty = true →
      cfs x.rhs.conc = cfs r.rhs.conc
```

`bareAgreeP_of_sat` discharges `BareAgreeP` from satisfiability, exactly as `bareAgree_of_sat`
discharges `BareAgree`, so `stepP_noLoss_or` and `runP_noLoss` carry no new proviso.

## 6c The table: original → transported

`n` is the source size of the declaration (doc comment included) in each tree.  Every
transported statement is the original with `step s` → `stepP pol aux s`,
`s.incm.dequeue` → `dequeuePol pol aux s.incm`, and the four predicates replaced by their
policy forms.  **Nothing else changed in any statement.**

| original | module, lines (`93e9454`) | n | transported | n |
|---|---|---|---|---|
| `step_qok` | `Loop/Wf.lean` 943–1004 | 62 | `stepP_qok` | 61 |
| `step_wf` | `Loop/Wf.lean` 1049–1059 | 12 | `stepP_wf` | 11 |
| `step_flags` | `Loop/RefineLearn.lean` 1472–1476 | 5 | `stepP_flags` | 5 |
| `step_names` | `Loop/Reject.lean` 500–504 | 4 | `stepP_names` | 5 |
| `step_died_sys` | `Loop/Refine.lean` 1424–1428 | 6 | `stepP_died_sys` | 6 |
| `step_died_parts` | `Loop/Hygiene.lean` 1396–1401 | 6 | `stepP_died_parts` | 7 |
| `step_empty_branch` | `Loop/Order.lean` 60–77 | 19 | `stepP_empty_branch` | 18 |
| `step_unify_branch` | `Loop/Order.lean` 79–113 | 35 | `stepP_unify_branch` | 35 |
| `step_common_branch` | `Loop/Order.lean` 116–130 | 16 | `stepP_common_branch` | 15 |
| `step_learn_shape` | `Loop/Order.lean` 132–153 | 22 | `stepP_learn_shape` | 22 |
| `common_self_drops` | `Loop/Order.lean` 515–523 | 11 | `common_self_dropsP` | 8 |
| `step_queueHygiene` | `Loop/Hygiene.lean` 1210–1340 | 131 | `stepP_queueHygiene` | 131 |
| `queueHygiene_binds_unbound` | `Loop/Hygiene.lean` 1438–1462 | 31 | `queueHygiene_binds_unboundP` | 25 |
| `step_link_no_death` | `Loop/Hygiene.lean` 1476–1504 | 31 | `stepP_link_no_death` | 29 |
| `step_supFresh` | `Loop/Supply.lean` 545–726 | 183 | `stepP_supFresh` | 182 |
| `step_drawn_le` | `Loop/Mints.lean` 287–346 | 62 | `stepP_drawn_le` | 60 |
| `step_su` | `Loop/StrictBound.lean` 34–85 | 54 | `stepP_su` | 52 |
| `step_envNodup` | `Loop/StrictBound.lean` 150–208 | 59 | `stepP_envNodup` | 59 |
| `step_refines` | `Loop/Refine.lean` 1146–1262 | 119 | `stepP_refines` | 117 |
| `step_sat` | `Loop/Refine.lean` 1264–1268 | 4 | `stepP_sat` | 4 |
| `step_refines_nonlearn` | `Loop/RefineConcrete.lean` 650–701 | 52 | `stepP_refines_nonlearn` | 52 |
| `step_sat_nonlearn` | `Loop/RefineConcrete.lean` 704–708 | 5 | `stepP_sat_nonlearn` | 4 |
| `step_refines_learn` | `Loop/RefineLearn.lean` 1353–1468 | 116 | `stepP_refines_learn` | 116 |
| `step_refines_all` | `Loop/RefineLearn.lean` 1479–1487 | 10 | `stepP_refines_all` | 9 |
| `step_sat_all` | `Loop/RefineLearn.lean` 1489–1495 | 7 | `stepP_sat_all` | 7 |
| `common_eq_sys` | `Loop/StrictStep.lean` 231–255 | 28 | `common_eq_sysP` | 25 |
| `step_strict_common_eq` | `Loop/StrictStep.lean` 257–264 | 8 | `stepP_strict_common_eq` | 8 |
| `step_strict_empty` | `Loop/StrictStep.lean` 1080–1154 | 76 | `stepP_strict_empty` | 74 |
| `step_strict_common` | `Loop/StrictStep.lean` 1389–1492 | 104 | `stepP_strict_common` | 104 |
| `step_strict_unify` | `Loop/StrictStep.lean` 1495–1597 | 103 | `stepP_strict_unify` | 102 |
| `step_strict` | `Loop/StrictStep.lean` 1604–1626 | 26 | `stepP_strict` | 23 |
| `step_learn_env` | `Loop/StrictStep.lean` 1757–1776 | 19 | `stepP_learn_env` | 20 |
| `step_learn_sys_mono` | `Loop/StrictStep.lean` 1778–1790 | 13 | `stepP_learn_sys_mono` | 13 |
| `step_learn_noLoss` | `Loop/StrictStep.lean` 1792–1797 | 6 | `stepP_learn_noLoss` | 6 |
| `step_noLoss` | `Loop/StrictStep.lean` 1805–1830 | 26 | `stepP_noLoss` | 25 |
| `bareAgree_of_sat` | `Loop/Sound.lean` 899–911 | 14 | `bareAgreeP_of_sat` | 13 |
| `step_noLoss_concrete` | `Loop/Sound.lean` 914–956 | 44 | `stepP_noLoss_concrete` | 43 |
| `step_noLoss_all` | `Loop/Sound.lean` 959–980 | 23 | `stepP_noLoss_all` | 22 |
| `step_noLoss_sat` | `Loop/Sound.lean` 982–985 | 4 | `stepP_noLoss_sat` | 4 |
| `step_noLoss_or` | `Loop/Sound.lean` 988–993 | 7 | `stepP_noLoss_or` | 6 |
| `step_died_refutes` | `Loop/Reject.lean` 517–609 | 94 | `stepP_died_refutes` | 93 |
| **totals** | | **1,657** | | **1,621** |

`step_done` is NOT re-proved: `FlaggedSound.stepP_done` already is it, and the module uses that
one.  `QOk.dequeue` becomes `QOk.shape`, stated over `DequeueShape` rather than over a policy.

## 6d The step level, verbatim

```lean
theorem stepP_qok {L : List Lbl} {s s' : State} (hi : QOk L s.incm) (hp : QOk L s.proc)
    (h : stepP pol aux s = .continue s') : QOk L s'.incm ∧ QOk L s'.proc

theorem stepP_wf {s s' : State} (hw : Wf s) (h : stepP pol aux s = .continue s') : Wf s'

theorem stepP_supFresh {s s' : State} (hdj : s.flags.disjRule = false)
    (hcse : s.flags.cseMints = false) (hok : SupOk s.su) (hfr : SupFresh s.su (sys s))
    (h : stepP pol aux s = .continue s') :
    SupOk s'.su ∧ (∀ z, Sup.Reach s'.su z → Sup.Reach s.su z) ∧ SupFresh s'.su (sys s')

theorem stepP_queueHygiene {s s' : State} (hdj : s.flags.disjRule = false)
    (hok : SupOk s.su) (hfr : SupFresh s.su (sys s))
    (h0 : QueueHygiene s) (h : stepP pol aux s = .continue s') : QueueHygiene s'

theorem stepP_drawn_le {s s' : State} (hdj : s.flags.disjRule = false)
    (hcse : s.flags.cseMints = false) (h : stepP pol aux s = .continue s') :
    s'.su.drawn ≤ s.su.drawn + 1 + s.proc.elems.length

theorem stepP_refines_all {s s' : State} (hw : Wf s)
    (hem : s.flags.emptyRow = false) (hdj : s.flags.disjRule = false)
    (hcse : s.flags.cseMints = false)
    (hok : SupOk s.su) (hfr : SupFresh s.su (sys s))
    (h : stepP pol aux s = .continue s') : LoopRun (sys s) (sys s')

theorem stepP_sat_all {s s' : State} (hw : Wf s)
    (hem : s.flags.emptyRow = false) (hdj : s.flags.disjRule = false)
    (hcse : s.flags.cseMints = false)
    (hok : SupOk s.su) (hfr : SupFresh s.su (sys s))
    (h : stepP pol aux s = .continue s') : SSat (sys s) → SSat (sys s')

theorem stepP_noLoss_all {s s' : State} (hw : Wf s) (hba : BareAgreeP pol aux s)
    (h : stepP pol aux s = .continue s') : NoLoss (sys s) (sys s')

theorem stepP_noLoss_or {s s' : State} (hw : Wf s) (h : stepP pol aux s = .continue s') :
    NoLoss (sys s) (sys s') ∨ ¬ SSat (sys s)

theorem stepP_died_refutes {s s' : State} {m : String} (hw : Wf s) (hq : QueueHygiene s)
    (h : stepP pol aux s = .died m s') : ¬ SSat (sys s) ∨ NonRefutation s.names m
```

(`pol : Policy` and `aux : Aux` are section variables, auto-bound implicit in front of every
binder shown.  `stepP_envNodup`, `stepP_su`, `stepP_strict`, `stepP_noLoss`, `stepP_refines`,
`stepP_refines_nonlearn`, `stepP_refines_learn` and the branch lemmas are in the module in the
same form.)

## 6e The run level, verbatim

```lean
def runP (pol : Policy) : Aux → State → Nat → RunResult
  | _, s, 0 => .outOfFuel s
  | a, s, n + 1 =>
    match stepP pol a s with
    | .done s' => .solved s'
    | .died m s' => .rejected m s'
    | .continue s' => runP pol (a.next pol s') s' n

theorem runP_shipped (aux : Aux) (s : State) : ∀ n, runP .shipped aux s n = run s n

def RunSupOkP (pol : Policy) : Aux → Nat → State → Prop
  | _, 0, _ => True
  | a, n + 1, s => SupOk s.su ∧ SupFresh s.su (sys s) ∧
      ∀ s', stepP pol a s = .continue s' → RunSupOkP pol (a.next pol s') n s'

theorem runP_sat_all : ∀ (n : Nat) {aux : Aux} {s : State}, Wf s → s.flags.emptyRow = false →
    s.flags.disjRule = false → s.flags.cseMints = false → RunSupOkP pol aux n s → SSat (sys s) →
    ∀ s', (runP pol aux s n = .solved s' ∨ runP pol aux s n = .outOfFuel s') → SSat (sys s')

theorem runP_noLoss : ∀ (n : Nat) {aux : Aux} {s : State}, Wf s → s.flags.emptyRow = false →
    s.flags.disjRule = false → s.flags.cseMints = false → RunSupOkP pol aux n s → SSat (sys s) →
    ∀ s', (runP pol aux s n = .solved s' ∨ runP pol aux s n = .outOfFuel s') →
      NoLoss (sys s) (sys s')

theorem runP_models {n : Nat} {aux : Aux} {s s' : State} (hw : Wf s)
    (hem : s.flags.emptyRow = false) (hdj : s.flags.disjRule = false)
    (hcse : s.flags.cseMints = false) (hb : RunSupOkP pol aux n s) (hsat : SSat (sys s))
    (hres : runP pol aux s n = .solved s' ∨ runP pol aux s n = .outOfFuel s') :
    ∀ rho, SModels rho (sys s') → SModels rho (sys s)

theorem runP_ssat_iff {n : Nat} {aux : Aux} {s s' : State} (hw : Wf s)
    (hem : s.flags.emptyRow = false) (hdj : s.flags.disjRule = false)
    (hcse : s.flags.cseMints = false) (hb : RunSupOkP pol aux n s) (hsat : SSat (sys s))
    (hres : runP pol aux s n = .solved s' ∨ runP pol aux s n = .outOfFuel s') :
    SSat (sys s) ↔ SSat (sys s')

theorem runP_noLoss_or {n : Nat} {aux : Aux} {s s' : State} (hw : Wf s)
    (hem : s.flags.emptyRow = false) (hdj : s.flags.disjRule = false)
    (hcse : s.flags.cseMints = false) (hb : RunSupOkP pol aux n s)
    (hres : runP pol aux s n = .solved s' ∨ runP pol aux s n = .outOfFuel s') :
    NoLoss (sys s) (sys s') ∨ ¬ SSat (sys s)

theorem runP_refutes_all : ∀ (n : Nat) {aux : Aux} {s : State}, Wf s →
    s.flags.emptyRow = false → s.flags.disjRule = false → s.flags.cseMints = false →
    RunSupOkP pol aux n s →
    ∀ (m : String) (s' : State), runP pol aux s n = .rejected m s' → ¬ SSat (sys s') →
      ¬ SSat (sys s)

theorem runP_rejects_unsat : ∀ (n : Nat) {aux : Aux} {s : State}, Wf s →
    s.flags.emptyRow = false → s.flags.disjRule = false → s.flags.cseMints = false →
    RunSupOkP pol aux n s → QueueHygiene s →
    ∀ (m : String) (s' : State), runP pol aux s n = .rejected m s' →
      ¬ NonRefutation s.names m → ¬ SSat (sys s)

theorem runP_rejects_unsat_noSkolem (n : Nat) {aux : Aux} {s : State} (hw : Wf s)
    (hem : s.flags.emptyRow = false) (hdj : s.flags.disjRule = false)
    (hcse : s.flags.cseMints = false) (hb : RunSupOkP pol aux n s) (hq : QueueHygiene s)
    (hsk : ∀ v, s.names.isSkolem v = false)
    (m : String) (s' : State) (hres : runP pol aux s n = .rejected m s') : ¬ SSat (sys s)
```

Note the exception list: at the run level of `runP` there is NO budget, so the exception list is
`NonRefutation` — the skolem refusal and nothing else, exactly as in `Reject.run_rejects_unsat`.
`NonRefutationB` enters where the budget does, in §6g.

## 6f ACCEPTANCE — `stepP_done_dequeue` used, not merely stated (T3)

```lean
theorem runP_solved_saturated : ∀ (n : Nat) {aux : Aux} {s s' : State},
    runP pol aux s n = .solved s' → s'.incm.elems = []
  | 0, aux, s, s', hres => by simp only [runP] at hres; exact absurd hres (by simp)
  | n + 1, aux, s, s', hres => by
    simp only [runP] at hres
    cases hst : stepP pol aux s with
    | done s0 =>
      rw [hst] at hres
      rw [RunResult.solved.injEq] at hres
      subst hres
      -- THE ACCEPTANCE FACT, at the point of use: `.done` is `dequeuePol … = none`, and
      -- `dequeuePol_none` says that happens only on an empty queue.
      rw [stepP_done hst]
      exact stepP_done_dequeue hst
    | died m0 s0 => rw [hst] at hres; exact absurd hres (by simp)
    | «continue» s0 => rw [hst] at hres; exact runP_solved_saturated n hres

theorem runP_accepted_saturated_noLoss {n : Nat} {aux : Aux} {s s' : State} (hw : Wf s)
    (hem : s.flags.emptyRow = false) (hdj : s.flags.disjRule = false)
    (hcse : s.flags.cseMints = false) (hb : RunSupOkP pol aux n s) (hsat : SSat (sys s))
    (hres : runP pol aux s n = .solved s') :
    s'.incm.elems = [] ∧ NoLoss (sys s) (sys s') ∧ SSat (sys s')
```

This is the failure mode a dequeue order could introduce all on its own — a `pop` answering
`none` on a non-empty queue would make `incorporateAll` return `proc` and the solve accept
WITHOUT SATURATING.  The `.solved` case of the run induction is where `stepP_done_dequeue`
(hence `dequeuePol_none`) is consumed.

## 6g The driver the replay actually runs: `runSP pol d0 b`

`PolicyReplay.solveSeedP` runs `runSP pol d0 bud`, whose step is `stepSP`.  Two reductions bring
it back to `runP` — the exact analogues of `FlaggedSound` SS1–SS3 for the budget, now over a
policy — and the budget's death joins the skolem refusal on `NonRefutationB`.

```lean
theorem runSP_eq_runP {d0 : Nat} : ∀ (n : Nat) (aux : Aux) {s : State},
    s.flags.rowSoundBare = false → runSP pol d0 0 aux s n = runP pol aux s n

theorem runSP_outOfFuel {d0 b : Nat} : ∀ (n : Nat) (aux : Aux) {s s' : State},
    s.flags.rowSoundBare = false → runSP pol d0 b aux s n = .outOfFuel s' →
    runP pol aux s n = .outOfFuel s'

theorem runSP_never_accepts {d0 b : Nat} : ∀ (n : Nat) (aux : Aux) {s s' : State},
    s.flags.rowSoundBare = false → runSP pol d0 b aux s n = .solved s' →
    runP pol aux s n = .solved s'

theorem runSP_noLoss {d0 b n : Nat} {aux : Aux} {s : State} (hrs : s.flags.rowSoundBare = false)
    (hw : Wf s) (hem : s.flags.emptyRow = false) (hdj : s.flags.disjRule = false)
    (hcse : s.flags.cseMints = false) (hb : RunSupOkP pol aux n s) (hsat : SSat (sys s))
    (s' : State)
    (hres : runSP pol d0 b aux s n = .solved s' ∨ runSP pol d0 b aux s n = .outOfFuel s') :
    NoLoss (sys s) (sys s')

theorem runSP_sat_all … : SSat (sys s')
theorem runSP_models … : ∀ rho, SModels rho (sys s') → SModels rho (sys s)

theorem runSP_solved_saturated {d0 b n : Nat} {aux : Aux} {s s' : State}
    (hrs : s.flags.rowSoundBare = false) (hres : runSP pol d0 b aux s n = .solved s') :
    s'.incm.elems = []

theorem runSP_rejects_unsat {d0 b : Nat} : ∀ (n : Nat) (aux : Aux) {s : State},
    s.flags.rowSoundBare = false → Wf s →
    s.flags.emptyRow = false → s.flags.disjRule = false → s.flags.cseMints = false →
    RunSupOkP pol aux n s → QueueHygiene s →
    ∀ (m : String) (s' : State), runSP pol d0 b aux s n = .rejected m s' →
      ¬ NonRefutationB s.names m → ¬ SSat (sys s)

theorem runSP_rejects_of_runP_rejects {d0 b : Nat} : ∀ (n : Nat) (aux : Aux) {s : State}
    {m : String} {s' : State}, s.flags.rowSoundBare = false →
    runP pol aux s n = .rejected m s' → ∃ m0 s0, runSP pol d0 b aux s n = .rejected m0 s0

theorem runSP_not_rejected {d0 b n : Nat} {aux : Aux} {s : State}
    (hrs : s.flags.rowSoundBare = false)
    (h : ∀ m s', runSP pol d0 b aux s n ≠ .rejected m s') :
    ∀ m s', runP pol aux s n ≠ .rejected m s'
```

`runSP_not_rejected` is the policy version of `FlaggedSound.runBud_not_rejected`, and it lands
on `runP` rather than on `run`: `runSP pol` follows `stepP pol`, and there is no theorem
relating a NON-shipped run to the shipped one — nor could there be, since they dequeue different
partitions.  That is the right target, because §6h's chain is stated over `runP`.

The hypothesis `s.flags.rowSoundBare = false` is S2's layer (i) off, which is the shipped
setting; `stepP_flags` propagates it along the run, so it is required only at the initial state.

## 6h S2's chain, for the policy solve

```lean
theorem solveSeedP_rejects_of_refuted {bud : Nat} {fl : Flags} {site loc : String}
    {cs : List CsItem} {ns : Names} {su0 : Sup} {fuel : Nat} {envFacts : List LPart}
    {q : PQueue} {su1 : Sup}
    (hq : buildQueue cs su0 = .ok (q, su1))
    (hearly : (if fl.labelCheck && fl.labelCheckEarly then labelClash ns q.elems else none) =
      none)
    (hflag : fl.rowSoundDecide = true)
    {l : Lbl} {a : Nat} {w : String}
    (href : (labelDecide (q.elems ++ envFacts) fl.rowSoundBudget
              fl.rowSoundSolveBudget).1 = .refuted l a w) :
    (solveSeedP pol bud fl site loc cs ns su0 fuel envFacts).verdict = "REJECTED"

theorem solveP_noFalseAccept {L : List Lbl} (hcoh : LblCoh L) {bud : Nat}
    {fl : Flags} {site loc : String} {cs : List CsItem} {ns : Names} {su0 : Sup} {fuel : Nat}
    {envFacts : List LPart} {q : PQueue} {su1 : Sup}
    (hq : buildQueue cs su0 = .ok (q, su1))
    (hearly : (if fl.labelCheck && fl.labelCheckEarly then labelClash ns q.elems else none) =
      none)
    (hflag : fl.rowSoundDecide = true)
    (hnd : ∀ p ∈ q.elems ++ envFacts, p.rhs.abstr.elems.Nodup)
    (hmem : ∀ p ∈ q.elems ++ envFacts, ∀ x ∈ p.rhs.conc.elems, x ∈ L)
    (hbud : ∀ l w, (labelDecide (q.elems ++ envFacts) fl.rowSoundBudget
                     fl.rowSoundSolveBudget).1 ≠ .noVerdict l w)
    (hacc : (solveSeedP pol bud fl site loc cs ns su0 fuel envFacts).verdict ≠ "REJECTED") :
    SSat ((((q.elems ++ envFacts).map LPart.toConstraint)).toFinset)

theorem solveP_accepted_faithful {L : List Lbl} (hcoh : LblCoh L) {bud : Nat}
    {fl : Flags} {site loc : String} {cs : List CsItem} {ns : Names} {su0 : Sup} {fuel : Nat}
    {envFacts : List LPart} {q : PQueue} {su1 : Sup} {tr : List String} {z : Nat}
    (hq : buildQueue cs su0 = .ok (q, su1))
    (hearly : (if fl.labelCheck && fl.labelCheckEarly then labelClash ns q.elems else none) =
      none)
    (hflag : fl.rowSoundDecide = true)
    (hnd : ∀ p ∈ q.elems ++ envFacts, p.rhs.abstr.elems.Nodup)
    (hmem : ∀ p ∈ q.elems ++ envFacts, ∀ x ∈ p.rhs.conc.elems, x ∈ L)
    (hbud : ∀ l w, (labelDecide (q.elems ++ envFacts) fl.rowSoundBudget
                     fl.rowSoundSolveBudget).1 ≠ .noVerdict l w)
    (hacc : (solveSeedP pol bud fl site loc cs ns su0 fuel envFacts).verdict ≠ "REJECTED")
    (n : Nat) (aux : Aux) (hw : Wf (initState q su1 tr fl ns site z))
    (hem : fl.emptyRow = false) (hdj : fl.disjRule = false) (hcse : fl.cseMints = false)
    (hb : RunSupOkP pol aux n (initState q su1 tr fl ns site z))
    {s' : State}
    (hres : runP pol aux (initState q su1 tr fl ns site z) n = .solved s' ∨
            runP pol aux (initState q su1 tr fl ns site z) n = .outOfFuel s') :
    NoLoss (sys (initState q su1 tr fl ns site z)) (sys s') ∧
    (∀ rho, SModels rho (sys s') → SModels rho (sys (initState q su1 tr fl ns site z))) ∧
    (SSat (sys (initState q su1 tr fl ns site z)) ↔ SSat (sys s'))
```

Layer (iii) runs BEFORE the loop in `solveSeedP` exactly as it does in `solveSeed`, so the
policy changes nothing about it and the two S2 theorems transport line for line, with `runP`
supplying the S1 half.

## 6i What §4d of `D1-CHANGE.md` said, and what it now says

`FlaggedSound` §SS5 ("NOT PROVED, and not claimed: that a run under a NON-DEFAULT policy refines
`LoopRun`, preserves satisfiability, loses nothing, or refutes when it rejects") is now
SUPERSEDED.  All four are theorems: `stepP_refines_all`, `runP_sat_all`, `runP_noLoss`,
`runP_rejects_unsat`.  The measurement — 0 verdict differences in 2,301,195 corpus solves — is
now corroboration of a theorem rather than a substitute for one.  `FlaggedSound.lean` itself was
NOT edited (this stage may not edit it); the correction belongs in Part B's document.

**What is still not proved, and is not claimed here.**  TERMINATION under a policy: nothing in
this module says a non-shipped order finishes, and D1 Part A's measurement (`canon` failing to
finish `GU05`'s corpus instance in 1,800 s) says orders differ on that.  Termination under a
policy is the draw budget's business (`budget_terminates` is stated for `run`/`runBud`, not for
`runP`), and it is not part of this transport.

## 6k Termination under a budget, transported

D1 ships the budget TOGETHER with the policy, and the budget's whole point is *every solve
stops*.  `Budget.budget_terminates` and `VocFix.terminates_of_drawsAtMost` were stated for
`run`/`runBud`, i.e. for the SHIPPED order.  A second module carries them across.

| | |
|---|---|
| new module | `tracker/lean/Rowpartition/Loop/PolicyTerm.lean`, **1,127 lines**, 54 declarations |
| files edited | `tracker/lean/Rowpartition.lean` — one more import line |
| originals touched | **none** |
| `sorry` | 0 |
| `#print axioms` | 54 declarations, `[propext, Classical.choice, Quot.sound]` (53) / `[propext, Quot.sound]` (1) — `tmp/D1T2/print-axioms-T2.out` |
| build | `lake build Rowpartition` **867 jobs** |
| audit | **4,112 theorems / 0 non-standard axioms** |

**Outcome: it goes through for every policy.**  No goal resisted; there is no policy-dependent
obstruction to report.

### Why it transports

Round 7's argument measures the STATE — the incoming queue's length, the processed set, the
row set, the environment and the vocabulary — and never the ORDER a partition was chosen in.
The four facts about `pop` it uses are `shape_mem`, `shape_mem_or`, `shape_kdist` and the
queue-length equation, all of which hold for every policy.  `shape_length_lt` (`Policy.lean`)
gives only `<` and `step_quadrichotomy`'s third case needs the equation, so the module opens
with the one missing fact:

```lean
theorem shape_length_eq {q : PQueue} {r : LPart} {rest : PQueue} (h : DequeueShape q r rest) :
    rest.elems.length + 1 = q.elems.length
```

### The step level: 9 declarations, scripted, statement-diffed

Same two substitutions as §6a, plus `shape_length_eq (dequeuePol_shape hd)` for
`dequeue_length_lt hd`.  **8 statements compared against their originals, 0 differences**
(`tmp/D1T2/stmt-diff2.txt`; `IsConcStep` is excluded because it is restated by hand with
explicit `(pol) (aux)` binders, its body otherwise identical).

| original | module, lines | n | transported | n |
|---|---|---|---|---|
| `IsConcStep` | `Loop/VocFix.lean` 1060–1064 | 5 | `IsConcStepP` | 5 |
| `step_inVoc_noDraw` | `Loop/VocFix.lean` 466–600 | 138 | `stepP_inVoc_noDraw` | 135 |
| `rowSet_lt_concrete` | `Loop/VocFix.lean` 964–1052 | 89 | `rowSetP_lt_concrete` | 89 |
| `learn_procSys_lt` | `Loop/Order.lean` 442–479 | 39 | `learnP_procSys_lt` | 37 |
| `step_quadrichotomy` | `Loop/VocFix.lean` 1070–1163 | 98 | `stepP_quadrichotomy` | 95 |
| `measure4_lt` | `Loop/VocFix.lean` 1211–1230 | 22 | `measureP4_lt` | 21 |
| `step_kdist'` | `Loop/VocFix.lean` 1336–1403 | 69 | `stepP_kdist'` | 68 |
| `step_drawn_ge` | `Loop/VocFix.lean` 1825–1888 | 64 | `stepP_drawn_ge` | 64 |
| `step_concSub` | `Loop/VocFix.lean` 108–113 | 7 | `stepP_concSub` | 6 |
| **totals** | | **531** | | **520** |

`measure4`, `measure4_arith`, `rowSet`, `rowSet_card_le`, `rowSet_subset_of`, `procSys`,
`procSys_card_leL`, `kdist_length_leL`, `env_len_le_card`, `InVoc`, `ConcSub` are functions of
the STATE, so they are REUSED unchanged — the coordinator's "reuse `measure4`, only the decrease
lemma changes" is exactly right, and `measureP4_lt` is stated over the very same `measure4`.

### The run level: the ONE shape change, stated

`Reaches`, `Runs`, `Terminates` and `NoDrawB` are defined in terms of `step`/`run`.  Under a
policy the loop also threads the auxiliary state `Aux` (`fifo`'s arrival batches, `canon`'s
cached priority), and `Aux.next` depends on the previous `Aux`, so the relations must carry it:

```lean
inductive ReachesP (pol : Policy) (a0 : Aux) (s0 : State) : Aux → State → Prop
  | refl : ReachesP pol a0 s0 a0 s0
  | tail {b : Aux} {t u : State} : ReachesP pol a0 s0 b t → stepP pol b t = .continue u →
      ReachesP pol a0 s0 (b.next pol u) u

def RunsP (pol : Policy) : Nat → Aux → State → Aux → State → Prop
  | 0, a, s, b, t => a = b ∧ s = t
  | n + 1, a, s, b, t => ∃ u, stepP pol a s = .continue u ∧ RunsP pol n (a.next pol u) u b t

def TerminatesP (pol : Policy) (a : Aux) (s : State) : Prop := ∃ n : Nat, Finished (runP pol a s n)

def TerminatesBP (pol : Policy) (d0 b : Nat) (a : Aux) (s : State) : Prop :=
  ∃ n : Nat, Finished (runSP pol d0 b a s n)

def VocFixedP (pol : Policy) (V : Finset Var) (a : Aux) (s : State) : Prop :=
  ∀ b t, ReachesP pol a s b t → InVoc V t

def NoDrawP (pol : Policy) (a : Aux) (s : State) : Prop :=
  ∀ b t t', ReachesP pol a s b t → stepP pol b t = .continue t' → t'.su.drawn = t.su.drawn
```

So **every statement quantified over `Reaches s t` gains exactly one binder** — the auxiliary
state at the reached configuration — and nothing else changes.  This is a shape change, not a
weakening, and §10 of the module proves it in the kernel: `reachesP_shipped` (a `ReachesP
.shipped` is a `Reaches`), `reachesP_of_reaches` (and back, threading any `Aux`),
`terminatesP_shipped` (`TerminatesP .shipped a s ↔ Terminates s`), and the two recovery
theorems below.

| original | module, lines | transported | n |
|---|---|---|---|
| `Reaches` | `Loop/Refuted.lean` 483–486 | `ReachesP` | 5 |
| `reaches_trans` | `Loop/NoConc.lean` 566–570 | `reachesP_trans` | 6 |
| `Runs` | `Loop/Cycle.lean` 223–226 | `RunsP` | 4 |
| `Runs.run_eq` | `Loop/Cycle.lean` 229–235 | `RunsP.run_eq` | 13 |
| `Terminates` | `Loop/Order.lean` 30 | `TerminatesP` | 2 |
| `TerminatesB` | `Loop/Budget.lean` 69 | `TerminatesBP` | 3 |
| `runs_snoc` | `Loop/VocFix.lean` 1686–1692 | `runsP_snoc` | 10 |
| `runs_of_reaches` | `Loop/VocFix.lean` 1694–1699 | `runsP_of_reachesP` | 8 |
| `terminates_of_runs` | `Loop/VocFix.lean` 1701–1704 | `terminatesP_of_runsP` | 5 |
| `terminates_of_reaches` | `Loop/VocFix.lean` 1707–1710 | `terminatesP_of_reachesP` | 5 |
| `reaches_wf` | `Loop/NoConc.lean` 1173–1176 | `reachesP_wf` | 5 |
| `reaches_envNodup` | `Loop/NoConc.lean` 1178–1181 | `reachesP_envNodup` | 6 |
| `reaches_flags_eq` | `Loop/VocFix.lean` 101–104 | `reachesP_flags_eq` | 6 |
| `reaches_invariants` | `Loop/Supply.lean` 769–781 | `reachesP_invariants` | 14 |
| `reaches_concSub` | `Loop/VocFix.lean` 115–126 | `reachesP_concSub` | 13 |
| `reaches_kdist` | `Loop/VocFix.lean` 1404–1408 | `reachesP_kdist` | 7 |
| `reaches_drawn_ge` | `Loop/VocFix.lean` 1889–1895 | `reachesP_drawn_ge` | 8 |
| `terminates_of_bounds4_aux` | `Loop/VocFix.lean` 1232–1270 | `terminatesP_of_bounds4_aux` | 40 |
| `terminates_of_bounds4` | `Loop/VocFix.lean` 1272–1280 | `terminatesP_of_bounds4` | 11 |
| `VocFixed` | `Loop/VocFix.lean` 1423 | `VocFixedP` | 3 |
| `NoDraw` | `Loop/VocFix.lean` 1428–1429 | `NoDrawP` | 3 |
| `vocFixed_of_noDraw` | `Loop/VocFix.lean` 1432–1441 | `vocFixedP_of_noDraw` | 11 |
| `vocFixed_terminates` | `Loop/VocFix.lean` 1446–1463 | `vocFixedP_terminates` | 18 |
| `vocFixed_run` | `Loop/VocFix.lean` 1465–1483 | `vocFixedP_run` | 18 |
| `noDraw_terminates` | `Loop/VocFix.lean` 1485–1492 | `noDrawP_terminates` | 9 |
| `EventuallyNoDraw` | `Loop/VocFix.lean` 1713 | `EventuallyNoDrawP` | 3 |
| `terminates_of_eventuallyNoDraw` | `Loop/VocFix.lean` 1716–1731 | `terminatesP_of_eventuallyNoDrawP` | 14 |
| `draws_cofinally_of_not_terminates` | `Loop/VocFix.lean` 1734–1742 | `drawsP_cofinally_of_not_terminatesP` | 9 |
| `not_vocFixed_of_not_terminates` | `Loop/VocFix.lean` 1745–1752 | `not_vocFixedP_of_not_terminatesP` | 8 |
| `drawn_unbounded_of_not_terminates` | `Loop/VocFix.lean` 1898–1923 | `drawnP_unbounded_of_not_terminatesP` | 27 |
| `terminates_of_drawsAtMost` | `Loop/VocFix.lean` 1926–1937 | `terminatesP_of_drawsAtMost` | 12 |
| `NoDrawB` | `Loop/VocFix.lean` 1542–1548 | `NoDrawBP` | 8 |
| `noDrawB_reaches` | `Loop/VocFix.lean` 1550–1562 | `noDrawBP_reaches` | 14 |
| `noDraw_of_noDrawB` | `Loop/VocFix.lean` 1565–1574 | `noDrawP_of_noDrawBP` | 11 |
| `terminatesB_of_finished` | `Loop/Budget.lean` 150–163 | `terminatesBP_of_finished` | 15 |
| `terminatesB_of_over` | `Loop/Budget.lean` 166–190 | `terminatesBP_of_over` | 16 |
| `budget_terminates` | `Loop/Budget.lean` 193–207 | `budgetP_terminates` | 15 |
| `budget_terminates_of_buildQueue` | `Loop/Budget.lean` 209–221 | `budgetP_terminates_of_buildQueue` | 13 |
| **totals** | | **38 declarations** | **398** |

### The final theorems, verbatim

```lean
theorem measureP4_lt {P Q E R : Nat} {V : Finset Var} {L : Finset Label} {s s' : State}
    (hw : Wf s) (hv : InVoc V s) (hcs : ConcSub L (sys s))
    (hR' : (rowSet V L s').card ≤ R) (hP' : (procSys s').card ≤ P)
    (hQ' : s'.incm.elems.length ≤ Q) (hE' : s'.env.binds.length ≤ E)
    (h : stepP pol aux s = .continue s') :
    measure4 P Q E R V L s' < measure4 P Q E R V L s

theorem terminatesP_of_bounds4 {P Q E R : Nat} {V : Finset Var} {L : Finset Label} {a : Aux}
    {s : State}
    (hw : ∀ b t, ReachesP pol a s b t → Wf t) (hv : ∀ b t, ReachesP pol a s b t → InVoc V t)
    (hcs : ∀ b t, ReachesP pol a s b t → ConcSub L (sys t))
    (hr : ∀ b t, ReachesP pol a s b t → (rowSet V L t).card ≤ R)
    (hp : ∀ b t, ReachesP pol a s b t → (procSys t).card ≤ P)
    (hq : ∀ b t, ReachesP pol a s b t → t.incm.elems.length ≤ Q)
    (he : ∀ b t, ReachesP pol a s b t → t.env.binds.length ≤ E) : TerminatesP pol a s

theorem vocFixedP_terminates {V : Finset Var} {L : Finset Label} {a : Aux} {s : State}
    (hem : s.flags.emptyRow = false) (hdj : s.flags.disjRule = false)
    (hcse : s.flags.cseMints = false) (hw : Wf s) (hnd : EnvNodup s)
    (hok : SupOk s.su) (hfr : SupFresh s.su (sys s)) (hqh : QueueHygiene s)
    (hcs : ConcSub L (sys s)) (hki : KDist s.incm.elems) (hkp : KDist s.proc.elems)
    (hvf : VocFixedP pol V a s) : TerminatesP pol a s

theorem vocFixedP_run {V : Finset Var} {L : Finset Label} {a : Aux} {s : State}
    … (hvf : VocFixedP pol V a s) :
    Finished (runP pol a s (measure4 (V.card * 2 ^ V.card * 2 ^ L.card)
      (V.card * 2 ^ V.card * 2 ^ L.card) V.card (V.card * 2 ^ L.card) V L s + 1))

theorem drawnP_unbounded_of_not_terminatesP {a : Aux} {s : State}
    (hem : s.flags.emptyRow = false) (hdj : s.flags.disjRule = false)
    (hcse : s.flags.cseMints = false) (hw : Wf s) (hnd : EnvNodup s)
    (hok : SupOk s.su) (hfr : SupFresh s.su (sys s)) (hqh : QueueHygiene s)
    (hki : KDist s.incm.elems) (hkp : KDist s.proc.elems)
    (h : ¬ TerminatesP pol a s) :
    ∀ n : Nat, ∃ b t, ReachesP pol a s b t ∧ s.su.drawn + n ≤ t.su.drawn

theorem terminatesP_of_drawsAtMost {k : Nat} {a : Aux} {s : State}
    (hem : s.flags.emptyRow = false) (hdj : s.flags.disjRule = false)
    (hcse : s.flags.cseMints = false) (hw : Wf s) (hnd : EnvNodup s)
    (hok : SupOk s.su) (hfr : SupFresh s.su (sys s)) (hqh : QueueHygiene s)
    (hki : KDist s.incm.elems) (hkp : KDist s.proc.elems)
    (h : ∀ b t, ReachesP pol a s b t → t.su.drawn ≤ s.su.drawn + k) : TerminatesP pol a s

theorem terminatesBP_of_finished {d0 b : Nat} : ∀ (n : Nat) (a : Aux) (s : State),
    s.flags.rowSoundBare = false → Finished (runP pol a s n) → Finished (runSP pol d0 b a s n)

theorem terminatesBP_of_over {d0 b : Nat} (hb0 : b ≠ 0) :
    ∀ (k : Nat) {a c : Aux} {s t : State}, s.flags.rowSoundBare = false →
    RunsP pol k a s c t → d0 + b < t.su.drawn → TerminatesBP pol d0 b a s

theorem budgetP_terminates {b : Nat} {a : Aux} {s : State} (hb0 : b ≠ 0)
    (hrs : s.flags.rowSoundBare = false)
    (hem : s.flags.emptyRow = false) (hdj : s.flags.disjRule = false)
    (hcse : s.flags.cseMints = false) (hw : Wf s) (hnd : EnvNodup s)
    (hok : SupOk s.su) (hfr : SupFresh s.su (sys s)) (hqh : QueueHygiene s)
    (hki : KDist s.incm.elems) (hkp : KDist s.proc.elems) :
    TerminatesBP pol s.su.drawn b a s

theorem budgetP_terminates_of_buildQueue {b : Nat} {a : Aux} {cs : List CsItem} {su : Sup}
    {q : PQueue} {su' : Sup} {fl : Flags} {ns : Names} {site : String} {tr : List String}
    {z : Nat} (hb0 : b ≠ 0) (hq : buildQueue cs su = .ok (q, su'))
    (hrs : fl.rowSoundBare = false)
    (hem : fl.emptyRow = false) (hdj : fl.disjRule = false) (hcse : fl.cseMints = false)
    (hw : Wf (initState q su' tr fl ns site z))
    (hok : SupOk su')
    (hfr : SupFresh su' (sys (initState q su' tr fl ns site z))) :
    TerminatesBP pol su'.drawn b a (initState q su' tr fl ns site z)
```

and `budgetP_never_accepts` is already covered: `runSP_never_accepts` (`PolicyStep` §5) says
whatever the budgeted driver accepts, `runP` accepts, at the same state, so budget exhaustion
can only turn an acceptance into a rejection.

### The recovery witnesses (no silent weakening)

```lean
theorem reachesP_shipped {a b : Aux} {s t : State} (h : ReachesP .shipped a s b t) : Reaches s t
theorem reachesP_of_reaches (a : Aux) {s t : State} (h : Reaches s t) :
    ∃ b, ReachesP .shipped a s b t
theorem terminatesP_shipped (a : Aux) (s : State) : TerminatesP .shipped a s ↔ Terminates s

theorem terminatesP_of_drawsAtMost_recovers {k : Nat} (a : Aux) {s : State}
    … (h : ∀ t, Reaches s t → t.su.drawn ≤ s.su.drawn + k) : Terminates s

theorem vocFixedP_terminates_recovers {V : Finset Var} {L : Finset Label} (a : Aux) {s : State}
    … (hvf : VocFixed V s) : Terminates s

theorem stepP_quadrichotomy_recovers (aux : Aux) {s s' : State} (h : step s = .continue s') :
    (IsLearnStepP .shipped aux s ∧ s'.env = s.env ∧ ∀ p ∈ s.proc.elems, p ∈ s'.proc.elems) ∨
    (s'.env.binds.length = s.env.binds.length + 1) ∨
    (s'.env = s.env ∧ s'.proc = s.proc ∧ s'.incm.elems.length + 1 = s.incm.elems.length) ∨
    (IsConcStepP .shipped aux s s' ∧ s'.env = s.env)
```

`terminatesP_of_drawsAtMost_recovers` and `vocFixedP_terminates_recovers` take the ORIGINAL
`Reaches`/`VocFixed` hypotheses and produce the ORIGINAL `Terminates s`, so the extra binder
costs the caller nothing.

### THE ONE REAL DIFFERENCE, reported not hidden

`Budget.runBud` tests `d0 + b < s.su.drawn` unconditionally; `PolicyReplay.runSP` — the driver
the replay actually runs, and the one D1 Part B wired to `-Dermine.solveBudget` — tests
`b != 0 && d0 + b < s.su.drawn`, so **`b = 0` means the budget is OFF**.  `budgetP_terminates`
therefore carries `hb0 : b ≠ 0`, which `budget_terminates` does not need.  That is a property of
the driver, not of the policy: at `b = 0` no cap is being asked for, and `Budget.budget_terminates`
at `b = 0` is the degenerate "die at the first draw" statement.  It is stated, not silently
dropped, and it is the only hypothesis in this half that the original does not have.

### What termination under a policy still does NOT give

An a-priori FUEL number.  `TerminatesP`/`TerminatesBP` are the same existentials
`Order.Terminates`/`Budget.TerminatesB` are; converting a draw budget into a dequeue bound needs
a bound on dequeues per draw, which is `L5-TERMINATION.md` §R8.6b and is open for every order.
`vocFixedP_run` does give an explicit fuel, but only on the vocabulary-fixed fragment.

## 6j Reproduction

```
export PATH=$HOME/.elan/bin:$PATH
cd tracker/lean
lake build Rowpartition          # 866 jobs
lake env lean Audit.lean         # 4059 theorems / 0 non-standard axioms
lake env lean /home/dmitry/.claude/jobs/880c725d/tmp/D1T/PrintAxioms.lean    # 84 declarations
lake env lean /home/dmitry/.claude/jobs/880c725d/tmp/D1T2/PrintAxioms2.lean  # 54 declarations
```


## 7. Applied to the main tree (2026-09-06)

### 7a What was applied, and what was not

`git diff` of the worktree, three files, applied to `/home/dmitry/research/ermine/ermine-scala`
with `git apply` (clean, no fuzz), then verified byte for byte against the worktree's copies:

```
231  8  core/src/main/scala/com/clarifi/reporting/ermine/Constraints.scala
 16  1  core/src/main/scala/com/clarifi/reporting/ermine/RowTrace.scala
 33  7  core/src/test/scala/com/clarifi/reporting/ermine/loopmodel/TestLoopTrace.scala
```

Nothing else in the worktree was carried over: the Lean mirror was written directly in the main
tree (`Loop/PolicyReplay.lean` new; `Loop/Policy.lean`, `Loop/Replay.lean`, `Loop/Main.lean`,
`Rowpartition.lean` edited), and D1-T's `Loop/PolicyStep.lean` and `Loop/PolicyTerm.lean` were
written there too.  `tracker/lean/Rowpartition.lean` was re-read before every touch and is the
union of both agents' import lines — it was not overwritten by either.

**No commits.  Both flags DEFAULT OFF**: `ermine.dequeuePolicy` defaults to `shipped`, whose
`pop` is the original body verbatim, and `ermine.solveBudget` defaults to `0`, which is off.

### 7b The gates re-run in the MAIN tree after the diff landed

| gate | result |
|---|---|
| `sbt core/compile core/test:compile` | **`[success]`**, 17 pre-existing deprecation warnings, no new ones |
| `sbt core/test` | **914 total, 913 passed, 1 failed** — `com.clarifi.reporting.TestConstraints`, the same known failure the worktree's gate 1 and S2's baseline record, unmoved (333 s) |
| `TestLoopTrace`, flags OFF | **714 solves, 714 segments, 714 agree**, 3 of 3 properties; controls detect (id base +1: 53 of 714; `--flags=nongen`: 65 of 714) |
| `TestLoopTrace`, `-Dermine.dequeuePolicy=smallcanon` | **714 / 714 / 714**, 3 of 3; the test prints `flags forwarded to both sides: -Dermine.dequeuePolicy=smallcanon -> --policy=smallcanon --trace`; controls detect (46 of 714; 58 of 714) |
| `TestLoopTrace`, policy **and** `-Dermine.solveBudget=20000` | **714 / 714 / 714**, 3 of 3; forwarded as `--policy=smallcanon --budget=20000 --trace`; controls detect |

That third row is the one worth pausing on: the compiler under the policy and a budget, and the
model under the policy and the same budget read off the trace's own `sin` record, agree on every
record of every one of 714 solves — 19 seeds at 6 id bases plus 600 generated systems.

### 7c Cost: `perf-bench.sh batch`, OFF vs ON

The measurement of record, in the main tree, cold (interface-free, full inference), 5 reps per
run, OFF and ON **alternated twice** so that drift shows up as disagreement between rounds:

| | round 1 | round 2 |
|---|---|---|
| flags OFF | **13.63 s** (min 13.22, max 13.81, spread 0.59) | **13.68 s** (13.10 / 13.88 / 0.78) |
| `-Dermine.dequeuePolicy=smallcanon` | **13.42 s** (13.21 / 13.75 / 0.54) | **13.55 s** (13.33 / 13.78 / 0.45) |

ON is 0.17 s (1.2 %) faster at the median of medians, which is well inside a single run's own
spread: the honest reading is **no measurable difference**, the same reading the `gu05` load-time
triple gave — and NOT that the policy is faster.  The reviewer re-ran it on a quieter host (OFF
11.45 / 11.56 s, ON 11.34 / 11.57 s, `-n 3`) and reached the same conclusion, with the resolution
of the harness put at about 5 %: any claim below that, in either direction, is noise (U-12).  The O(n) `foldRight` in `popSmallCanon` is invisible on the 129-module closure
because the queues are small (the corpus's whole population is 68,940 dequeues over 2.3 M
solves); where it is not invisible is `GU05`, and there it replaces 47,317 draws with 306.

**The caveat, stated because the harness is the measurement of record and its guard was
overridden.**  `perf-bench.sh` refuses above a 1-minute load average of 1.5.  This machine's
floor is the user's own desktop (a browser at ~60 % of one core, a music player) and never fell
below 1.5 in the measurement window; worse, a batch run leaves the average at ~4.3 itself, so
every run after the first would refuse whatever the threshold.  `PERF_MAX_LOAD` was therefore
raised to 6.0 and each run recorded its own `load_before` (2.33, 1.56, 1.77, 1.85 — comparable
across the four).  Twelve cores, the JVM pinned to two, runs alternated: **the OFF/ON comparison
is sound; the absolute seconds are not comparable with numbers taken on a quiet machine** (S2
recorded 12.78 s on this host at a lower background load, and this stage's OFF rounds are 0.85 s
above that).

### 7d What is NOT done here

* **No commit.**  Everything above is uncommitted work in the main tree, alongside D1-T's two
  Lean modules and Part A's `93e9454`.
* **No default moved.**  Adoption of `smallcanon`, of a non-zero `solveBudget`, and of S2's
  `rowSound`, are the user's decisions and were not made here.
* **The a-priori fuel gap is still open**, for every order including the shipped one: a draw
  budget bounds DRAWS, and turning that into a bound on DEQUEUES needs a dequeues-per-draw bound
  (`L5-TERMINATION.md` §R8.6b).  The budget stops divergence-by-minting — the divergence eight
  L5 rounds actually found — and is not a wall-clock watchdog.
* **`.ei` text moves under the policy**, but far less than this section first said (FINDING 2 and
  §8a, restated after the review): with a deterministic loader, ONE interface differs
  (`GridExample`, two bindings, by a VACUOUS kind binder) and 6 are published only under the
  policy.  No published TYPE changes; every other residual is alpha-equivalent.
* **The policy must not ship without `-Dermine.rowSound`** (FINDING 3 / U-0): at the shipped
  `rowSound` default it stops refuting `MIN2` and `FALSE-ACCEPT-2`, and with `rowSound` on the
  loss is exactly zero.  That is the adoption condition this document did not have before the
  review.


## 8. POST-REVIEW CORRECTIONS (2026-09-06)

The D1 Part B + D1-T review (`tracker/loopmodel/D1B-REVIEW.md`, 763 lines) returned
**FIX-THEN-ADVANCE**: no defect in the Scala or the Lean, every number it re-ran reproduced (most
to the digit), and three things wrong in the EVIDENCE plus a list of smaller items.  This section
records what changed, old → new.  Findings are the review's `U-` numbers.

### 8a The three that mattered

| # | old | new |
|---|---|---|
| **U-0** | *(absent — this document did not measure it)* | **§2b FINDING 3**: at the shipped `rowSound` default the policy stops refuting `MIN2` and `FALSE-ACCEPT-2` (8 rejections in 20 → 0); with `-Dermine.rowSound=true` all seven `seeds/unsat/` witnesses are refuted 10/10 under BOTH orders.  Reproduced here on the compiler, all seven seeds × 10 bases × 2 orders × 2 `rowSound` settings.  **Adoption consequence stated: the policy must not ship without `rowSound`.** |
| **U-1** | *"the worktree swept twice at the flags OFF gives 181 of 181 identical, 0 differing.  The noise floor is ZERO, so anything the policy comparison shows is signal."* | that control was ONE repetition of a nondeterministic experiment — the sweep runs the shipped PARALLEL loader (`Session.scala:558-560`).  Re-measured with `-Dermine.loadInSeries=true`: the floor is zero **at the byte level**, twice at each setting (`52b0cefc554d` OFF, `546b42fde523` ON, 152 interfaces, `diff -rq` empty) |
| **U-2 / U-3** | *"the policy CHANGES the published signature of five modules … 176 of 181 identical, 5 differing"*, with three of them called *"same `exists[N]`, different residual row shapes"* | the residuals are **alpha-equivalent** — the same set under a renaming — and `einorm2.py` reported three of them as differences only because it sorted each constraint group BEFORE anonymising the binder names (U-3).  `einorm3.py` anonymises first: on the same snapshots 5 → **2**, and with the deterministic loader OFF vs ON is **1 of 152 files** (`GridExample`, `stackedBarChart` + `stackedAreaChart`), differing by ONE VACUOUS implicit kind binder.  *"different residual row shapes"* is withdrawn |

### 8b The two code changes the review asked for

**The budget footgun, made structural.**  The reviewer reproduced the thing T-13 only warned
about: `-Dermine.solveBudget=20000` at the SHIPPED order REJECTS a satisfiable `GU05` at base 0
after 56 s while accepting it at bases 1 and 2 — a well-typed program failing by id base.  A
`System.err` warning at class-initialisation time is easy to miss in an `sbt` or LSP session.

* **Old:** `solveBudget` was read from the property and APPLIED whatever the order; the warning
  said the two "are meant to be adopted together".
* **New:** `GenRules.dequeuePolicy` is declared first and `val solveBudget = if (dequeuePolicy ==
  "shipped") 0 else solveBudgetRequested` — the budget is **IGNORED** at the shipped order, and
  the warning says `is IGNORED … Set -Dermine.dequeuePolicy=smallcanon to enable the budget`.
  `RowTrace`'s `sin` record carries the EFFECTIVE budget, so a replay applies the cap the run
  applied.
* **Mirrored in the model**, so the differential stays exact by construction and not by luck:
  `Loop/Policy.lean` gains `effBudget pol b := if pol == .shipped then 0 else b` (with
  `effBudget_shipped` and `effBudget_of_ne_shipped`), used by `polCensus` and by
  `PolicyReplay.solveSeedP`.  It is deliberately a DRIVER rule and not a change to
  `stepPB`/`runSP`: `budgetP_terminates`, `runSP_never_accepts` and `runSP_rejects_unsat` keep
  their statements exactly, and the drivers simply choose which `b` to hand them.
* **Gate** (`tmp/D1/post-review-gates.sh` §3): `incomplete/gu05` at `-Dermine.solveBudget=20`
  under `shipped` — the module **LOADS**, `limit-hits=0`, exactly one `is IGNORED` warning, and
  the replay agrees on **54,235 of 54,235** segments with `rejected=0`.  Under `smallcanon` the
  same budget still fires: `limit-hits=1`, module rejected at `gu05…e:62:1`, **54,235 of 54,235**
  agree with `rejected=1`.  Budget 0 under the policy: imported, 54,235 agree, `rejected=0`.

**U-6, the flags in the configuration fingerprint.**

* **Old:** `GenRules.toString` carried S2's tokens and nothing about D1's flags.
* **New:** `+pol:<name>` when the order is non-shipped and `+budget:<n>` when the EFFECTIVE budget
  is active, in the same `+…` form S2 used.  Measured at four settings:

  | setting | `genRules=` |
  |---|---|
  | defaults | `cut+label-early+resguard+splitkey+splitrow+resrow` — **byte-identical to S2's** |
  | `-Dermine.dequeuePolicy=smallcanon` | `…+resrow+pol:smallcanon` |
  | policy + `-Dermine.solveBudget=20000` | `…+pol:smallcanon+budget:20000` |
  | `-Dermine.solveBudget=20000` alone | unchanged from the defaults, plus the `is IGNORED` warning |

  **What this does NOT do, stated because U-6 is about a real gap:** nothing in the tree keys a
  published `.ei` by this string (its only consumer is `DisjProbe`), so a tree built partly with
  the policy on still mixes interfaces silently.  That is safe today — the interfaces the policy
  moves are alpha-variants and a mixed tree loads in both directions (`rc=0`, the reviewer's gate
  16) — and it is recorded here as the thing to fix before any INCREMENTAL adoption.

### 8c The smaller items

| # | old | new |
|---|---|---|
| **U-4** | `PERF-ROADMAP.md` P10 ticked `[x]` | un-ticked.  P10 is **answered, not closed**: the change is uncommitted, default OFF and unadopted, and the note says so |
| **U-5** | *"`#print axioms` over all 84 new declarations"* — the census file had 83 and omitted `QOk.shape` | re-run over every declaration in the four new modules **plus** the three new `effBudget` declarations: **161 declarations, 0 non-standard axioms** (5 × `[propext]`, 153 × `[propext, Classical.choice, Quot.sound]`, 1 × `[propext, Quot.sound]`, 2 with no axioms).  `QOk.shape` is in the list and is clean (`[propext]`).  `tmp/D1/PrintAxiomsD1B.lean`, `axioms-D1B.out` |
| **U-7** | *"flags OFF … the shipped path byte-identical"*, and brief B2's "byte-identical row trace" | the `sin` record gains its two columns UNCONDITIONALLY, so a flags-OFF trace ends `…\tshipped\t0\t<thread>` and is **not** byte-identical to a pre-D1 trace.  What IS byte-identical is the loop: `popShipped` is `Q.pop`'s body verbatim (the reviewer extracted both by brace matching and compared token for token), and the gate that matters — model against compiler, record for record — is 2,355,430 of 2,355,430.  Old traces still parse (`Loop/Replay.lean` reads `sin` positionally with a trailing wildcard) |
| **U-8** | `tmp/D1/bindcmp.sh` compared `looptrace --verdict`'s whole last line, which BEGINS with the policy name, so the two sides differed by construction and it printed `SAME` only when both produced no output; it was never run | fixed to compare the **verdict FIELD** (`steps` and `drawn` are expected to differ between orders; the verdict is what must not move) and RUN, over the 19 tracked seeds and the 7 unsat witnesses at ten id bases: **260 pairs, 242 SAME, 18 DIFF — and all 18 are `REJECTED → SOLVED`**: `MIN2` ×8, `FALSE-ACCEPT-2` ×8 (the same eight bases the compiler flips at, which is what makes U-0 a property of the ORDER), `PANIC-1` ×2 (where the compiler's rejection is `Subst.reduce`'s pre-existing panic, outside the modelled loop).  **This is the gate that would have caught U-0 before the review did.**  The two `slow/` seeds are excluded from the tally: the MODEL needs far longer on them than the compiler (`GU05` base 0 does not finish in 120 s under either order in the model, while the compiler does 306 draws in about a second), so a verdict comparison there measures the cap, not the order |
| **U-9** | `lblKey` read UTF-16 code UNITS in Scala (`Char.toInt`) and code POINTS in Lean (`Char.toNat`) | the Scala side now reads code POINTS (`GenRules.codePoints`, `String.codePoints`), so the two agree for every string and not merely below U+10000.  No name in this corpus is affected; `TestLoopTrace` 714/714 and the `boot`+`top` differential are unchanged after the edit |
| **U-10** | `val drawRecords` sat between `withSite`'s scaladoc and `withSite` | moved: `withSite` has its doc comment back and `drawRecords` carries only its own |
| **U-11** | §1a/§1b said `withLoopDraws` wraps "the only two callers of `incorporateAll`" | true, and one of them is dead: **`Constraints.combine` has no callers in the main sources**, so `PQueue.expand` (from `Subst.scala:1302`) is the single live loop entry.  Wrapping `combine` is harmless insurance |
| **U-12** | wall clocks quoted as figures of record (`128,354 / 1,399 / 1,304 ms`) | **DRAWS are the reproducible measure and are what this document now leads with**; the reviewer's independent run gave `137,645 / 314 / 199 ms` for the same three bases with the draw counts identical to the digit (47,317 / 1,091 / 743), and ~217 ms median under the policy against this document's "~1.0 s".  Wall clocks are quoted as ranges |
| T-9(b) | *"the diagnostic … distinguishes a resource limit from a verdict"* — recorded as done | **PARTIAL, as the reviewer says**: the WORDING does, the SEVERITY does not — it is still a `Death` and renders at error severity, so an IDE files it beside real type errors |
| T-14.5 | not recorded | `replayPolicyOne` skips the early label check, but the DIFFERENTIAL goes through `replayP` → `solveSeedP`, which runs it; the caveat applies only to the `--policy=` census |

### 8d What was re-run after the code changes

| gate | result |
|---|---|
| `lake build Rowpartition` (`LEAN_NUM_THREADS=2`) | **867 jobs, success** |
| `Audit.lean` | **4,115 theorems / 0 non-standard axioms** (4,112 before the two `effBudget` lemmas) |
| `lake build looptrace` | **1,670 jobs, success** |
| `#print axioms`, 161 declarations | **0 non-standard** |
| `sbt core/compile core/test:compile` | `[success]`, no new warnings |
| `TestLoopTrace`, three settings | **714 / 714 / 714, 3 of 3 each**; controls detect (53 / 65 OFF, 46 / 58 ON) |
| L2 differential, `boot`+`top`, flags OFF | **146,872 of 146,872 agree**, 0 skip |
| L2 differential, `boot`+`top`, under the policy | **146,872 of 146,872 agree**, 0 skip |
| `incomplete/gu05` budget matrix (policy × 0/20, shipped × 20) | as §8b: fires under the policy, IGNORED at the shipped order, model agrees in all three |
| the configuration fingerprint at four settings | as §8b: **unchanged at the defaults** |
| `.ei`, deterministic loader, four sweeps | floor byte-identical twice at each setting; OFF vs ON 1 of 152 |
| **`.ei` at the flags OFF, BEFORE vs AFTER the post-review code changes** | **byte-identical**: the reviewer's own pre-change deterministic sweep and mine give the same md5 over all 152 interfaces (`52b0cefc554d1c21035a9411e21ce19f`), `diff -rq` empty — the code changes are invisible at the defaults, which is the gate the coordinator asked for |

**Still uncommitted, both flags still DEFAULT OFF.**

