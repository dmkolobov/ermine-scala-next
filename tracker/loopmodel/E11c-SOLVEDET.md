# E11c — the CAUSE of the SET class: making the solver's residual a function of the source

Stage E11c (brief `tracker/loopmodel/briefs/brief-E11c.md`), implementer run 2026-09-13,
branch `scala3-migration`, HEAD `ebd2de1b`, main checkout.  Scratch and every log:
`/tmp/claude-1000/-home-dmitry-research-ermine/78a8325a-2e2d-49f8-9877-67480d272e9e/scratchpad/e11c/`
(`<s>` below).  **Nothing committed; no default flipped; `find core/target -name '*.ei'` is 0.**

## Answer first

**The cause is TWO order reads, both local, both fixed here behind one flag.**

1. **`SCC.scala:46` — Tarjan's driver `comps.foreach`**, `comps` being an immutable
   `Map[Int, Component]` keyed by a variable id, and **`V.hashCode` IS the id**
   (`Vars.scala:109`).  Both callers seed it the same way (`Binding.scala:107`,
   `syntax/Statement.scala:152`: `vm.keySet.toList` on an id-keyed `Map`) and expand each
   component with `Set[Int].toList` (`Binding.scala:112`, `Statement.scala:161`).  So the
   order of Tarjan's DFS **roots**, and hence the order of the components, is a function of
   the **absolute id base**, and two cold checks of one unchanged module **infer its
   binding groups in different orders** — on `Relation.e` the first solve of one check is at
   `139:23` and of the other at `137:11`.
2. **`Subst.scala:1630` — `var ps = q.expand.toList`**, the SATURATED SET, read out of a
   finger tree whose measure is `(some(graph.sort(lhs), (rhs.hashCode, lhs.hashCode)), 1)`
   (`Constraints.scala:499`).  `RHS.hashCode` is `MurmurHash3` over the raw ids, which is
   **not monotone**, so a constant shift of the base **permutes** that list —
   and `Subst.reduce` (`Subst.scala:1341`) folds **right** over it, splicing each
   existential into an accumulator the later arms read.  That fold is **not confluent**, so
   a permutation of the list is a **different residual**.  This is the one that moves the SET
   class.

**Fixable locally: YES, and fixed.**  `-Dermine.solveDet=true|false`, **default OFF**, read
once at class init in `Constraints.GenRules` and carried into `Session.interfaceKey`.  Five
files, 79 insertions, 7 deletions.  Under ON the SCC driver walks the vertex list (source
order) and the saturated set is sorted by `Q.canonLt` (`canonKey`: sorted rhs ids, sorted
label keys, lhs id — an id *order*, invariant under a constant shift) before `reduce`.
Neither order is read by a rule of the loop, but **neither is inert either** — see §4's
"What else reads these orders" (R-2): `ps` also feeds `checkSaturated`, and the SCC change
re-orders bindings within a component and so the constraint list `solve` receives.  Their
safety is established by the gates, not structurally.

**SET count under ON: 2, down from 5.**  E11a corpus sweep, 257 files, 4047 published
bindings, three runs a side (`<s>/gate2-sweep-*.log`):

| | FORM | KIND | **SET** | SET membership |
|---|---|---|---|---|
| OFF ×1 (control, same build) | 0 | 3 | **5** | `cutoffGroupedFldsPosNegRel'`, `reportFor`, `investmentTableData`, `joinCumRet`, `joinTotalValue` |
| ON, my runs ×3 | 0 / 0 / 0 | 1 / 1 / 1 | **2 / 2 / 2** | `cutoffGroupedFldsPosNegRel'`, `lookbackJoin` |
| ON, reviewer's run of the CHECKED-IN property | 0 | 0 | **2** | `cutoffGroupedFldsPosNegRel'`, `Yahoo.e:investmentTableData` |

**Read "5 → 2" as a COUNT, not a subset, and not a fixed pair** (R-5).  The ON two are not a
subset of the OFF five, and the membership ROTATES: the count is 2 in all four ON runs on
record, only `cutoffGroupedFldsPosNegRel'` is in every one, and the reviewer's ON run
(`<r>/rv-e11a-on.log`) puts back `Yahoo.e:investmentTableData` — which my three runs had
leave — and drops `lookbackJoin`.  §6 says why that rotation is itself evidence about the
residue.  `cutoffGroupedFldsPosNegRel'` is E11b-PROBE §5.4's variable-split case and is not an
order read at all.  KIND 3 → 1 (0 in the reviewer's run) is collateral: two of its three
members were `typeDefComponents`' order.

Published signatures get **strictly smaller** under ON: the g1 oracle's 1447 signatures move
on exactly two bindings, `lookbackJoin` (9 → 8 constraints, losing E11b-PROBE §6's `B6`) and
`drilldownKeyValueTable2` (losing `a2 <- (k, v, b1)`, entailed by its siblings) — in both
cases the ON side is the entailment-equivalent set with one redundant conjunct fewer.

## 1. Step 1 — locating the divergence (measurement, no source change)

**Repro.**  `<s>/src/E11cRepro.scala`, compiled with `dotc` against `target/ermine-classpath`
(the recipe `tracker/repro/nameloss/run.sh` uses; nothing added to the repo).  It boots a
`Resident`, warms it with the whole stdlib and calls `resident.checkFile(f, new Documents)`
N times — the E11a properties' own recipe, so every round is a COLD check with the `Supply`
advanced — printing `Pretty.prettyType` and `Canonical.key` per round and writing a
`MARK ROUNDSTART` line into the row trace so the rounds can be cut apart exactly.
`Relation.e` is `core/src/main/resources/modules/Relation.e`, not `core/examples`.

Six cold checks under `-Dermine.loadInSeries=true`, with and without `-Dermine.rowTrace`,
give the **same** sequence of published constraint counts for `lookbackJoin` — `8, 8, 9, 8,
9, 9` (`<s>/s1-series6.log`, `<s>/s1-trace6.log`, `<s>/s1-trace6m.log`) — so tracing does not
perturb the ids, as `RowTrace`'s header claims.  Round 3 (9) is round 1 (8) **plus**
`P[t <- (r, c, h)]`, which is E11b-PROBE §6's `B6`, entailed by `A1`+`A2`+`A7` through
associativity of disjoint union.

**Trace diff A — as shipped (`<s>/s1-ab-marked.log`, `tracker/tools/trace-ab.py`, ALL record
kinds).**  Cut at the markers, each check is **1820 segments**:

```
c1-vs-c3(marked)  segments=1820  CONTENT-DIFFERS=242  KINDCOUNT-DIFFERS=206
                                 PERMUTATION-ONLY=1372  sinmoved=1820
```

**Segment 0 already differs — in its `loc`.**  The first `sin` locs run

```
check 1: 139:23  139:23  139:1  Aggregate.e(40:1)  1:1  139:1  137:11 ...
check 3: 137:11  137:11  137:1  Aggregate.e(38:1)  1:1  137:1  135:9  ...
```

the same work on **different bindings in a different order**.  That is not a solver choice:
it is the order `ImplicitBinding.implicitBindingComponents` hands the groups to
`inferImplicitBindingTypes`.  Chased to its source (all five lines are cause 1 above);
`session/TolerantCheck.scala:993-997` had already sighted it from the other end — the per-SCC
editor cache could not fingerprint stably because `comp` order "is an SCC traversal order
over id-keyed maps and is NOT stable between runs".

**Trace diff B — with cause 1 fixed (`<s>/s4-ab-on.log`).**  The same two cold checks now
align **segment for segment and loc for loc**:

```
ON r1-vs-r2       segments=1820  CONTENT-DIFFERS=120  KINDCOUNT-DIFFERS=2
                                 PERMUTATION-ONLY=1698  sinmoved=1820
```

448 differing segments → 122; `KINDCOUNT-DIFFERS` 206 → **2**, and the two survivors are
`Relation.e(222:3)` and `Relation.e(1:1)` — **exactly the two solves that build and publish
`lookbackJoin`'s residual**, the 8-against-9.  Segment 0's remaining `CONTENT-DIFFERS`
(`trace-ab.py --show 2`) is **only the index columns** of `scon`, `in` and `sat`: the same
records, reordered.

```
only-A: sat ... 1  INPUT                r^# ro^# rs^#
only-A: sat ... 2  CommonSubexpression  t^# c^# ro^#
only-B: sat ... 1  CommonSubexpression  t^# c^# ro^#
only-B: sat ... 2  INPUT                r^# ro^# rs^#
```

`sat` is written as `ps.zipWithIndex` (`Subst.scala:1659`), `ps` being `q.expand.toList`
(`:1630`) — and `ps` is exactly the list `reduce` folds right over at `:1341`.  That is
cause 2, named by the trace.  (`scon`'s order is `Exists.apply`'s `p.toSet.toList`,
`Type.scala:302`, a `Set[Type]` keyed by `Part.hashCode`, `Type.scala:396`; it is
downstream of the same ids and is absorbed at publication by `Canonical.scheme`.)

**The publishing solve, by hand** (`<s>/seg378-c1.txt`, `<s>/seg378-c3.txt`).  The final
`inferImplicitBindingTypes` solve at `Relation.e(1:1)` receives **eight** input partitions in
check 1 and **nine** in check 3; both saturate to 14.  Under the bijection
`r541↦r199, c552↦c212, 543↦201, 547↦210, 542↦200, 546↦204, 545↦211, 548↦205, 544↦202,
554↦209, 553↦208, 550↦207, 555↦213, 549↦206` the input lists agree except for check 3's
`t <- (r, c, h)`.  One step earlier, at `Relation.e(222:3)` (`<s>/seg362-c1.txt`,
`<s>/seg362-c3.txt`), the two runs perform the **same multiset of 13 splices in a different
order** — `<s>/s1-seg362-kinds.log` classifies `splice` and `learn` as PERMUTATION — and that
fold is `reduce`.

**`Yahoo.e`.**  Not re-traced by hand.  It is covered by the same mechanism: all three
`Yahoo.e` bindings leave the SET class under ON (§5(a)), which is what cause 2 predicts and
what a second hand-trace would have been run to confirm.  Listed under NOT DONE.

## 2. Step 2 — the audit

A dedicated read-only pass over the publication path.  Classification: BASE-INVARIANT = the
choice depends only on the RELATIVE order of ids minted in one sequence, or on a structural
key; BASE-DEPENDENT = it reads an absolute id value or a hash of one.  Rows step 1 touches
are marked ★.

**Correction to the brief's premise.**  `Type.scala:169` is `ProductT.hashCode = 38 + n * 17`
— constant per arity, base-INvariant, and not `V`.  The real one is **`Vars.scala:109`,
`override def hashCode = id.hashCode`**, literally the id.  That cuts both ways: as a raw
*ordering* key (`lhs.hashCode` as the tree's secondary key) it is monotone in the id and so
base-INVARIANT; as a *hash bucket* (`Set[V]`/`Map[V,_]` at size ≥ 5, where CHAMP applies
`improve()`) and inside a *composite* hash (`RHS`, `Partition`, `Part` — MurmurHash3, at every
size) it is base-DEPENDENT.  The dominant channel is therefore **not** `Set[TypeVar]`
iteration but `RHS.hashCode` as the queue's primary sort key.

### A. Primitives — `Type.scala`, `Vars.scala`

| # | file:line | construct | choice | class |
|---|---|---|---|---|
| 1 ★ | `Vars.scala:109` | `V.hashCode = id.hashCode` | bucket for every `Set[V]`/`Map[V,_]`; input to every composite hash | **DEPENDENT** |
| 2 | `Vars.scala:105` | `V.equals` on `id` | equality | INVARIANT |
| 3 | `Vars.scala:143` | `Variable.hashCode = v.hashCode` | `VarT`'s hash | **DEPENDENT** |
| 4 | `Type.scala:151` | `ConcreteRho.hashCode = fields.hashCode * 111` | hash of a concrete row | INVARIANT |
| 5 ★ | `Type.scala:396` | `Part.hashCode = 3 + 23*lhs + 5*rhs` | bucket for `Set[Type]` of constraints | **DEPENDENT** |
| 6 | `Type.scala:169` | `ProductT.hashCode = 38 + n*17` | — | INVARIANT (*the line the brief cited*) |
| 7 ★ | `Type.scala:302` | `Exists.apply`: `p.toSet.toList` | order of every published / re-instantiated constraint list | **DEPENDENT** |
| 8 | `Type.scala:310` | `Exists.mk`: `typeVars(q).filter(xm).toList` | existential binder order | INVARIANT given `q` |
| 9-11 | `Type.scala:864-1005` | `Canonical.varOrder` / `colours` / `key` | the fingerprint | INVARIANT |
| 12 | `Type.scala:1029` | `xs.sortBy(xorder.getOrElse(v.id, MaxValue))` | published existential binder order | DEPENDENT (stable-sort tail) |
| 13 | `Type.scala:1037` | ditto for universals | binder order | DEPENDENT (stable-sort tail) |
| 14 | `Type.scala:770` | `mapHasTypeVars.vars` folds a `Map` | message order only | DEPENDENT (diagnostic) |

### B. The queue — `Constraints.scala`

| # | file:line | construct | choice | class |
|---|---|---|---|---|
| 15 ★ | **`:499`** | measure `(graph.sort(lhs), (rhs.hashCode, lhs.hashCode))` | **the finger tree's total order** | **DEPENDENT** |
| 16 | `:443-447` | `TypeVarGraph.+`: `reverseTopSort(newNodes.toStream)` | topological index | **DEPENDENT** |
| 17 | `:460-464` | `canonSort`: `sortBy(_.id)` | id-ordered topological index | INVARIANT (D1's fix) |
| 19 | `:561-567` | `popShipped` | dequeued element | **DEPENDENT** — *not the default* |
| 20 | `:640-679` | `canonKey` / `smallCanonLt` / `popSmallCanon` | **which partition is dequeued** | INVARIANT (the default) |
| 21-23 | `:657-665`, `:516-520`, `:743-760` | `removeOne`, `rhsLookup`, `findRHS` | which duplicate / which lhs names a shared RHS | INVARIANT (`lhs.hashCode` **is** the id, so the equal-`rhs` block is id-ascending: minimum-id lhs) |
| 24 | `:547-551` | `insert`: equal-RHS ⇒ `CommonPartition` unification instead of a definition | definition vs unification | DEPENDENT **via insertion order** |
| 25 ★ | `:682` | `PQueue.foreach` ⇒ `toList` / `toSet` / `foldLeft` / `foldRight` / `vars` | **every list derived from a queue** | **DEPENDENT** |
| 26-27 | `:721-728`, `:784-791` | `PQueue.partition`, `PQueue.toType` | split value / published order | value INVARIANT, iteration DEPENDENT |
| 28 | `:1603` | `Partition.hashCode` | bucket for `Set[Partition]` | **DEPENDENT** |

### C. The solver loop — `Constraints.scala`

| # | file:line | construct | choice | class |
|---|---|---|---|---|
| 29 | `:1625` | `findRHS`'s third disjunct `s.find(_._2 == rhs)` on a `Set[Partition]` | which var is reused as the name of a shared RHS | **DEPENDENT** |
| 30 | `:1691` | `rest ++! trim(learned, proc)` folds a `Set[Partition]` | definition vs unification (row 24) | **DEPENDENT** |
| 31 | `:1680-1688` | `stepLog` branch dispatch | which rule fires | INVARIANT given the dequeue |
| 33 | `:1928-1933` | **`resolvents`** `= incm.foldLeft(proc.foldLeft(Map())(add))(add)` | which witness a later rule reuses at a concrete key — last writer wins | **DEPENDENT** |
| 34 | `:1935-1938` | `findResolvent(s)` consults the batch first | same | **DEPENDENT** |
| 35 | `:1965-1972` | **`concRows`**, built the same way | which concrete-row carrier `splitRow`/`resRow` reuse (both default ON) | **DEPENDENT** |
| 37 | `:2020-2049` | `proc.foldLeft[Set[Partition]](splitConcrete(..))`, accumulator fed back into `findResolvent(s)` / `findRHS(.., s)` | whether the k-th rule sees the (k−1)-th's resolvent ⇒ MINT vs REUSE | **DEPENDENT** |
| 39, 40, 43 | `:2091-2093`, `:2136-2145`, `:2204-2228` | `instantiate`, `makeEmpty`, `destructiveSub`: `++!` folds over `Set[Partition]` | insertion order ⇒ row 24 | **DEPENDENT** |
| 41, 44 | `:2153-2161`, `:2255-2259` | `subPartitions`, `cancellation` | set algebra / `size==1` guarded `head` | INVARIANT |
| 42 | `:2169-2177` | `makeConcrete`: `Set[RHS].foreach(ensure*)` | which incompatibility dies first | DEPENDENT (diagnostic) |
| 45 | `:2296-2307` | `topFamilies(q0.toList)` | family and carrier-minting order | DEPENDENT — `topNormalise` default OFF |
| 46, 47 | `:2381-2400`, `:2430-2455` | `splitConcrete` / `resolution` 4-way cascade | reuse vs mint | **DEPENDENT** (inherits 29/33-35) |
| 48, 50 | `:2588-2590`, `:2718-2740` | `labelClash`, `labelDecide` label iteration | which label refutes | INVARIANT |
| 49 | `:2612` | `checkLabel`: `absList = abstr.toList` | which variable and reason is BLAMED | **DEPENDENT (diagnostic)** |
| 51 | `:2806-2807` | `LabelSearch.ix` `LinkedHashMap` over `ps` | SAT branch order | verdict INVARIANT, node count DEPENDENT (can flip a budget no-verdict) |

### D. Publication — `Subst.scala`

| # | file:line | construct | choice | class |
|---|---|---|---|---|
| 52 ★ | **`:1341`** | `reduce`: `ps.foldRight(csz)` | **order of the splices and of `instantiateType`'s side effects** — non-confluent | **DEPENDENT** |
| 53 | `:1359` | splice rhs `ConcreteRho :: abs.toList` | rhs order of the spliced `Part` | **DEPENDENT** |
| 55, 56 | `:1543-1545`, `:1623`, `:1702` | `liveInput`, `checkLabels(q.toList)` | propagation / decision order | DEPENDENT (feeds 49/51) |
| 57 ★ | **`:1630`** | `var ps = q.expand.toList` | **the saturated set as a list** — the input to row 52 | **DEPENDENT** |
| 58 | `:1703` | `Exists(l, List(), reduce(..))` | constraint list order out of `solve` | **DEPENDENT** (row 7) |
| 59-61 | `:1763`, `:1764`, `:1770` | `gs`, `ts`, `xs` | universal binder order INVARIANT; **existential** binder order DEPENDENT (feeds `refreshList`) |
| 63, 67, 70 | `:2087-2093`, `:1975-1983`, `:2060-2084` | `isolated`, `NormalPart.equals/hashCode`, `deleteTautologies` | set algebra / sorted-id keys / index sets | INVARIANT |
| 64, 66, 69, 71 | `:2099-2110`, `:2132`, `:2140`, `:2183` | `normalPart`'s `vs`, `normal.distinct` (keep-first), `pruned`, the final `Exists` | published list order, which `Loc` of a duplicate survives | **DEPENDENT** (`Canonical.scheme` absorbs most) |

### E. `SigEntail.scala`

On the path (`Subst.scala:639`) but **read-only**: it dies or returns `Unit`, and the
published scheme is built independently at `Subst.scala:660`.  Its own ordering is explicitly
canonical (`canonRows` by `canonKey`, `F.toList.sortBy(_.id)`,
`(rigidW -- qv).toList.sortBy(canonVar)`, `blame` sorted before `ws.head`) — INVARIANT.  Two
diagnostic reads are base-dependent: the `HashSet` of counterexample models
(`SigEntail.scala:537-544`) and the shared `LabelSearch` budget (row 51).

### F. The binding-group order (outside the solver, and where the trace pointed)

| # | file:line | construct | choice | class |
|---|---|---|---|---|
| S1 ★ | `SCC.scala:46` | `comps.foreach` on `Map[Int, Component]` | **Tarjan's DFS root order ⇒ the order of the components** | **DEPENDENT** |
| S2 ★ | `Binding.scala:107`, `Statement.scala:152` | `vm.keySet.toList` on `Map[Int, _]` | the vertex list handed to Tarjan | **DEPENDENT** |
| S3 ★ | `Binding.scala:112`, `Statement.scala:161` | `Set[Int].toList` | order of the bindings **inside** a component | **DEPENDENT** |

**Totals: 33 BASE-DEPENDENT sites.  About 11 are consequential** (can change the SET: rows
29, 30, 33, 34, 35, 37, 39, 43, 46, 47, 52); about 12 reorder a published list without
changing it (5, 7, 12, 13, 25, 27, 53, 58, 61, 64, 66, 69, 71 — `Canonical.scheme` absorbs
most at publication); the rest are diagnostics or a budget cutoff.  They cluster in **two**
places: `RHS.hashCode` as the tree's sort key (`:499`), which every queue traversal inherits,
and `Set[Partition]` / `Set[Type]` iteration.  The places one would expect to be dirty are
clean: `V.equals`, `NormalPart`, `deleteTautologies`, `isolated`, `cancellation`,
`labelDecide`, all of `Canonical` bar two stable-sort residues, and all of `SigEntail`'s
ordering.

**Which entries step 1 touches.**  Cause 1 is rows S1-S3 (outside the solver, which is why
the audit's solver scope did not reach it and the trace had to).  Cause 2 is
row 15 → row 25 → row **57** → row **52**, and it is rows 33/35/37 that turn an order read
into a *different derivation* rather than a permutation.  **The change touches S1-S3 and
57 only.**  Rows 33/35/37 were deliberately **not** touched: they are inside the loop, they
decide mint-vs-reuse, and re-ordering them would change what the solver derives.

## 3. Step 3 — the STOP POINT

**It did NOT fire.**  Both causes are local order reads.  Neither is a cache hit/miss; after
cause 1 is fixed the two checks are 1820 segments each, loc for loc, so the runs are not
minting different variables for structural reasons; and neither order has a theorem behind
it — `smallcanon`'s theorem is about the **dequeued element**, which is untouched, and D1
review T-2's constraint is that the finger tree must stay **sorted** by
`(rhs.hashCode, lhs.hashCode)` because `PQueue.findRHS`, `PQueue.contains` and `Q.insert`'s
`sandwich` are range splits on that key (`Constraints.scala:576-585`).  The fix respects that
exactly: **the tree is not re-keyed.**  Only the list `q.expand.toList` hands to `reduce` is
sorted, after the loop has finished and after every range split has been performed.

What the STOP POINT *would* have covered, and what was therefore left alone, is rows 33/35/37
— `resolvents`, `concRows` and `learnPartitions`' driving fold, the sites where the queue's
order decides **mint versus reuse**.  Re-ordering those changes what the solver *derives*,
which the brief forbids, and they are not needed: the two order reads above account for
three of the five SET members outright.

## 4. The change

`<s>/e11c.diff`; **5 files, 79 insertions, 7 deletions**.  Flag `-Dermine.solveDet`,
**DEFAULT OFF**, read once at class init in `Constraints.GenRules` next to `tautoDelete`.

* `Constraints.scala` — `val solveDet = System.getProperty("ermine.solveDet","false")=="true"`
  with the mechanism documented, `(if (solveDet) "+solvedet" else "")` appended to
  `GenRules.toString`, and a new public `Q.canonLt(a, b) = intListLt(canonKey(a), canonKey(b))`
  (the existing private `canonKey`, no `graph.canonSort` and no arity prefix; total on the
  partitions of one solve).
* `SCC.scala:46` — under ON the driver walks the **`vertices` list** it was handed instead of
  `comps`.  Tarjan is correct for any choice of roots, so this picks a different, equally
  valid topological order of the condensation and changes no dependency; a repeated id in
  `vertices` is absorbed by the existing `index` test.
* `Binding.scala` (`implicitBindingComponents`) and `syntax/Statement.scala`
  (`typeDefComponents`) — under ON the vertex list is `xs.map(_.v.id)`, i.e. **source order**,
  and each component is expanded `sortBy` its position in that list instead of `Set.toList`.
* `Subst.scala:1630` — under ON `q.expand.toList` is `sortWith(Constraints.Q.canonLt)` before
  it reaches `checkSaturated`, the trace and `reduce`.  `q.expand` has exactly one call site in
  the compiler, so the sort covers every consumer of that list.

**Two bounds on `canonLt`, for the record (R-4).**  (i) *Totality.*  Two distinct partitions
tie only if two distinct `Name`s share a `lblKey` (same kind tag, module, string and
`fixity.con`); on a tie `sortWith` is stable and falls back to the finger tree's
base-dependent order.  (ii) *Base invariance* holds under any strictly monotone renumbering
of ids **below `canonSep = 1000000000`** (`Constraints.scala:607`), because the id-vs-`canonSep`
comparisons keep their sign only under that bound.  Both are exactly the bounds `smallcanon`'s
dequeue already lives with; no measurement here contradicts either.

**What else reads these orders (R-2).**  The claim "no rule, guard or verdict reads either
order" is too strong, in two places, and the report should not lean on it:

* `ps` is not consumed by `reduce` alone.  When `GenRules.rowSoundSat` is on — and `+rssat` IS
  in the shipped key — `checkSaturated(ps.map(_.tup))` (`Subst.scala:1638`) runs the
  `LabelSearch` over it, which audit row 51 classifies as "verdict INVARIANT, node count
  DEPENDENT (can flip a budget no-verdict)".  So the sort does change that search's traversal;
  it cannot change its verdict, but it can change how many nodes it spends reaching one.
* The SCC change does more than re-order whole groups: its ON branch also sorts the bindings
  **inside** a component into source order, and `inferImplicitBindingTypes` accumulates the
  wanted constraints in that order — so the constraint LIST handed to `solve`, and hence the
  queue's INSERTION order, changes.  **Audit row 24** (`Constraints.scala:547-551`) says
  insertion order is precisely what decides `CommonPartition` unification against a fresh
  definition.  That is not a cosmetic re-order.

Neither is a defect — but the argument that they are safe is **empirical**: the corpus output
is byte-identical under ON down to every blame sentence and `NO VERDICT` warning
(`<r>/rv-corpus-out-diff.log`), and `TestLoopTrace` is 720/720 on the final build
(`<r>/rv-looptrace-on.log`).  It is a gate argument, not a structural one.

**The interface key: YES.**  `Session.interfaceKey` is
`interfaceFormatVersion + "|" + Constraints.GenRules.toString + …` (`session/Session.scala:184`),
and the flag changes what is published (§5(d): two signatures move, both getting smaller), so
an `.ei` written under ON must not be read back under OFF.  Verified on disk: an `.ei` from an
ON run opens
`-- ermine-interface 2|cut+label-early+…+topnorm+tauto+solvedet|sigEntail=error`
(`<s>/g1b-on/ei/DB.ei`).  Because the default is OFF, `GenRules.toString` is **byte-identical
to today at every shipped configuration**, so the flag's existence invalidates no cached
interface.

Under OFF every touched expression is literally the pre-change expression in the `else`
branch; no shared code path changed.

## 5. Gates

Every figure comes from a command whose log is named.

**Which build each figure is on (R-1).**  The first draft of this section claimed "all figures
below are on the FINAL build"; the reviewer checked the file times and that claim is not
supported as written, so here is the honest version.

* **Intermediate build** (cause 1 — the SCC driver — only; compiled 21:19): every log prefixed
  `tier0-`, `tier1-` or `gate-sweep-`, plus `<s>/ei-postoff` and `<s>/gate-e-eidiff.log`.  They
  are kept because they are what isolates cause 1 from cause 2 (SET 5 with cause 1 alone), and
  they are labelled as such wherever they are cited below.
* **Final build** (both sites; compiled 22:05, `<s>/exp-compile.log`): every log prefixed `g2-`
  or `gate2-` — sweeps 22:08, `TestLoopTrace` 22:10, corpus 22:11/22:12, g1 22:14/22:15,
  `ei-classify` 22:36, `core/test` 23:01.
* **The gap the reviewer found.**  `Subst.scala` and `Constraints.scala` carry mtime **22:16**,
  i.e. AFTER the sweep/`TestLoopTrace`/corpus/g1 logs that cite them.  Those 22:16 writes were
  **comment-only** (renaming the in-code "E11c EXPERIMENT" wording and extending the `GenRules`
  doc comment) and were never recompiled, so the binaries every `g2-` figure was measured on
  hold the same executable code as the tree on disk — but that is an argument, not a
  measurement, and the file times cannot distinguish it from a code edit.
* **What settles it** are the reviewer's re-runs on the recompiled current tree, all under
  `<r>` = the sibling scratch `…/scratchpad/e11c-review/`, and these are the figures to trust
  for the three gates that matter:
  * `TestLoopTrace` under ON — **720 solves / 720 segments / 720 agree, hashdiff 0, eqdiff 0;
    Passed 3, Failed 0** (`<r>/rv-looptrace-on.log`);
  * corpus OFF vs ON — `corpus-verdicts.py` output identical, rc 0 (`<r>/rv-verdict-diff.log`),
    and the raw per-file outputs differ only in timing lines (`<r>/rv-corpus-out-diff.log`);
  * **OFF byte-identity on the FINAL build** — `ei-diff.sh --batch --snapshot` after a fresh
    `core/compile`, 274 interfaces, `diff -r <s>/ei-pre <r>/ei-off-final` is **0 lines**
    (`<r>/rv-eidiff-off-final.log`, `<r>/rv-ei-off.log`).  This closes what was NOT DONE 2.
  * `ei-classify.py` reproduced exactly: 7 of 274 differ,
    `{'identical': 3516, 'order-only': 1, 'other': 6}` (`<r>/rv-ei-classify.log`).

**(a) The E11a form properties with the SET ceiling read under the flag, ×3.**  Run as
`<s>/src/E11cSweep.scala`, which is
`TestTolerantCheck."E11a: the corpus sweep — two cold checks publish ONE form"` transcribed
verbatim so it can be repeated under a flag without a whole suite.  257 files (1 skipped),
4047 published bindings every run.  Logs `<s>/gate2-sweep-{false-1,true-1,true-2,true-3}.log`;
the intermediate build's six runs are in `<s>/gate-sweep-*.log`.

| | identical | FORM | KIND | SET |
|---|---|---|---|---|
| OFF (control, same build) | 4039 | **0** | 3 | **5** |
| ON run 1 | 4044 | **0** | **1** | **2** |
| ON run 2 | 4044 | **0** | **1** | **2** |
| ON run 3 | 4044 | **0** | **1** | **2** |

Target SET 0 **not reached; 5 → 2**, and both survivors are explained by a named cause (§6).
FORM stays 0 (E11a is not regressed).  KIND 3 → 1: `PivotTest.e:pivotData` and `:pivotData2`
leave, `SoftSchema.e:pivoted` stays.

**(b) Two-base stability.**  Each sweep row IS a two-base comparison (two cold checks per file
with the `Supply` advanced), repeated three times with identical results.  Additionally six
consecutive cold checks of `Relation.e` alone publish **one** key for `lookbackJoin` under ON
(`<s>/exp-lbj.log`) against **four distinct keys** over six checks as shipped
(`<s>/s4-lbj-false.log`).

**(c) Tier 0** (all under the default, OFF).
* `sbt core/compile core/copyResources` — `[success]`, 12 s (`<s>/exp-compile.log`).
* `sbt 'core/testOnly *TestLoopTrace'` — **720 solves / 720 segments / 720 agree; skipped 0,
  hashdiff 0, eqdiff 0, rejected 36, fuel 0; Passed 3, Failed 0** (`<s>/g2-looptrace-off.log`).
* `tracker/tools/corpus-run.sh --batch` — **89 LOADED / 79 REJECTED / 0 UNKNOWN of 168**
  (`<s>/g2-corpus-off.log`).
* `tracker/tools/repl-smoke.sh` rc=0, `PASS smoke (23 checks)` (`<s>/g2-repl-smoke.log`);
  `tracker/tools/lsp-smoke.sh` rc=0, `PASS tauto (5 checks)`, `PASS lsp (573 checks)`
  (`<s>/g2-lsp-smoke.log`).
* `tracker/tools/g1-validate.sh` — **all 9 checks PASS, `G1 COMPARE: EQUIVALENT` on 129 files
  / 1447 signatures, `PASS no drift from tracker/g1-baseline`** (`<s>/g2-g1-off.log`).  The
  baseline was **not** re-cut.
* No Lean changed.
* **Tier 2, taken anyway because the change is in the solver: `sbt core/test` in full —
  `Passed: Total 1070, Failed 0, Errors 0`, 25 min 11 s** (`<s>/g2-coretest-off.log`).  Green
  with NO quarantine invoked: `TestConstraints."disjunction sound"` is registered only under
  its flag, and neither `TestInterfaceRoundTrip` nor `TestLegend."extra args are ignored"`
  flaked on this run.  That run includes both E11a properties with their SET ceilings and the
  whole of `TestTolerantCheck`.

**(d) Tier 1 under ON.**
* `sbt -Dermine.solveDet=true 'core/testOnly *TestLoopTrace'` — **720 / 720 / 720 agree,
  hashdiff 0, eqdiff 0; Passed 3, Failed 0** (`<s>/g2-looptrace-on.log`).  The model-agreement
  invariant is intact, which is the brief's signal that the change moved an ORDER and not a
  DECISION.
* `corpus-run.sh --batch` under ON — **89 / 79 / 0 of 168, and the verdict listing is
  byte-identical to OFF: `diff` is empty** (`<s>/g2-corpus-on.log`,
  `<s>/g2-verdict-diff.log`).  Worth recording: on the intermediate build (cause 1 only) 12 of
  the 79 rejections printed a different *blame sentence* for the same field of the same file
  (`<s>/tier1-verdict-diff.log`, audit row 49); adding cause 2's sort removed that drift too.
* `g1-validate.sh` under ON — the drift, **reported and NOT re-cut**
  (`<s>/g2-g1-on-cmp.log`, `<s>/g2-g1-browse.diff`): `g1-compare: 129 files, 1447 signatures,
  **2 differing**`.  Both are the ON side losing a redundant conjunct:

  | binding | baseline (OFF) | ON |
  |---|---|---|
  | `lookbackJoin` | `… j <- (r, c, k), j <- (d, e, k), l <- (h, i), m <- (e, k)` (9) | `… j <- (d, k), l <- (d, e, k), m <- (h, i)` (8) |
  | `drilldownKeyValueTable2` | `a2 <- (k,v,i,r), a2 <- (k,v,b1), b1 <- (i,r), c <- (k,v,i)` | `a2 <- (k,v,i,r), b1 <- (i,r), c <- (k,v,i)` |

  `lookbackJoin`'s loss is E11b-PROBE §6's `B6`, entailed by its two siblings;
  `drilldownKeyValueTable2`'s is `a2 <- (k,v,b1)`, entailed by `a2 <- (k,v,i,r)` and
  `b1 <- (i,r)`.  G1Compare's equivalence checker is alpha/order only, so it correctly calls
  these DIFFERING rather than equivalent — they are a real (and strictly better) change to
  what is published, which is why the flag is in `interfaceKey`.
* **`ei-diff` OFF-vs-ON, classified with `ei-classify.py`** (`<s>/g2-ei-classify.log`).  Two
  `--batch --snapshot` sweeps with `-Dermine.loadInSeries=true` on both sides, 274 interfaces
  each, A = the pre-change compiler (`<s>/ei-pre`), B = the final build under ON
  (`<s>/ei-on`):

  ```
  interfaces: A 274  B 274   only-in-A -   only-in-B -
  == 7 of 274 interfaces differ
  == bindings by verdict: {'identical': 3516, 'order-only': 1, 'other': 6}
  == interface key differs on 274 of 274 (expected in a flag A/B): … +tauto  ->  … +tauto+solvedet
  ```

  **3516 identical, one order-only (`SoftSchema.e:pivoted`), six `other`** — every one of the
  six named and hand-classified:

  | binding | verdict | what moved |
  |---|---|---|
  | `Present/WriterOutputs.e:reportFor` | constraints **3 → 1** | ON drops `a <- ((\|pMinValue,pRegion\|), c)` and `a <- ((\|pRegion,pTitle\|), d)`, both E11b-PROBE §5.2's unused-existential conjuncts. A strictly smaller, equivalent set. |
  | `Relation.e:lookbackJoin` | constraints 8 → 9 | one of its two known variants (E11b-PROBE §6). Direction is regime-dependent: in the g1 oracle's per-file regime the ON side is the **8** and the baseline the 9 (§5(d) table); in this batch regime it is the other way. Under ON each regime is stable; as shipped neither is. |
  | `Layout/Report.ei:drilldownKeyValueTable2` | constraints 5 → 6 | the `a2 <- (k, v, b1)` conjunct, entailed by `a2 <- (k,v,i,r)` and `b1 <- (i,r)`; same regime remark. |
  | `Layout/Report/Relation.ei:cutoffGroupedFldsPosNegRel'` | other | §6: the variable-split case, not an order read. |
  | `incomplete/RevenueShare.ei:shareOfGroup` | other | same family as `cutoffGroupedFldsPosNegRel'` — the two sides carry a row as different splits; `incomplete/` is outside the clean corpus. |
  | `ChartsExample.ei:stackedPair` | other | **no row constraint moved**: the implicit KIND binder list goes `{a a1 b b1 c}` → `{a b}`, i.e. `tdxfyf'`, `tdxfyf` and `sa` lose their kind variables and take `*`. That is the `typeDefComponents` half of the change (the same mechanism as KIND 3 → 1), not the row solver — and it is **an OPEN DECISION, see §6a (R-3)**. |

  Nothing classified `concrete->polymorphic`.  Note that `ei-classify`'s verdicts are about
  TYPES: "no published type got weaker" does not cover KIND generality, and `stackedPair` is
  about kinds (R-3).

**(e) Under OFF.**  A pre-change interface snapshot was taken before any source was touched
(`ei-diff.sh --batch --snapshot <s>/ei-pre "-Dermine.loadInSeries=true"`, **274 interfaces**,
`<s>/ei-pre.log`), and the same command re-run on the intermediate build into
`<s>/ei-postoff` (274 interfaces): **`diff -r <s>/ei-pre <s>/ei-postoff` is EMPTY**
(`<s>/gate-e-eidiff.log`, 0 lines) — OFF is byte-identical to the shipped compiler across all
274 published interfaces.  That snapshot predates cause 2's line; for the FINAL build the
evidence is `g1-validate.sh`'s `PASS no drift from tracker/g1-baseline` above (129 files,
1447 signatures, against a baseline recorded long before this stage) plus the structural
argument that every touched expression sits in an `else` branch.  A fresh 274-interface OFF
snapshot on the final build was **NOT DONE 2, and the reviewer closed it**: 274 interfaces,
`diff -r <s>/ei-pre <r>/ei-off-final` **0 lines** (`<r>/rv-eidiff-off-final.log`).
`TestTolerantCheck` under OFF is **green inside the 1070/1070 `core/test` run above**, and
the OFF sweep in (a) — that suite's corpus property transcribed — reproduces
`E11a-CANON.md` §4's checked-in numbers (FORM 0, KIND 3, SET 5).

**Perf.**  NOT RUN (§7).  The change costs one `zipWithIndex.toMap` per binding group and one
`sortWith` per solve over a list whose median length is small; no solve does different work.

## 6. The SET survivors — a count of two, with rotating membership

* **`Layout/Report/Relation.e:cutoffGroupedFldsPosNegRel'`** — E11b-PROBE §5.4: 28 constraints
  each way, no bijection even with 4 set aside, because one run carries a row as a single
  variable `d3` and the other as `d1, ro`.  That is a **generative** difference (a split that
  happened on one run and not the other), not an order read, and no re-ordering can close it;
  closing it needs either a common-subexpression contraction that recognises `d1, ro` as
  always co-occurring or the entailment oracle E11b was rejected for.
* **The second survivor is whichever binding the base disturbs — NOT a fixed binding** (R-5).
  My three ON runs named `Relation.e:lookbackJoin`; the reviewer's ON run of the checked-in
  property named `Yahoo.e:investmentTableData` instead (`<r>/rv-e11a-on.log`), a binding this
  report elsewhere calls "gone" under ON.  The count is 2 in all four ON runs on record; only
  `cutoffGroupedFldsPosNegRel'` appears in every one.  **That rotation is itself the evidence
  about the residue**: a third BOUNDARY order read would move the same binding every time,
  whereas a `Set[Partition]` iteration INSIDE the loop — audit rows 33/35/37, where the order
  decides mint-vs-reuse — lands wherever the base happens to change enough CHAMP hash bits.
  It is consistent with `lookbackJoin` being stable under six consecutive cold checks of its
  own module (one key, `<s>/exp-lbj.log`, small base jumps) and unstable across the 257-file
  sweep's much larger ones.  Closing it would mean changing what the solver derives, which the
  STOP POINT forbids.  Nobody has yet trace-diffed two ON variants of one such binding at two
  sweep-sized bases; until that exists, rows 33/35/37 are the best-supported explanation
  rather than a measured one (follow-up).

## 6a. OPEN DECISION for the user — `ChartsExample.e:stackedPair` loses kind polymorphism

Not resolved here, and deliberately not argued either way; it is a question about which
inference is *intended*, which is the user's to answer before any default flip.

**What changes.**  Under ON the published signature of `ChartsExample.e:stackedPair` binds
**three fewer implicit kind binders**: `forall {a a1 b b1 c} (tdxfyf': a) (xa': a1) (ya': b)
(tdxfyf: b1) xa ya … (sa: c) …` becomes `forall {a b} tdxfyf' (xa': a) (ya': b) tdxfyf xa ya …
sa …`.  `tdxfyf'`, `tdxfyf` and `sa` stop being kind-polymorphic and take `*`.  **No row
constraint moved**; this is not the row solver.

**What is known about why.**  It is the `typeDefComponents` half of the change
(`syntax/Statement.scala`), the same mechanism that takes the E11a KIND class from 3 to 1: the
order in which kind inference visits the module's type/data groups decides whether a kind
variable is still free — and therefore generalised — at the point a group is generalised.  As
shipped that order is an id-hash order, so which of the two answers you get is a function of
the id base; under ON it is source order, so it is stable, but it is stable *at the less
general answer* for this binding.  That is the same phenomenon the KIND class measures, only
here it lands in a published interface rather than in a two-cold-checks comparison.

**What is NOT known.**  Which of the two is the intended inference.  A strictly less
kind-polymorphic signature is a real narrowing of what a downstream module may instantiate,
and no corpus client notices today (the whole corpus still loads identically under ON,
§5(d)) — but "no corpus client notices" is not "nobody may".  Deciding it needs someone who
knows whether `ChartsExample`'s three binders are *meant* to be kind-polymorphic.  A cheap
next step would be to check whether the ON answer is the one the checker produces when the
groups are visited in dependency order alone, i.e. whether source order is merely *a* valid
order or the *right* one for kind generalisation.
* `looptrace-corpus.sh` ON vs a pre-change run through `trace-ab.py` — **NOT RUN** (§7).

## 7. NOT DONE

1. **SET 0 not reached: 2, from 5.**  §6 names both survivors and says why neither is an
   order read the change may touch.
2. A fresh 274-interface `--snapshot` under OFF on the FINAL build, diffed against
   `<s>/ei-pre`.  The same diff was run and was EMPTY on the intermediate build (cause 1
   only); for the final build OFF-identity rests on `g1-validate`'s no-drift PASS plus the
   structural argument.  A reviewer should close this: `tracker/tools/ei-diff.sh --batch
   --snapshot <dir> "-Dermine.loadInSeries=true"` then `diff -r <s>/ei-pre <dir>`, expect
   empty.
3. `sbt core/test` in full was run under **OFF only** (1070/1070); it was not repeated under
   `-Dermine.solveDet=true`.  Nothing in the CHECKED-IN tests yet records the 5 → 2: the E11a
   properties read the SET class at the shipped default, so their ceilings (3 per binding over
   four cold checks, 10 over the corpus) are unchanged and would not notice if the flag
   regressed.  Tightening them is the natural follow-up ONCE the user decides on the default.
4. `looptrace-corpus.sh` ON vs a pre-change run through `trace-ab.py` (18 groups) — no budget.
   The `Relation.e` segment-aligned diff in §1 is a sample of one module, not the corpus.
5. The interleaved `perf-bench.sh batch -n 3` OFF/ON/OFF/ON — not run; the machine was never
   below load 1.3 for long enough inside the budget.
6. A second binding (`Yahoo.e`) re-traced by hand.  The sweep shows all three `Yahoo.e`
   bindings leaving the SET class under ON, which is the confirmation such a trace would have
   given, but it is an inference from the sweep, not a trace.
7. **OPEN DECISION, not a task: `ChartsExample.e:stackedPair` publishes three fewer implicit
   KIND binders under ON** — §6a.  Deliberately unresolved; it needs someone who knows whether
   those binders are meant to be kind-polymorphic.
8. Nobody has trace-diffed two ON variants of one rotating SET survivor at two sweep-sized
   bases.  Audit rows 33/35/37 are the best-supported explanation of the residue (§6), not a
   measured one.
9. Adoption is the user's.  Nothing here proposes flipping the default, and the published
   signature changes in §5(d) — two row-constraint sets and one kind-binder list — are a
   shipped-behaviour change that belongs in a Tier 2 conversation.

## 8. Time

Started 2026-09-13 20:47, finished 23:1x — **about 2 h 30 m**, inside the 3 h budget.
Roughly: 25 min reading and orienting; 55 min step 1 (harness, six traced cold checks, marker
splitting, segment alignment, the publishing solve by hand); 70 min step 2 (a dedicated
read-only audit agent, run in parallel with step 1); 35 min step 4 (the flag, three SCC call
sites, `Q.canonLt`, `Subst:1630`); the rest gates, of which the two 22-minute interface
sweeps and the 25-minute `core/test` were the bulk.  Nothing committed.

## 9. Review corrections (E11c-REVIEW.md, applied)

Fix round on `tracker/loopmodel/E11c-REVIEW.md` (**ACCEPT WITH FIXES**, none blocking),
applied in place 2026-09-13.  Report edits only: no source file, no other tracker file and no
JVM was touched in this round, and nothing was committed.  `<r>` =
`…/scratchpad/e11c-review/`, the reviewer's scratch.

| # | what the review said | where it is now applied |
|---|---|---|
| **R-1** | §5's "All figures below are on the FINAL build" is not supported by the file times: `Subst.scala` and `Constraints.scala` carry mtime 22:16, after the sweeps (22:08), `TestLoopTrace` (22:10), corpus (22:11/22:12) and g1 (22:14/22:15) logs that cite them. | **§5 preamble**, rewritten: it now lists which logs are from the INTERMEDIATE build (cause 1 only) and which from the final one, states that the 22:16 writes were comment-only and never recompiled *and* that this is an argument rather than a measurement, and cites the reviewer's final-build re-runs as the figures to trust — `TestLoopTrace` ON 720/720 (`<r>/rv-looptrace-on.log`), corpus OFF vs ON identical (`<r>/rv-verdict-diff.log`, `<r>/rv-corpus-out-diff.log`), OFF byte-identity on the final build 0 lines over 274 interfaces (`<r>/rv-eidiff-off-final.log`), `ei-classify` reproduced (`<r>/rv-ei-classify.log`).  **§5(e)** now records NOT DONE 2 as CLOSED by that snapshot. |
| **R-2** | "No rule, guard or verdict reads either order" is too strong: `ps` also feeds `checkSaturated` (`+rssat` is in the shipped key; audit row 51 — verdict invariant, node count not), and the SCC change re-orders bindings WITHIN a component and so the constraint list handed to `solve`, where audit row 24 says insertion order decides definition-vs-unification. | **Answer first**, weakened with a pointer; **§4, new block "What else reads these orders (R-2)"** spelling out both consumers and closing with the correction that safety here is established **empirically by the gates** (corpus output byte-identical including every blame sentence and `NO VERDICT` warning; 720/720 on the final build), **not structurally**. |
| **R-3** | `ChartsExample.e:stackedPair` publishes three fewer implicit KIND binders under ON (`{a a1 b b1 c}` → `{a b}`), a strictly less kind-polymorphic signature, which `ei-classify`'s "nothing weaker" does not cover because that verdict is about types. | **New §6a, "OPEN DECISION for the user"**, plus a note under §5(d)'s table and its summary line, plus **NOT DONE 7**.  Recorded, NOT resolved: it says exactly what changes, what is known about why (the `typeDefComponents` order decides whether a kind variable is still free at generalisation; ON is stable but stable at the less general answer), what is not known (which inference is intended), and a cheap next step. |
| **R-4** | `Q.canonLt`'s ties fall back to `sortWith`'s stability, i.e. to the base-dependent finger-tree order — reachable only if two distinct `Name`s share a `lblKey`; and `canonKey`'s `canonSep = 1e9` bounds the ids for which the key is base-invariant. | **§4, new block "Two bounds on `canonLt`, for the record (R-4)"**, noting both and that they are the bounds `smallcanon`'s dequeue already lives with. |
| **R-5** | "SET 5 → 2" is a count, not a subset and not a fixed pair: the reviewer's ON run of the checked-in property gave `cutoffGroupedFldsPosNegRel'` + `Yahoo.e:investmentTableData`, mine gave `cutoffGroupedFldsPosNegRel'` + `lookbackJoin`; membership rotates, only `cutoffGroupedFldsPosNegRel'` is constant, the count is 2 in all four ON runs. | **Answer first**: the table gains the reviewer's run as a fourth row and the paragraph under it now reads "a COUNT, not a subset, and not a fixed pair".  **§6** retitled "The SET survivors — a count of two, with rotating membership", and its second bullet rewritten around the rotation — including the point that the rotation is itself evidence that the residue is a `Set[Partition]` read INSIDE the loop rather than a third boundary read, since a boundary read would move the same binding every time.  **NOT DONE 8** records that nobody has trace-diffed two ON variants at two sweep-sized bases. |

Not re-measured in this round, by instruction: no JVM was started, so every figure above is
either unchanged from §5 or taken from the reviewer's logs under `<r>`.
