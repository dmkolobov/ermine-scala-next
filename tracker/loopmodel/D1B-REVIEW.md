# D1 Part B + D1-T — review

Reviewer: independent agent, 2026-09-06.  Base `93e9454` (`scala3-migration`) + the uncommitted
D1-B / D1-T files.  Findings prefixed `U-`.  Scratch:
`/home/dmitry/.claude/jobs/880c725d/tmp/review-D1B/`.  Nothing in the tree was edited by this
review except this file.

## VERDICT: **FIX-THEN-ADVANCE**

Every number in `D1-CHANGE.md` §2/§3 that I re-ran reproduced — most of them to the digit — and
the transport is a faithful copy with the originals recovered in the kernel.  I found no defect
in the Scala or in the Lean.  Three things must be fixed in the EVIDENCE before this is put to
the user as an adoption decision: the `.ei` control that FINDING 2 rests on is broken (`U-1`);
the five signatures are mischaracterised — they are alpha-variants, not different types (`U-2`,
`U-3`); and the one behavioural change that actually matters is missing from the report
altogether (`U-0`: at the shipped `rowSound` default the policy stops refuting `MIN2` and
`FALSE-ACCEPT-2`).  All three are documentation and measurement; none is code.  Reasoning and
the two adoption recommendations are in §8.

## THE CENTRAL QUESTION — the five signatures that change text

### Answer in one paragraph, for a non-specialist

**None of the five is a different type, and at least one of them is not even a policy effect.**
All five publish residual constraint sets that are **alpha-equivalent** — identical once the
existentially bound row variables are renamed — which I checked mechanically rather than by eye
(`tmp/review-D1B/alpha2.py`: a backtracking isomorphism search over the constraint sets, with the
`forall`-bound variables and every qualified name held fixed, and `x <- (a, b, c)` treated as the
unordered set it is in `Constraints.RHS`).  For three of the five
(`incomplete/TargetList.restrictTo`, `incomplete/RunCalibration.valueAsOf`,
`Relation.lookbackJoin`) the `forall` prefix and the body after `=>` are **textually identical**
and only the existential names move: they are the SAME TYPE, full stop.  The other two
(`ChartsExample.stackedPair`, `GridExample.stackedBarChart`) also have alpha-equivalent residuals
and identical bodies; they differ in exactly **one implicit KIND binder** — `sa` publishes as
`(sa : c)` with `c` added to the `{…}` group in one run and as a bare `sa` in the other, and a
bare binder means kind `*` (`Pretty.ppTypeVarBinder`, `Pretty.scala:259-266`: `case Star(_) => d`).
Both bodies contain `s sr sa` with `s : rho -> * -> *`, which pins that kind to `*` either way, so
the extra quantifier is **vacuous**.  And the report's calibration is wrong: I re-ran the
flags-OFF configuration **ten times** with the identical command line and `einorm2.py` reports
**1 of 152 interfaces DIFFERING on every one of the nine comparisons** — and the one is
`Relation.lookbackJoin`, i.e. one of the five, with exactly the shape the report attributes to
the policy.  The claimed "ZERO noise floor" came from a single repetition of a **nondeterministic
experiment**: the `.ei` sweep runs the shipped PARALLEL module loader, and `Session.scala:558-560`
says so in its own comment — *"parallel makes give thread-timing-dependent Supply order, which
reaches interface bytes through the constraint solver's id-hash queue"*.  Eight of my ten
same-configuration runs produced a different md5 over the interface set.

**What IS a real policy effect, measured with the loader made deterministic.**  Re-run with
`-Dermine.loadInSeries=true`, the noise floor really is zero (OFF twice: 152 of 152 identical; ON
twice: 152 of 152 identical) and OFF vs ON gives **150 of 152 identical, 2 differing**:
`GridExample` (both `stackedBarChart` AND `stackedAreaChart` — a binding the report's parallel
sweep did not flag) and `Relation.lookbackJoin`.  Every one of those residuals is alpha-equivalent
too; the Grid differences are again the single vacuous kind binder.  So the policy does move
published text, but only in these two ways — existential renaming, and one vacuous kind
quantifier — and the honest description is **(a) the same type up to renaming**, not (b).

**Where the residue comes from, since the Lean forbids (b).**  `runP_ssat_iff`, `runP_noLoss` and
`runP_models` say the derived SYSTEM is equivalent, and it is — the residuals are isomorphic.
What is left is downstream of the loop and unmodelled: the existential NAMES come from
`Subst.reduce`'s generalisation over a set whose iteration order is an id order, and the kind
binder from whether a kind meta-variable is still a variable at generalisation.  Neither is the
row solver deriving a different set.

**The six interfaces published only under the policy are real, and are the point of the stage.**
`incomplete/Gu05` does not finish inside its ten-file chunk's 900 s cap under the shipped order,
so `Gu06`/`Gu08`/`Gu10`/`Np01` are never reached; under the policy `Gu05` takes ~2 s.  (The sixth
is `.probeC.ei`, which the report's table does not name.)

### The evidence, run by run

| experiment | loader | runs | result |
|---|---|---|---|
| `einorm2` A(worktree OFF) vs B(main), the implementer's own snapshots | parallel | 1 | 181/181 identical — **reproduced** |
| `einorm2` A vs A2, same configuration (the "zero noise floor" control) | parallel | 1 | 181/181 identical — **reproduced**, but see the next row |
| `einorm2` OFF vs policy ON, the implementer's snapshots | parallel | 1 | 176/181, 5 differing, 6 only-ON — **reproduced exactly** |
| raw BYTE compare, A vs A2 (same configuration) | parallel | 1 | **180/181; `Relation_Predicate.ei` differs** |
| **my control: flags OFF, identical command, chunks 0-1** | parallel | **10** | 8 distinct md5s; 5 of 152 files byte-unstable; **`einorm2` 151/152, 1 DIFFERING (`Relation.lookbackJoin`) in all 9 comparisons** |
| **my control: flags OFF** | **series** | 2 | **152/152 identical, 0 differing** |
| **my control: policy ON** | **series** | 2 | **152/152 identical, 0 differing** |
| **OFF vs ON** | **series** | 1 each | **150/152, 2 differing**: `GridExample` (`stackedBarChart`, `stackedAreaChart`), `Relation.lookbackJoin` |
| alpha-equivalence of every differing residual | — | — | **ALPHA-EQUIVALENT in all cases** (`alpha2.py`) |
| `ChartsExample`+`GridExample` compiled ALONE, OFF vs ON | either | 1 each | **identical signatures** — the wobble needs the batch context |

## 1. Rebuild, re-audit, re-test — my own runs

| step | command | result | claim | verdict |
|---|---|---|---|---|
| build | `LEAN_NUM_THREADS=2 lake build Rowpartition` | **867 jobs, success** | 867 | MATCH |
| audit | `lake env lean Audit.lean` | **4,112 theorems / 0 non-standard axioms** | 4,112 / 0 | MATCH |
| looptrace | `lake build looptrace` | **1,670 jobs, success** | 1,670 | MATCH |
| grep | `sorry|admit|native_decide|unsafe|opaque|partial|axiom|implemented_by|#exit|Classical` over the four new modules | **0 hits** | none | MATCH |
| line counts | `wc -l` on the four new modules | 267 / 161 / 2,373 / 1,127 | same | MATCH |
| `git diff --stat` on `tracker/lean` | | `README.md`, `Rowpartition.lean`, `Loop/{Main,Policy,Replay}.lean` only | same | MATCH |

`Rowpartition/CutSearch.lean` is still out of the root import list; the four new imports are
appended to the `Loop` block.

**Did any pre-existing theorem's STATEMENT change?**  No.  `Loop/Policy.lean` is the only
pre-existing module with a semantic edit and it is a DEFINITION change, not a statement change:
`canonKey` now orders a right-hand side's concrete part by the label's `Name`
(`lblKey`, new, plus `sortLblKeys`) instead of by `Lbl.n`, the trace's `slbl` index — which is the
Part-A defect §1e reports, and it is a real one (a key built from a trace table is not
implementable in the compiler).  `Main.lean` and `Replay.lean` are drivers.  `shape_length_eq` is
NOT in `Policy.lean`; it is the first theorem of the new `PolicyTerm.lean`, as §6k says.

## 2. The transport — my own anti-weakening check

I did not reuse `tmp/D1T/gen.py`.  `tmp/review-D1B/stmtdiff.py` re-derives each transported
statement from the ORIGINAL by applying exactly the two substitutions
(`step s → stepP pol aux s`, `s.incm.dequeue → dequeuePol pol aux s.incm`, plus the six
predicates renamed to their policy forms) and compares signatures with the transported file:

**49 declarations compared, 0 real weakenings.**  The two the script flagged are its own
artefacts: `IsConcStepP` (restated by hand with explicit `(pol) (aux)` binders — I read both and
the bodies are identical modulo the dequeue call) and `step_kdist'` (my regex does not survive the
trailing apostrophe; read by hand, it is the two substitutions and nothing else).

Every Lean statement quoted in `D1-CHANGE.md` is verbatim: `tmp/review-D1B/verbatim.py` extracts
all 77 `theorem`/`def` declarations from the document's ```lean blocks and finds **77 of 77**
present character for character in the sources (9 are quoted with an explicit `…` elision and were
checked up to it).

## 3. The Scala change, read line by line

### 3a Flags OFF is a no-op — checked, not assumed

* **`popShipped` is `Q.pop`'s body verbatim.**  Machine-checked, not eyeballed: I extracted both
  bodies by brace matching from `93e9454` and from the working tree and compared them token for
  token — **equal** (`tmp/review-D1B/`, the `popShipped` check).  The only change to the
  signature is dropping the now-unused `graph` parameter.
* Every new branch is dead at the defaults: `pop` dispatches on
  `GenRules.dequeuePolicy == "shipped"`; `incorporateAll`'s budget test short-circuits on
  `solveBudget > 0`; `countDraw()` and `withLoopDraws` short-circuit on `drawCountActive`, which
  is `solveBudget > 0 || RowTrace.enabled` and therefore `false` in a normal compile.
* **`GenRules.toString` is unchanged.**  Its only consumer in the tree is
  `core/src/test/.../DisjProbe.scala:170`, a debug probe — it is **not** an `.ei` fingerprint, and
  no `.ei` cache key records either flag.  See `U-6`.
* `RowTrace`'s `sin` record gains its two columns UNCONDITIONALLY, so a flags-OFF trace is not
  byte-identical to a `93e9454` trace (it ends `…\tshipped\t0\t<thread>`).  That is fine — the
  gate that matters is model/compiler agreement, and `Loop/Replay.lean` parses positionally with a
  trailing wildcard so old traces still parse — but B2's wording ("byte-identical row trace") is
  not literally met and the report does not say so.  `U-7`.
* One real cost at the defaults: `TypeVarGraph` is a case class allocated on essentially every
  insert, and it now carries a `lazy val canonSort` — an extra reference field plus Scala 3's
  lazy-val bitmap — that is never forced when the policy is off.  Not measurable at this scale,
  but it is not literally "the loop pays nothing".

### 3b `smallcanon`, against the model

| | `Loop/Policy.lean` | `Constraints.scala` | agree |
|---|---|---|---|
| arity | `preKey .smallRhs` = `abstr.size + (conc.isEmpty ? 0 : 1)` | `arityOf` — same | YES |
| priority | `(alGet a.pr lhs).getD 0`, `a.pr = canonPrio` = `reverseTopSort` over id-sorted nodes and id-sorted children | `graph.canonSort.getOrElse(lhs, 0)`, same construction | YES |
| key | `sortNats abstr ++ [sep] ++ (sortLblKeys (conc.map lblKey)).flatten ++ [sep, lhs]` | identical | YES |
| `lblKey` | `(glob ? 2 : 1) :: mod ++ [sep] ++ str ++ [sep, con]` | identical (`Global` → `(2, module)`, else `(1, "")`) | YES |
| comparison | `natListLt`, shorter-is-smaller at a common prefix | `intListLt`, written out | YES |
| argmin | `foldl`, FIRST wins on a tie | `foldLeft`, first wins | YES |

`canonSort` **is** a valid reverse-topological order of the same graph the shipped order uses:
`StreamTUtils.reverseTopSort` is a DFS post-order and produces one for any enumeration order of
the vertices and children; only the tie-breaking within it changes.  The `lazy val` **cannot go
stale**: `TypeVarGraph` is an immutable `case class` and `+`/`rename` return new instances, so a
changed graph is a different object with its own unforced `canonSort`.  (Cost: it is recomputed at
most once per dequeue, since a new graph object is made on every insert that reaches `sandwich`.)

`lblKey` is injective on `Name` up to `Name.equals`: `Local.equals` is `(string, fixity.con)` and
`Global.equals` is `(module, string, fixity.con)` (`Name.scala:19-24,33-39`), and the flattened
concatenation is unambiguous because `canonSep = 10^9` exceeds every code point and every
`Fixity.con`.  So the doc-comment claim that the order is total holds.  One nit: the model reads
`Char.toNat` (code POINTS) and the Scala `Char.toInt` (UTF-16 code UNITS); they differ only above
the BMP, which no module or label name in this corpus reaches.  `U-9`.

### 3c `removeOne` — can it drop the wrong element?  **No.**

This was the sharpest question in the brief, because `Partition.equals` ignores the `inf` tag
(`Constraints.scala:1370-1373`: `case Partition(u, r, _) => _1 == u && _2 == r`) and
`removeOne` drops *the first element of the key block that is `==` to `p`*.

**The queue can never hold two `==` partitions.**  `Q.insert` (`:525-552`) is the ONLY way a
`Partition` enters a `PSQI` — `heapify`, `filter`, `partition`, `pop` and `removeOne` only ever
re-fold or drop, `PQueue.empty` is empty, and `PQueue.build`/`+`/`+!`/`++`/`++!` all go through
`insert` — and `insert`'s guard `if (leq any (p == _)) (q, graph)` refuses a duplicate.  `leq` is
exactly the block with the same `(rhs.hashCode, lhs.hashCode)`, and `Partition.hashCode` is
`(_1, _2).hashCode`, so any `==` copy is necessarily inside `leq`.  Hence at most one candidate
and `removeOne` is unambiguous.  It also cannot fail to remove anything (`best` comes from a fold
over `q`, so it is in its own key block), which would otherwise loop forever.

The tree's `(rhs.hashCode, lhs.hashCode)` order and the `PSQK` measure are untouched (T-2
honoured): `removeOne` splits at the chosen partition's own key block with `part`, whose key
`_._1.map(_._2)` is the pair, and rejoins `less <++> kept <++> greater`, preserving every
survivor's position — which is what the model's `elems.eraseIdx i` does, and what makes the
2.3 M-segment differential meaningful.

### 3d The budget

* **Where it is counted.**  The two loop mint sites only — `splitConcrete`'s `fresh`
  (`:1659-1662`) and `resolution`'s (`:2108-2110`).  `PQueue.build`'s mint is a third site and is
  not wrapped, so it is excluded by construction (T-10's mechanism, correctly chosen).
* **Where it is checked.**  Once per dequeue at the top of `incorporateAll`, BEFORE the dequeue —
  which is exactly `PolicyReplay.runSP`'s `if b != 0 && d0 + b < s.su.drawn`.  The compiler tests
  `drawnThisSolve > solveBudget` where `drawnThisSolve` is reset to 0 at loop entry, so
  `drawnThisSolve = drawn - d0` and the two tests are the same test.  `solveSeedP` passes
  `d0 := su1.drawn`, the draw count at loop entry.  **The two sides stop on the same dequeue.**
* **T-1 is fixed, and fixed at the right place.**  `withLoopDraws` wraps `PQueue.expand`
  (`:764-772`) and `Constraints.combine` (`:1409-1414`).  These are the only two callers of
  `incorporateAll` other than its own tail recursion — and in fact `Constraints.combine` has **no
  callers at all** in the main sources, so `expand` (reached only from `Subst.scala:1302`,
  `var ps = q.expand.toList`) is the single live loop entry.  Save/restore is `try … finally`, so
  a nested solve restores its parent's count even on a `Death`.  `ThreadLocal`, as T-1 asked.
* `runSP` carries `b != 0` in its guard and `budgetP_terminates` therefore carries
  `hb0 : b ≠ 0`.  **That hypothesis is honest**: at `b = 0` the compiler's `solveBudget > 0` is
  also false, i.e. no cap is being asked for, and the theorem would otherwise be the degenerate
  "die at the first draw".  `runSP_never_accepts` is the right shape for "the budget never
  accepts" — a `.solved` under the budget is a `.solved` without it — and `runSP_outOfFuel`
  covers the fuel case; exhaustion returns `.rejected (budgetMsg …)`, never `.solved`.
* **T-13's warning is there** (`:1290-1297`), on `System.err`, when `solveBudget > 0 &&
  dequeuePolicy == "shipped"`.


## 4. The gates, re-run by me

Everything below is my own run, sequential, one JVM at a time, `-XX:ActiveProcessorCount=2`.
Driver `tmp/review-D1B/gates.sh`, log `tmp/review-D1B/gates.log`.

| # | gate | my result | reported | verdict |
|---|---|---|---|---|
| 0 | `#print axioms` over MY list of every declaration in the four new modules | **158 declarations, 0 non-standard**: 4 × `[propext]`, 153 × `[propext, Classical.choice, Quot.sound]`, 1 × `[propext, Quot.sound]` | 19 + 84 + 54 | MATCH (see `U-5`: the implementer's own census file has **83** entries for `PolicyStep`, not 84 — it omits `QOk.shape`, which is clean: `[propext]`) |
| 1 | `sbt core/test`, flags OFF | **Total 914, Failed 1, Errors 0, Passed 913**; the failure is `com.clarifi.reporting.TestConstraints` | 913/914, same test | MATCH |
| 2a | `TestLoopTrace`, flags OFF | **714 solves / 714 segments / 714 agree**, `hashdiff=0 eqdiff=0 skipped=0`, 3 of 3 properties; controls detect (base +1: **53** of 714; `nongen`: **65**) | same | MATCH |
| 2b | `TestLoopTrace`, `-Dermine.dequeuePolicy=smallcanon` | **714 / 714 / 714**, 3 of 3; prints `flags forwarded to both sides: -Dermine.dequeuePolicy=smallcanon -> --policy=smallcanon --trace`; controls detect (**46**, **58**) | same | MATCH — the `setD1` child-JVM fix is present and working |
| 2c | `TestLoopTrace`, policy + `-Dermine.solveBudget=20000` | **714 / 714 / 714**, 3 of 3; forwarded as `--policy=smallcanon --budget=20000 --trace`; controls detect | same | MATCH |
| 3 | `GU05` on the COMPILER, policy, bases 0–9 | **SOLVED at all 10, `drawn` = 306 at every base** (min=median=max=306); 144–861 ms | 306 at all 25 | MATCH |
| 4 | `GU05` on the COMPILER, SHIPPED control, bases 0–2 | **47,317 / 1,091 / 743 draws** — 137,645 ms / 314 ms / 199 ms | 47,317 / 1,091 / 743; 128,354 / 1,399 / 1,304 ms | draws MATCH exactly; wall clock differs (see `U-12`) |
| 5 | `GU05MIN` on the COMPILER, policy, bases 0–4 | **SOLVED at all 5, 256 draws at every base** | 256 at all 25 | MATCH |
| 6 | S2 environment-fact gate (`run.sh env`), OFF and ON | **9 cases, differ = 4 — both ways** | `cases=9 differ=4` both | MATCH |
| 7 | `repl-smoke` | **PASS** — aliasing 2, relations 6, scoping 4, smoke 23 | same | MATCH |
| 7 | `lsp-smoke` | **PASS** — lsp 98 checks | same | MATCH |


### 4b The gates that need the corpus

| # | gate | my result | reported | verdict |
|---|---|---|---|---|
| 8 | L2 corpus differential UNDER the policy, all eight groups | `boot` 54,199 / `top` 92,673 / `Ai` 83,942 / `shouldfail` 56,032 / `bugs` 54,235 / `guide` 54,244 / `shouldfail-controls` 54,739 / `incomplete` 1,905,366 — **2,355,430 segments, 2,355,430 AGREE, 0 skip, `hashdiff=0 eqdiff=0`**, every group `timeouts=0 dropped=0 threads=1` | identical, group for group | MATCH |
| 9 | corpus at `-Dermine.solveBudget=20000` under the policy (`bugs`, `guide`) | 54,235 / 54,235 and 54,244 / 54,244 agree, **`rejected=0`** — the budget is inert | same | MATCH |
| 10 | a budget that FIRES: `incomplete/gu05` at `-Dermine.solveBudget=20` | budget 0: `Importing module 'Incomplete.Gu05' (0.46 seconds)`, 54,235 agree, `rejected=0`.  budget 20: the module is REJECTED at `…gu05…e:62:1`, 54,235 agree, **`rejected=1`** — the model agrees on the firing dequeue | same | MATCH |
| 11 | per-solve draw equality on `boot` under the policy (`-Dermine.rowTrace.draws=true`) | **54,199 `sdraw` records, 54,199 `sin`, model 54,199, compiler 54,199, IDENTICAL** | same | MATCH |

**The diagnostic, exactly as a user sees it** (my run, `tmp/review-D1B/logs/bud20.out`):

```
core/examples/incomplete/gu05_star_join_4dim_concrete_signature.e:62:1: Row solver resource
limit reached (this is NOT a type error): the row constraint solver drew 21 fresh row variables
at this signature, past the -Dermine.solveBudget=20 limit, so it was stopped rather than left to
run.  Raise the limit with -Dermine.solveBudget=<n>, simplify the row constraints at this
signature, or report it.
```

T-9(a) — "say what to do" — is fully addressed.  T-9(b) — "a distinct prefix or SEVERITY" — is
addressed in the prefix only: it is still emitted through `Death`, so it renders at error
severity and an IDE's problem list will file it beside real type errors.  That is a reasonable
place to stop, but it is a partial fix and the report calls T-9 done.


### 4c The remaining gates

| # | gate | my result | reported | verdict |
|---|---|---|---|---|
| 14 | `perf-bench.sh batch -n 3`, OFF vs ON, alternated twice, `PERF_MAX_LOAD=6.0` | OFF **11.45 / 11.56 s** cold median; ON **11.34 / 11.57 s**.  Median of medians OFF 11.50, ON 11.46 — a 0.04 s (0.35 %) difference inside every run's own spread (0.17–0.44 s).  **No measurable cost** | OFF 13.63/13.68, ON 13.42/13.55, "no measurable difference" | same CONCLUSION, different absolute seconds (`U-12`) |
| 15 | CONTROL: a policy-ON trace replayed at the SHIPPED order | model forced to `--policy=shipped`: **54,073 of 54,199 agree — 126 segments DISAGREE**.  The same trace with the policy taken off its own `sin` record: **54,199 of 54,199 agree** | the 419/714 failure mode `setD1` fixed | **the control DOES detect**, on corpus data |
| 16 | ADOPTION: `.ei` written under one policy, read under the other | chunk 0 written OFF then chunk 1 compiled ON: **rc=0**, no new errors; and the reverse: **rc=0**, no new errors.  (The three "error" lines in each log are the pre-existing `guide/HelloWorld.e:43:6` parse error and two module-list lines containing the word "Error".) | not run | **PASS** — a mixed-policy tree loads |

**On the `PERF_MAX_LOAD` override.**  The comparison IS still meaningful, at the resolution the
harness has: the runs were alternated on one host inside one window, each recorded its own
`load_before`, and the OFF/ON medians land on top of each other in both rounds.  What it cannot
support is the report's "ON is 1.2 % FASTER": on my host the load fell from 2.64 to 0.52 across
the window and the per-run spread is 1.5–4 %, so any claim below ~5 % is noise in either
direction.  The honest statement — which the report does also make — is that the O(n) scan costs
nothing measurable on this corpus.  Note that on my window the host was quiet enough that only
the FIRST run needed the override, so "this host's floor never fell below 1.5" is not a stable
property of the machine.


### 4d Measurements the report does not have

**What one budgeted solve costs at worst, in seconds** (T-13 asked; the report does not answer).
`GU05.json` at base 0, SHIPPED order, `-Dermine.solveBudget=20000`:

```
ermine: WARNING -Dermine.solveBudget=20000 is set but -Dermine.dequeuePolicy is 'shipped'. …
base=0: REJECTED in 56140 ms  drawn=20002
```

**56 seconds, per solve** — and the overshoot is 2 draws past the limit, inside
`Draws.learnPartitions_drawn`'s `1 + proc.size`.  Unbudgeted the same solve takes 137,645 ms and
47,317 draws, so the cap does cut it roughly in half.

**And the footgun is not hypothetical.**  That run is a REJECTION of a SATISFIABLE input that the
compiler accepts at bases 1 and 2 (743 and 1,091 draws) and accepts at base 0 too if left alone.
So `-Dermine.solveBudget=20000` **alone**, at the shipped order, turns `GU05` from
"slow but correct at every base" into "correct at some id bases and a hard error at others."
T-13 predicted exactly this and the warning names it; I am recording that it REPRODUCES, because
it is the single strongest argument for the two flags being adopt-together.  Under the policy the
same budget is inert (306 draws at every base) and a budget of 200 trips cleanly at 202.

**Does the policy make the published interface deterministic?  No.**  Five repetitions of the
identical two-chunk sweep at `-Dermine.dequeuePolicy=smallcanon` under the shipped parallel
loader give **five distinct md5s**, the same five files are byte-unstable as at the defaults, and
`einorm2` reports 1 of 152 DIFFERING in 2 of the 4 comparisons.  The residual nondeterminism is
`Subst.reduce`'s `Set` iteration order over a thread-dependent id base, and the dequeue policy
does not touch it.

| configuration | loader | reps | `einorm2` residue | byte-unstable files |
|---|---|---|---|---|
| flags OFF | parallel (shipped default) | 10 | **1 of 152, in 9 of 9 comparisons** | 5 of 152 |
| policy ON | parallel | 5 | **1 of 152, in 2 of 4 comparisons** | 5 of 152 |
| flags OFF | `loadInSeries=true` | 2 | **0 of 152** | 0 |
| policy ON | `loadInSeries=true` | 2 | **0 of 152** | 0 |
| OFF vs ON | `loadInSeries=true` | 1 each | **2 of 152** (`GridExample` ×2 bindings, `Relation.lookbackJoin`) | — |


### 4e The comparison the implementer's own script could not make: SUBSTITUTIONS

`tmp/D1/bindcmp.sh` compares a line that begins with the policy name, so it differs by
construction (`U-8`); it was never run.  I compared the COMPILER's published substitution
instead — `run.sh sweep <seed> 0 9`, whose `SOLVED` line prints `v0 := …; v1 := …` and the
residual — over all 28 tracked seeds (`seeds/*.json`, `seeds/unsat/*`, `seeds/slow/*`) at ten id
bases, shipped against `smallcanon`, at the shipped `rowSound` default (OFF).
Driver `tmp/review-D1B/post2.sh`, output `tmp/review-D1B/subst/`.

**22 of 28 seeds: the substitution is IDENTICAL at all ten bases.**  The six that differ:

| seed | what differs |
|---|---|
| `GU05` | base 0 HANGs at the 60 s cap under `shipped` and SOLVES under the policy — the stage's whole point.  Bases 1–9 are identical |
| `NE6` | 9 of 10 bases: the SAME bindings printed with a `Set`'s members in a different order (`Set(l2, l3, l4, l1)` vs `Set(l1, l4, l2, l3)`) — print order, not content |
| `H2` | base 9 only: `v2 := unbound` under `shipped`, `v2 := 14` (an alias to a fresh mint) under the policy; the residual is `residual=3` in both |
| `PANIC-1` | bases 5, 6: REJECTED under both, with a different internal message (`Infinite row partition` vs the pre-existing `panic: reinstantiated type`) |
| **`MIN2`** | **8 of 10 bases: REJECTED under `shipped`, SOLVED under the policy** |
| **`FALSE-ACCEPT-2`** | **8 of 10 bases: REJECTED under `shipped`, SOLVED under the policy** |

The last two are the finding of this review that the report does not have; it is `U-0` below.


### 4f Does S2's `-Dermine.rowSound` put the refutation back?  YES, completely.

The seven witnesses of `seeds/unsat/`, on the COMPILER, bases 0–9, two orders × two `rowSound`
settings (`tmp/review-D1B/post3.sh`).  `SOLVED` on an unsatisfiable input is a FALSE ACCEPTANCE.

| seed | `shipped`, rowSound OFF | `smallcanon`, rowSound OFF | `shipped`, rowSound ON | `smallcanon`, rowSound ON |
|---|---|---|---|---|
| `MIN1` | SOLVED 10/10 | SOLVED 10/10 | **REJECTED 10/10** | **REJECTED 10/10** |
| `FALSE-ACCEPT-1` | SOLVED 10/10 | SOLVED 10/10 | **REJECTED 10/10** | **REJECTED 10/10** |
| `MIN2` | SOLVED **2**/10 | SOLVED **10**/10 | **REJECTED 10/10** | **REJECTED 10/10** |
| `FALSE-ACCEPT-2` | SOLVED **2**/10 | SOLVED **10**/10 | **REJECTED 10/10** | **REJECTED 10/10** |
| `SURV1` | SOLVED 10/10 | SOLVED 10/10 | **REJECTED 10/10** | **REJECTED 10/10** |
| `ENV-LINK` | SOLVED 10/10 | SOLVED 10/10 | **REJECTED 10/10** | **REJECTED 10/10** |
| `PANIC-1` | REJECTED 10/10 | REJECTED 10/10 | REJECTED 10/10 | REJECTED 10/10 |

Two readings, and both matter:

* **At the shipped `rowSound` default the policy loses refutation power** on two of the seven
  (`U-0`): 8 rejections in 20 become 0.
* **With `-Dermine.rowSound=true` the loss is exactly zero**: all seven are refuted at all ten
  bases under BOTH orders.  S2's layers do not depend on the dequeue order — layer (iii) runs
  BEFORE the loop, which is what `solveP_noFalseAccept`'s shape says — and they dominate whatever
  the loop's incidental refutations were.

**The model agrees, so it is the ORDER and not a compiler bug** (`--verdict`, same ten bases;
`S`=SOLVED, `R`=REJECTED):

```
MIN2            model shipped=RRRSRRRSRR   smallcanon=SSSSSSSSSS
FALSE-ACCEPT-2  model shipped=RRRSRRRSRR   smallcanon=SSSSSSSSSS
```

(`PANIC-1` is the one place the model and compiler disagree on the verdict, at both orders: the
compiler's rejection there is `Subst.reduce`'s pre-existing panic, which is outside the modelled
loop — exactly as `seeds/unsat/README.md` records.)


### 4g A hunt of my own: does the policy change VERDICTS on random systems?  Essentially never.

600 of round 8's generated hunt seeds (`tmp/L5r8/hunt/grid`, every sixth of 3,840) at three id
bases, shipped against `smallcanon`, on the model (`--verdict`):
**1,799 of 1,800 identical; 1 differing.**  The one is `g12_8_10_000026` at base 0, where the
SHIPPED order does not finish inside a 30 s cap and `smallcanon` SOLVES — i.e. the difference is
in the policy's favour, and it is the stage's own thesis appearing in a random sample.

So the policy is not a verdict lottery.  `U-0` is not "the policy changes verdicts at random"; it
is the sharper and narrower statement that on the two curated witnesses of a KNOWN unsoundness the
shipped order's incidental refutations disappear.

A cruder comparison of the derived SET (the `sat` records with mint ids collapsed) over 60 of the
same seeds finds 87 of 187 seed/base pairs differing — as expected, and as `runP_noLoss` /
`runP_models` allow: a different order derives a different but equivalent saturated set.  That is
the same phenomenon as the alpha-variant signatures.


## 5. The Part A review's T-1…T-14, as shipped

| # | what it asked for | shipped? | evidence |
|---|---|---|---|
| T-1 | reset the draw counter at the LOOP's entry, not at `RowTrace.withSite`; `ThreadLocal`; save/restore because solves nest | **PASS** | `GenRules.withLoopDraws` (`Constraints.scala:1315-1322`) wraps `PQueue.expand` (`:764`) and `Constraints.combine` (`:1409`) — the only two callers of `incorporateAll` outside its own tail recursion, and `combine` in fact has **no callers at all**, so `expand` is the single live entry. `private val loopDrawn = new ThreadLocal[Int]`; `try body finally loopDrawn.set(old)` |
| T-2 | the tree must keep its `(rhs.hashCode, lhs.hashCode)` order; say measure-or-scan | **PASS** | `removeOne` re-splits on that key and rejoins `less <++> kept <++> greater`; `PSQK`/`pr` untouched; §1d states the scan decision and §3 measures it.  I verified the `==`-duplicate hazard cannot arise (§3c above) |
| T-3 | `dequeuePol_none` (a `pop` answering `none` on a non-empty queue would accept without saturating) | **PASS** | `Policy.dequeuePol_none`, consumed at the point of use in `runP_solved_saturated`'s `.solved` case (`PolicyStep.lean:2001-2020`), not merely stated |
| T-4/T-5/T-6/T-7 | prose and number corrections in `D1-DESIGN.md` | **PASS** | `D1-DESIGN.md` was edited (+20/-? lines) and §6b now records the `canonKey` change; the theorem statements are quoted verbatim in `D1-CHANGE.md` (77 of 77 checked) |
| T-8 | do not `lake build` during a differential | **PASS** | §1f and §5d both record it; the build was deliberately deferred |
| T-9 | the diagnostic should say what to do, and distinguish a resource limit from a verdict | **PARTIAL** | the WORDING does both (I ran it, §4b).  The SEVERITY does not: it is still a `Death` and renders as an error |
| T-10 | delete the "the `Supply`'s `drawn`" sentence; count at the call sites | **PASS** | §1b says so explicitly and the counter is at the two `fresh` sites |
| T-11 | name the mechanism (arity-1 repair links dequeued first) | **PASS** | `PERF-ROADMAP.md` P10's D1 note carries it |
| T-12 | what a mirror needs beyond `DequeueShape` | **PASS** (superseded by D1-T) | the full transport is now theorems |
| T-13 | warn when `solveBudget > 0 && dequeuePolicy == shipped` | **PASS** | `Constraints.scala:1290-1297`, `System.err` |
| T-14.1 | the `.ei` gate with the policy ON | **PASS in form, FAIL in method** | the gate exists and found something, but it was run under the nondeterministic parallel loader with a one-repetition control — `U-1` |
| T-14.2 | the S2 environment-fact gate | **PASS** | 9 cases, differ 4, both ways (my run) |
| T-14.3 | `repl-smoke` / `lsp-smoke` | **PASS** | my run |
| T-14.4 | `perf-bench batch` with the policy ON | **PASS** | §3 and my §4c |
| T-14.5 | say that `replayPolicyOne` skips the early label check | not found in `D1-CHANGE.md` | **MINOR GAP** — the point survives because `replayP` goes through `solveSeedP`, which DOES run the early check; the caveat now applies only to the `--policy=` census, not to the differential |

### The budget value

20,000 is 61× the compiler's worst corpus solve under the policy (328) and 134× the corpus
maximum at the shipped defaults (149).  What one budgeted solve costs at worst in seconds is the
number the report does not give and T-13 asked for; I measured it (§4c).

### The two flags' coupling

They are independent properties and the warning is the only coupling.  That is the right design
— a budget is useful under any order once you accept that the *number* is order-dependent — but
the warning goes to `System.err` at `GenRules` class-initialisation time, which in a `sbt`/LSP
session is easy to miss.  Since the two are "meant to be adopted together", consider making
`dequeuePolicy` default to `smallcanon` **when** `solveBudget > 0` is set explicitly, or at least
repeating the warning in the budget's own death message.

### `TestLoopTrace`'s child-JVM forwarding

Confirmed present and confirmed load-bearing.  `setD1` is computed from the outer JVM's
properties, translated into `--policy=`/`--budget=`/`--trace` for the model (`flagArgs`) AND
put on the child JVM's command line (`:645-649`).  The test prints the forwarding line, which I
saw at both ON settings.  All three replays — `honest`, the id-base control and the `nongen`
control — go through the same `flagArgs`, so the controls run under the policy too, and they
still detect (46 and 58 of 714 under the policy, against 53 and 65 at the defaults).

## 6. Findings, ranked

### U-0 (HIGH, CONFIRMED, NEW) — `smallcanon` makes the shipped solver ACCEPT the known unsatisfiable witnesses at every id base

`tracker/repro/satterm/seeds/unsat/MIN2.json` and `FALSE-ACCEPT-2.json` are the S1 review's
minimised witnesses that the shipped row solver accepts UNSATISFIABLE systems
(`seeds/unsat/README.md`: MIN2 witnesses "the `concrete` branch's unlicensed BARE-ROW deletion";
`SOLVED` 4 of 20 bases at the shipped flags).  On the compiler, at the shipped `rowSound` default,
bases 0–9:

| seed | `shipped` | `-Dermine.dequeuePolicy=smallcanon` |
|---|---|---|
| `MIN2.json` | REJECTED at 8 of 10 bases, SOLVED at 2 | **SOLVED at 10 of 10** |
| `FALSE-ACCEPT-2.json` | REJECTED at 8 of 10 bases, SOLVED at 2 | **SOLVED at 10 of 10** |

So the policy turns a solver that refutes these 80 % of the time into one that never refutes them.
**This does not contradict any theorem** — `runP_rejects_unsat` says a rejection is sound, and
says nothing about whether an unsatisfiable input WILL be rejected; the shipped loop's refutation
is incomplete and S2 exists because of it.  But it is a real, user-visible change of behaviour on
inputs the project already tracks, in the direction of accepting more wrong programs, and it is
NOT visible to any gate the stage ran: the L2 differential compares the compiler against the MODEL
at the same policy, the Part A corpus census contains no unsat witness of this shape, and
`bindcmp.sh` — the one script that would have looked — is broken and was never run.

Two things follow.  (1) The adoption question is not "policy alone vs nothing"; it is whether
`-Dermine.rowSound` (S2, default OFF) must be adopted WITH it.  I measure that in §4f: **with `-Dermine.rowSound=true` all seven witnesses are refuted at all ten bases under both orders**, so S2 removes the loss entirely.
(2) `D1-CHANGE.md`'s "zero verdict changes in 2,301,195 solves" should be qualified: it is zero
verdict changes on the corpus, which is a population with no known unsatisfiable inputs.


### U-1 (HIGH, CONFIRMED) — the `.ei` finding that drives the adoption caveat was measured with a broken control

`D1-CHANGE.md` §2b FINDING 1/2, `ROW-CONSTRAINT-STATE.md`'s "The one adoption caveat",
`PERF-ROADMAP.md` P10, the plan's D1 row.  The claim is *"the worktree swept twice at the flags
OFF gives 181 of 181 identical, 0 differing.  The noise floor is ZERO, so anything the policy
comparison shows is signal."*

The sweep (`tmp/D1/b-ei2.sh`) runs `bin/ermine` at the DEFAULTS, i.e. under the shipped PARALLEL
module loader, and `session/Session.scala:558-560` says in its own comment what that means:
*"The G1 oracle needs deterministic fresh-id draws: parallel makes give thread-timing-dependent
Supply order, which reaches interface bytes through the constraint solver's id-hash queue."*
The "zero noise floor" is therefore one repetition of a nondeterministic experiment.

**Measured.**  Ten repetitions of an identical flags-OFF two-chunk sweep
(`tmp/review-D1B/flip2.sh`): eight distinct md5s over the interface set, five files byte-unstable,
and `einorm2.py` reports **1 of 152 interfaces DIFFERING in every one of the nine comparisons** —
and the one is **`Relation.lookbackJoin`, one of the five the report attributes to the policy,
with exactly the shape the report attributes to the policy**.  Five repetitions with the policy
ON give the same picture.  With `-Dermine.loadInSeries=true` the floor really is zero (0 of 152,
both settings), and OFF vs ON is then **2 of 152**, not 5 — `GridExample` (`stackedBarChart` and
`stackedAreaChart`, the second of which the parallel sweep did not flag) and
`Relation.lookbackJoin`.

**Fix.** Re-run the `.ei` gate with `-Dermine.loadInSeries=true` on both sides and restate
FINDING 2 with the numbers it gives; keep the parallel sweep only as the "does everything still
publish" check, where the six extra interfaces live.  Then say, as `U-2` requires, that the
differences are alpha-variants.

### U-2 (MEDIUM, CONFIRMED) — "different but equivalent saturated sets" understates the answer: the residuals are ISOMORPHIC

`D1-CHANGE.md` §2b FINDING 2's table calls three of the five *"same `exists[N]`, different
residual row shapes"* and the prose says *"two dequeue orders derive different but equivalent
saturated sets"*.  Mechanically (`tmp/review-D1B/alpha2.py`), every differing residual — in the
implementer's own snapshots and in my deterministic-loader ones — is **alpha-equivalent**: there
is a bijection of the existentially bound row variables carrying one constraint set exactly onto
the other, with the `forall`-bound variables and every qualified name fixed.  For
`TargetList.restrictTo`, `RunCalibration.valueAsOf` and `Relation.lookbackJoin` the `forall` prefix
and the body after `=>` are textually identical as well, so those three are the SAME TYPE.
The only genuine text change is the chart signatures' single implicit KIND binder, and it is
vacuous (`Pretty.scala:263-265`: a bare binder is kind `*`; the body's `s sr sa` with
`s : rho -> * -> *` pins `sa` to `*` either way).

This matters for the decision the caveat exists to inform: *"a consumer that recorded a
signature's exact shape … would see a change"* is true, but *"the signature changed"* is not.

### U-3 (MEDIUM, CONFIRMED) — `einorm2.py` sorts each constraint group BEFORE anonymising, so it reports alpha-variants as differences

`tmp/D1/einorm2.py`: `norm_line` sorts every `=>`-preceding group (`' ; '.join(sorted(split_top(…)))`)
and only afterwards substitutes `_` for the binder names.  The sort key is therefore the
ORDER-DEPENDENT names, so two alpha-variants sort into different orders and compare unequal.
That is precisely why three of the five come out as "differing residual shapes" when they are the
same set.  **Fix:** anonymise first, then sort — or, better, canonicalise by isomorphism as
`alpha2.py` does.

### U-4 (LOW-MEDIUM) — `PERF-ROADMAP.md` P10 is ticked `[x]` for an uncommitted, unadopted, default-OFF change

The note under it is accurate and says "not committed … adoption is the user's decision", but the
checkbox reads as done to anyone scanning the roadmap.  P10 is *answered*, not *closed*.

### U-5 (LOW, CONFIRMED) — `#print axioms` covered 83 of `PolicyStep`'s 84 declarations

`tmp/D1T/PrintAxioms.lean` has 83 `#print axioms` lines and the report says 84.  The missing one
is `QOk.shape` (`PolicyStep.lean:59`).  I ran my own census over all four new modules — **158
declarations, 0 non-standard axioms**, `QOk.shape` included and clean (`[propext]`) — so nothing
is wrong; the claim is one wider than the evidence.

### U-6 (LOW) — neither flag is in any interface cache key

`GenRules.toString` (`Constraints.scala:1342-1349`) is unchanged, which is what keeps gate 4
honest — but its only consumer in the tree is `core/src/test/.../DisjProbe.scala:170`, a debug
probe, so it is not an `.ei` fingerprint and nothing records the policy or the budget in a
published interface.  A tree built partly with the policy on and partly off silently mixes them.
My gate 16 shows nothing breaks today (both directions load, rc=0), and `U-2` explains why —
the types are the same — but if the policy is ever adopted incrementally this should be stated.

### U-7 (LOW, CONFIRMED) — the flags-OFF row trace is NOT byte-identical to a pre-D1 trace

`RowTrace.solveInput` appends the policy and the budget to `sin` unconditionally, so every trace
now ends `…\tshipped\t0\t<thread>`.  Brief B2 asks for a "byte-identical row trace" at the flags
OFF and the plan's D1 row says "shipped path byte-identical".  The substantive gate — model and
compiler agreeing record for record — is met (2,355,430 of 2,355,430, my run), and old traces
still parse, but the literal claim is not.

### U-8 (LOW, CONFIRMED) — `tmp/D1/bindcmp.sh` cannot make the comparison it claims to

The script the implementer wrote for "do two policies publish the same VERDICT and the same loop
substitution on every tracked seed" compares `looptrace … --verdict --policy=<p> | tail -1`, and
that line **begins with the policy name** (`pol\tshipped\tbase=9\tSOLVED\t…`), so the two sides
differ by construction on every seed; it reports `SAME` only when both sides produce NO output,
i.e. on a timeout.  It was never run (no output file exists), so nothing in the report rests on
it — but it is in the scratch as if it were a gate.  I replaced it with a comparison of the
COMPILER's published substitution (§4e).

### U-9 (LOW) — `lblKey` reads code UNITS on one side and code POINTS on the other

`Loop/Policy.lean`'s `lblKey` maps a name's characters with `Char.toNat` (Unicode code points);
`Constraints.scala`'s maps with `Char.toInt` (UTF-16 code units).  They agree below U+10000 and
diverge above it, where a surrogate pair would give the Scala side two keys and Lean one.  No
module or label name in this corpus is affected; it should be a comment, or the Lean should use
the UTF-16 encoding.

### U-10 (LOW) — a misplaced doc comment in `RowTrace.scala`

`val drawRecords` was inserted between `withSite`'s scaladoc and `withSite`
(`RowTrace.scala:171-179`), so `withSite` now has none and `drawRecords` carries two, the first
of which describes `withSite`.

### U-11 (INFO, CONFIRMED) — `Constraints.combine` has no callers

`PQueue.expand` (reached only from `Subst.scala:1302`) is the single live entry to
`incorporateAll`.  The T-1 fix is therefore complete; wrapping `combine` too is dead but harmless
insurance.

### U-12 (LOW) — wall-clock numbers do not reproduce; draw counts do, exactly

`GU05` shipped at bases 0/1/2: draws **47,317 / 1,091 / 743** — the report's figures to the digit.
Wall clock: mine **137,645 / 314 / 199 ms** against the report's 128,354 / 1,399 / 1,304 ms, and
under the policy my median is 217 ms against the report's "~1.0 s per base".  Same harness, same
machine, different JIT state.  Nothing is wrong; the report should not present the seconds as
figures of record when the draws are the invariant.

## 7. Prose and acceptance

### `ROW-CONSTRAINT-STATE.md`'s D1 section

DEFAULT OFF is stated, twice, and correctly.  The theorem inventory is correct (I checked every
name against the sources).  The numbers reproduce.  **The interface finding is stated but is
wrong in method and in substance**: it rests on the broken control (`U-1`) and it describes
alpha-variants as "different but equivalent saturated sets" whose "published TEXT" differs
(`U-2`).  It should also carry `U-0`: at the shipped `rowSound` default the policy stops refuting
`MIN2`/`FALSE-ACCEPT-2`.

### The plan's D1 row

Accurate except "shipped path byte-identical" (`U-7`) and the same "5 signatures change text"
(`U-1`, `U-2`).

### `tracker/lean/README.md`

Correct throughout: `Budget.lean` 221, `Policy.lean` 752, `PolicyReplay.lean` 161,
`FlaggedSound.lean` 267, `PolicyStep.lean` 2,373, `PolicyTerm.lean` 1,127 — all confirmed by
`wc -l`.  The theorem names all exist.  The one over-statement is "41 statements compared
mechanically against their originals, 0 differences" — true, and my independent re-derivation
agrees at 49 declarations / 0 differences.

### `PERF-ROADMAP.md` P10

Text accurate; the checkbox is premature (`U-4`).

### `D1-CHANGE.md` §2 / §3 against my numbers

Everything reproduces except the wall-clock seconds (`U-12`), the `.ei` methodology (`U-1`) and
the residual characterisation (`U-2`).  Specifically confirmed to the digit: 913/914; 714/714 ×3
with both controls detecting; 2,355,430/2,355,430 over eight groups under the policy; 54,199
`sdraw` records identical to the model; budget 20 firing at draw 21 with the quoted diagnostic and
`rejected=1` in the replay; budget 20,000 inert; GU05 306 at every base and 47,317/1,091/743 at
the shipped bases 0–2; GU05MIN 256; `env` 9 cases / differ 4 both ways; repl 2+6+4+23; lsp 98;
`einorm2` 181/181, 181/181 and 176/181+6.

### Acceptance

| criterion | verdict |
|---|---|
| brief **B1** — budget and winning policy behind two flags, DEFAULT OFF, mirrored in the model, trace records carry the policy so `--replay` reproduces a policy-on trace | **PASS** |
| brief **B2** — flags OFF nothing changes (`core/test`, `TestLoopTrace`, L2 differential, `.ei`); flags ON the same differential, `core/test`, `perf-bench` before/after, GU05 at 25 bases, gu05's module load time | **PASS with two qualifications**: the OFF row trace is not literally byte-identical (`U-7`), and the `.ei` gate's method is unsound (`U-1`) |
| brief **B3** — report with every measurement, plan row, adoption left to the user | **PASS** |
| D1-T brief **T1–T4** — all 22 (in fact 41 + 9) transported, run level, acceptance fact used, axioms clean, verbatim quotes, table | **PASS** (`U-5` is a bookkeeping nit) |
| plan's D1 row as written | **PASS** |

Outcome claimed: **B-done** and **T-DONE**.  I agree with both.

## 8. Verdict and the two recommendations

### VERDICT: **FIX-THEN-ADVANCE**

The engineering is sound and the theorems are real.  Nothing I found is a defect in the Scala or
in the Lean: the flags are genuinely off by default, `popShipped` is byte-identical to `Q.pop`,
the budget is counted and checked where the model checks it, `removeOne` cannot drop the wrong
element, and the transport is a faithful copy with the originals recovered in the kernel.  What
needs fixing before this is presented to the user as a decision is the **evidence about
adoption**, in three places: the `.ei` control is broken (`U-1`), the five signatures are
mischaracterised (`U-2`, `U-3`), and the one behavioural change that actually matters — `U-0`,
the lost refutations on `MIN2`/`FALSE-ACCEPT-2` — is missing entirely.  All three are
documentation and measurement, not code.

### (i) Committing this stage, flags OFF

**COMMIT IT.**  At the defaults the tree is byte-for-byte the loop it was: `core/test` 913/914
unmoved, `TestLoopTrace` 714/714, the L2 corpus differential 2,355,430/2,355,430, the published
interfaces identical to the base compiler's, `repl-smoke`/`lsp-smoke`/`env` unmoved, and no
measurable perf cost.  The Lean adds 3,928 lines and 158 clean declarations and touches no
existing theorem's statement.  Fold in the corrections above — restate FINDING 2 from a
deterministic-loader sweep, record `U-0` — and commit.

### (ii) Adoption: should `smallcanon` become the default?

**Yes — but only together with `-Dermine.rowSound`, and that is the finding this review adds.**

* **The case for.** `smallcanon` removes the id-order blow-up outright: `GU05` 306 draws at every
  base against 47,317 at the worst shipped base, `incomplete/Gu05` 2 s in a batch load where the
  shipped order does not finish inside 900 s and takes four more modules down with it, corpus
  dequeues −0.39 %, no measurable wall-clock cost, and the compiler and the model agree record for
  record over 2.36 M solve segments under the policy.  It is also base-INVARIANT by construction,
  which is a property the shipped order simply does not have.
* **The case against, and its answer.** At the shipped `rowSound` default the policy stops
  refuting `MIN2` and `FALSE-ACCEPT-2` — 8 rejections in 20 become 0 (`U-0`).  Those refutations
  were never a guarantee (the loop's refutation is incomplete and order-dependent; that is why S2
  exists), but they are behaviour users have today.  **With `-Dermine.rowSound=true` the loss is
  exactly zero**: all seven tracked unsatisfiable witnesses are refuted at all ten bases under
  both orders (§4f).  So the two should be adopted as a pair, and S2's `rowSound` should go first.
* **What must be true of the five signatures first — nothing further.**  They are alpha-variants
  (§ the central question), three of them the same type outright and two differing by one vacuous
  kind quantifier.  Re-run the `.ei` gate with `-Dermine.loadInSeries=true` to get the real list
  (it is 2 files / 3 bindings, not 5, and it includes `GridExample.stackedAreaChart` which the
  parallel sweep missed), state that they are isomorphic, and adopt.  A mixed-policy tree already
  loads (gate 16), so no interface migration is needed; if the policy is adopted incrementally,
  say in the release note that `.ei` files are not keyed by it (`U-6`).
* **With or without a budget, and at what value.**  Adopt the policy FIRST and the budget SECOND,
  or both together — never the budget alone.  `-Dermine.solveBudget=20000` at the SHIPPED order
  rejects `GU05` at base 0 after 56 s while accepting it at bases 1 and 2 (§4d): that is a
  well-typed program failing by id base, which is worse than slow, and it is exactly what the
  built-in warning says.  Under the policy 20,000 is 61× the compiler's worst corpus solve (328)
  and 65× `GU05`'s 306, and it never fires anywhere in the corpus.  **20,000 is a defensible
  value once the policy is on**; its worst cost is ~56 s for one solve, which is a tolerable
  ceiling for a diagnostic that only fires on a diverging mint chain.  If a tighter ceiling is
  wanted, 5,000 is still 15× the worst known solve and caps a firing solve at ~10 s.

### (iii) `-Dermine.rowSound` (S2), now that D1 is in

**Adopt it, and adopt it before or with the policy.**  D1 strengthens the case rather than
weakening it: `rowSound` is the only thing that makes the solver's refutation of the known
unsatisfiable witnesses independent of the dequeue order and of the id base (10/10 under all four
combinations I ran), and without it the policy is a net loss in refutation power on exactly the
inputs the project has spent two stages minimising.  S2's own caveats (cost, the `noVerdict`
budget) are unchanged by D1; nothing in D1 makes `rowSound` more expensive.

## 9. Every number of mine that differs from the implementer's

Everything not listed here reproduced **exactly**, including all eight L2 group counts under the
policy, 913/914, 714/714 × 3 with both controls, 47,317 / 1,091 / 743, 306, 256, 54,199 `sdraw`,
`rejected=0`/`rejected=1`, `cases=9 differ=4`, 2+6+4+23, 98, and all three `einorm2` comparisons
on the implementer's own snapshots.

| quantity | implementer | mine |
|---|---|---|
| `.ei` same-configuration control residue (parallel loader) | 0 of 181, from **1** repetition | **1 of 152 in 9 of 9 comparisons**, from **10** repetitions; 5 of 152 files byte-unstable |
| `.ei` OFF vs ON, with the loader made deterministic | not measured | **2 of 152**, and it includes `GridExample.stackedAreaChart`, a binding the parallel sweep did not flag |
| the five signatures' residuals | "different residual row shapes" / "different but equivalent saturated sets" | **alpha-EQUIVALENT in every case**; three of the five are the same type outright |
| `MIN2` / `FALSE-ACCEPT-2` under the policy | not measured | **SOLVED 10/10 against `shipped`'s 2/10** (`U-0`) |
| `#print axioms` census for `PolicyStep` | "84 declarations" | the census file has **83**; `QOk.shape` is missing (my own census: 158 across all four modules, 0 non-standard) |
| `perf-bench batch` cold median | OFF 13.63 / 13.68, ON 13.42 / 13.55 (`-n 5`) | OFF **11.45 / 11.56**, ON **11.34 / 11.57** (`-n 3`); same conclusion, quieter host |
| `GU05` wall clock, shipped bases 0/1/2 | 128,354 / 1,399 / 1,304 ms | **137,645 / 314 / 199 ms** (draws identical) |
| `GU05` wall clock under the policy | "~1.0 s per base" | median **217 ms**, max 861 ms over 10 bases |
| cost of one budgeted solve at 20,000 | not measured | **56,140 ms**, and it REJECTS a satisfiable input at the shipped order |
| verdict changes under the policy on random seeds | not measured | **1 of 1,800** (600 hunt seeds × 3 bases), and that one is a shipped-side timeout |
| `tmp/D1/bindcmp.sh` | written, presented as the seed substitution gate | **cannot work** (`U-8`) and was never run; I replaced it (§4e) |

## 10. Reproduction

```
# Lean
export PATH=$HOME/.elan/bin:$PATH; cd tracker/lean
LEAN_NUM_THREADS=2 lake build Rowpartition      # 867 jobs
lake env lean Audit.lean                        # 4112 theorems / 0 non-standard axioms
lake build looptrace                            # 1670 jobs
lake env lean /home/dmitry/.claude/jobs/880c725d/tmp/review-D1B/PrintAxiomsRev.lean   # 158 decls

# anti-weakening, independent of tmp/D1T/gen.py
python3 /home/dmitry/.claude/jobs/880c725d/tmp/review-D1B/stmtdiff.py   # 49 compared, 0 weakenings
python3 /home/dmitry/.claude/jobs/880c725d/tmp/review-D1B/verbatim.py   # 77 of 77 quotes verbatim

# the central question
cd /home/dmitry/.claude/jobs/880c725d/tmp/D1
python3 einorm2.py ei-A-wt-off ei-C2-wt-on               # 176/181, 5 differing, 6 only-ON
python3 ../review-D1B/alpha2.py ei-A-wt-off ei-C2-wt-on \
  'core_examples_incomplete_TargetList.ei::restrictTo' … # ALPHA-EQUIVALENT for all five

# the controls the report did not run
/home/dmitry/.claude/jobs/880c725d/tmp/review-D1B/flip2.sh   # 10x OFF parallel, then series OFF/ON
/home/dmitry/.claude/jobs/880c725d/tmp/review-D1B/post3.sh   # the seven unsat witnesses x 2 orders x 2 rowSound

# the gates
/home/dmitry/.claude/jobs/880c725d/tmp/review-D1B/gates.sh   # 0-13
/home/dmitry/.claude/jobs/880c725d/tmp/review-D1B/gates2.sh  # 14-16
/home/dmitry/.claude/jobs/880c725d/tmp/review-D1B/post.sh    # budget cost, .ei stability under the policy
/home/dmitry/.claude/jobs/880c725d/tmp/review-D1B/post2.sh   # compiler substitutions, 28 seeds x 10 bases
```

Nothing in the working tree was modified by this review except this file; no `.ei` files were
left behind under `core/examples` or the stdlib module directory.
