# L1 review — trust nothing you have not re-run

Reviewer agent, 2026-09-04. **Verdict: FIX-THEN-ADVANCE** (two confirmed model bugs, both in
`Loop/SSet.lean`, both with a concrete fix; everything else in the stage stands).

**Summary.** All four acceptance criteria PASS on my own re-run. I rebuilt and re-audited,
re-ran the implementer's whole differential from scratch, added five id bases it never tried,
built eleven seeds of my own for the branches the report itself lists as untested, re-probed
every JVM constant the model depends on, and fuzzed 120 random systems. **696 of 701 trace comparisons
agree, and 691 of them byte-identically.** The five that are not are one seed I constructed to attack
the one modelling claim that reading alone could not settle — and it is wrong:
`SSet.excl`/`filter` do not model CHAMP sub-node inlining (F1), and `SSet.rightWins` misses
`concat`'s early return (F2).

**Reproducing F1** (the end-to-end divergence), from the repo root:

```bash
cat > /tmp/LBL.json <<'JSON'
{"rho": {"0":[3,5,6,7,8], "1":[5,6,7,8], "2":[5,6,7,8]},
 "cons": [[0,[1],[3,5,6,7,8]], [0,[2],[3]]]}
JSON
export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH
ERMINE_JAVA_OPTS=-Dermine.rowTrace=/tmp/LBL.tsv \
  tracker/repro/satterm/run.sh trace json:/tmp/LBL.json 0 20 1
(cd tracker/lean && .lake/build/bin/looptrace /tmp/LBL.json 0 --site='json:/tmp/LBL.json@0') \
  > /tmp/LBL.lean.tsv
diff /tmp/LBL.lean.tsv <(grep -E '^(step|learn|in|inpart|sat|solve)\b' /tmp/LBL.tsv)
```

## Step 1 — rebuild and re-audit (DONE)

```
cd tracker/lean && export PATH=$HOME/.elan/bin:$PATH
lake build Rowpartition   -> Build completed successfully (832 jobs).   exit 0
lake env lean Audit.lean  -> Rowpartition theorems audited: 2508; declarations using a non-standard axiom: 0
lake build looptrace      -> Build completed successfully (22 jobs).    exit 0
```

Greps over `Rowpartition/Loop.lean` + `Rowpartition/Loop/`: no `sorry`, `Classical`, `partial`,
`axiom`, `unsafe`, `native_decide`, `opaque`, `implemented_by`, `extern`. The only hits for
`partial`/`Classical` are the two prose lines in `Step.lean:11` and `Step.lean:350`.
CONFIRMED as reported.

(rest pending)

## Step 2 — re-running the implementer's evidence, and more

Compiler traces regenerated from scratch (nothing reused from the implementer's scratch):

```
export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH
for s in W2 H2 NE6 W3 W4 G7; do for b in 0..9 30..34; do
  ERMINE_JAVA_OPTS="-Dermine.rowTrace=$D/scala-traces/$s-$b.tsv" \
    tracker/repro/satterm/run.sh trace json:tracker/repro/satterm/seeds/$s.json $b 20 1
done; done
cd tracker/lean; for ...; do .lake/build/bin/looptrace ../repro/satterm/seeds/$s.json $b > ...; done
python3 ../tools/looptrace-diff.py --sweep --lean $D/lean-traces --scala $D/scala-traces --bases 0-9
```

| sweep | comparisons | result |
|---|---|---|
| 6 seeds x bases 0-9 (the report's own claim) | 60 | **all agree** — reproduced |
| 6 seeds x bases 30-34 (reviewer's extra, never run by the implementer) | 30 | **all agree** |
| byte-identity of all 90 (`--site=...` vs the compiler file grepped to the six record types) | 90 | **90 identical, 0 differing** |

So §6a of the report is CONFIRMED and extends to five bases the implementer never tried.

(rest pending)

### Seeds of the reviewer's own construction

Eleven new seeds in the repro-harness `json:` format (scratch:
`/home/dmitry/.claude/jobs/880c725d/tmp/review-L1/seeds/`), aimed at branches the report's
§6c marks "modelled by reading only" or otherwise untested:

| seed | what it aims at | reached? |
|---|---|---|
| `RR` | `ResolutionRow` — `resRow`'s concrete-row reuse | YES, 2 firings (bases 5 and 20 of the base probe; 0-14 sweep) |
| `RE` | `ResolutionEmpty` under `emptyRow` | YES, 8 firings under `-Dermine.emptyRow=true` / `--flags=emptyrow` |
| `CSE` | `commonSubexpression`'s REUSE branch | YES, 95 `CommonSubexpression` firings |
| `CP`, `CP2` | the queue-level `CommonPartition` redirect in `Q.insert(process=true)` | CP/CP2 only reached the `common:` dispatch; `CHAIN` reached the redirect |
| `CHAIN` | a ten-deep variable graph (`Graph.dfs` recursion depth) — and, unplanned, **the `CommonPartition` redirect**: 6 firings | YES |
| `KD` | `makeConcrete` -> `destructiveSub` with `keepDefs` (a two-abstract definition survives) | YES |
| `UC` | a `unify:` chain of four | YES, 15 `unify` steps over the sweep |
| `BIG` | seven input constraints (so `Exists.apply`'s `toSet` really is a CHAMP `HashSet`, not a `SetN`) and a six-variable right-hand side (so `Partition.toString` and the edge sets are CHAMP-ordered) | YES |
| `REF`, `SUP` | refutation by the early `labelClash` | YES |
| `D1`..`D4` | the four `die` paths: `selfSubstitution`, `RHS.merge`, `makeEmpty`'s `aux`, `ensureSuperset` (all with `labelCheck` off) | YES |

Results:

| sweep | comparisons | result |
|---|---|---|
| `RR,CSE,CP,KD,UC,REF,SUP,RE` x bases 0-14, shipped flags | 120 | all agree |
| `RE,RR,CSE,KD` x bases 0-14, `emptyRow` on both sides | 60 | all agree |
| `CP2,BIG,CHAIN` x bases 0-14 | 45 | all agree |
| byte-identity of all 165 above (`--site=` vs the compiler file) | 165 | **165 identical, 0 differing** |
| `D1`..`D4` x bases 0,3 with `labelCheck` off, byte-identity of the records written before the death | 8 | 8 identical |

`CommonPartition` firings: compiler 6, model 6 (`CHAIN`). Refutation messages compared
separately (the harness's own `short()` strips the `Repro.` qualifier from the compiler's
side, so `l1` vs `Repro.l1` is the harness, not the model):

* `REF`/`SUP`: identical, including SUP@3 choosing a *different* reason string
  ("the whole contains it but no part does") from SUP@0/1/2/4 — so `checkLabel`'s
  propagation order is modelled, not just its verdict;
* `D1` `Infinite row partition for 'v0^0'`, `D2` `Fields appear twice in row: Set(l1)`,
  `D3` `Incompatible instantiations of 'v0^0'`: identical;
* `D4` `ensureSuperset`: compiler `Row types failed to unify:  R1 =    l2 R2 =    l1 R1 R2`,
  model `Row types failed to unify: R1 = Set(Repro.l2) R2 = Set(Repro.l1)`. **Different, and
  this is exactly the abstraction the report declares in §7** (`displayFactoredRow` and the
  two `Located.report` lines are not modelled). CONFIRMED as declared scope, not a defect.

(rest pending)

## Step 3 — reading the correspondence table against the Scala

I opened every function `incorporateAll` reaches and compared it with its Lean definition.
The dispatch, the queue, the rules, `makeEmpty`/`makeConcrete`/`destructiveSub`/`unify`,
`learnPartitions`' three lookups, `Subst.solve`'s wrapper and `checkLabel` are faithful; the
details I checked and agree with are listed in §"Rows checked and confirmed" below. Two rows
of §8 are WRONG, both in `Loop/SSet.lean`, and both are confirmed against the JVM.

## FINDINGS

### F1 — CONFIRMED, HIGH. `SSet.excl` / `SSet.filter` do not model CHAMP subnode INLINING, so a removal from a `HashSet` leaves the survivors in the wrong iteration order

`tracker/lean/Rowpartition/Loop/SSet.lean:88-91` (`excl`) and `:135-136` (`filter`), hence
`inter` (`:139`) and `removedAll` (`:133`).

The docstring claims "removing an element from a CHAMP trie leaves the others in the same
relative order", and both functions are a plain `List.filter` that keeps `s.hashed`. That is
false. `scala/collection/immutable/HashSet.scala:603 BitmapIndexedSetNode.removed` has

```scala
case 1 =>
  if (this.size == subNode.size) subNodeNew.asInstanceOf[BitmapIndexedSetNode[A]]
  // inline value (move to front)
  else copyAndMigrateFromNodeToInline(bitpos, elementHash, subNode, subNodeNew)
```

— when a removal leaves a sub-node holding ONE element, that element is INLINED into the
parent as data, and `foreach` emits all data before all sub-nodes, so it MOVES FORWARD. The
same canonicalisation happens in `filterImpl`. The real result is always the canonical CHAMP
order of the survivors; the model's is the pre-removal order with holes.

**Reproduced end to end, through the solver**, with `LBL.json` (scratch `seeds/LBL.json`):

```json
{"rho": {"0":[3,5,6,7,8], "1":[5,6,7,8], "2":[5,6,7,8]},
 "cons": [[0,[1],[3,5,6,7,8]], [0,[2],[3]]]}
```

`Repro.l3` and `Repro.l5` share a level-0 trie slot, so `{l3,l5,l6,l7,l8}` has a sub-node;
`cancellation`'s `con1 -- conInt` removes `l3`, which inlines `l5`. `Partition.toString`
prints `con.mkString(" ")` RAW (unlike `abs`, which goes through `map` and is re-champed), so
the divergence reaches the trace directly:

```
compiler: learn ... new  Cancellation: ^free2 <- (^free1,Repro.l8 Repro.l6 Repro.l5 Repro.l7)
model   : learn ... new  Cancellation: ^free2 <- (^free1,Repro.l8 Repro.l6 Repro.l7 Repro.l5)
```

at bases 0, 1, 2, 3 and 4 — **5 of 5 bases differ**, in both the `learn` and the following
`step` record.

Rate, measured on 400 random JVM-vs-model op comparisons (`RevProbe5.scala` + `RevOps.lean`
in the scratch; every input-set construction agreed, so the model's `ofList`/`incl`/`champ`
are right): `filter` **10/76 wrong**, `excl` 1/80, `removedAll` 1/70, `inter` 0/85, `map` 0/89.

**Fix**: re-champ the survivors when the representation is a `HashSet` —

```lean
def excl (s : SSet α) (x : α) : SSet α :=
  let ys := s.elems.filter (fun y => !SVal.eq x y)
  if s.hashed then ⟨true, champ ys⟩ else ⟨false, ys⟩
-- and the same for `filter`
```

Verified: re-champing the survivors reproduces the JVM answer in **12 of the 12** failing
random cases, and gives exactly `Repro.l8 Repro.l6 Repro.l5 Repro.l7` on the `LBL` repro.
(`Bridge.lean`'s `nodup_excl`/`nodup_filter` still go through — `champ` is a permutation by
`champSort_perm`, which is already proved.)

Why the six tracked seeds missed it: their concrete parts have at most two labels and their
variable sets at most four, so no set is ever a `HashSet` with a sub-node that a removal
collapses.

### F2 — CONFIRMED at the `SSet` level, PLAUSIBLE at the trace level, MEDIUM. `SSet.rightWins` misses `BitmapIndexedSetNode.concat`'s "nothing from `bm` will make it into the result" early return, so `HashSet ++ HashSet` picks the wrong REPRESENTATIVE when the right operand is already contained in the left

`tracker/lean/Rowpartition/Loop/SSet.lean:103-130`.

`HashSet.scala:1532`:

```scala
if ((newDataMap == (leftDataOnly | leftDataRightDataLeftOverwrites)) && (newNodeMap == leftNodeOnly)) {
  // nothing from `bm` will make it into the result -- return early
  return this
}
```

It fires at EVERY level of the recursive merge, not just the root: when every slot the right
node occupies is a data slot that the left also holds as data with an EQUAL payload, the whole
LEFT node is returned and every one of its representatives survives. `rightWins` has no such
case: it goes straight to "both data ⇒ right wins".

Reproduced against the JVM (`RevProbe6.scala` + `RevUnion.lean`, 540 unions of two directly
built `HashSet`s of size 5-14 over 25 keys; all 540 input constructions agreed):

```
ks1=2,9,23,19,4,21,6,20,24,22,11,7,13   ks2=13,4,11,6,21        (ks2 ⊆ ks1)
L    = 24L,20L,6L,21L,9L,13L,2L,22L,7L,11L,23L,19L,4L
R    = 6R,21R,13R,11R,4R
jvm  = 24L,20L,6L,21L,9L,13L,2L,22L,7L,11L,23L,19L,4L      <- all LEFT
lean = 24L,20L,6R,21R,9L,13R,2L,22L,7L,11R,23L,19L,4R      <- shared ones RIGHT
```

1 of 540 with that generator, plus 2 more in an earlier 300-case run at a sub-node level. The
ORDER is right in every case; only the representative is wrong — which matters exactly where
the report says it does (`Partition`s that differ only in their `Inference` tag, `RHS`s that
differ only in iteration order), and which is the very bug the report's §6d records finding on
NE6.

I could not trigger it through `looptrace` because it needs BOTH operands of a `Set ++ Set` to
be `HashSet`s, i.e. five or more partitions on each side, and no seed I could build at this
size gets there: in `learnPartitions` the right operand is always at most three elements.
The reachable call sites are `destructiveSub`'s `srs` fold (`s ++ subPartitions(...)`),
`makeConcrete`'s `rhss` (`Set[RHS]`, whose elements ARE distinguishable by iteration order),
`makeEmpty`'s `qps ++ pps`, and `RHS.merge`'s `(abstr ++ abs)`. **L2's corpus, with
1372-partition solves, is where this will appear**, and it will look like a one-record
mismatch with the tag or the inner order wrong — exactly the shape that cost the implementer
a debugging cycle on NE6.

**Fix**: in `rightWins`, before the four-way dispatch, return `false` when the current node's
right content is entirely "data on both sides, equal payloads":

```lean
-- at this node: for every occupied slot j of T, |T_j| = 1 and |S_j| = 1 and S_j ≈ T_j
if (List.range 32).all (fun j =>
      let Sj := S.filter (slot · == j); let Tj := T.filter (slot · == j)
      Tj.isEmpty || (Tj.length == 1 && Sj.length == 1)) then false else ...
```

(the `Sj.length == 1 && Tj.length == 1` slots are `leftDataRightDataLeftOverwrites`, and
`Tj.isEmpty` is `leftDataOnly | leftNodeOnly`; anything else sets `rightDataOnly`,
`rightNodeOnly`, `leftDataRightNode`, `leftNodeRightData`, `leftNodeRightNode` or
`dataToNodeMigrationTargets` and defeats the early return).

### F3 — CONFIRMED, LOW. `tracker/lean/README.md`'s headline counts are now stale, and L1's own import is what invalidated them

L1 added `import Rowpartition.Loop` to `Rowpartition.lean` and thirteen rows to the README's
build table, but left the headline paragraph at Stage 7's numbers. Re-measured by me with the
README's own commands:

| README says | actually |
|---|---|
| `36 module files`, `1888 named theorems in source` | 38 files / 1952 by the README's own `grep`, plus 28 more in `Rowpartition/Loop/` that its glob does not reach |
| `Rowpartition theorems audited: 2378` | **2508** |
| `lake build Rowpartition -> (820 jobs)` | **832 jobs** |

`tracker/loopmodel/L1-MODEL.md` §1 has the right numbers (832 / 2508); only the README is
stale. Fix: one paragraph.

### F4 — LOW, documentation. Three §7 "not modelled" entries misattribute dead code

`Constraints.combine` (1103), `Q.PQueue.build(v, t)` (645) and `Q.PQueue.toType` (624) are
called from NOWHERE in `core/src/main` — I grepped. §7 says `combine` and `build(v,t)` are
"reached from `Subst.unifyRow`, not from `solve`" and that `toType` is "`reduce`'s". The
conclusion ("not reached from `solve`") is right and conservative; the reason is not. Same for
`RHS.toTypes`, whose only caller is the dead `toType`.

### F5 — LOW, documentation. Two unstated-fuel claims, one of which I checked and one of which the report already flags

* `Loop/Json.lean:135 checkLabel` takes fuel `ps.length + 2` and the docstring asserts it
  "cannot run out early" with no argument. It IS sufficient, and here is why: after ANY
  productive event at a partition — `(b)` `ones == 1`, `(c)` `bits(v) = false`, `(d)`
  `ones == 0 && unknown = ∅`, `(e)` `bits(v) = true && |unknown| = 1` — every variable of that
  partition is known, so it can never set another bit. Hence at most `|ps|` productive passes
  plus one quiescent pass. Worth putting in the docstring, because if it were ever too small
  the model would silently report NO clash where the compiler refutes.
* `Loop/Queue.lean:78 Graph.dfs` gets `vertices.length + 1`; the report says "argued, not
  proved". The argument is sound (every child is a node, marking is on entry, so the stack
  holds distinct nodes) and I confirmed the side condition: `Graph.add`'s short-circuit branch
  adds no node that is not already in `sort`, because `ok` requires `u` and every `v ∈ vs` to
  be in `sort` already.
* Report §1 says "the two other bounded recursions carry explicit depth arguments" and names
  `Graph.dfs` and `SSet.champSort`; there are FOUR (`checkLabel` and `SSet.rightWins` as well).

### F6 — LOW. `Bridge.lean` proves one direction, and no invariant connects it to `step`

`LPart.toConstraint_ofConstraint` is a section on `mk`-form constraints; `ofConstraint ∘
toConstraint = id` is not proved (and is false — the `SSet` order/representation and the `inf`
tag are forgotten). That is the right pair to prove and the report says so plainly, so this is
not a defect. But `LPart.eqv_iff_toConstraint` needs four `Nodup` hypotheses and nothing in L1
proves that the states `step` produces satisfy them: the `SSet.nodup_*` lemmas are
per-operation. An invariant `∀ s, Wf s → Wf (step s)` is the natural L3 obligation and should
be written into L3's acceptance criteria rather than discovered there.

### F7 — LOW, scope note for L2. `Names.pvar` infers `V.ty` from the id

`Loop/State.lean:179`: `pvar v = if v < supplyLo then "^free" ++ v else "^ambiguous(free)" ++ v`.
That is exact for a `json:` seed, where the harness makes every input variable `Free` and every
mint `Ambiguous(Free)` with ids from `supplyLo` up. It is NOT exact for the corpus, where
`Partition.toString`'s `pvar` prints `v.ty.toString.toLowerCase` and `ty` can be `Skolem`,
`Bound`, `Ambiguous(Skolem)` … with no relation to the id. L2 will have to carry the real `ty`
per variable in the seed. Not a defect of L1; it is not in §7's list and should be.

## Step 4 — the L1 acceptance criteria, one by one

| criterion | verdict | evidence |
|---|---|---|
| (a) `lake build Rowpartition` and the audit green | **PASS** | re-run by me: 832 jobs, `Rowpartition theorems audited: 2508; declarations using a non-standard axiom: 0`, `lake build looptrace` 22 jobs. No `sorry`/`Classical`/`partial`/`axiom`/`unsafe`/`native_decide`/`opaque`/`implemented_by` anywhere under `Rowpartition/Loop/`; `run` carries an explicit fuel and `outOfFuel` is a distinguishable answer. |
| (b) the module reuses `Rowpartition.Constraint`/`mk`/`vset` so later refinement proofs connect | **PASS** | `Loop/Bridge.lean` imports `Rowpartition.Divergence`, defines `LPart.toConstraint` as `Rowpartition.mk p.lhs …` and `LPart.ofConstraint` via `slist (vset c)` / `c.conc.sort`, and proves `toConstraint_ofConstraint`, `toConstraint_eq_iff` and `eqv_iff_toConstraint`. See F6 for what is NOT proved and why that is the right boundary. |
| (c) six tracked seeds × ten id bases, traces agree step for step or every disagreement is explained | **PASS, exceeded** | I regenerated both sides from scratch: 60/60 agree at bases 0-9, 30/30 at bases 30-34 (which the implementer never ran), and all 90 are BYTE-identical, not merely normalised-equal. |
| (d) a written Scala→Lean table covering every function `incorporateAll` reaches, with the "not modelled" entries stated | **PASS with corrections** | §8 is five sub-tables, ~70 rows; §7 is thirteen "not modelled" entries. I checked every row against the Scala. Two rows are wrong (F1, F2 — both `SSet`), three misattribute dead code (F4), one entry is missing (F7), and one §7 entry (`labelClash`'s label order) is over-conservative: the model DOES compute that order through `SSet`. |

## Rows checked and confirmed (the ones that decide the trace)

* **dequeue order.** `Q.pr`'s monoid takes the MIN priority and the RIGHTMOST `(rhs.hashCode,
  lhs.hashCode)`, so `part`'s two `split`s are block boundaries of a list sorted ascending by
  that key under `scalaz.Order[Int]` (SIGNED), and `sandwich` puts the new element at the FRONT
  of its block. `pop` splits on "prefix min = global min", i.e. the first element of minimal
  `graph.sort(lhs)`. `PQueue.insertSorted` and `PQueue.dequeue` are exactly that. `heapify`
  (`q.foldRight(FingerTree.empty)(_ +: _)`) does preserve the order, as §7 claims.
* **the hashes.** I re-probed the JVM myself (`RevProbe.scala` against `target/ermine-classpath`,
  scala-library 2.13.18): all 21 constants of the report's §5 — `"Repro"/"l1"/"RHS"/"Seq"/"Set"`
  hashes, `Set(...)`/`List(...)` hashes including `listHash`'s arithmetic-range branch,
  `Global`, `RHS`, `Partition`, `ConcreteRho`, `VarT` and `Part` — reproduce EXACTLY, and match
  the `#guard`s in `Loop/Conformance.lean` (45 of them, checked at build time).
* **`immutable.Set`'s order.** All 14 order/representation `#guard`s independently reproduced by
  my probe. `SetN` ≤ 4 in insertion order, promotion at 5, `filter`/`-`/`map` keeping the
  receiver's representation, `map` starting the builder in the receiver's representation.
* **`HashSet ++ HashSet`'s representative rule.** I built the tagged-element probe the report
  only describes (`RevProbe3.scala`) and ran the same cases through the model
  (`RevSSet.lean` via `lake env lean`): `L ++ HashSet(2)` keeps the RIGHT, `L ++ HashSet(1)`
  keeps the LEFT (`bm.size == 1` shortcut), `L ++ HashSet(5)` keeps the RIGHT per slot, a right
  SUBNODE over a left DATA keeps the RIGHT, and an empty left returns the right. **The model
  reproduces all five.** Only the early-return case (F2) is missed.
* **`incorporateAll`'s dispatch**: `proc.findRHS` first, then `RHSEmpty` / `RHSConcr` /
  `RHSAbstr(Single(u))` / general, with `stepLog` reading `rest.size` and the ORIGINAL
  `proc.size`, `learn` records tagged against the ORIGINAL `proc`, and `(rest ++! trim(learned,
  proc), proc + r)`. Exact. The `RHSAbstr(Single(u))` / `RHS(Single(w), con)` split that §6d
  records is right: `RHS.single?` (conc empty) is used by the dispatch, `Q.rhsLookup` and
  `isSelfUnification`; `RHS.abstrSingle?` (conc anything) by `resolvents`, `findResolvent` and
  `resolution`'s premise.
* **`learnPartitions`**: `splitConcrete` as the fold's seed, one pass over `proc`,
  `s ++ rps ++ cps ++ dps` / `s ++ csps ++ sps ++ dps` in that order, `findRHS(incm, proc, s)`
  consulting **`proc` first then `incm`** (the Scala's argument names are `(ps, cs, s)` and the
  call is `findRHS(incm, proc, …)`, so `cs = proc`) — `findRHS3` has it right — and all three
  lookups folded `proc` then `incm`, later writes winning, over the system MINUS the dequeued
  premise.
* **the rules**: `splitConcrete`'s five branches with `fresh` only in the last;
  `resolution`'s `fresh` drawn ONCE per call that matches the lone-variable pattern, BEFORE the
  `tops`/`bots` guard; `cancellation`'s two arms; `subBody`'s `es.map(...) + Partition(u, nrhs)`;
  `commonSubexpression`'s reuse, two folding branches and cut mint; `disjunction`'s two `fresh`
  draws. All exact. `drawn` (ids taken from the `Supply`) agreed with the compiler on **18 of
  18** fresh comparisons across my seeds.
* **`makeEmpty`** (`qps ++ pps` in that order, `aux`'s three arms, the erasure of mentions,
  `incmg ++! trim(nps, procd)`), **`subPartitions`** (`proc` then `incm` minus `v`'s own
  definitions), **`destructiveSub`** (`keep`, the `(pps ++ qps).map(_._2)` RHS set, `srs`,
  `keepDefs`, `abs.size ≥ 2`, `++` for `proc` and `++!` for `incm`), **`makeConcrete`**
  (`proc.toSet` then `incm.toSet`, `ensureSuperset` per element, `can`, `nproc + Partition(v,
  RHSConcr(fs))` with `inf = none`), **`instantiate`/`replace`** (the two-element `PQueue` and
  its key ordering). All exact.
* **`PQueue.partition`** folds from the RIGHT, so the returned `Set` receives the matches in
  reverse queue order — the model's `.reverse` before `SSet.ofList` is right.
* **`Subst.solve`'s wrapper**: `unbindExists` with `xs = []` really is the identity, because
  `Type.subType` short-circuits on an empty map (`Type.scala:634`) — so `Part.apply`'s
  reordering smart constructor is genuinely not reached, as §7 says. `Exists.apply`'s
  reverse-then-`toSet` is applied TWICE (once in the smart constructor, once through
  `Exists.nfWith` → `Exists.mk` → `Exists.apply`), which `buildQueue`'s
  `existsApply (existsApply cs)` matches. The `in`/`ex`/`inpart`/`sat`/`solve` record order and
  every field of the `solve` line (including `byRule`'s `groupBy … .toList.sorted`) are exact.
* **`checkLabel`/`labelClash`**: the stale `unknown` list reused by arms (b) and (c), `note`
  keeping only the FIRST clash, the per-partition `clash.isEmpty` guard, and the label set built
  by `ps.foldLeft(Set())(_ ++ _.concr)` — all exact. Confirmed by the messages: my `SUP` seed
  gives `the whole contains it but no part does` at base 3 and `a part contains it but the whole
  does not` at bases 0,1,2,4, and the model matches base for base.

## Step 5 — a random fuzz the implementer did not run

120 random SATISFIABLE systems from `tracker/tools/rowclosure.py`'s own `gen_random`
(k = 6-11 variables, m = 2-5 labels, n = 4-8 constraints, rng seed 20260904), at bases 0, 13
and 24, compiler vs model, compared BYTE for byte on the six record types:

```
FUZZ RESULT identical=360 differing=0
```

7,927 records, no empty trace, 320 SOLVED and 40 REJECTED runs, all five dispatch branches
(`empty` 791, `learn` 611, `concrete` 460, `unify` 400, `common` 117) and eight rules
(`Substitution` 202, `CommonSubexpression` 111, `Cancellation` 110, `SplitConcrete` 94,
`SelfSubstitution` 93, `DeDuplication` 82, `Resolution` 15, `SplitKeyed` 3) — including
`SelfSubstitution` and `DeDuplication`, which none of the tracked seeds nor my hand seeds
reached.

Worth recording WHY this fuzz cannot see F1: `gen_random` was given at most five labels, and
`Repro.l0 … Repro.l4` have five distinct level-0 CHAMP slots, so no removal ever collapses a
sub-node. The colliding label pairs start at `{l3,l5}`, `{l9,l18}`, `{l16,l27}`, `{l20,l26}`,
`{l1,l30}`, `{l8,l41}` — a corpus with real `Global(module, name)` labels has them everywhere.
Any future fuzz should draw labels from a wider range.

## Totals

| what | comparisons | result |
|---|---|---|
| tracked seeds, bases 0-9 (the report's claim, re-run) | 60 | agree, byte-identical |
| tracked seeds, bases 30-34 (new) | 30 | agree, byte-identical |
| reviewer seeds `RR CSE CP KD UC REF SUP RE`, bases 0-14 | 120 | agree |
| reviewer seeds `RE RR CSE KD` with `emptyRow`, bases 0-14 | 60 | agree |
| reviewer seeds `CP2 BIG CHAIN`, bases 0-14 | 45 | agree |
| death paths `D1`-`D4`, bases 0,3, `labelCheck` off | 8 | agree |
| random fuzz, 120 systems x 3 bases | 360 | agree |
| `COLL`, 13 bases | 13 | agree |
| **`LBL`, 5 bases** | 5 | **all 5 DIFFER (F1)** |
| JVM probes: hashes and `Set` orders | 35 constants | reproduce exactly |
| JVM vs model, random `Set` ops | 400 | 12 differ (F1) |
| JVM vs model, random `HashSet ++ HashSet` | 540 + 300 | 3 differ (F2) |

## VERDICT: FIX-THEN-ADVANCE

The stage's four acceptance criteria are met, the build and audit are green on my own re-run,
the model is computable with no admitted anything, the correspondence table is genuinely
exhaustive and — apart from the two `SSet` rows — correct, and the differential holds up under
five bases the implementer never tried, eleven seeds of my construction aimed at the branches
the report itself flagged as untested (`ResolutionRow`, `ResolutionEmpty`, the queue-level
`CommonPartition` redirect, `keepDefs`, a CHAMP-sized input, a ten-deep variable graph, four
`die` paths) and 360 random systems. This is careful work and the report is honest about its
own limits.

Two things must land before L2, because L2 is exactly where they bite:

1. **F1** — `SSet.excl`/`filter` must re-`champ` the survivors of a `HashSet`. CONFIRMED by an
   end-to-end trace divergence at 5 of 5 bases (`LBL.json`), by 12 of 400 random op
   comparisons, and the fix is verified to reproduce the JVM in 12 of 12.
2. **F2** — `SSet.rightWins` must take `BitmapIndexedSetNode.concat`'s early return. CONFIRMED
   against the JVM at the `SSet` level; not yet reachable through a seed of this size, but the
   corpus's 1372-partition solves will reach it.

Both are a few lines. After them the report's §4 and §8 rows need correcting, and F3 (the
README's stale headline), F4, F5 and F7 are one-paragraph documentation fixes. F6 is a note
for L3's acceptance criteria, not a change to L1.

The report's headline sentence — "There are no unexplained disagreements" — should be narrowed
to the seeds actually tested, since `LBL.json` is a disagreement on shipped defaults.

---

# Re-review — 2026-09-04 (later)

Targeted re-review of the fixes only, against the six findings above. Everything below was
re-run by me; nothing is taken from the implementer's report.

## R0 — build, audit, and the tree

```
cd tracker/lean && export PATH=$HOME/.elan/bin:$PATH
lake build Rowpartition   -> Build completed successfully (832 jobs).   exit 0
lake env lean Audit.lean  -> Rowpartition theorems audited: 2508; declarations using a non-standard axiom: 0
lake build looptrace      -> Build completed successfully (22 jobs).    exit 0
```

Greps over `Rowpartition/Loop.lean` + `Rowpartition/Loop/`: still no `sorry`, `Classical`,
`partial`, `axiom`, `unsafe`, `native_decide`, `opaque`, `implemented_by`, `@[extern]` — the
only two hits are the same prose lines in `Step.lean`. The eleven adopted seeds under
`tracker/repro/satterm/seeds/` are byte-for-byte the same SYSTEMS as the ones I built (I
compared the `rho`/`cons` of each). The compiler side is unchanged: `W2@0` regenerated now is
byte-identical to the capture I took before the fixes, so every compiler trace I already had
is still a valid reference.

## R1 — F1 (`excl`/`filter` re-champ): FIXED, and I could not break it

The new `excl` and `filter` are exactly the recommended shape (`if s.hashed then ⟨true, champ
(...)⟩ else ⟨false, ...⟩`), the docstrings quote `BitmapIndexedSetNode.removed`'s
`copyAndMigrateFromNodeToInline`, and `Bridge.lean`'s `nodup_excl`/`nodup_filter` now discharge
the hashed branch through `((champ_perm _).nodup_iff).mpr` — which is legitimate, `champ_perm`
being `champSort_perm 7 0` and already proved.

| check | before | now |
|---|---|---|
| my 400 random JVM `Set`-op comparisons (`excl` 80, `removedAll` 70, `filter` 76, `inter` 85, `map` 89), replayed against the SAME JVM capture | 12 differ | **0 differ** |
| **new** adversarial removals: 693 JVM cases, sets of 5-18 elements over key ranges 30/60/120 (dense in level-0 trie collisions), `excl`/`removedAll`/`filter`, 1-3 elements dropped | — | **0 differ** (`excl` 239, `removedAll` 243, `filter` 211) |
| `LBL.json`, bases 0-4, byte-for-byte against the compiler | 5 of 5 DIFFER | **5 of 5 identical** |
| `COLL.json`, 13 bases | agreed | still agrees |

F1 is closed.

## R2 — F2 (`concat`'s early return): PARTLY FIXED. One case is still wrong, and it is the common one

The new `rightWins` models `HashSet.scala:1532` — the FIRST early return
(`newDataMap == leftDataOnly|leftDataRightDataLeftOverwrites && newNodeMap == leftNodeOnly`),
checked at every level before the four-way dispatch. That transcription is correct, and it
does fix the three cases I originally reported: replaying my own captures against the new
model gives **400/400, 300/300 and 540/540**, and the five hand-built `HashSet ++ HashSet`
cases still reproduce the JVM.

But `BitmapIndexedSetNode.concat` has a **SECOND** early return that neither version models,
at the very end of the merge (`HashSet.scala:1686`):

```scala
if (anyChangesMadeSoFar)
  new BitmapIndexedSetNode(dataMap = newDataMap, ...)   // right payloads at the overwrite slots
else this                                               // <- the whole LEFT node
```

`leftDataRightDataLeftOverwrites` writes the right's payload into `newContent` but does **not**
set `anyChangesMadeSoFar`. So when nothing at a node actually changes, the left node is
returned wholesale and every one of its representatives survives — even at slots where both
sides hold the element as data. The first early return is a strictly stronger condition: it
also forbids `leftNodeRightNode`, `leftNodeRightData`, `leftDataRightNode` and the migrations,
whereas `¬anyChangesMadeSoFar` tolerates `leftNodeRightNode` whose sub-merge changed nothing
and `leftNodeRightData` whose element was already in the left sub-node. That is exactly the
"the right operand is contained in the left" case, which is the shape that arises in
`destructiveSub`'s `srs` fold, `makeConcrete`'s `rhss` and `makeEmpty`'s `qps ++ pps`.

**Measured.** A fresh JVM probe of 639 `HashSet ++ HashSet` unions engineered around the
containment boundary — mode 0: `T ⊆ S`; mode 1: `T ⊆ S` plus one outsider; mode 2: arbitrary;
key ranges 12/20/32/64, `|S| = 5..16`:

```
current model:  76 of 639 differ   (mode 0: 57 of 172, mode 1: 19 of 235, mode 2: 0 of 232)
```

One of them, at the root:

```
S = 27,22,2,14,18,23,8,19,30,10      T = 18,10,2,23,30,27,22,8,19        (T ⊆ S)
L    = 10L,14L,2L,18L,23L,8L,22L,27L,30L,19L
R    = 10R,2R,18R,23R,8R,22R,27R,30R,19R
jvm  = 10L,14L,2L,18L,23L,8L,22L,27L,30L,19L        <- all LEFT
lean = 10R,14L,2R,18R,23R,8R,22L,27L,30L,19L        <- data slots given to the RIGHT
```

The first early return cannot fire here (some slots are `leftNodeRightNode`), but nothing sets
`anyChangesMadeSoFar`, so the JVM returns the left root untouched.

**Verified fix.** Replace the early-return predicate by `anyChangesMadeSoFar` itself, which
subsumes it (if the first early return's condition holds, no flag is set either):

```lean
/-- `anyChangesMadeSoFar` for `BitmapIndexedSetNode.concat(that, shift)`: does the right node
change this one at all?  If not, `concat` returns `this` -- the LEFT node -- at :1532 or at
:1686, and every one of the left's representatives survives, at every depth. -/
def changed : Nat → List α → List α → Bool
  | 0, _, T => !T.isEmpty
  | d + 1, S, T =>
    let shift := 5 * (7 - (d + 1))
    let slot := fun (y : α) => champMask (improve (SVal.hsh y)) shift
    (List.range 32).any (fun j =>
      let Sj := S.filter (fun y => slot y == j)
      let Tj := T.filter (fun y => slot y == j)
      match Sj, Tj with
      | _,   []  => false                              -- leftDataOnly / leftNodeOnly
      | [],  _   => true                               -- rightDataOnly / rightNodeOnly
      | [a], [b] => !SVal.eq a b                       -- overwrite (no change) / migrate (change)
      | [_], _   => true                               -- leftDataRightNode: unconditional
      | _,   [b] => !(Sj.any (fun y => SVal.eq y b))   -- leftNodeRightData: `updated ne leftNode`
      | _,   _   => changed d Sj Tj)                   -- leftNodeRightNode: recurse

def rightWins : Nat → List α → List α → α → Bool
  | 0, _, _, _ => true
  | d + 1, S, T, x =>
    if !changed (d + 1) S T then false else
    <the existing four-way dispatch, unchanged, recursing into `rightWins d Si Ti x`>
```

I ran exactly this (in my scratch, as `Fix2`, without touching the project) against every JVM
capture I hold:

| capture | candidate fix |
|---|---|
| 639 adversarial unions (the ones that fail now) | **0 differ** |
| 540 direct `HashSet ++ HashSet` unions | 0 differ |
| 300 mixed `SetN`/`HashSet` concats | 0 differ |
| the 5 hand-built cases A-E (right-wins at data/data, `bm.size == 1` keeps left, right sub-node over left data, empty left) | all 5 reproduce the JVM |

**1484 of 1484.** The docstring on `rightWins` and §4 of `L1-MODEL.md` need the same
correction: "at a data/data slot the RIGHT one overwrites the left" is true only when the node
changed at all.

As before, I could not reach this through a `looptrace` seed: it needs BOTH operands of a
`Set ++ Set` to be `HashSet`s, i.e. five or more partitions on each side, and in
`learnPartitions` the right operand is never more than three elements. It stays an L2 exposure.

## R3 — the documentation corrections (F3, F4, F5, F7)

* **F3, README counts.** Fixed additively — the Stage 7 paragraphs are left intact and
  "UPDATED 2026-09-04" paragraphs follow them. I re-measured every number with the README's own
  commands: **38 top-level files / 1952 theorems** by its `grep` glob, **12 more files and 28
  more theorems under `Rowpartition/Loop/`**, `Audit.lean` **2508 / 0**, `lake build` **832
  jobs**. All four match what the README now says.
* **F4.** §7 now says `Constraints.combine` (1103), `Q.PQueue.build(v, t)` (645),
  `PQueue.toType` (624) and `RHS.toTypes` are DEAD, called from nowhere in `core/src/main`, and
  records that the earlier reason was wrong. That matches my greps, including the added
  `PQueue.vars` ("only `toType`'s" — correct, `toType` is its one caller and is itself dead).
* **F5.** §1 now says FOUR bounded recursions and gives the `checkLabel` argument
  ("after ANY productive event at a partition every variable of that partition is known, so at
  most `|ps|` productive passes plus one quiescent pass") and the `Graph.dfs` side condition
  about `Graph.add`'s short circuit. Both are the arguments I gave, correctly transcribed.
* **F7.** §7 has a new row for `Names.pvar` inferring `V.ty` from the id, marked an L2
  BLOCKER. Accurate. §7's `labelClash` row is now struck through as "NOT an abstraction", which
  is right.
* The headline is narrowed to "on every system tested … scoped to what was actually run", and
  §6e/§6f record the two review bugs and the new totals honestly, including which comparisons
  were byte-identical and which merely normalised. I checked §6f's arithmetic: 851 = 60+120+60
  +120+60+45+8+13+5+360, of which 671 byte-identical. Correct.

## R4 — re-running the whole trace differential myself

Model side regenerated with the new build; compiler side is my own earlier capture (verified
unchanged).

| sweep | comparisons | result |
|---|---|---|
| tracked six × bases 0-9 and 30-34, byte-for-byte | 90 | **0 differing** |
| `RR CSE CP KD UC REF SUP RE CP2 BIG CHAIN` × bases 0-14, byte | 165 | **0 differing** |
| `RE RR CSE KD` × bases 0-14 with `emptyRow`, normalised | 60 | **0 differing** |
| `D1`-`D4` × bases 0,3 with `labelCheck` off, byte | 8 | **0 differing** |
| `COLL` × 13 bases, byte | 13 | **0 differing** |
| **`LBL` × 5 bases, byte** | 5 | **0 differing** (was 5/5 differing) |
| my 120-system `rowclosure.py` fuzz × 3 bases, byte | 360 | **0 differing** |

## R5 — a NEW fuzz aimed at the fixed code

My first fuzz could not have caught F1: it drew labels `l0…l4`, which occupy five distinct
level-0 CHAMP slots, so no removal ever collapsed a sub-node. I built a second one that can.
150 random satisfiable systems from `rowclosure.py`'s `gen_random` (k = 8-14 variables,
m = 6-12 labels, n = 6-12 constraints, rng 31337), with the labels **remapped onto ten
colliding trie slots** — `{l3,l5} {l9,l18} {l16,l27} {l20,l26} {l1,l30} {l8,l41} {l2,l31}
{l4,l12} {l0,l24} {l7,l40}` — at bases 0, 24 and 36 (24/25 and 36/37 are themselves colliding
variable ids):

```
FUZZ2 RESULT identical=450 differing=0
```

10,946 records, 75 REJECTED runs, all five dispatch branches (`empty` 1088, `concrete` 775,
`unify` 520, `learn` 376, `common` 111) and seven rules. It reaches the territory the first
fuzz could not: **573 records print a concrete part of five or more labels** (up to ten), so
the label sets really are `HashSet`s with sub-nodes, and **601 records print a label list that
is not in ascending order**, i.e. a genuine CHAMP order rather than an accident. 450 of 450
byte-identical.

## Re-review totals

| what | comparisons | result |
|---|---|---|
| trace comparisons re-run by me (R4) | 701 | **0 differing** |
| new wide-label fuzz (R5) | 450 | **0 differing** |
| **trace total** | **1151** | **0 differing** |
| JVM vs model, my three original `SSet` captures replayed | 1240 | **0 differing** (was 15) |
| **new** JVM vs model, adversarial removals | 693 | **0 differing** |
| **new** JVM vs model, adversarial unions around the containment boundary | 639 | **76 differing** |
| the same 639 + 540 + 300 + 5 under the candidate `changed` fix | 1484 | **0 differing** |

## FINAL VERDICT: FIX-THEN-ADVANCE — one item

Everything I asked for has landed and holds up under evidence the implementer did not have:

* **F1 CLOSED.** `LBL.json` is byte-identical at 5 of 5 bases, 693 fresh adversarial removals
  agree, my 400 original op comparisons went 388/400 → 400/400, and a wide-label fuzz of 450
  comparisons that genuinely reaches `HashSet`s with sub-nodes is clean.
* **F3, F4, F5, F7 CLOSED.** Every corrected number and every corrected reason matches what I
  re-measured or re-grepped.
* **F6** remains, as intended, a note for L3's acceptance criteria.
* The 1,151 trace comparisons I re-ran are all identical, and so are the 1,933 `SSet`-level
  comparisons that do not touch the containment boundary.

**The one required item: finish F2.** `rightWins` models `concat`'s first early return but not
its second (`if (anyChangesMadeSoFar) … else this`, `HashSet.scala:1686`), and the second is
the one that fires when the right operand is contained in the left — 76 of 639 JVM unions
built around that boundary still disagree, 57 of them in the plain `T ⊆ S` case. The fix is
the `changed` predicate in R2, which I verified on 1,484 JVM cases including every capture I
already held and all five hand cases. Until it lands, §4 and §6e of `L1-MODEL.md` and the
`rightWins` docstring overstate what is modelled, and L2 will meet this on the corpus.

With that one change (and the two documentation lines that go with it), this is an ADVANCE.

---

# Final check — 2026-09-04 (evening)

## Build

```
lake build Rowpartition  -> Build completed successfully (832 jobs).                       exit 0
lake env lean Audit.lean -> Rowpartition theorems audited: 2508; non-standard axioms: 0    exit 0
lake build looptrace     -> Build completed successfully (22 jobs).                        exit 0
```

Greps over `Rowpartition/Loop/`: nothing beyond the two prose lines in `Step.lean`.

## Reading `SSet.changed` against `HashSet.scala:1480-1700`, arm by arm

The applied `changed` is the predicate I verified, and it gates `rightWins` at every depth
(`changed (d+1) S T` at each level; the `leftNodeRightNode` arm recurses as `changed d Sj Tj`,
so the shift advances by five). Its six arms are the classification loop's six outcomes and
the flag each one sets:

| Lean arm | Scala slot classification | sets `anyChangesMadeSoFar`? |
|---|---|---|
| `_, [] => false` | `leftDataOnly` (:1614) / `leftNodeOnly` (:1632) | no — left content copied |
| `[], _ => true` | `rightDataOnly` (:1623) / `rightNodeOnly` (:1640) | yes, unconditionally |
| `[a], [b] => !eq a b` | `leftDataRightDataLeftOverwrites` (:1667) if equal, else `leftDataRightDataMigrateToNode` (:1648) | no / yes |
| `[_], _ => true` | `leftDataRightNode` (:1574) | yes, unconditionally |
| `_, [b] => !(Sj.any (eq · b))` | `leftNodeRightData` (:1591) — flag iff `updated ne leftNode`, and `updated` returns `this` iff the element is already there | conditional, correctly |
| `_, _ => changed d Sj Tj` | `leftNodeRightNode` (:1561) — flag iff the recursive `concat` returns a different node | conditional, correctly |

The three shortcuts above the loop are still covered: `size == 0` by `concat`'s
`!s.elems.isEmpty`, `bm.size == 0`/`bm.size == 1` by `t.elems.length > 1` at the root and by a
canonical sub-node always holding at least two elements below it, and `bm eq this` by
`changed` being false on identical content. `changed 0 _ T = !T.isEmpty` keeps the old
behaviour at a hash-collision node, which §4 still lists as not modelled. The docstrings now
cite both :1532 and :1686 and say the right wins at a data/data slot *only if the node changed
at all* — which is what the code does.

## Re-run

| driver, replayed against my own JVM captures | comparisons | result |
|---|---|---|
| `RevOps` — random `excl`/`removedAll`/`filter`/`inter`/`map` | 400 | **0 differing** |
| `RevConcat` — mixed `SetN`/`HashSet` concats | 300 | **0 differing** |
| `RevUnion` — direct `HashSet ++ HashSet` | 540 | **0 differing** |
| `RevAdv` unions — the containment boundary (mode 0 `T ⊆ S` 172, mode 1 `T ⊆ S`+1 234, mode 2 random 232) | 639 | **0 differing** (was 76) |
| `RevAdv` removals — `excl` 239, `removedAll` 243, `filter` 211 | 693 | **0 differing** |
| **`SSet` total** | **2572** | **0 differing** |

Traces regenerated on BOTH sides just now and diffed byte-for-byte:

| seed | result |
|---|---|
| `LBL` bases 0-4 (the F1 regression seed) | 5/5 identical, 13 records each |
| `COLL` bases 23, 0, 12 | 3/3 identical, 8 records each |
| fuzz-2 systems `G000`, `G077`, `G143` at bases 0, 24, 36 | 9/9 identical |

(My first pass at these reported differences; that was my own slip — I handed `looptrace` a
repo-relative seed path while it runs in `tracker/lean`, so it read nothing. With absolute
paths all seventeen are identical. Recorded because a reviewer's tooling error is exactly the
kind of thing that should not be quietly deleted.)

## VERDICT: ADVANCE

F1, F2, F3, F4, F5 and F7 are all closed, each against evidence I re-ran rather than took on
report. The `SSet` model now agrees with the JVM on all 2,572 comparisons I hold, including
the 639-case probe built specifically to break it; the two regression seeds and the wide-label
fuzz systems are byte-identical on freshly generated traces from both sides; the build is 832
jobs and the audit 2508 theorems with no non-standard axiom; and `changed`/`rightWins` read
correctly against the Scala arm for arm.

Carried into L3, not L1: **F6** — `Bridge.lean`'s `eqv_iff_toConstraint` needs `Nodup`
hypotheses that no invariant yet connects to `step`; `∀ s, Wf s → Wf (step s)` belongs in L3's
acceptance criteria. Carried into L2, and already recorded in `L1-MODEL.md` §7: **F7**, the
`V.ty`-from-id assumption in `Names.pvar`, which the corpus will violate.
