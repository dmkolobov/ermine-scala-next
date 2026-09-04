# L1 — the row-constraint loop as a Lean FUNCTION, executable, trace-comparable

Stage L1 of `tracker/LOOP-MODEL-PLAN.md`. Implemented 2026-09-04.

**Result.** `Constraints.incorporateAll` is now a total Lean function with an executable that
prints the compiler's own `-Dermine.rowTrace` TSV. On every system tested — the six tracked
seeds, eleven seeds built by the L1 reviewer for branches the seeds do not reach, two
regression seeds for a CHAMP ordering bug, and 120 random systems from `rowclosure.py` — the
two traces agree, and where byte-identity was checked they are byte-identical rather than
merely equal after id normalisation. §6 has the totals.

That claim is scoped to **what was actually run**: `json:` seeds of at most a dozen variables
and a dozen labels, at the flag settings listed, through the LOOP only. It is not a claim
about the 110-module example corpus or the 129-module stdlib boot — that is L2 — and §7 lists
what the model deliberately does not reach, chiefly `Subst.reduce`, which runs *after* the
loop and whose effect on the reported bindings is quantified exactly. Two model bugs have been
found by differential testing so far (§6d) and two more by the L1 review (§6e); all four are
fixed. Both review findings were in `Loop/SSet.lean`, and neither was visible to reading —
which is the argument for keeping the differential, not for trusting the model.

---

## 1. What was built

| file | lines | what |
|---|---|---|
| `tracker/lean/Rowpartition/Loop.lean` | 47 | umbrella, imported from `Rowpartition.lean` |
| `tracker/lean/Rowpartition/Loop/Hash.lean` | 168 | `MurmurHash3`, `Hashing.improve`, `String.hashCode` |
| `tracker/lean/Rowpartition/Loop/SSet.lean` | 237 | `scala.collection.immutable.Set` **with its iteration order** |
| `tracker/lean/Rowpartition/Loop/State.lean` | 284 | `RHS`, `Partition`, `Inference`, `SubstEnv`, `GenRules`, `Partition.toString` |
| `tracker/lean/Rowpartition/Loop/Queue.lean` | 230 | `Q`: `TypeVarGraph`, `reverseTopSort`, `insert`, `pop`, `findRHS` |
| `tracker/lean/Rowpartition/Loop/Rules.lean` | 226 | the seven rules, branch for branch |
| `tracker/lean/Rowpartition/Loop/Step.lean` | 359 | `learnPartitions`, `makeEmpty`/`makeConcrete`/`destructiveSub`/`unify`, `step`, `run` |
| `tracker/lean/Rowpartition/Loop/Trace.lean` | 58 | the TSV record formats |
| `tracker/lean/Rowpartition/Loop/Json.lean` | 197 | `Exists.apply`, `RHS.build`, `PQueue.build`, `labelClash` |
| `tracker/lean/Rowpartition/Loop/Seed.lean` | 170 | the `json:` seed format and `Subst.solve` around the loop |
| `tracker/lean/Rowpartition/Loop/Conformance.lean` | 121 | 45 JVM-checked `#guard`s on the hashes and the set order |
| `tracker/lean/Rowpartition/Loop/Bridge.lean` | 373 | the `Rowpartition.Constraint` conversion, proved a bijection |
| `tracker/lean/Rowpartition/Loop/Main.lean` | 79 | the `looptrace` executable |
| `tracker/tools/looptrace-diff.py` | 163 | the differential harness |

Plus one `[[lean_exe]]` stanza in `tracker/lean/lakefile.toml` (no new `require`), one
import line and one doc bullet in `tracker/lean/Rowpartition.lean`, thirteen build-table rows
and one "Loop model (L1)" section in `tracker/lean/README.md`, and the L1 status row in
`tracker/LOOP-MODEL-PLAN.md`.  The last three files already carried uncommitted Stage 7 work;
every edit made to them here is strictly ADDITIVE (nothing existing was removed or rewritten),
which the brief's deliverable 5 asks for and its "do not touch the nine" trap otherwise
forbids.  Nothing else in the tree was touched, and nothing was committed.

`lake build Rowpartition` — **832 jobs**, success.
`lake env lean Audit.lean` — **`Rowpartition theorems audited: 2508; declarations using a
non-standard axiom: 0`**.
`lake build looptrace` — 22 jobs, success.

No `sorry`, no `partial`, no `Classical`, no `axiom`, no `native_decide` anywhere under
`Rowpartition/Loop/`. `run` takes an explicit fuel and `outOfFuel` is a distinguishable
answer; **four** other recursions carry explicit depth arguments, and each is large enough:

* `Graph.dfs` gets `#nodes + 1`. Each nested call marks a previously unmarked node, and every
  child is a node (`Graph.add` puts the edge targets into `newNodes = nodes ++ vs + u`), so
  the stack holds distinct nodes and its depth is at most `#nodes`. The short-circuit branch
  of `Graph.add` adds no node that is not already in `sort`, because its guard `ok` requires
  `u` and every `v ∈ vs` to be in `sort` already. Argued, not proved.
* `SSet.champSort` and `SSet.rightWins` get 7, the number of 5-bit levels in a 32-bit hash,
  which is the depth at which a real CHAMP trie makes a collision node; beyond it the model
  keeps insertion order, as a collision node does (§4).
* `checkLabel` gets `#partitions + 2`. After ANY productive event at a partition — `ones = 1`,
  `bits(v) = false`, `ones = 0` with `unknown = ∅`, or `bits(v) = true` with `|unknown| = 1` —
  every variable of that partition is known, so that partition can never set another bit.
  There are therefore at most `|ps|` productive passes plus one quiescent pass. This matters:
  a fuel that were too small would make the model silently report NO clash where the compiler
  refutes. (Argument supplied by the L1 review, F5.)

---

## 2. The executable

```
cd tracker/lean
lake exe looptrace <seed.json> <base> [fuel] [--verdict] [--site=S] [--flags=..]
```

* default: prints the `RowTrace` TSV — `step` and `learn` for the loop, then `in`, `inpart`,
  `sat` and the single `solve` line, in the order `Subst.solve` writes them;
* `--verdict`: prints `SOLVED` / `REJECTED <msg>` / `FUEL` and the loop's bindings in the
  repro harness's `v0 := ...` shape;
* `--site=S`: sets the second column (default `json:<path>@<base>`), so the output can be
  diffed byte-for-byte against a compiler trace;
* `--flags=a,b,c`: `all`, `cut`, `nongen`, `disj`, `nolabel`, `lateLabel`, `noresguard`,
  `nosplitkey`, `nosplitrow`, `noresrow`, `emptyrow`. With no `--flags` the SHIPPED defaults
  are used (`cut+label-early+resguard+splitkey+splitrow+resrow`, `emptyRow` off).

Fuel defaults to 100000 dequeues.

Example (byte-identical to the compiler's trace for the same solve):

```
$ lake exe looptrace ../repro/satterm/seeds/W2.json 0 \
      --site='json:tracker/repro/satterm/seeds/W2.json@0'
step	json:…/W2.json@0	learn	^free0 <- (^free2,Repro.l100)	incm=1	proc=0
step	json:…/W2.json@0	learn	^free0 <- (^free1 ^free2,Repro.l100)	incm=0	proc=1
learn	json:…/W2.json@0	new	SplitKeyed: ^free2 <- (^free1 ^free2,)
learn	json:…/W2.json@0	new	Cancellation: ^free1 <- (,)
step	json:…/W2.json@0	empty	Cancellation: ^free1 <- (,)	incm=1	proc=2
in	json:…/W2.json@0	-	0	v0^0	v2^2 | (|Repro.l100|)
…
solve	json:…/W2.json@0	-	2	2	1	0	true	2;3	-
```

---

## 3. The dequeue order, stated as a function

This is the fact the plan asked for, and it is the fact everything else in the model rests on.

`Constraints.Q` (lines 403–640) keeps each queue in a `scalaz.FingerTree` measured by
`PSQK = (Option[(Int, (Int, Int))], Int)`, whose monoid takes the MINIMUM of the first
component's priority and the RIGHTMOST element's `(rhs.hashCode, lhs.hashCode)`. Two
observations turn that into a list:

* every `insert` splits the tree on the *last element's* key, so the tree is a **search tree
  ordered ascending by `(rhs.hashCode, lhs.hashCode)`**, compared as SIGNED Java `int`s
  (`scalaz.Order[Int]`), and `heapify`, `filter`, `partition` and `pop` all preserve that
  order — `heapify` only re-measures;
* `pop` splits on "the prefix's minimum priority equals the whole tree's minimum", which
  selects the FIRST element, in that order, whose priority `graph.sort(lhs)` is minimal.

Since `sort` is a bijection `nodes → 0..n-1`, the minimum selects a UNIQUE variable, so:

> **Dequeue rule.** Let `v` be the variable of minimal reverse-topological index among the
> left-hand sides present in the queue — `reverseTopSort` emits children before parents, so
> `v` is the *deepest*. Dequeue the partition with `lhs = v` whose `rhs.hashCode` is smallest
> as a signed Java `int`. Among partitions with equal `(rhs.hashCode, lhs.hashCode)` the most
> recently inserted wins, because `insert` places a new element at the FRONT of its key block.

`Rowpartition.Loop.PQueue.dequeue` is that rule; `PQueue.insertSorted` is that insertion
point.

**It depends on `hashCode`, and the model computes the real one.** `V.hashCode = id`
(`Vars.scala:109`), so `lhs.hashCode` is the id — the identity function. `rhs.hashCode` is
NOT: `RHS` is a case class over two `Set`s, so it is
`MurmurHash3.productHash("RHS", [setHash(abstr), setHash(conc)])` with
`setHash = unorderedHash(·, "Set".hashCode)` and each element hashed by
`V.hashCode = id` / `Global.hashCode = (2, module, string, fixity.con).hashCode`. All of
that is transcribed in `Loop/Hash.lean` and checked against the JVM (§5).

`graph.sort` is the position in `StreamTUtils.reverseTopSort(newNodes.toStream)(edgeFun)`,
and *that* depends on the ITERATION ORDER of `newNodes` and of each edge set — which is why
`Loop/SSet.lean` exists.

---

## 4. `scala.collection.immutable.Set`, modelled with its order

The solver reads sets in order in five places that reach the output: the DFS root order and
child order inside `reverseTopSort`; the `Set[Partition]` that `learnPartitions` returns,
which `++!` folds into the queue and which `incorporateAll` prints one `learn` record per
element of; the `Set[Partition]` that `instantiate`/`makeEmpty` fold; and
`Partition.toString`, which prints `abs.map(pvar).mkString(" ")` and `con.mkString(" ")`.

Scala 2.13 has two representations and they iterate differently:

* `EmptySet`, `Set1`..`Set4` (size ≤ 4) iterate in **insertion order**;
* `immutable.HashSet` (a CHAMP trie) iterates in a **canonical** order fixed by
  `Hashing.improve(x.##)`: at each node the data entries first, in increasing 5-bit index
  order, then the sub-nodes, in increasing index order.

A set becomes a `HashSet` when it grows past four, or when it is derived from one, and never
goes back. `SSet` is exactly that: a flag plus a list.

**Removal from a `HashSet` re-canonicalises the survivors** (L1 review, F1 — the model got
this wrong and it reached the trace). `BitmapIndexedSetNode.removed`
(`HashSet.scala:603`) INLINES a sub-node that drops to a single element into the parent as
DATA, and `foreach` emits all data before all sub-nodes, so that element MOVES FORWARD:

```scala
case 1 =>
  if (this.size == subNode.size) subNodeNew.asInstanceOf[BitmapIndexedSetNode[A]]
  else copyAndMigrateFromNodeToInline(bitpos, elementHash, subNode, subNodeNew)  // move to front
```

`HashSet.filterImpl` canonicalises the same way. So `-` and `filter` on a `HashSet` return the
CHAMP order of what is left, not the pre-removal order with holes; `SSet.excl` and
`SSet.filter` re-`champ` the survivors, and `inter` and `removedAll`, which are built from
them, inherit it. The tracked seeds missed this because their concrete parts have at most two
labels and their variable sets at most four, so no set of theirs is ever a `HashSet` with a
sub-node that a removal can collapse. `LBL.json` and `COLL.json` are the regression seeds
(§6e).

**One subtlety was found by the differential and is worth recording**, because it is invisible
to reading and it changed a trace. `Partition.equals` and `RHS.equals` IGNORE, respectively,
the `Inference` tag and the sets' iteration order — so two `equals`-equal partitions are
distinguishable in the trace, and *which representative a set keeps* is observable.
`+` keeps the element already present (left wins), and so does
`StrictOptimizedSetOps.concat`, which every `SetN` uses and which `HashSet.concat` falls back
to whenever `that` is not itself a `HashSet`. But `HashSet ++ HashSet` with a right operand of
two or more is a CHAMP bulk union, and at a trie slot where both sides carry the element as
DATA the RIGHT one overwrites the left (`HashSet.scala:1667`,
`leftDataRightDataLeftOverwrites`); where one side carries a SUBNODE the winner is whichever
side owns the node that `updated` is called on (`leftNodeRightData` keeps the LEFT,
`leftDataRightNode` keeps the RIGHT). `SSet.rightWins` is that walk. Before it was modelled,
NE6 at bases 0 and 8 disagreed with the compiler at one record — `destructiveSub`'s
`srs = subPartitions(v, rhs, …) ++ subPartitions(v, rhs_i, …)` had picked the `INPUT`-tagged
copy of `^free0 <- (, {l1,l2,l3,l4})` where the compiler picked the `Substitution`-tagged one.
With `rightWins` in place, all 60 traces became byte-identical.

`rightWins` also has to take **`concat`'s EARLY RETURN** (L1 review, F2). `HashSet.scala:1532`:

```scala
if ((newDataMap == (leftDataOnly | leftDataRightDataLeftOverwrites)) && (newNodeMap == leftNodeOnly)) {
  // nothing from `bm` will make it into the result -- return early
  return this
}
```

It fires at every level of the merge, not only the root, and returns the whole LEFT node, so
every one of its representatives survives.

There is a **SECOND** early return at the end of the same merge (`HashSet.scala:1686`) —
`if (anyChangesMadeSoFar) new BitmapIndexedSetNode(...) else this` — and
`leftDataRightDataLeftOverwrites` writes the right's payload into `newContent` WITHOUT setting
that flag. So when nothing at a node actually changes, the left node is again returned whole,
even at slots where both sides hold the element as data. The second condition strictly
subsumes the first: it also tolerates a `leftNodeRightNode` whose sub-merge changed nothing and
a `leftNodeRightData` whose element was already in the left sub-node — which is exactly the
"the right operand is contained in the left" case, the shape `destructiveSub`'s `srs` fold,
`makeConcrete`'s `rhss` and `makeEmpty`'s `qps ++ pps` produce.

`SSet.changed` is `anyChangesMadeSoFar`, transcribed arm by arm from the classification loop,
and `SSet.rightWins` tests it before its four-way dispatch; nothing else is needed, because the
first early return implies the second. No seed of this size reaches the case through
`looptrace` — it needs both operands of a `Set ++ Set` to be `HashSet`s, i.e. five or more
elements each, and in `learnPartitions` the right operand is at most three — but the reviewer
reproduced it against the JVM at the `SSet` level (76 of 639 unions built around the
containment boundary failed with the first early return alone; 0 of 639 with `changed`), and
L2's 1372-partition solves will reach it.

Not modelled here: **hash-collision nodes**. Two distinct elements whose `improve` hashes
agree in all 32 bits would go into a `HashCollisionSetNode`, which keeps insertion order;
the model keeps insertion order too, but only after seven 5-bit levels, so the two agree
except for elements that collide in the low 30 bits but not the top 2. No corpus seed
reaches that; a random 32-bit collision is what it sounds like.

---

## 5. Probing the JVM

Every constant the model needs was read off the JVM rather than guessed. The probe
programmes are in the job scratch (`Probe.scala` … `Probe6.scala`), compiled with the same
`dotty.tools.dotc.Main` invocation `tracker/repro/satterm/run.sh` uses and run against
`target/ermine-classpath` (`scala-library 2.13.18`). Every value below is now a `#guard` in
`Loop/Conformance.lean`, so a change that breaks the correspondence breaks the build.

```
"Repro".hashCode = 78848890      "l1".hashCode = 3397        "RHS".hashCode = 81117
MurmurHash3.productSeed = 0xcafebabe = -889275714
seqSeed = "Seq".hashCode = 83007  setSeed = "Set".hashCode = 83010
Set[Int]().hashCode          =  835491922
Set(1).hashCode              = -1075495872
Set(1,2).hashCode            = -2081538426
Set(1,2,3,7,9).hashCode      =  696780465
List().hashCode              =  473519988
List(5).hashCode             =  1669515522
List(1,2,3).hashCode         =  1836368899      <- takes listHash's arithmetic-RANGE branch
List(1..8).hashCode          = -159536971       <- likewise
Global("Repro","l1").hashCode=  2069000494  ==  (2,"Repro","l1",1).hashCode
RHS().hashCode               = -1285229852
RHS(Set(v1),Set()).hashCode  = -1065199571
RHS({v1,v2},{l1}).hashCode   = -1720534804
(v1, RHS()).hashCode         =  257672878       <- Partition.hashCode
VarT(v0).hashCode            =  0               <- the `Variable` trait: v.hashCode = id
ConcreteRho({l100}).hashCode =  1040573865      <- fields.hashCode * 111
Part(VarT(v0),[VarT(v2),ConcreteRho({l100})]).hashCode = 1723884977
```

and the iteration orders (`Probe.scala`, `Probe3.scala`):

```
Set(3,1,2)           Set3     3,1,2            <- insertion order
Set(3,1,2,4)         Set4     3,1,2,4
Set(3,1,2,4,5)       HashSet  5,1,2,3,4        <- CHAMP
(0 to 9).toSet       HashSet  0,5,1,6,9,2,7,3,8,4
(1000 to 1005).toSet HashSet  1005,1001,1002,1000,1003,1004
(0 to 40).toSet      HashSet  0,5,10,14,1,6,9,13,2,12,18,11,8,4,15,24,37,25,20,29,21,…
Set(3,1,2,4,5)-5     HashSet  1,2,3,4          <- representation survives the shrink
Set(1,2,3,4)--Set(1) Set3     2,3,4            <- and so does SetN's
Set(3,1,2)++Set(9,8) HashSet  1,9,2,3,8
Set(3,1,2)++Set(3,1) Set3     3,1,2            <- no growth, no promotion
Set(3,1,2,4,5).map(_/100) HashSet 0            <- a HashSet maps to a HashSet
```

`Hashing.improve` was confirmed by predicting all of these orders from the CHAMP rule and
matching every one (`Probe2.scala`): the jenkins mixer
`h = hcode + ~(hcode<<9); h ^= h>>>14; h += h<<4; h ^= h>>>10` reproduced 7/7 test sets, and
`scala.util.hashing.byteswap32` reproduced 0/7. The source was then read from
`scala-library-2.13.18-sources.jar` (`scala/collection/Hashing.scala:21`) and matches.

---

## 6. The differential

`tracker/tools/looptrace-diff.py` normalises both traces — keeps only the record types the
model produces (`step`, `learn`, `in`, `inpart`, `sat`, `solve`; drops `concr` and `splice`,
which `reduce` writes after the loop), drops the site column, and rewrites every variable id
to the position of its first occurrence — and then diffs record by record, reporting the
FIRST differing record on each side.

Compiler traces produced with the repro harness:

```bash
export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH
for s in W2 H2 NE6 W3 W4 G7; do for b in $(seq 0 9); do
  ERMINE_JAVA_OPTS="-Dermine.rowTrace=$D/scala-traces/$s-$b.tsv" \
    tracker/repro/satterm/run.sh trace json:tracker/repro/satterm/seeds/$s.json $b 20 1
done; done
```

Model traces:

```bash
cd tracker/lean
for s in W2 H2 NE6 W3 W4 G7; do for b in $(seq 0 9); do
  .lake/build/bin/looptrace ../repro/satterm/seeds/$s.json $b > $D/lean-traces/$s-$b.tsv
done; done
python3 ../tools/looptrace-diff.py --sweep --lean $D/lean-traces --scala $D/scala-traces
```

### 6a. The six tracked seeds, bases 0–9, shipped flags

| seed | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 |
|---|---|---|---|---|---|---|---|---|---|---|
| W2  | ok | ok | ok | ok | ok | ok | ok | ok | ok | ok |
| H2  | ok | ok | ok | ok | ok | ok | ok | ok | ok | ok |
| NE6 | ok | ok | ok | ok | ok | ok | ok | ok | ok | ok |
| W3  | ok | ok | ok | ok | ok | ok | ok | ok | ok | ok |
| W4  | ok | ok | ok | ok | ok | ok | ok | ok | ok | ok |
| G7  | ok | ok | ok | ok | ok | ok | ok | ok | ok | ok |

`all 60 comparisons agree`.

These 60 are also **byte-identical**, not merely normalised-equal: running the model with
`--site` set to the compiler's site string and comparing with `diff` against the compiler's
file restricted to the six record types gives *60 identical, 0 differing*. So the model
reproduces the branch names, the `Inference` tags, the `incm=`/`proc=` counts, the
`seen`/`new` classification of each learned partition, the printed variable ids, the SET
ITERATION ORDER inside every printed right-hand side, the saturated set and its order, and
every field of the `solve` line — including `byRule`.

### 6b. Extra evidence (not required by the acceptance criteria, run anyway)

| sweep | comparisons | result |
|---|---|---|
| 6 seeds × bases 10–29, shipped flags | 120 | all agree |
| 6 seeds × bases 0–9, `-Dermine.emptyRow=true` vs `--flags=emptyrow` | 60 | all agree |

The `emptyRow` sweep matters because it is the only way to reach the Stage 7 branches:
`SplitEmpty` fires 40 times across it and is otherwise dead.

### 6c. Rule coverage of the 180 shipped-flag comparisons

`Cancellation` 961, `SplitConcrete` 916, `Substitution` 647, `CommonSubexpression` 609,
`SplitKeyed` 214, `SplitRow` 104, `PartitionEmpty` 60, `Resolution` 46, `SelfSubstitution` 32,
`DeDuplication` 3; dispatch branches `learn` 947, `concrete` 302, `empty` 184, `common` 59,
`unify` 31. With `--flags=emptyrow`, `SplitEmpty` 40 more.

**Rules the six tracked seeds do not exercise.** Three of them are now covered by the
regression seeds added in §6e: `ResolutionRow` (`RR`, 8 firings), `ResolutionEmpty` (`RE`, 16),
and `CommonPartition` — the tag `Q.insert` attaches when `+!`'s reverse lookup turns an
insertion into a unification, distinct from the `common:` DISPATCH branch, which the tracked
seeds fire 59 times (`CHAIN`, 6 firings). `SelfSubstitution` and `DeDuplication`, which the
tracked seeds fire only rarely, are hit 93 and 82 times by the random fuzz. Two rules remain
modelled by reading only, both behind non-default flags: `CommonSubexpressionMint` (needs
`-Dermine.genRules=all`) and `Disjunction` (needs `-Dermine.disjunction=true`).

### 6d. Disagreements found and fixed during development (implementer)

Two, both real model bugs, both now fixed; recorded because the plan asks for the cause of
every disagreement.

1. **`RHS(Single(w), con)` is not `RHSAbstr(Single(u))`.** The model first used one
   `single?` for both. `RHSAbstr(Single(u))` — `incorporateAll`'s dispatch, `Q.rhsLookup` and
   `Partition.isSelfUnification` — requires the concrete part EMPTY; `RHS(Single(w), con)` —
   `learnPartitions`' `resolvents` fold and `resolution`'s premise — does not. Conflating
   them turned every keyed reuse into a mint; W2@0 diverged at its third record
   (`SplitKeyed: ^free2 <- (^free1 ^free2,)` became a `SplitConcrete` mint). Fixed by
   splitting `RHS.single?` from `RHS.abstrSingle?`.
2. **`HashSet ++ HashSet` keeps the RIGHT operand's representative.** §4. NE6 at bases 0 and
   8 diverged at one record each. Fixed by `SSet.rightWins`.

After both fixes: 0 disagreements in 240 comparisons.

### 6e. Disagreements found by the L1 review, and fixed

The review (`tracker/loopmodel/L1-REVIEW.md`, verdict FIX-THEN-ADVANCE) re-ran everything
above from scratch, added five id bases, built eleven seeds of its own aimed at the branches
§6c lists as untested, re-probed every JVM constant, differentially tested `SSet` against the
JVM at the operation level, and fuzzed 120 random systems. It reproduced §6a and found **two
more model bugs, both in `Loop/SSet.lean`, both invisible to reading**:

* **F1 — `SSet.excl` / `SSet.filter` did not model CHAMP sub-node INLINING.** §4. The
  docstring's claim that "removing an element from a CHAMP trie leaves the others in the same
  relative order" is false: a sub-node that drops to one element is inlined into the parent as
  data and MOVES FORWARD. Reproduced end to end on `LBL.json`, where `cancellation` removes
  `l3` from `{l3,l5,l6,l7,l8}` and inlines `l5`, and `Partition.toString` prints `con` raw:
  **5 of 5 bases differed**. Also 12 of 400 random JVM-vs-model `Set`-operation comparisons.
  Fixed by re-`champ`ing the survivors of a `HashSet`.
* **F2 — `SSet.rightWins` missed `concat`'s early returns.** §4. Confirmed against the JVM at
  the `SSet` level (3 of 840 random `HashSet ++ HashSet` unions), not reachable through a seed
  of this size, but reachable in L2. Fixed in two rounds. The first modelled `HashSet.scala:1532`
  only; the **re-review** then showed that `BitmapIndexedSetNode.concat` has a SECOND early
  return at `:1686` — `if (anyChangesMadeSoFar) … else this`, which
  `leftDataRightDataLeftOverwrites` does not trip — and that it is the one that fires when the
  right operand is CONTAINED in the left: a fresh 639-case JVM probe engineered around that
  boundary still failed 76 times (57 of 172 in the plain `T ⊆ S` mode). `SSet.changed` is now
  `anyChangesMadeSoFar` transcribed arm by arm, and subsumes the `:1532` condition; the same
  639 cases and every earlier capture now agree.

All fixes verified: **`LBL.json` 5/5 byte-identical**, the whole trace sweep still agrees, and
every `SSet`-level differential the review built now agrees completely — random operations
**400/400** (was 388/400), `concat` **300/300** (was 298/300), unions **540/540** (was
539/540), adversarial removals **693/693**, and adversarial unions around the containment
boundary **639/639** (was 563/639). The five hand-built `HashSet ++ HashSet` cases (right wins
at data/data, `bm.size == 1` keeps the left, a right sub-node over left data, an empty left)
reproduce the JVM.

**New tracked regression seeds.** Eleven of the reviewer's seeds are now in
`tracker/repro/satterm/seeds/`, because each reaches something no tracked seed did:
`LBL` and `COLL` (F1's CHAMP sub-node inlining, from `cancellation`'s `con1 -- conInt` and
from `makeEmpty` erasing a variable from a six-variable right-hand side); `RR`
(`ResolutionRow`, 8 firings); `RE` (`ResolutionEmpty`, 16 firings, needs `--flags=emptyrow` /
`-Dermine.emptyRow=true`); `CHAIN` (the queue-level `CommonPartition` redirect, 6 firings, and
a ten-deep `Graph.dfs`); `REF` and `SUP` (refutation by the early `labelClash`, which emits no
trace records at all); and `D1`–`D4` (the four `die` paths — `selfSubstitution`, `RHS.merge`,
`makeEmpty`'s `aux`, `ensureSuperset` — which need `--flags=nolabel` /
`-Dermine.labelCheck=false`).

### 6f. Totals after the review fixes

| sweep | comparisons | how compared | result |
|---|---|---|---|
| tracked seeds × bases 0–9, shipped flags | 60 | byte | agree |
| tracked seeds × bases 10–29, shipped flags | 120 | normalised | agree |
| tracked seeds × bases 0–9, `emptyRow` | 60 | normalised | agree |
| `RR CSE CP KD UC REF SUP RE` × bases 0–14, shipped | 120 | byte | agree |
| `RE RR CSE KD` × bases 0–14, `emptyRow` | 60 | byte | agree |
| `CP2 BIG CHAIN` × bases 0–14, shipped | 45 | byte | agree |
| `D1`–`D4` × bases 0,3, `labelCheck` off | 8 | byte | agree |
| `COLL` × bases 17–29 | 13 | byte | agree |
| `LBL` × bases 0–4 | 5 | byte | agree (**5/5 differed before F1**) |
| 120 random `rowclosure.py` systems × bases 0,13,24 | 360 | byte | agree (7,927 records) |
| 150 colliding-label `rowclosure.py` systems × bases 0,24,36 | 450 | byte | agree (10,946 records; 573 print a concrete part of five or more labels, 601 print a label list that is not ascending — so the label sets really are `HashSet`s with sub-nodes) |
| **trace total** | **1301** | 1121 byte-identical | **0 differing** |
| rejection messages, `REF SUP D1`–`D4` | 18 | text, after the harness's own `short()` | 16 identical; the 2 `D4` cases are the declared `ensureSuperset` abstraction (§7) |
| JVM vs model, random `Set` operations | 400 | element-by-element | 0 differing |
| JVM vs model, `Set ++ Set` with tagged elements | 300 | element-by-element | 0 differing |
| JVM vs model, `HashSet ++ HashSet` | 540 | element-by-element | 0 differing |
| JVM vs model, adversarial removals (sets of 5–18 over key ranges 30/60/120, dense in level-0 collisions) | 693 | element-by-element | 0 differing |
| JVM vs model, adversarial unions around the `T ⊆ S` containment boundary | 639 | element-by-element | 0 differing (**76 differing** before the `:1686` early return was modelled) |
| **`SSet`-level total** | **2572** | | **0 differing** |

---

## 7. What is NOT modelled, and why it does not matter for L1

| not modelled | why | does it show? |
|---|---|---|
| `Subst.reduce` (and its `concr`/`splice` records) | L1's scope is the LOOP. `reduce` runs after `q.expand` returns, and the `solve` record is written before it. | Yes, in `--verdict` only: the compiler reports more BOUND variables. The difference is **exactly** the number of `concr` records: NE6@0 lean bound=1 + 4 concr = compiler bound=5; W3 0+2=2; W4 0+3=3; G7 4+1=5. `drawn` (ids taken from the `Supply`) agrees exactly on every seed and base checked. |
| `makeEmpty`'s `v.ty == Skolem` refusal | a seed variable is `Free` and a mint is `Ambiguous(Free)`; a skolem reaches `incorporateAll` only from type CHECKING, never from a `json:` seed | no |
| `ensureSuperset`'s message | the Scala renders a two-row `Document` with `displayFactoredRow`; the model reports the same failure with a flat message | no — no tracked seed reaches it |
| `Located`/`Loc`, `sourcePosition`, the `labelClash` blame search | the model has one location, `-`, which is what `Loc.builtin` prints | no — the trace's location column is `-` on both sides |
| `Q.heapify` | it re-measures the finger tree without changing its ORDER, and the model stores no measures | no |
| `TypeVarGraph.rename`, `Q.substSet`, `Constraints.simpleSubst`, `PQueue.vars` | DEAD: `rename`/`substSet`/`simpleSubst` have no call site anywhere in `core/src/main`; `vars` is only `toType`'s | no |
| `Constraints.combine` (1103), `Q.PQueue.build(v, t)` (645), `PQueue.toType` (624), `RHS.toTypes` | DEAD as well — all four are called from NOWHERE in `core/src/main` (corrected after the L1 review, F4: an earlier draft said `combine` and `build(v,t)` were "reached from `Subst.unifyRow`" and `toType` was "`reduce`'s"; the conclusion — not reached from `solve` — was right, the reason was not) | no |
| `Part.apply` (the smart constructor) | the repro harness builds raw `new Part`, deliberately, so the rhs list order is exactly as written | no |
| `hm.types` ITERATION order in `envEmptyRow` | `collectFirst` walks a `Map`; the model takes the first binding in insertion order | no: the empty-row branches do not mention the carrier they find, so which one it is cannot reach the output. Verified empirically by the `--flags=emptyrow` sweep. |
| ~~`labelClash`'s label ITERATION order~~ — NOT an abstraction | `labels.view.flatMap(...).headOption` walks a `Set[Name]`, which is an `SSet` in the model, so the model DOES compute the order. Listed here in an earlier draft out of caution; the L1 review checked it: its `SUP` seed reports a different reason string at base 3 from bases 0,1,2,4 and the model matches base for base | no |
| CHAMP hash-collision nodes | §4 | no |
| `Map` iteration order for `edges`, `sort`, `resolvents`, `concRows` | only `get` and `+` are used on them | no |
| `RowTrace.clean`'s tab/newline escaping | no label or variable name in a seed contains a tab | no |
| **`V.ty`: `Names.pvar` INFERS it from the id** — `Loop/State.lean`'s `pvar v = if v < supplyLo then "^free" ++ v else "^ambiguous(free)" ++ v` | exact for a `json:` seed, where the repro harness makes every input variable `Free` and every mint `Ambiguous(Free)` with ids from `supplyLo` up | **no for L1, and an L2 BLOCKER.** In the corpus `Partition.toString`'s `pvar` prints `v.ty.toString.toLowerCase`, and `ty` can be `Skolem`, `Bound`, `Unspecified`, `Ambiguous(Skolem)` … with no relation to the id, so every `step`/`learn` record of a corpus solve involving such a variable would differ. L2 must carry the real `ty` per variable in the seed format before it can diff the corpus. (L1 review, F7.) |

---

## 8. Scala → Lean correspondence

Every function `incorporateAll` reaches. `exact` means transcribed branch for branch with the
same evaluation order and the same `Set` construction order.

### `Constraints.scala` — the loop

| Scala | Lean | faithfulness |
|---|---|---|
| `incorporateAll` (1109) | `Loop.step`, `Loop.run` | exact; the Scala's tail recursion becomes `run` with an explicit fuel |
| `stepLog` (inner) | `step`'s `stepLog` | exact, including `rest.size` / `proc.size` |
| the `learn` record loop | `step`'s `learned.elems.foldl` | exact, including `seen`/`new` tested against the ORIGINAL `proc` |
| `learnPartitions` (1355) | `learnPartitions` | exact: `splitConcrete` as the fold's initial value, then one pass over `proc`, threading the supply |
| `resolvents` / `findResolvent` | `mkLookups`, `findResolvent` | exact: `proc` then `incm`, later writes winning; batch consulted first |
| `concRows` / `findConcRow` | `mkLookups`, `findConcRow` | exact, including the explicit `k ⊆ C` |
| `envEmptyRow` / `findEmptyRow` | `findEmptyRow` | abstracted: `Map` iteration order (§7) |
| `noConcRow` | the `if flag then … else none` guards | exact |
| `selfSubstitution` (1156) | `selfSubstitution` | exact |
| `splitConcrete` (1301) | `splitConcrete` | exact, all five branches, `fresh` only in the last |
| `cancellation` (1667) | `cancellation` | exact |
| `resolution` (1758) | `resolution` | exact, all four branches; `fresh` drawn once per call that reaches the lone-variable pattern, BEFORE the branches |
| `subBody` (1807), `substitution` (1821) | `subBody`, `substitution` | exact |
| `commonSubexpression` (1834) | `commonSubexpression` | exact, incl. the two folding branches and the cut mint |
| `disjunction` (1867) | `disjunction` | exact; flag off, never called on these seeds |
| `unify` (1520) | `unifyVars` | exact |
| `replace` (1523) | `replace` | exact, incl. the two-element `PQueue` and its key ordering |
| `instantiate` (1533) | `instantiate` | exact, incl. `nps = pps ++ qps` and the fold into `nincm` |
| `makeEmpty` (1561) | `makeEmpty` | exact except the skolem check (§7) |
| `subPartitions` (1588) | `subPartitions` | exact: `proc` first, then `incm` minus `v`'s own definitions |
| `makeConcrete` (1600) | `makeConcrete` | exact, incl. `rhss`, `ensureSuperset`, `can`, `nproc + Partition(v, RHSConcr(fs))` with `inf = none` |
| `destructiveSub` (1622) | `destructiveSub` | exact, incl. `srs`, `keep`, `keepDefs` and the `abs.size ≥ 2` filter |
| `ensureSuperset` (312) | `ensureSuperset` | abstracted message (§7) |
| `trim` (1084) | `trim` | exact |
| `findRHS(ps, cs, s)` (1087) | `findRHS3` | exact: `cs`, then `ps`, then the batch |
| `ruleInvolves` (1081) | `LPart.involves` | exact |
| `combine` (1103) | — | not modelled (§7) |
| `labelClash` (1929) / `checkLabel` (1936) | `labelClash` / `checkLabel` | exact fixpoint; label order abstracted (§7); bounded by `#partitions + 2` |
| `GenRules` (763) | `Flags` | exact, all nine switches, shipped defaults |
| `Inference` (680–1044) | `Inference` | exact, all 16 tags and their `toString` |
| `displayRHS`, `displayFields`, `displayFactoredRow` | — | error rendering only |

### `Constraints.scala` — `Q`, the queue

| Scala | Lean | faithfulness |
|---|---|---|
| `Q.PSQK`, `Q.pr` (the Reducer) | `PQueue.keyOf`, `Graph.prio` | exact; the measure's monoid is what makes the tree a search tree, which the model represents as a sorted list |
| `Q.part` | `PQueue.insertSorted`, `contains`, `findRHS` | exact: a split on the last-element key over a key-sorted tree is a list position |
| `Q.rhsLookup` | `PQueue.rhsLookup` | exact, incl. the two exclusions and "first in the block" |
| `Q.insert(process=false)` / `PQueue.+` | `PQueue.insertNP` | exact, incl. `isSelfUnification`, the already-present test, and `sandwich`'s front-of-block position |
| `Q.insert(process=true)` / `PQueue.+!` | `PQueue.insertP` | exact, incl. the `CommonPartition` redirect that does NOT extend the graph |
| `Q.pop` / `PQueue.dequeue` | `PQueue.dequeue` | exact (§3) |
| `Q.heapify` | — | order-preserving (§7) |
| `PQueue.filter` | `PQueue.filter` | exact |
| `PQueue.partition` | `PQueue.partition` | exact — the Scala folds from the RIGHT, so the returned `Set` receives the matching partitions in reverse queue order, which is their insertion order |
| `PQueue.findRHS` | `PQueue.findRHS` | exact |
| `PQueue.contains`, `size`, `isEmpty`, `foldLeft`, `foldRight`, `foreach` | the corresponding `PQueue`/`List` operations | exact |
| `PQueue.++`, `++!` | `concatNP`, `concatP` | exact |
| `PQueue.apply(ps)` | `PQueue.ofList` | exact |
| `PQueue.build(t)` (aux) | `buildQueue`, `partToPartitions` | exact, incl. the non-variable-lhs mint |
| `PQueue.build(v, t)` | — | not modelled (§7) |
| `PQueue.expand` | `solveSeed`'s `run st0 fuel` | exact |
| `PQueue.toType`, `PQueue.vars` | — | `reduce`'s (§7) |
| `TypeVarGraph.+` | `Graph.add`, `Graph.addPart` | exact, incl. the "sort still valid" short-circuit |
| `TypeVarGraph.empty` | `Graph.empty` | exact |
| `TypeVarGraph.rename`, `Q.substSet` | — | dead code (§7) |
| `StreamTUtils.reverseTopSort` | `Graph.reverseTopSort`, `Graph.dfs` | exact: the explicit stack machine is post-order DFS with marking on entry; depth fuel `#nodes + 1` |
| `indexMap` | `withIndex` | exact |

### `Constraints.scala` — `RHS`, `Partition`

| Scala | Lean | faithfulness |
|---|---|---|
| `RHS` (case class), `equals`, `hashCode` | `RHS`, `RHS.eqv`, `RHS.hshOf` | exact |
| `RHS.merge`, `RHS.substitute` | `rhsMerge`, `rhsSubstitute` | exact, incl. the returned duplicate set |
| `RHS.-`, `contains`, `isEmpty`, `isConcrete` | `RHS.erase`, `contains`, `isEmpty`, `isConcrete` | exact |
| `RHS.build` (381) | `rhsBuild` | exact, incl. the twice-occurring-variable case |
| `RHSEmpty` / `RHSAbstr` / `RHSConcr` / `Single` | `RHS.isEmpty` / `RHS.single?` / `RHS.abstr.isEmpty` / `SSet.single?` | exact — and `RHS.abstrSingle?` for the `RHS(Single(w), con)` pattern, which is a DIFFERENT pattern (§6d) |
| `Partition` `equals` / `hashCode` / `toString` / `isSelfUnification` | `LPart.eqv` / `hshOf` / `toStr` / `isSelfUnification` | exact, incl. `pvar`'s `ty.toString.toLowerCase` |
| `RHS.vars`, `RHS.toTypes` | — | `reduce`'s (§7) |

### `Subst.scala`

| Scala | Lean | faithfulness |
|---|---|---|
| `solve` up to and including the `solve` record | `solveSeed` | exact |
| `unbindExists` | — | identity for a seed's `Exists` with no bound variables |
| `checkLabels` (the `labelCheckEarly` position) | `solveSeed`'s `early` / `late` | exact position; blame not modelled (§7) |
| `SubstEnv.types` | `Env` | exact for the two shapes the loop writes |
| `instantiateType` | `Env.instantiate` | exact, incl. the "keep the map fully substituted" rewrite and the reinstantiation panic |
| `substType` | `Env.lookup` | exact for those shapes |
| `reduce` | — | not modelled (§7) |
| `RowTrace.{log, site, withSite, clean}` | `State.trace`, `State.site` | exact but for `clean` (§7) |
| `fresh` / `Supply.fresh` (`ermine.scala:68`, `Supply.scala:22`) | `State.su` | exact — `drawn` agrees on every seed and base checked |

### `Type.scala`, `Vars.scala`, `Name.scala`

| Scala | Lean | faithfulness |
|---|---|---|
| `Exists.apply` (295) | `existsApply` | exact: reverse, then `toSet.toList` |
| `Exists.mk` (311) | folded into `existsApply` | exact when `xs = []`, which is the case here |
| `Type.nf` / `Exists.nfWith` | the second `existsApply` | exact — `Part` does not override `nfWith`, so `Part.nf = Part` |
| `Part.hashCode`, `Part.equals` | `IPart.hshOf`, `IPart.eqv` | exact |
| `VarT.hashCode` (the `Variable` trait, `Vars.scala:143`) | `ITerm.hshOf` | exact: `v.hashCode = id` |
| `ConcreteRho.hashCode` | `ITerm.hshOf` | exact: `fields.hashCode * 111` |
| `Part.apply` (the smart constructor) | — | not reached (§7) |
| `V.equals`, `V.hashCode`, `V.toString` | `Nat` equality, identity hash, `varStr` | exact |
| `Global.hashCode`, `Global.toString`, `Idfix.con` | `Lbl.hshOf`, `Lbl.toStr` | exact for `Global("Repro", "l"++n, Idfix)`, which is every label a seed has |

### The Scala library

| Scala | Lean | faithfulness |
|---|---|---|
| `MurmurHash3.{mix, mixLast, avalanche, finalizeHash, productHash, unorderedHash, setHash, listHash, seqHash, rangeHash}` | `Murmur.*` | exact, transcribed from the 2.13.18 sources; 12 `#guard`s |
| `Hashing.improve` | `improve` | exact; 12 order `#guard`s |
| `java.lang.String.hashCode` | `javaStringHash` | exact |
| `immutable.Set` (`SetN` / `HashSet`) | `SSet` | exact but for collision nodes (§4); 21 `#guard`s |
| `BitmapIndexedSetNode.removed` / `HashSet.filterImpl` sub-node INLINING | `SSet.excl`, `SSet.filter` (hence `inter`, `removedAll`) | exact: the survivors of a `HashSet` are re-`champ`ed, which is what the inlining canonicalises to (§4). Corrected after the L1 review, F1 |
| `HashSet.concat`'s union-representative rule, INCLUDING BOTH early returns at every level — "nothing from `bm` will make it into the result" (`:1532`) and `if (anyChangesMadeSoFar) … else this` (`:1686`) | `SSet.rightWins`, `SSet.changed` | exact for `BitmapIndexedSetNode` (§4). `changed` is `anyChangesMadeSoFar` arm by arm and subsumes the `:1532` condition. Added after the L1 review and completed after the re-review, F2 |
| `scalaz.FingerTree` | `PQueue.elems` | exact in ORDER; measures not stored (§3) |
| `scalaz.Order[Int]`, `Order[Option[A]]` | `PQueue.keyLt` over `I32.toSigned` | exact |
| `scala.collection.immutable.Map` | association lists | exact for `get` and `+` (§7) |

---

## 9. The bridge to `Rowpartition.Constraint`

The plan requires the two vocabularies to meet, because L3's refinement proofs need it.
`Loop/Bridge.lean`:

* `LPart.toConstraint p = Rowpartition.mk p.lhs (abstr as a Finset) (conc as a Finset)` and
  `LPart.ofConstraint`, both total;
* `LPart.toConstraint_ofConstraint : (ofConstraint (mk a S k)).toConstraint = mk a S k` —
  `ofConstraint` is a section on every `mk`-form constraint, which is every constraint the
  relational development builds;
* `LPart.toConstraint_eq_iff` — the constraints agree exactly when the left-hand variables and
  the two underlying finite sets do;
* `LPart.eqv_iff_toConstraint` — **the model's own notion of partition equality is equality of
  the constraints**, for duplicate-free partitions. `LPart.eqv` is `Partition.equals`, which
  is what the queue's `insert` and every `Set[Partition]` compare with, and it ignores the
  `Inference` tag and both sets' iteration order — exactly the data `toConstraint` forgets.

To state that honestly the file first proves that an `SSet` really is a set:

* `SSet.champSort_perm : (champSort d shift xs).Perm xs` — the CHAMP order is a permutation.
  Proved from two general bucket lemmas, `flatten_map_range_update` and
  `flatten_buckets_perm`, with `champMask_lt` supplying "every key is below 32";
* `LawfulSVal` — the class saying `equals` decides equality, instantiated for row variables and
  labels and deliberately NOT for `RHS`/`LPart`;
* `SSet.nodup_{empty, incl, excl, filter, ofList, map, concat, removedAll, inter}` — every
  operation the loop performs preserves duplicate-freeness, including `concat`'s CHAMP branch
  (where the substituted representative is provably EQUAL to the one it replaces);
* `SSet.eqv_iff_toFinset` — for duplicate-free sets, Scala's `size == that.size && subsetOf`
  is equality of the underlying finite sets.

---

## 10. Open items for L2

1. **`Subst.reduce`.** L2 diffs every solve of the corpus; `reduce` writes `concr` and
   `splice` records after each. Either the diff keeps ignoring them (and the model's
   `--verdict` stays a statement about the loop only, as quantified in §7), or `reduce` is
   modelled too. The second is a bigger job than it looks — `reduce` splices partitions drawn
   from the SATURATED queue into the committed output.
2. **Getting the corpus's inputs.** The `in`/`inpart` records already contain the input
   system, but not the id base or the `Supply` start, and `solve` is called from four sites.
   Either extend `RowTrace` with an `su` record or reconstruct the base from `inpart`.
   The model's `solveSeed` takes `(parts, names, supplyLo)` directly, so the seed format is
   the only adapter needed.
3. **Branches no seed reaches.** `ResolutionRow`, `ResolutionEmpty` and the queue-level
   `CommonPartition` redirect now have regression seeds (§6e). What is still modelled by
   reading only is `CommonSubexpressionMint` (needs `-Dermine.genRules=all`) and `Disjunction`
   (needs `-Dermine.disjunction=true`); neither can be reached at the shipped defaults, so L2
   should run at least one flag-variant sweep.
4. **Errors.** All four `die` paths and the early `labelClash` refutation now have regression
   seeds (`D1`–`D4`, `REF`, `SUP`, §6e), and 16 of their 18 messages match the compiler's
   character for character; the two that do not are `ensureSuperset`'s, which §7 declares
   abstracted. The corpus's `shouldfail/` modules will exercise them at scale; the diff will
   need to compare the message, or to compare only "rejected at all", and `ensureSuperset`'s
   `displayFactoredRow` will have to be modelled if the former.
5. **Performance.** The model is a list-based transcription: `PQueue.insertSorted` is linear,
   `Graph.dfs` appends to the output list. Fine at the seeds' sizes (a whole 30-record trace
   is instant); a 1372-partition corpus solve may not be. If it bites, the fix is a better
   data structure behind the same `dequeue` rule, with the rule itself as the specification.
6. **Set-collision nodes.** §4. Cheap to add if a corpus solve ever produces two partitions
   whose `improve`d hashes agree in 32 bits; nothing does today.
