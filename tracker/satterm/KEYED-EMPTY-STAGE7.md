# Stage 7 — `-Dermine.emptyRow`: the EMPTY row made visible to the concrete-row reuse, measured

Date 2026-09-04, branch `scala3-migration`, clean tree at `2411296` before this stage.
**The flag is DEFAULT OFF, no default was flipped, and nothing was committed.**
Stage 6 (the Lean that licenses it) is `tracker/satterm/KEYED-EMPTY-STAGE6.md` /
`Rowpartition/KeyedEmpty.lean`; this stage is its §9 implemented and measured, in the method
of `tracker/satterm/KEYED-ROW-STAGE5.md`.

Toolchain for every command below:

```
export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH
cd /home/dmitry/research/ermine/ermine-scala
export PATH=$HOME/.elan/bin:$PATH          # Lean, in tracker/lean
```

Scratch (raw outputs, drivers): `/home/dmitry/.claude/jobs/880c725d/tmp/stage7/`.

Configurations, throughout:

| tag | properties | `GenRules.toString` (the banner every `repro/*/run.sh` prints) |
|---|---|---|
| `D` | none — the shipped default (Stage 5's two flags ON, the new one off) | `cut+label-early+resguard+splitkey+splitrow+resrow` |
| `E` | `-Dermine.emptyRow=true` | `cut+label-early+resguard+splitkey+splitrow+resrow+emptyrow` |

Part A is the implementation and the two design decisions the brief left open; Part D is the
Lean; Part B is the gates in the order they were run; Part C is the gate table, the unapplied
flip, the scope and the recommendation.

---

## Part A — the implementation

### A.1 The change (`core/src/main/scala/com/clarifi/reporting/ermine/Constraints.scala`, LF preserved)

Comment-heavy; six edits, and the six existing ADOPTED comments are untouched.

1. **`case object SplitEmpty extends Inference`** and **`case object ResolutionEmpty extends
   Inference`** (after `ResolutionRow`, ~line 725).  TWO tags, not one: the two branches emit
   DIFFERENT shapes (a propagation `x <- ()` per group member; two bare concrete partitions),
   they fire on different rules, and `keptdef-mints.py` counts split branches and resolution
   branches in separate tallies — one tag would merge two populations that Stage 5's own
   figures keep apart.  `Inference` is never inspected and `Partition.equals`/`hashCode`
   ignore it, so both tags are behaviour-neutral.
2. **`GenRules.emptyRow`**, read once at class-init like every other flag:

   ```scala
   val emptyRow: Boolean = System.getProperty("ermine.emptyRow", "false") == "true"
   ```

   documented with the Lean that licenses it (`KeyedEmpty.makeEmptyD`/`makeEmptyE`,
   `carried_not_invariant`, `hmeas_increases`, `carried_makeEmptyE`,
   `mintsBoundedOnSatKeyed3E`, `G7_mints`, `G7_blocked`) and with the scope limit.
   `toString` gains `+emptyrow`.
3. **`splitConcrete`** gains a SEVENTH parameter `emptyRow: Fields => Option[TypeVar] = _ =>
   none` and a FIFTH branch, between the concrete-row reuse and the mint:

   ```scala
   case None =>
     (if (GenRules.emptyRow) emptyRow(concr) else none) match {
       case Some(_) => abstr.map(x => Partition(x, RHSEmpty(), SplitEmpty))   // NEW
       case None    => val u = fresh(...); Set(Partition(u, RHSAbstr(abstr), SplitConcrete),
                                              Partition(v, RHS(Set(u), concr), SplitConcrete))
     }
   ```

   The order of the match is unchanged, so behaviour is unchanged when any earlier lookup
   hits, when `!GenRules.splitMints`, and when the flag is off.  `fresh` is still called only
   in the mint branch.
4. **`resolution`** gains the same parameter and a FOURTH branch, taken when both earlier
   lookups miss:

   ```scala
   case None =>
     (if (GenRules.emptyRow) emptyRow(all) else none) match {
       case Some(_) => Set(Partition(x, RHSConcr(bots), ResolutionEmpty),      // NEW
                           Partition(y, RHSConcr(tops), ResolutionEmpty))
       case None    => Set(Partition(v, RHS(Set(z), all), Resolution), ...)    // the mint
     }
   ```
5. **`learnPartitions`** builds the lookup, lazily, next to Stage 5's `concRows`, and gains
   `implicit hm: SubstEnv` (its only caller, `incorporateAll`, already has one):

   ```scala
   lazy val envEmptyRow: Option[TypeVar] =
     hm.types.collectFirst { case (z, ConcreteRho(_, fs)) if fs.isEmpty => z }
   def findEmptyRow(k: Fields): Option[TypeVar] = {
     val (rows, myRow) = concRows
     myRow.filter(c => (k subsetOf c) && (c -- k).isEmpty)
          .flatMap(_ => rows.get(Set[Name]()) orElse envEmptyRow)
   }
   val emptyRow: Fields => Option[TypeVar] =
     if (GenRules.emptyRow) findEmptyRow else noConcRow
   ```
6. The correspondence comments at `def splitConcrete`, at `def resolution` and at the lookup,
   and the flag comment in `GenRules`.

### A.2 **Which lookup design, and why — the brief's (a) against (b)**

The brief offered (a) seed the concrete-row map from the substitution environment's empty
instantiations, or (b) thread an `emptied : Set[TypeVar]` alongside the queues.  **(a) was
chosen, and the decision was made on data, before a line was written.**

`stage7/pre-empty.py` replays the 110 Stage 5 DEFAULT traces (`stage5/b6/D/trace-*.tsv.gz`)
and asks, at each of the 157 kept-definition mints, which empty-row carrier a Stage 7 lookup
COULD have found:

```
$ python3 stage7/pre-empty.py stage5/b6/D/trace-*.tsv.gz
TOTALS {'mints': 157, 'compl-empty': 74, 'mod-empty': 74, 'seg-empty': 14}
```

* `compl-empty` **74** — Stage 5's §B7-2 figure, reproduced exactly.
* `mod-empty` **74 of 74** — at every one of them a `makeEmpty` had already run earlier in
  the module's trace, so the fact is in the `SubstEnv`: design (a) can find a carrier at ALL
  of them.
* `seg-empty` **14 of 74** — only 14 have a `makeEmpty` earlier in the SAME solve segment,
  which is the most a threaded per-run set could see (and an over-count: the set would reset
  at each `incorporateAll` call, and a segment can contain several).
* `live-zero` **0 of 74** — never is there a bare `x <- ()` still in the queues, which is
  why Stage 5's lookup misses all 74 and why this is a new branch rather than a wider one.

So (b) would reach at most 19 % of the population this stage exists to serve.  Two further
reasons: (a) needs no change to `incorporateAll`'s recursion, `makeEmpty`'s signature or the
queue plumbing — the fact is read where the compiler already writes it, which is literally
what Stage 6 §9 proposed; and it is the closer model of `makeEmptyE`, which retains the fact
FOREVER, where a per-run set forgets it at the next `combine`/`expand`.

**Cost.**  `hm.types.collectFirst` is a scan of the substitution environment.  It is behind
three cheap tests — the flag, `myRow = Some(concr)`, and a miss on the queue map — and it is
a `lazy val`, so it runs at most once per `learnPartitions` call and never at all with the
flag off.  It is also the same order as work the compiler already does on every
instantiation: `Subst.instantiateType` rebuilds `hm.types` with `subType(Map(v -> e),
hm.types)`, an O(|types|) pass, on every single instantiation.  B4 measures the result.

### A.3 **What the branch emits, and the faithfulness note**

**Traced on the G7 instance before anything was relied on**, exactly as the brief requires
(§B0 below has the two traces in full).  The compiler's dequeue path for an
already-instantiated left-hand side does NOT go through `makeEmpty`'s propagation: a
partition `z <- (x, y)` is dequeued by `incorporateAll` into the `RHS(abstr, concr)` **learn**
branch (only `RHSEmpty()` reaches `makeEmpty`), so emitting the Lean's conclusion
`z <- (abstr)` would (i) re-enter a partition about a variable that `instantiateType` has
already bound, and (ii) once the group is erased, reach `makeEmpty z` a second time — which
is `instantiateType`'s `panic: reinstantiated type`.  **So the branch emits the propagation
directly**, as the brief's second option:

* split: `Partition(x, RHSEmpty(), SplitEmpty)` for every `x ∈ abstr`;
* resolution: `Partition(x, RHSConcr(bots), ResolutionEmpty)` and
  `Partition(y, RHSConcr(tops), ResolutionEmpty)` — the reuse's two conclusions with the
  carrier's row (`∅`) substituted in.

Neither mentions the carrier at all, which is what makes the branch safe: the emptied
variable never re-enters the queues.

**That the Scala step is the Lean reuse composed with its forced `empty` step is a theorem,
not a remark**: `KeyedEmptyScala.emptyReuse_compose` and `resEmptyReuse_compose` compute
`makeEmptyE z (kSplitReuseResult H c z) = H ∪ emptyProp (vset c)` and
`makeEmptyE z (resReuseResult H x y C D z) = resEmptyResult H x y C D` on a state where the
carrier's only occurrence is the retained fact — which is what "`makeEmpty` deleted every
partition mentioning `z`" means.  Hence `splitEmpty_two_steps` / `resEmpty_two_steps`: one
Scala step is TWO steps of `K3ELoopStep`, the relation `mintsBoundedOnSatKeyed3E` bounds.

**And what is emitted is entailed by the premise alone, with no carrier anywhere**
(`splitEmpty_models_iff` via `KeyedEmpty.group_forced_empty`; `resEmpty_models_iff` via
`res_empty_forced`).  The carrier is asked for because it is what makes the step a step of
the RELATION that has the bound, not because the emission would otherwise be unsound.

**The faithfulness note, in the direction opposite to Stage 5's.**  Stage 5's `concRows` is a
LOWER bound on the Lean's `mk u ∅ R ∈ G` — it can only miss.  Stage 7's `envEmptyRow` is an
UPPER bound on `EmptyKnown G` for the *current solve*: `hm.types` holds the empty
instantiations of the whole module's inference, so the branch can fire when the current
system has no carrier of its own.  Three things make that acceptable, and they are stated
rather than argued away:

1. **Soundness does not use the carrier at all** (`group_forced_empty`), so a carrier from a
   wider scope cannot produce a wrong conclusion.
2. The variables are globally unique and a model is global: a variable the environment binds
   to `ConcreteRho(∅)` really does denote `∅`.  The state the Lean models is therefore the
   queues UNION the retained facts, which is exactly `makeEmptyE`'s system, and the adequacy
   theorems are stated for that state (`H` in `KeyedEmptyScala`).
3. What the branch emits adds NO variable, so even where the two-step reading does not apply
   the vocabulary cannot grow.

**One more difference, in the safe direction, inherited from Stage 5:** `concRows` ranges over
`proc ++ incm` and not the current batch `s`, so `resolution`'s empty branch sees one
partition set less than its own resolvent lookup does.

### A.4 Compile, and the flag is really read

```
$ sbt -batch core/compile                       # ONCE; every measurement below is this class set
[success] Total time: 11 s, completed Sep 4, 2026, 3:39:09 AM
$ sbt -batch -J-Xmx3g core/Test/compile
[success] Total time: 8 s, completed Sep 4, 2026, 3:39:26 AM

$ CP=$(cat target/ermine-classpath)
$ echo 'System.out.println(com.clarifi.reporting.ermine.Constraints.GenRules$.MODULE$.toString());' \
    | jshell -q --class-path "$CP" [-R-Dermine.emptyRow=true] -
   <none>                     -> cut+label-early+resguard+splitkey+splitrow+resrow
   -R-Dermine.emptyRow=true   -> cut+label-early+resguard+splitkey+splitrow+resrow+emptyrow
```

`core/test` (`Test / fork := false`, so `_JAVA_OPTIONS` is the way in), same classes:

```
$ sbt -batch -J-Xmx3g core/test                                                  # D
[info] Failed: Total 911, Failed 1, Errors 0, Passed 910
[info] ! Constraints.disjunction sound: Gave up after only 0 passed tests. 501 tests were discarded.
$ _JAVA_OPTIONS="-Dermine.emptyRow=true" sbt -batch -J-Xmx3g core/test           # E
[info] Failed: Total 911, Failed 1, Errors 0, Passed 910
[info] ! Constraints.disjunction sound: Gave up after only 0 passed tests. 501 tests were discarded.
```

*(Two COMMENT-only edits were made to `Constraints.scala` after that compile, to name the
Lean lemmas of Part D correctly once they existed — `scalaEmptySplit_run` /
`scalaEmptyRes_run` in place of a provisional name.  No token of code changed; the final
`sbt -batch core/compile` in "Housekeeping" below confirms the tree still compiles and the
class files are the ones every measurement used.)*

**910/911 on both sides, the same single failure** — the known `Constraints.disjunction
sound` generator starvation.  As in Stage 5, `Constraints.split concrete sound` and
`Constraints.resolution sound` call the rules through their SHORT signatures (the new
parameter defaults to `_ => none`), so they exercise the mint path; the new branch's
soundness evidence is the Lean plus the gates below.

---

## Part D — the Lean (`Rowpartition/KeyedEmptyScala.lean`, NEW, 749 lines, 39 theorems, 10 definitions)

```
$ cd tracker/lean
$ lake build Rowpartition       # Build completed successfully (820 jobs)          (819 before)
$ lake env lean Audit.lean      # Rowpartition theorems audited: 2378;
                                #   declarations using a non-standard axiom: 0     (2329 before)
```

`#print axioms` was run in scratch only (`stage7/PrintAxiomsStage7.lean`, output
`print-axioms-stage7.out`): all **15** headline theorems are
`[propext, Classical.choice, Quot.sound]`.

The module is the Stage 7 counterpart of `KeyedRowScala.lean`, written the same way.

**§1 the retained carrier.**  `SoleFact H z : ∀ c ∈ H, Involves z c → c = mk z ∅ ∅` — "`makeEmpty`
deleted every partition mentioning `z`", read on the state `H` = queues ∪ retained facts.
`SoleFact.lhs_ne`, `SoleFact.notMem_vset`.

**§2 the specification the lookup really meets.**

```lean
def EmptyRowSpec (H : System) (K : Row) : Option Row → Option Var → Prop
  | C?, some z => ∃ C, C? = some C ∧ K ⊆ C ∧ C \ K = ∅ ∧ mk z ∅ (∅ : Row) ∈ H
  | C?, none   => ∀ C, C? = some C → K ⊆ C → C \ K = ∅ → ∀ z, mk z ∅ (∅ : Row) ∉ H
```

i.e. Stage 5's `ConcRowSpec` with the complement pinned to the EMPTY row — which is exactly
what `myRow.filter(c => (k subsetOf c) && (c -- k).isEmpty)` asks — and with the carrier
allowed to come from the retained facts as well as the queues, both of which live in `H`.
`emptyRowSpec_toConcRow` proves a HIT is a `ConcRowSpec` hit, hence a `K2RowApp`;
`emptyRowLookup` / `emptyRowLookup_spec` inhabit the specification, so nothing is vacuous.

**§3–§4 what the branches emit, and that it is entailed.**  `emptyProp S = S.image (mk · ∅ ∅)`,
`splitEmptyResult G c = G ∪ emptyProp (vset c)`,
`resEmptyResult G x y C D = insert (mk x ∅ (D \ C)) (insert (mk y ∅ (C \ D)) G)`.
`splitEmpty_models_iff` (through `KeyedEmpty.group_forced_empty`) and `resEmpty_models_iff`
(through the new `res_empty_forced : rho x = F \ C` and `res_empty_F : F = C ∪ D`) say the
model set does not move — **with no carrier in the hypotheses at all.**

**§5 the composition, which is the point of the module.**

```lean
theorem emptyReuse_compose (hsole : SoleFact H z) (he : mk z ∅ (∅ : Row) ∈ H) :
    makeEmptyE z (insert (mk z S ∅) H) = H ∪ emptyProp S

theorem resEmptyReuse_compose (hsole : SoleFact H z) (he : mk z ∅ (∅ : Row) ∈ H)
    (hx : x ≠ z) (hy : y ≠ z) :
    makeEmptyE z (resReuseResult H x y C D z) = resEmptyResult H x y C D
```

The Lean reuse's conclusion, put through the `makeEmptyE` step it forces, is EXACTLY what the
Scala emits: nothing is deleted (the carrier occurs nowhere else — that is `SoleFact`), the
`propPart` arm supplies `x <- ()` for the split's group, and the `erasePart` arm turns the
resolution reuse's two conclusions into the bare concrete ones.

**§6 adequacy for the retained-carrier relation.**

```lean
theorem splitEmpty_two_steps (happ : K2RowApp H c z C) (hsole : SoleFact H z)
    (he : mk z ∅ (∅ : Row) ∈ H) : K3ELoopRun 2 H (splitEmptyResult H c)

theorem resEmpty_two_steps (hp : ResPair H v x y C D) (hF : mk v ∅ F ∈ H)
    (hFCD : F \ (C ∪ D) = ∅) (hsole : SoleFact H z) (he : mk z ∅ (∅ : Row) ∈ H) :
    K3ELoopRun 2 H (resEmptyResult H x y C D)
```

`K3ELoopRun` is `KeyedEmpty`'s repaired relation — the one `mintsBoundedOnSatKeyed3E` bounds
on every satisfiable input in every order.  **One Scala step is two of its steps.**

**§7–§8 the rules, branch for branch, and adequacy.**  `scalaEmptySplit G c u rhss resolvent
concRow emptyRow` mirrors the source's FIVE branches in order (`scalaEmptySplit_syntactic`,
`_keyed`, `_row`, `_empty`, `_mint`; `scalaEmptySplit_eq_none_iff` pins the only no-op to the
early return `concr.isEmpty || abstr.size < 2`), and `scalaEmptyRes` the FOUR of `resolution`.
The adequacy theorems are

```lean
theorem scalaEmptySplit_run (hm : SModels rho H) (hmem : c ∈ H) (hfresh : u ∉ allVars H)
    (hsole : ∀ z, emptyRow = some z → SoleFact H z) (hr : RhssSpec …) (hres : ResolventSpec …)
    (hmy : MyRowSpec …) (hcr : ConcRowSpec …) (hem : EmptyRowSpec …)
    (h : scalaEmptySplit H c u rhss resolvent concRow emptyRow = some G') :
    ∃ n, K3ELoopRun n H G'
```

and `scalaEmptyRes_run`: whatever either extended rule returns is REACHABLE from the state by
a run of the repaired relation — one step for the four Stage 5 branches (via
`scalaRowSplit_step` / `scalaRowRes_step`, lifted by `run_of_splitStep` / `run_of_resStep`),
two for the new one.  A no-op is `n = 0`, so the statement is uniform.

**§9 the bound, explicitly.**  `bounded_of_run`, `scalaEmptySplit_bounded`,
`scalaEmptyRes_bounded`:

```lean
(allVars G').card ≤ (allVars H).card + hmeas (labelsOf H) rho H
```

— Stage 4's bound verbatim, now covering the rule as the compiler writes it, against BOTH
deletions.

**§10** the closed functions `scalaEmptySplitOf` / `scalaEmptyResOf` with their `_run` lemmas.

Lemma names, in one list: `SoleFact`, `SoleFact.lhs_ne`, `SoleFact.notMem_vset`,
`EmptyRowSpec`, `emptyRowSpec_toConcRow`, `emptyRowLookup(_spec)`, `emptyProp`,
`mem_emptyProp`, `splitEmptyResult`, `resEmptyResult`, `subset_splitEmptyResult`,
`subset_resEmptyResult`, `sat_empty_mk`, `splitEmpty_models_iff`, `res_empty_forced`,
`res_empty_F`, `resEmpty_models_iff`, `emptyReuse_compose`, `resEmptyReuse_compose`,
`run_of_splitStep`, `run_of_resStep`, `splitEmpty_two_steps`, `resEmpty_two_steps`,
`scalaEmptySplit`, `scalaEmptySplit_eq_none_iff`, `scalaEmptySplit_syntactic`, `_keyed`,
`_row`, `_empty`, `_mint`, `scalaEmptyRes`, `scalaEmptyRes_eq_none_iff`, `_reuse`, `_row`,
`_empty`, `_mint`, `scalaEmptySplit_run`, `scalaEmptyRes_run`, `bounded_of_run`,
`scalaEmptySplit_bounded`, `scalaEmptyRes_bounded`, `scalaEmptySplitOf(_run)`,
`scalaEmptyResOf(_run)`.

**Scope, stated in the module header.**  The adequacy theorems take `SoleFact H z` for the
carrier.  In the shipped configuration that is automatic: with `-Dermine.splitRow` /
`-Dermine.resRow` ON, a carrier still sitting in a queue is taken by the Stage 5 branch
BEFORE this one, so the empty-row branch is reached only with an environment carrier, whose
partitions `makeEmpty` has deleted.  With the Stage 5 flags off and this one on, the branch
can fire on a queued `w <- ()`; the emission is still entailed, but the two-step reading does
not apply.  As in Stage 5 the MINT branch needs a model, and nothing here is about ill-typed
input, `common`, `unify`, or `incorporateAll`'s single pass.

---

## Part B — the gates

Every gate below uses the SAME class files (`sbt -batch core/compile` at 03:39:09; no
recompile between configurations).

### B0. Seed replays — the positive controls

```
$ [ERMINE_JAVA_OPTS="-Dermine.emptyRow=true"] tracker/repro/satterm/sweep.sh <seed> 0 99
$ [ERMINE_JAVA_OPTS="-Dermine.emptyRow=true"] tracker/repro/crule/sweep.sh   <sys>  0 99
```

(driver `stage7/b0.sh`, raw output `stage7/b0/`).  `drawn` is the number of ids the run's
`Supply` handed out.

| seed | `D` | `E` |
|---|---|---|
| `W2` | SOLVED 100, draws 0 ×100 | same |
| `H2` | SOLVED 100, draws 2 ×38, 3 ×62 | same |
| `NE6` | SOLVED 100, draws 1 ×24, 2 ×20, 3 ×15, 4 ×21, 5 ×7, 6 ×3, 7 ×2, 10–18 ×8 | same |
| `W3` | SOLVED 100, draws 0 ×100 | same |
| `W4` | SOLVED 100, draws 0 ×95, 1 ×2, 3 ×3 | same |
| **`G7`** (NEW, tracked) | SOLVED 100, **draws 1 ×100** | SOLVED 100, **draws 0 ×100** |
| crule `W` (unsat) | REJECTED 100 | REJECTED 100 |
| crule `gseed` (unsat) | REJECTED 100 | REJECTED 100 |

The five pre-existing seeds are **identical line for line** apart from the banner and the
`TIME` summary (a clock); the two unsatisfiable systems are **byte-identical bar the
banner** — `diff` after stripping `in N ms` gives exactly 2 differing lines, both `genRules=`.

**The new tracked seed** `tracker/repro/satterm/seeds/G7.json` is `KeyedEmpty.G7` —
`p <- ((|l1|))`, `p <- (x, y, (|l1|))`, whose split group is FORCED empty — together with the
one bare `e <- ()` that `KeyedEmpty.G7_blocked` inserts, with `e` given the LOWEST id so the
`empty` step runs first and the fact is in the `SubstEnv`, not the queues, when the split
premise is dequeued.  Model `e = {}, p = {l1}, x = {}, y = {}`.  Its three variants and what
each measures:

| system | `D` | `E` | what it shows |
|---|---|---|---|
| `seeds/G7.json` (carrier EMPTIED first) | draws **1 ×100** | draws **0 ×100** | the Stage 7 gap: Stage 5's lookup cannot see the carrier |
| `stage7/G7queued.json` (same, `e` given the HIGHEST id, so `e <- ()` is still queued) | draws 0 ×100, `SplitRow` fires | 0 ×100 | Stage 5 already covers a QUEUED `∅` |
| `stage7/G7bare.json` (`KeyedEmpty.G7` verbatim, no carrier anywhere) | draws 1 ×100 | **1 ×100 — unchanged** | `G7_not_emptyKnown`: with no `makeEmpty` anywhere, the repair has nothing to find (deviation B7-1) |

**The traces, `G7` base 0** (`stage7/tr2.tsv`, `tr3.tsv`) — the brief's "trace the G7 instance
before deciding what the branch emits", and the evidence for §A.3:

```
D  genRules=cut+label-early+resguard+splitkey+splitrow+resrow           records=23 drawn=1 bound=5
     step  empty     ^free0 <- (,)                     <- makeEmpty e: the fact goes to the SubstEnv
     step  concrete  ^free1 <- (,l1)                   <- makeConcrete p
     step  learn     ^free1 <- (^free2 ^free3,l1)      <- the KEPT split premise, complement EMPTY
     learn new  SplitConcrete: ^ambiguous(free)4 <- (^free2 ^free3,)     <- MINT
     learn new  SplitConcrete: ^free1 <- (^ambiguous(free)4,l1)
     step  learn     ...
     learn new  Cancellation: ^ambiguous(free)4 <- (,)  <- the mint is forced empty
     step  empty     Cancellation: ^ambiguous(free)4 <- (,)
     step  empty     PartitionEmpty: ^free2 <- (,)      <- and NOW the group is propagated
     step  empty     PartitionEmpty: ^free3 <- (,)

E  genRules=…+emptyrow                                                  records=16 drawn=0 bound=4
     step  empty     ^free0 <- (,)
     step  concrete  ^free1 <- (,l1)
     step  learn     ^free1 <- (^free2 ^free3,l1)
     learn new  SplitEmpty: ^free2 <- (,)               <- THE NEW BRANCH: the propagation,
     learn new  SplitEmpty: ^free3 <- (,)                  directly, and no mint
     step  empty     SplitEmpty: ^free2 <- (,)
     step  empty     SplitEmpty: ^free3 <- (,)
```

Same solved system on both sides (`e = {}, p = {l1}, x = {}, y = {}`), 4 bound variables
instead of 5.  **The rule does in one step what the default does in five** — mint,
cancellation, `makeEmpty` — which is the Stage 5 slogan ("what `common` does in some order")
with a different long way round.

**The `ResolutionEmpty` control** had to be synthesised, as Stage 5's `W4c` was
(`stage7/W4e.json`, scratch — the brief authorises one new tracked seed):
`e <- ()`, `v <- ((|l1,l2|))`, `v <- (x,(|l1|))`, `v <- (y,(|l2|))`, model
`v = {l1,l2}, x = {l2}, y = {l1}, e = {}`, so the RESOLVENT row `F \ (C ∪ D)` is empty.
20 bases: `D` draws `0 ×15, 1 ×1, 3 ×4`; `E` draws `0 ×15, 1 ×5`.  At base 2:

```
D   records=32 steps=10 drawn=3 bound=5   byRule: Cancellation=2 Resolution=3 Substitution=2
      learn new  Resolution: ^free3 <- (^ambiguous(free)6,l2 l1)   <- MINT the resolvent
      learn new  Resolution: ^free5 <- (^ambiguous(free)6,l1)
      learn new  Resolution: ^free4 <- (^ambiguous(free)6,l2)
      ...  step empty  Cancellation: ^ambiguous(free)6 <- (,)      <- and it is forced empty

E   records=23 steps=6  drawn=1 bound=4   byRule: ResolutionEmpty=2
      learn new  ResolutionEmpty: ^free5 <- (,l1)                  <- the two conclusions with
      learn new  ResolutionEmpty: ^free4 <- (,l2)                     the carrier's row `∅` in
      step  concrete  ResolutionEmpty: ^free4 <- (,l2)                place of the carrier
      step  concrete  ResolutionEmpty: ^free5 <- (,l1)
```

Same solved system, one bound variable fewer.  (`drawn` is 1 rather than 0 on the `E` side
because `resolution` draws its id BEFORE the match, as `resGuard` arranged and as Stage 5
§C.2 records.)

### B1. Stdlib boot

```
$ ERMINE_JAVA_OPTS="-Xmx2g -Dermine.useInterface=false [-Dermine.emptyRow=true]" bin/ermine </dev/null
```

| run | `D` wall / program's own `Loaded 129 modules (s)` | `E` wall / same |
|---|---|---|
| 1 | 12.19 s / 11.36 s | 12.14 s / 11.29 s |
| 2 | 12.17 s / 11.30 s | 12.05 s / 11.21 s |
| 3 | 12.03 s / 11.19 s | 12.10 s / 11.24 s |

**129 modules on both sides, all six runs; boot time identical within noise.**  Traced
(`-Dermine.rowTrace`, `-Dermine.loadInSeries=true`, one run per side):

| | `D` | `E` |
|---|---|---|
| trace records | 60,088 | 60,088 |
| `learn` records | 1,631 | 1,631 |
| by rule | CSE 785, Cancellation 424, Substitution 417, DeDuplication 3, SelfSubstitution 2 | identical |
| `SplitEmpty` / `ResolutionEmpty` | 0 / 0 | **0 / 0** |

**The two trace files are byte-identical (`cmp`).**  The stdlib boot cannot see the flag:
neither `splitConcrete` nor `resolution` fires in it at all — the same population fact
Stages 2 and 5 record, and the same 60,088/1,631 figures Stage 5 measured.

### B5. REPL and LSP smoke

`repl-smoke.sh` and `lsp-smoke.sh` invoke `java` directly and do not read `ERMINE_JAVA_OPTS`,
so the flag went in through `_JAVA_OPTIONS` (visible in the LSP log's own
`Picked up _JAVA_OPTIONS: -Dermine.emptyRow=true`).

| | `D` | `E` |
|---|---|---|
| `repl-smoke.sh` | PASS aliasing (2), relations (6), scoping (4), smoke (23) — **4/4 suites, 35 checks** | **identical, 4/4, 35 checks** |
| `lsp-smoke.sh` | **PASS lsp (98 checks)** | **PASS lsp (98 checks)** |

### B2. Corpus verdicts

```
$ ERMINE_JAVA_OPTS="-Xmx2g [-Dermine.emptyRow=true]" tracker/tools/corpus-run.sh --batch <out>       # 66 files
$ ERMINE_JAVA_OPTS="-Xmx2g [-Dermine.emptyRow=true]" tracker/tools/corpus-run.sh --incomplete --batch <out>  # 34
$ tracker/tools/corpus-verdicts.py <outD> <outE>
```

Four passes, **run strictly sequentially**, never alongside `ei-diff.sh`, `--batch` on BOTH
sides (batch is valid only batch-vs-batch).  Driver `stage7/b2.sh`.

| corpus | configuration | LOADED | REJECTED | UNKNOWN | total |
|---|---|---|---|---|---|
| examples + `Ai/` + `shouldfail/` | `D` | **23** | **43** | 0 | 66 |
| examples + `Ai/` + `shouldfail/` | `E` | **23** | **43** | 0 | 66 |
| `incomplete/` | `D` | **18** | **16** | 0 | 34 |
| `incomplete/` | `E` | **18** | **16** | 0 | 34 |

* `shouldfail/`: **40 of 40 REJECTED on both sides**, 0 modules loading.
* `corpus-verdicts.py`: **every VERDICT identical**; **1 of 66** and **3 of 34** files differ,
  all four in the MESSAGE only.  Whole-output text diff with the loader progress bar and the
  `(N.NN seconds)` timings normalised: the same 1 and 3 files, nothing else.
* The four are `shouldfail/der02_copy_column_onto_existing`,
  `incomplete/np03b_pinned_placeholder_rejects_refunds`, `incomplete/unsound01_keyed_halves`
  and `incomplete/unsound04_dead_helper`; in each the message is a DIFFERENT CLAUSE of the
  same label-check refutation at the SAME field and the SAME source position ("two parts of
  one partition both contain it" against "the whole contains it but no part does").
* **Re-run PER FILE on both sides, twice each** (`stage7/b2f.sh`), which is what the brief
  asks for: see B7-2 for the verdict and the mechanism.

**The per-file re-runs, in full** (`bin/ermine <file>` alone, `-Dermine.useInterface=false`,
`.ei` deleted before every run, twice per side):

```
=== shouldfail/der02_copy_column_onto_existing
  D-1 / D-2 / E-1 / E-2   ...at field 'Shouldfail.Der02.b': the whole contains it but no part does
=== incomplete/np03b_pinned_placeholder_rejects_refunds
  D-1 / D-2 / E-1 / E-2   ...at field 'Incomplete.Np03b.refund': the whole contains it but no part does
=== incomplete/unsound01_keyed_halves
  D-1 / D-2 / E-1 / E-2   ...at field 'Incomplete.Unsound01.accountId': the whole contains it but no part does
=== incomplete/unsound04_dead_helper
  D-1 / D-2 / E-1 / E-2   ...at field 'Incomplete.Unsound04.amount': the whole contains it but no part does
```

**All four are IDENTICAL per file on both sides** — the difference is the documented
`--batch` session drift (`corpus-run.sh`'s own header, `TICKET-editor-and-solver-
followups.md` item 4), **not the flag**.  Note also that in each case the per-file message
agrees with whichever side the batch happened to give it to, in both directions (the batch
`D` side produced "two parts…" on `der02` and the batch `E` side on `unsound01`/`unsound04`),
which is what session drift looks like and what a flag effect would not.

### B3. Published types (`.ei`)

```
$ tracker/tools/ei-diff.sh <out> "-Dermine.emptyRow=true"   # PER FILE, 2 x 110 example modules,
$ tracker/tools/ei-diff.sh <ctl> ""                         #   interfaces ENABLED; then the control
$ tracker/tools/ei-classify.py <out>/A <out>/B
```

Two invocations, each running BOTH sides itself, **strictly sequential and with nothing else
touching `.ei`** (driver `stage7/b3.sh`).  PER FILE, not `--batch` — the batch mode loses
chunks to the time cap.  Each sweep covers all 110 `core/examples/**/*.e` and snapshots BOTH
trees, the example interfaces and the 129-module stdlib under
`core/target/scala-3.3.8/classes/modules`: **188 interfaces, 1,933 bindings, none missing on
either side** (`only-in-A -  only-in-B -` in both).

| comparison | interfaces differing | bindings: identical / order-only / alpha-eq / **weaker** / other |
|---|---|---|
| **`D` vs `D′`** (same configuration, control) | **3** of 188 | 1901 / 28 / 3 / **0** / 1 (`Relation.lookbackJoin`) |
| `D` vs `E` | 8 of 188 | 1894 / 32 / 4 / **0** / 3 (`lookbackJoin`, `np01.inferredRestate`, `RunCalibration.scaledRuns`) |

**No signature became weaker anywhere: `concrete->polymorphic` is 0 in both comparisons.**

*(The control's side B ran with `-Dermine.spliceGuard=true`, because `ei-diff.sh`'s
`flagsB="${2:--Dermine.spliceGuard=true}"` treats an empty second argument as unset.  That
property was REMOVED from the compiler on 2026-09-02 and survives only in a comment
(`grep -rn spliceGuard core/src/main/scala` finds one comment line and no code), so both
sides really are the default configuration and the control is valid — the same note Stage 5
made.)*

**`Relation.lookbackJoin` is CHURN, and the control proves it here rather than by citation**:
it is the single `other` of the same-configuration control (constraints 9 → 10 between two
runs of ONE build), and it is the binding Stage 2's and Stage 5's controls produced as their
single `other` too.  Of the eight interfaces that move in `D` vs `E`, five are stdlib
(`Relation`, `Relation/Op`, `Relation/Predicate`, `Layout/Chart`, `Layout/Report`) and three
of those five are exactly the control's; **no stdlib interface CAN be attributable**, because
B1 shows the 129-module boot's trace is byte-identical `D` vs `E` and neither
`splitConcrete` nor `resolution` fires there at all.

**So exactly TWO bindings are attributable to the flag, both in `incomplete/`, and both are
equivalent — hand-classified below.**  (`core_examples_GridExample.stackedBarChart` also moves,
in a module where the branch fires twice, but the classifier's own verdict is `order-only`:
the same constraints in a different order.)

**`incomplete/np01.inferredRestate`, by hand.**  Write `K3 = (|unitCost, qty, unitPrice|)` and
`K4 = K3 ⊎ (|revenue|)`, and rename `E`'s `so`/`so1` to match `D`'s (`E` uses the names the
other way round).

```
D  7 existentials so, rs, a, b, rs1, t1, so1;  8 constraints
     (|revenue|) <- (rs1, so1)     t  <- (K4, rs, so, a)      t1 <- (K3, rs1, so1, b)
     r  <- (K3, rs1, b)            (|margin|) <- (rs, so)     r  <- (K3, b, rs1)
     RelationalComb rel            t1 <- (K4, rs, a)

E  6 existentials a, rs, rs1, so, t1, so1;    7 constraints
     (|revenue|) <- (rs1, so1)     t  <- (K4, rs, so, a)      t1 <- (K3, rs1, so1, rs, a)
     r  <- (K3, rs1, rs, a)        (|margin|) <- (rs, so)
     RelationalComb rel            t1 <- (K4, rs, a)
```

Five constraints are identical.  `E`'s other two are `D`'s with `b` replaced by the pair
`(rs, a)` — and **`b = rs ⊎ a` is FORCED in `D`**: `t1 <- (K4, rs, a)` gives
`t1 = K4 ⊎ rs ⊎ a`, while `t1 <- (K3, rs1, so1, b)` with `(|revenue|) <- (rs1, so1)` and
`K4 = K3 ⊎ (|revenue|)` gives `t1 = K4 ⊎ b`.  Substituting turns `D` into `E` and
instantiating `b` turns `E` into `D`, so the two published contexts are equivalent on
`(rel, r, t)` — a conservative extension at a name, in the direction that REMOVES the name.
`D`'s eighth constraint is its own order-only duplicate of `r <- (K3, rs1, b)`, which is why
the count is 8 → 7.  **This is the same binding, in the same direction (7 existentials → 6),
that Stage 5 measured for `-Dermine.splitRow`.**

**`incomplete/RunCalibration.scaledRuns`, by hand.**  Both sides publish SEVEN existentials; the
classifier flags it only because the constraint count falls 7 → 6.  Under the renaming
`E.d ↦ D.c`, `E.a ↦ D.d`, `E.b ↦ D.a`, `E.c ↦ D.b` the six `E` constraints are, one for one,
six of `D`'s seven — and `D`'s remaining constraint, `c <- (K4, d, rs)`, is an ORDER-ONLY
DUPLICATE of `c <- (K4, rs, d)`, which `E` does not publish twice.  **Equivalent, one
duplicate fewer.**

### B4. Timing — one JVM at a time, machine idle

```
$ ERMINE_JAVA_OPTS="-Xmx2g -Dermine.useInterface=false [-Dermine.emptyRow=true]" bin/ermine <instance> </dev/null
```

Drivers `stage7/b4.sh` (the generator family and `gu05`) and `stage7/b4b.sh` (three corpus
modules).  Each timed run waits (`ps -eo comm=`, polling) until NO other `java` process exists
and is marked `[NOT IDLE]` if it gives up — none was; the figure quoted is the program's own
`Importing module 'X' (N seconds)`, which excludes the ~12 s stdlib boot.

Module time, seconds (`p1` / `p2`):

| instance | `D` | `E` | `E/D` |
|---|---|---|---|
| ResStar5 | 0.18 | 0.16 | 0.89 |
| ResStar6 | 0.49 | 0.52 | 1.06 |
| ResStar7 | 1.84 | 1.86 | 1.01 |
| ResStar8 | 12.31 / 11.66 | 13.16 / 12.55 | 1.07 |
| ResStar9 | 72.57 / 80.08 | 76.22 / 80.94 | 1.05 / 1.01 |
| RowStress10 | 0.22 | 0.19 | 0.86 |
| RowStress14 | 0.44 | 0.45 | 1.02 |
| CoStar8 | 0.04 | 0.04 | (0.04 s) |
| `Accumulate.e` (0 firings) | 0.11 / 0.10 | 0.13 / 0.12 | 1.2 (of 0.1 s) |
| `incomplete/np01` (12 `SplitEmpty`, 75 `ResolutionEmpty`) | 0.45 / 0.43 | 0.47 / 0.47 | **1.07** |
| **`incomplete/gu05`** (0 / 44), three runs each | **1.08 / 0.99 / 1.03** | **1.95 / 2.08 / 1.96** | **1.9** |

**The `ResStar` family and the generators do not move**: every ratio is inside the
within-configuration spread (`D`'s own ResStar9 spread is 72.57 → 80.08 s, 10 %, larger than
any gap; ResStar8's steady 1.07 is 0.7 s on a 12 s run and within its own 5.6 % spread).  As
in Stage 5, the family cannot reach the new branch anyway — no left-hand side there is ever
concrete, so `myRow` is `None` and the lookup returns without touching the environment.

**`gu05` DOES move, and against us: 1.9× slower, three runs to three, far outside any spread.**
That is the one gate that failed, and B7-4 has what was and was not established about it.

### B6. Trace-based population: does the branch fire on real code?

```
$ KEPTDEF_EXTRA="[-Dermine.emptyRow=true]" stage7/keptdef-sweep-flag.sh --batch <out>   # 110 modules, 4 JVMs
$ python3 tracker/tools/keptdef-mints.py <(zcat <out>/trace-<group>.tsv.gz) --filter core/examples
$ python3 stage7/agg7.py <out>-*.kept                                                  # sums the four groups
```

110 `core/examples/**/*.e` in four serialized (`-Dermine.loadInSeries=true`)
`-Dermine.rowTrace` runs, one per corpus directory, `-Dermine.useInterface=false`, counts
attributed to solves under `core/examples` by the extended `keptdef-mints.py`.

**The segmentation does survive a batch** (the brief's check): `Subst.scala`'s `solve` record
carries the solve's source location, so `--filter core/examples` picks the corpus's solves
out of a whole group's trace exactly as it does per file.  **What does NOT survive is the
POPULATION**: in a batch every module is compiled in a session that already holds the modules
ahead of it, and `Ai/Common.e` is loaded once instead of once per `Ai` module, so the batch
sees far more solve segments than the per-file sweep and the absolute counts are NOT
comparable with Stage 5's per-file baseline of 157 kept-definition mints.  B6 is therefore reported PER FILE, which is the
mode Stage 5's 157 comes from (B7-3 has the batch attempt and why it was abandoned).

**The instrument's own positive control first** (`keptdef-mints.py`'s new `SplitEmpty`
bucket, on the two `G7` traces of B0 and the `W4e` trace):

| trace | MINTED | ROW-REUSED | **EMPTIED the group** | whole-trace `SplitEmpty` | `ResolutionEmpty` |
|---|---|---|---|---|---|
| `G7` base 0, `D` | **1** | 0 | 0 | 0 | 0 |
| `G7` base 0, `E` | **0** | 0 | **1** | **2** (one per group member) | 0 |
| `W4e` base 2, `E` | 0 | 0 | 0 | 0 | **2** |

so the bucket is recognised, and it is recognised the way the branch actually emits — by the
GROUP being covered by bare `SplitEmpty: ^x <- (,)` records, since this branch emits no name.

**The corpus, 110 modules, one serialized `-Dermine.rowTrace` JVM per module**
(`stage7/b6f.sh`, `KEPTDEF_TIMEOUT=180`, `-Dermine.useInterface=false`; aggregated by
`stage7/agg7.py`, compared per module by `stage7/cmp6.py`):

| | `D` | `E` |
|---|---|---|
| modules analysed | 110 | 110 |
| solve segments | 55,338 | 55,338 |
| `makeConcrete` steps | 3,613 | 3,612 |
| kept-definition dequeues | 738 (337 strict) | 697 (312) |
| ...with a nonempty concrete part | 298 | 291 |
| **kept-definition MINTS** | **154** (23 strict) **in 27 modules** | **82** (22) **in 25** |
| ...syntactically reused | 136 | 142 |
| ...KEYED-reused | 4 | 2 |
| ...ROW-reused (`SplitRow`) | 4 | 0 |
| **...EMPTIED the group (`SplitEmpty`)** | — | **65** |
| **whole-trace split MINTS** | **626** | **561** |
| whole-trace `SplitKeyed` | 76 | 76 |
| whole-trace `SplitRow` | 4 | 0 |
| **whole-trace `SplitEmpty` partitions** | 0 | **130** (= 65 firings × 2 group members) |
| **whole-trace `Resolution` conclusions** | **1,644** | **792** |
| whole-trace `ResolutionRow` | 19 | 14 |
| **whole-trace `ResolutionEmpty` partitions** | 0 | **366** (= 183 firings × 2) |

**The `D` column reproduces Stage 5's `B` column exactly** — 55,338 segments, 3,613
`makeConcrete`, 738 (337) dequeues, 298 with a concrete part, 154 mints, 136/4/4 reuses, 626
whole-trace split mints, 76 `SplitKeyed`, 4 `SplitRow`, 1,644 `Resolution`, 19
`ResolutionRow`.  That is the right baseline: today's default IS Stage 5's `B` (both Stage 5
flags were adopted), so the figure to compare against is **154 kept-definition mints, not the
157 of Stage 5's flags-off `D`**.

**The brief's question — of the kept-definition mints, how many become the new reuse?**

```
$ python3 stage7/pre-empty.py stage7/b6f/D/trace-*.tsv.gz
TOTALS {'mints': 154, 'compl-empty': 73, 'mod-empty': 73, 'seg-empty': 13}
```

* **73 of the 154 have an EMPTY complement** under today's default (Stage 5 counted 74 of 157
  under the older one), and at **73 of 73** a `makeEmpty` has already run in that module —
  which is what the branch needs.
* Under `E`, **65 kept-definition dequeues take the new branch** and the kept-definition mint
  count falls **154 → 82, by 72**.  The small gap between 73, 72 and 65 is the trajectory:
  emptying a group deletes partitions, so the kept-definition dequeues themselves fall
  738 → 697 and some of those premises never arrive.  **Essentially the whole
  empty-complement population is gone.**
* Corpus-wide the split mints fall 626 → 561 (−10.4 %) and resolution's conclusions fall
  **1,644 → 792 (−52 %)**, the largest population effect any flag in this series has had.

**Which modules move** (19 of 110; every other module is identical in both configurations,
and the LOADED/REJECTED verdict is identical on all 110):

| module | kept mints `D`→`E` | `SplitEmpty` | whole split mints | `Resolution` `D`→`E` | `ResolutionEmpty` |
|---|---|---|---|---|---|
| `Ai/BatteryCycling.e` | 7 → 3 | 4 | 23 → 20 | 52 → 27 | 8 |
| `Ai/ClinicalTrial.e` | 4 → 2 | 3 | 15 → 13 | 31 → 22 | 5 |
| `Ai/FiscalCalendar.e` | 4 → 1 | 2 | 17 → 12 | 56 → 15 | 5 |
| `Ai/GridTelemetry.e` | 9 → 5 | 4 | 42 → 38 | 81 → 43 | 21 |
| `Ai/HeadcountPlan.e` | 9 → 4 | 5 | 36 → 29 | 113 → 42 | 26 |
| `Ai/IncidentSeverity.e` | 10 → 4 | 5 | 34 → 30 | 98 → 48 | 29 |
| `Ai/RevenueByPeriod.e` | 9 → 5 | 5 | 36 → 31 | 68 → 44 | 21 |
| `Ai/SalesByRegion.e` | 8 → 3 | 4 | 31 → 27 | 59 → 33 | 11 |
| `Ai/SupplyChainInventory.e` | 9 → 4 | 5 | 40 → 35 | 94 → 49 | 30 |
| `Ai/TelescopeTime.e` | 8 → 4 | 6 | 35 → 32 | 63 → 40 | 18 |
| `GridExample.e` | 2 → 0 | 2 | 2 → 0 | 12 → 6 | 3 |
| `SoftRelation.e` | 3 → 3 | 0 | 7 → 7 | 6 → 3 | 1 |
| `incomplete/.probeC.e` | 5 → 5 | 0 | 20 → 20 | 156 → 63 | 54 |
| `incomplete/RevenueShare.e` | 3 → 1 | 1 | 23 → 22 | 47 → 38 | 4 |
| `incomplete/RunCalibration.e` | 1 → 0 | 1 | 23 → 22 | 18 → 15 | 2 |
| `incomplete/gu05_star_join_4dim_concrete_signature.e` | 6 → 6 | 0 | 14 → 13 | 125 → 31 | 44 |
| `incomplete/gu08_label_inline.e` | 6 → 3 | 3 | 18 → 15 | 65 → 25 | 4 |
| `incomplete/np01_add_or_recompute.e` | 32 → 16 | 12 | 100 → 89 | 345 → 158 | 75 |
| `incomplete/np05_label_column_no_escape.e` | 8 → 2 | 3 | 24 → 20 | 93 → 28 | 5 |

**Neither branch is dead code and neither is rare** — which is the difference from Stage 5.
`SplitEmpty` fires 65 times over 16 of the 110 modules; `ResolutionEmpty` 183 times over 19.
Both are zero in the 129-module stdlib boot (B1), as every split/resolution count there is.

**The design rule, "a name, never silence" (`ROW-CONSTRAINT-STATE.md`, Stage 3).**  This
branch emits no NAME for the group — but it does not emit silence either: it emits the
group's VALUES, `x <- ()` for every member, which is strictly more information than a name
for a row that is forced to be `∅`.  The channel the rule protects — two kept definitions of
one group meeting through the minted name — survives in its strongest form, because the
shared variables are pinned to `∅` everywhere, so any later partition mentioning them is
resolved by substitution rather than by unification with a mint.  (Stage 5's
`keptmint-consumers.py` measured "does something later use the mint as a name"; the question
does not transfer, because there is no name to use.  It is not measured here, and that is
stated rather than papered over.)


### B7. Every gate that differed from expectation, with its mechanism

**B7-1. The BARE `G7` — `KeyedEmpty.G7` with no empty-row carrier anywhere — is NOT changed
by the flag** (expected from the brief: "`G7` mints under `D` at some bases and never under
`E`").  Measured (`stage7/G7bare.json`, 100 bases): 1 draw at every base on BOTH sides.

Mechanism, and it is the Lean's own theorem: `KeyedEmpty.G7_not_emptyKnown`.  `G7` is two
constraints, nothing in it is ever made empty, and the repair this stage implements is
`makeEmptyE` — RETAIN the fact `makeEmpty` produces.  Where no `makeEmpty` has run there is no
fact to retain, and `G7_blocked` is explicit that what turns the mint into a reuse is the
INSERTION of one `e <- ()`.  So the tracked seed is `G7` plus that constraint, and the honest
statement of what the flag buys is not "the `G7` shape stops minting" but "**the `G7` shape
stops minting once anything in the solve has been made empty**" — which, on real code, is the
case at 74 of 74 of the empty-complement mints (§A.2).  The bare seed is kept in scratch as
the negative control.

**B7-2. Four corpus files differ in MESSAGE in `--batch` mode, and none of them is the flag.**
Expected: message-clause drift on a few `shouldfail/` files.  Measured: `shouldfail/der02`
(66-corpus) and `incomplete/np03b`, `unsound01`, `unsound04` (34-corpus), each a different
CLAUSE of the same label-check refutation at the same field and position, verdict unchanged.
Re-run PER FILE on both sides, twice each: **all four identical**, and the clause that the
per-file run produces is claimed by the `D` batch in one case and by the `E` batch in the
others.  That is the documented `--batch` session-id drift (`corpus-run.sh`'s header,
`TICKET-editor-and-solver-followups.md` item 4), not the flag.

**B7-3. `keptdef-sweep.sh --batch` does NOT survive the `incomplete/` group under
`-Dermine.rowTrace`, so B6 was taken PER FILE.**  The brief asked for `--batch` "(its
segmentation survives a batch; check)".  The segmentation does survive — `--filter
core/examples` picks a file's solves out of a group trace, and the `top`, `Ai` and
`shouldfail` groups completed in about four minutes each.  The `incomplete` group does not:
its four `.slow` modules diverge, one JVM must hold all 34 files, and with the trace on the
group's `.tsv` passed **504 MB in five minutes** and was heading for the 1800 s group cap
with no per-file cut-off — where the per-file mode's `KEPTDEF_TIMEOUT=180` truncates each
divergent file and keeps the rest measurable.  The batch run was stopped and B6 was taken in
the per-file mode, which is also the mode Stage 5's 157-mint baseline comes from, so the two
stages' numbers are directly comparable.

**B7-4. `incomplete/gu05` is 1.9× SLOWER under `E` (1.03 s → 1.96 s, medians of three runs
each), and the cause was NOT isolated.**  Expected: no timing movement, as in Stage 5.  This
is the one gate that fails, and it fails on the module that carried `splitKey`'s 5× win and
`resGuard`'s 11× win — the corpus's most expensive solve.

What IS established:

* It is not noise: 1.08 / 0.99 / 1.03 against 1.95 / 2.08 / 1.96, one JVM at a time on an
  idle machine, and reproduced again under JFR (1.36 s vs 2.61 s with the recorder attached).
* **It is not proportional to how often the branch fires.**  `np01`, where the branch fires
  most on the whole corpus (12 `SplitEmpty` + 75 `ResolutionEmpty` partitions), costs
  **+7 %** (0.44 → 0.47 s); `gu05`, with 0 `SplitEmpty` and 44 `ResolutionEmpty`, costs
  +90 %.  A module where the branch never fires (`Accumulate.e`) costs 0.01 s more, which is
  its own noise.
* **It is not more derivation.**  Under the serialized loader `gu05`'s whole trace is
  61,989 records / 1,496 `learn new` under `D` against 61,652 / 1,174 under `E`, with FEWER
  `empty` steps (59 → 33) and one fewer `concrete` step (29 → 28).  `E` derives less and
  takes longer.
* **Where the time goes, by JFR** (`stage7/gu05-{D,E}.jfr`, `jfr-buckets.py`; the recording
  covers the whole run, so the module's 1.25 s difference is ~33 extra samples): the
  attribution moves OUT of free-variable collection (32.5 % → 27.8 %) and the parser
  (27.0 % → 24.0 %) and INTO the row-constraint machinery — `row-constraint queue`
  5.1 % → 7.4 %, `row-constraint rules` 1.0 % → 3.2 %, `substitution application`
  16.1 % → 18.1 %.  The leaves that grow are `Constraints$Q$.part` (5 → 11 samples), the
  finger-tree monoid `Constraints$Q$$anon$1.append` (4 → 9), `Constraints$RHS.hashCode`
  (6 → 8) and `PQueue.foldLeft` (0 → 5).
* **The environment scan is NOT visible.**  No `Map`/`collectFirst` frame appears anywhere in
  either profile, and the leaves that grow are queue inserts and queue folds.  So the
  hypothesis of §A.2 — that `hm.types.collectFirst` would be the cost — is NOT what the
  profile shows.

What is NOT established: which of the queue's costs it is.  The two candidates the profile
leaves standing are (i) the emitted conclusions are BARE CONCRETE (`x <- ((|D \ C|))`) where
the mint's were variable-headed, and every insert of a non-empty, non-lone-variable
right-hand side makes `Q.rhsLookup` scan the whole queue for a common right-hand side
(`RHS.hashCode` is on the list), which is quadratic in a queue as large as `gu05`'s; and
(ii) each such fact then drives a `makeConcrete` / `destructiveSub` pass over both queues
earlier than the mint route would have.  Distinguishing them needs an instrumented build,
which is a Stage 8 measurement, not a Stage 7 one.

**This is the finding that decides the recommendation** (Part C.5): every correctness gate is
green, the theorem is the strongest of the series, and the population is the largest — but a
1.9× regression on the corpus's most expensive module, with no isolated cause, is not
something to make a default.

**B7-5. The Stage 5 branches lose firings under `E`: `SplitRow` 4 → 0, `ResolutionRow`
19 → 14, kept-definition keyed reuses 4 → 2.**  Expected: the new branch is strictly after
them, so they should be untouched.  Mechanism: the same incomparability Stage 5's B7-4 and
B7-6 recorded, one layer further.  The branches are ordered within ONE call, but across calls
a reuse changes what the next dequeue sees; emptying a group deletes partitions from both
queues, so the premises at which `SplitRow` fired under `D` are, under `E`, either already
resolved or never dequeued (kept-definition dequeues fall 738 → 697).  Nothing is lost by it:
those four premises end as reuses of a different kind or do not arise.

**B7-6. TWO published bindings are attributable to the flag, where Stage 5's `resRow` had
none.**  Expected (from Stage 5's shape): stdlib churn only.  Measured: `incomplete/np01.
inferredRestate` (7 existentials → 6) and `incomplete/RunCalibration.scaledRuns` (one order-only
duplicate fewer), both hand-checked EQUIVALENT in §B3 and both in the direction that removes
a name — the same direction, and for `np01` the same binding and the same 7 → 6, that Stage 5
measured for `-Dermine.splitRow`.  `Relation.lookbackJoin` also moves, and the
same-configuration control shows it moving there too, so it is churn.  **No signature is
weaker in either comparison.**


---

## Part C — the path to default

### C.1 The gate table

`D` = today's default (`splitkey+splitrow+resrow`), `E` = `-Dermine.emptyRow=true`.
One class set for every row.

| gate | expected | `D` | `E` | verdict |
|---|---|---|---|---|
| `sbt -batch core/compile` | clean | ok, 11 s | — one class set for both columns — | PASS |
| `core/test` (911) | 910/911, known `disjunction sound` starvation | **910/911** | **910/911** | PASS |
| B0 `W2` 100 bases | solved, unchanged | 100 SOLVED, draws 0 ×100 | = `D` | PASS |
| B0 `H2` 100 bases | solved, unchanged | 100 SOLVED, 2 ×38 / 3 ×62 | = `D` | PASS |
| B0 `NE6` 100 bases | solved, unchanged | 100 SOLVED, 1–18 draws | = `D` | PASS |
| B0 `W3` 100 bases | solved, unchanged | 100 SOLVED, draws 0 ×100 | = `D` | PASS |
| B0 `W4` 100 bases | solved, unchanged | 100 SOLVED, 0 ×95 / 1 ×2 / 3 ×3 | = `D` | PASS |
| **B0 `G7` 100 bases** (NEW tracked seed) | mints under `D`, **never under `E`** | 100 SOLVED, **draws 1 ×100** | 100 SOLVED, **draws 0 ×100** | PASS, non-vacuous |
| B0 `G7` base 0 trace | `SplitEmpty` must fire | mint + cancellation + `makeEmpty` (8 steps) | **`SplitEmpty: ^free2 <- (,)`, `^free3 <- (,)`** (5 steps) | PASS |
| B0 `G7bare` (scratch) | — | draws 1 ×100 | **1 ×100, unchanged** | DEVIATION (B7-1), explained |
| B0 `W4e` control (scratch) | `ResolutionEmpty` must fire | base 2: 3 draws, 3 `Resolution` | **1 draw, 2 `ResolutionEmpty`** | PASS, non-vacuous |
| B0 crule `W` (unsat) 100 bases | still rejected | 100 REJECTED | 100 REJECTED, byte-identical bar the banner | PASS |
| B0 crule `gseed` (unsat) 100 bases | still rejected | 100 REJECTED | 100 REJECTED, byte-identical bar the banner | PASS |
| B1 stdlib boot | 129 modules | 129, 11.19–11.36 s | 129, 11.21–11.29 s | PASS |
| B1 boot trace | (population fact) | 60,088 records, 1,631 learns | **byte-identical**; `SplitEmpty`/`ResolutionEmpty` 0/0 | PASS (flag invisible there) |
| B2 examples corpus (66), `--batch` both sides | 23/43, no verdict change | 23 LOADED / 43 REJECTED | 23/43, **1 of 66 differs, MESSAGE only** | PASS (B7-2) |
| B2 `shouldfail/` (40) | 40/40 rejected | 40/40 | 40/40 | PASS |
| B2 `incomplete/` (34), `--batch` both sides | 18/16 | 18/16 | 18/16, **3 of 34 differ, MESSAGE only** | PASS (B7-2) |
| B2 the four message differences | drift or flag? | — | **drift**: identical per file, twice per side | PASS |
| B3 published types (188 interfaces, 1,933 bindings, per file) | **no signature weaker** | control `D` vs `D′`: 3 interfaces, 1 `other` (`lookbackJoin`) | `D` vs `E`: 8 interfaces, **0 weaker**, **2 attributable, both equivalent** | PASS (B7-6) |
| B4 ResStar 5–9, RowStress 10/14, CoStar8 | unchanged | see §B4 | 0.86–1.07×, all inside `D`'s own spread | PASS |
| B4 `np01` (most firings), `Accumulate` (none) | unchanged | 0.44 s / 0.10 s | 0.47 s / 0.12 s | PASS |
| **B4 `gu05`, three runs each** | unchanged | **1.03 s** (1.08/0.99/1.03) | **1.96 s** (1.95/2.08/1.96) | **FAIL — 1.9×, cause not isolated (B7-4)** |
| B5 `repl-smoke` | 4/4 | 4/4, 35 checks | 4/4, 35 checks | PASS |
| B5 `lsp-smoke` | 98/98 | PASS 98 | PASS 98 | PASS |
| B6 firings on real code (110 modules) | non-zero, or say so | 0 | **`SplitEmpty` 65 in 16 modules, `ResolutionEmpty` 183 in 19** | PASS, non-vacuous |
| B6 kept-definition mints | fewer | 154 in 27 modules | **82 in 25** | PASS |
| B6 whole-trace split mints | fewer | 626 | **561** | PASS |
| B6 `Resolution` conclusions | fewer | 1,644 | **792** | PASS |
| B6 verdicts over 110 modules | unchanged | — | 0 differ | PASS |
| Part D `lake build Rowpartition` | green | **820 jobs** | | PASS |
| Part D `lake env lean Audit.lean` | 0 non-standard | **2,378 audited, 0 non-standard** | | PASS |

### C.2 The exact unapplied one-line diff, and the ADOPTED comment it would need

NOT applied.  One character in one line, plus a comment paragraph.

`core/src/main/scala/com/clarifi/reporting/ermine/Constraints.scala`, line 1026:

```diff
-    val emptyRow: Boolean = System.getProperty("ermine.emptyRow", "false") == "true"
+    val emptyRow: Boolean = System.getProperty("ermine.emptyRow", "true") == "true"
```

and lines 1024–1025 would change from

```
     * DEFAULT OFF pending the adoption gates in `tracker/satterm/KEYED-EMPTY-STAGE7.md`.
     * `-Dermine.emptyRow=true` enables it. */
```

to an ADOPTED paragraph in the shape the other seven flags use:

```
     * ADOPTED <date>: DEFAULT ON.  `-Dermine.emptyRow=false` restores the previous
     * behaviour exactly.  The evidence (`tracker/satterm/KEYED-EMPTY-STAGE7.md`):
     *   - proved not a semantic change, and WITHOUT needing the carrier:
     *     `KeyedEmptyScala.splitEmpty_models_iff` (through `KeyedEmpty.group_forced_empty`:
     *     a concrete definition of `v` whose row IS the premise's concrete part forces every
     *     variable of the premise's group to `∅`) and `resEmpty_models_iff` (through
     *     `res_empty_forced`);
     *   - it is the flag that closes the SECOND deletion: with it, minting is bounded on
     *     every satisfiable input in every run order against BOTH the concretisation and
     *     `makeEmpty` (`KeyedEmpty.mintsBoundedOnSatKeyed3E`), which Stage 6 proved FALSE for
     *     `makeEmpty` as the compiler leaves it (`carried_not_invariant`, `hmeas_increases`);
     *     and the rule AS WRITTEN is a step-pair of that calculus
     *     (`KeyedEmptyScala.emptyReuse_compose`, `splitEmpty_two_steps`,
     *     `scalaEmptySplit_run`, `scalaEmptySplit_bounded`, and the same four for
     *     `resolution`);
     *   - the tracked seed `G7` (`KeyedEmpty.G7` plus the `e <- ()` of `G7_blocked`): the
     *     re-mint happens at 100 of 100 id bases with the flag off and at NONE with it on,
     *     same solved system with one bound variable fewer;
     *   - 66-file example corpus and 34-file incompleteness corpus: verdicts identical
     *     (23/43 and 18/16), `shouldfail/` 40/40 still rejected, and the four files whose
     *     batch MESSAGE differs are identical when re-run per file (batch session drift);
     *   - 188 published interfaces / 1,933 bindings, per file, with a same-configuration
     *     control: NO signature weaker; the two bindings attributable to the flag are
     *     `incomplete/np01.inferredRestate` (7 existentials -> 6, the removed name FORCED by
     *     the remaining constraints) and `incomplete/RunCalibration.scaledRuns` (one order-only
     *     duplicate fewer), both hand-checked equivalent;
     *   - `core/test` 910/911 with the flag on, the one failure being the pre-existing
     *     `Constraints.disjunction sound` generator; `repl-smoke` 4/4, `lsp-smoke` 98/98;
     *     129 stdlib modules with a byte-identical trace;
     *   - population, and it is the largest in this series: `SplitEmpty` fires 65 times in
     *     16 of the 110 example modules and `ResolutionEmpty` 183 times in 19, taking
     *     kept-definition mints 154 -> 82 (the empty-complement population is 73 of the 154),
     *     corpus split mints 626 -> 561 and resolution conclusions 1,644 -> 792.
     *   - and the cost, measured: `incomplete/gu05` was 1.9x SLOWER when this flag was first
     *     gated (1.03 s -> 1.96 s, three runs each) with the cause unisolated -- the JFR
     *     attribution moving into the row-constraint QUEUE rather than the environment scan;
     *     <what settled it>.
     * COVERAGE, stated at adoption: with this flag the mint bound is UNCONDITIONAL against
     * BOTH modelled deletions -- the concretisation `concretizeSrs` and `makeEmpty`.  What
     * remains outside: `unify`, the third deletion, which moves `v := VarT(u)` into the
     * `SubstEnv` the same way and is modelled by no relation here; `common` and
     * `incorporateAll`'s single pass, still unmodelled; and ill-typed input, untouched
     * (`DefaultDiverge.not_CRule` still lives).  The lookup is also an UPPER bound on the
     * current solve's `EmptyKnown` -- `hm.types` holds the whole inference's empties -- so a
     * firing is a `K2RowApp` of the system PLUS the environment, not of the queues alone;
     * soundness does not depend on that (the emission is entailed by the premise), but the
     * two-step reading does. */
```

**The comment above is written for the day the flip happens, and this stage does NOT
recommend that day is today**: the `<what settled it>` slot is B7-4's regression, which has to
be understood first (§C.5).  If settling it changes what the branch emits, the population and
timing bullets have to be re-measured before the comment is true.

### C.3 What would be re-run after a flip, and what `toString` prints

The same gates against the NEW default with no properties, which is how `cut`, `labelCheck`,
`resGuard`, `labelCheckEarly`, `splitKey`, `splitRow` and `resRow` were each confirmed:

* `sbt -batch core/compile`, then `sbt -batch -J-Xmx3g core/test` (expect 910/911);
* `tracker/tools/corpus-run.sh --batch` and `--incomplete --batch`, against a
  `-Dermine.emptyRow=false` side — the flag inverts, so the RESTORE side now needs the
  property — with `corpus-verdicts.py`, the normalised whole-output diff, and a PER-FILE
  re-run of any file whose message differs;
* `tracker/tools/ei-diff.sh <out> "-Dermine.emptyRow=false"`, classified with
  `ei-classify.py`, **with a same-configuration control sweep**;
* `tracker/tools/repl-smoke.sh`, `tracker/tools/lsp-smoke.sh`;
* `tracker/repro/satterm/sweep.sh` for `W2`, `H2`, `NE6`, `seeds/W3.json`, `seeds/W4.json`,
  **`seeds/G7.json`** and `tracker/repro/crule/sweep.sh` for `W`, `gseed`;
* `tracker/tools/keptdef-sweep.sh` (PER FILE — see B7-3) + `keptdef-mints.py`, for the
  population and the check that the kept-definition mints that remain still find a name;
* the `gu05` and `ResStar` timings, one JVM at a time.

`GenRules.toString` needs NO edit — it already prints a marker per flag that is on — and the
banner every `tracker/repro/*/run.sh` prints becomes:

```
cut+label-early+resguard+splitkey+splitrow+resrow+emptyrow   (adopted, no properties)
cut+label-early+resguard+splitkey+splitrow+resrow            (-Dermine.emptyRow=false: today's default)
```

### C.4 The honest scope

* **What becomes true for the first time.**  `KeyedEmpty.mintsBoundedOnSatKeyed3E`: from
  every satisfiable input, in every run order, the loop-extended calculus with BOTH of the
  compiler's modelled deletions — the concretisation `concretizeSrs` AND `makeEmpty` — mints
  boundedly, with the explicit bound `|allVars G₀| + hmeas (labelsOf G₀) rho G₀`.  Stage 6
  proved that statement is FALSE for `makeEmpty` as the compiler leaves it
  (`carried_not_invariant`, `hmeas_increases`): the deleted `v <- ()` is the carrier of the
  empty row and nothing replaces it.  This flag is what puts the carrier back within reach of
  the lookup, and `KeyedEmptyScala.scalaEmptySplit_run` / `scalaEmptyRes_run` say the rules AS
  WRITTEN are steps of that calculus.
* **What does NOT become true.**
  1. **`unify` is the last unmodelled deletion.**  It moves `v := VarT(u)` into the `SubstEnv`
     and removes `v`'s partitions exactly as `makeEmpty` does, and no relation in the
     development models it.  Stage 7 closes `makeEmpty`; `unify` is open.
  2. **`common` and `incorporateAll`'s single pass remain unmodelled.**  Every seed
     measurement where the flag-off side reaches the same answer reaches it through `common`
     or through mint-plus-cancellation-plus-`makeEmpty` — properties of the real loop that no
     theorem states.
  3. **Bounded minting is not termination.**  The bound is on the VOCABULARY, not on run
     length.
  4. **Ill-typed input is untouched.**  `hmeas` needs a model; `DefaultDiverge.not_CRule`
     still exhibits an unsatisfiable system on which this rule set diverges and which the
     input check does not refute.  B0's `W`/`gseed` measure exactly this: byte-identical in
     both configurations.
  5. **The lookup is an UPPER bound on the current solve's `EmptyKnown`**, the opposite
     direction from Stage 5's (§A.3).  Soundness does not depend on the carrier
     (`group_forced_empty`), and the emission adds no variable, but a firing is a `K2RowApp`
     of the system PLUS the environment, not of the queues alone.
  6. **It is a behaviour change, not a refactor.**  Ids shift and the derivation order
     changes wherever the branch fires.
### C.5 Recommendation

**`-Dermine.emptyRow`: DO NOT ADOPT YET — keep the flag, settle `gu05` first.**

The case FOR is the strongest in this series:

1. **The theorem is the one that was missing.**  Stage 6 proved that `makeEmpty`, as the
   compiler leaves it, breaks the Stage 4 mint bound in exactly one way; with this flag the
   bound is UNCONDITIONAL against BOTH modelled deletions, in every run order, on every
   satisfiable input (`mintsBoundedOnSatKeyed3E`), and the rule AS WRITTEN is a step-pair of
   that calculus (`emptyReuse_compose`, `splitEmpty_two_steps`, `scalaEmptySplit_run`,
   `scalaEmptySplit_bounded`, and the four counterparts for `resolution`).
2. **Soundness needs no carrier at all** (`group_forced_empty`, `res_empty_forced`): what the
   branch emits is entailed by the premise alone, so the one place the implementation is
   loose — the environment holds the empties of the whole inference, not of this solve — cannot
   produce a wrong conclusion.
3. **The population is real, and large.**  Not insurance: 65 `SplitEmpty` firings in 16 of 110
   modules and 183 `ResolutionEmpty` in 19, kept-definition mints 154 → 82, resolution
   conclusions halved.  Stage 5's branches fired 4 and 19 times.
4. **Every correctness gate is green**: 910/911 `core/test`; verdicts identical on both
   corpora with `shouldfail/` 40/40 and the four message differences shown to be batch drift;
   188 interfaces with NO signature weaker and the two attributable bindings equivalent and
   more economical; `repl-smoke` 4/4, `lsp-smoke` 98/98; 129 stdlib modules with a
   byte-identical trace; 600/600 satisfiable seed replays solved per side (six seeds × 100
   id bases) and 200/200 unsatisfiable ones rejected byte-identically; and the new tracked seed `G7` mints at 100 of 100 bases
   with the flag off and at none with it on.

The case AGAINST is one number, and it is enough to hold the flip:

5. **`incomplete/gu05` is 1.9× slower** (1.03 s → 1.96 s, three runs each, idle machine), and
   B7-4 could not isolate why.  It is the corpus's most expensive solve and the module whose
   time `resGuard` (11×) and `splitKey` (5×) were adopted on; a rule that halves its
   derivation and doubles its clock is not understood, and "not understood" is the wrong state
   for a default.  The profile says the extra time is in the row-constraint QUEUE, not in the
   environment scan, which narrows it to two candidates (§B7-4) that an instrumented build
   would separate in an afternoon.
6. Two smaller caveats, neither a blocker: the lookup is an UPPER bound on the current solve's
   `EmptyKnown` (§A.3), and `unify` — the third deletion — is still unmodelled, so the
   "unconditional" of point 1 covers two of the compiler's three deletions, not three.

**What would change the answer.**  Either an explanation of `gu05` plus a fix that removes the
regression (the two candidates are named), or a measurement showing the regression is confined
to a shape real code does not have — which `np01`'s +7 %, with six times as many firings, hints
at but does not establish.  Nothing else in the gate table needs to move.

**If the flag is wanted for its theorem rather than its behaviour**, it can stay exactly as it
is: DEFAULT OFF, with the Lean and the report on record, and `-Dermine.emptyRow=true` for
anyone who wants the bound.  That is the state this stage leaves it in.  Nothing was flipped
and nothing was committed; the decision is the user's.

---

## Housekeeping and final state

```
$ find core/examples -name '*.ei' -delete                        # 0 were left by the sweeps
$ find core/target/scala-3.3.8/classes/modules -name '*.ei' -delete
$ bin/ermine core/examples/syntaxExample.e </dev/null            # ONE run, no properties
$ find core/examples -name '*.ei' -delete                        # the .ei that run writes
```

* `core/examples`: **0** `.ei` files.
* stdlib interfaces: 138 before (9 of them stale, left by older builds), deleted, and
  **129 regenerated by one DEFAULT run** — one per loaded module — so the next default run does
  not read a flag-on artifact.
* `java` processes left running: **0**.
* `cd tracker/lean && lake build Rowpartition` → **`Build completed successfully (820 jobs)`**
  (819 before this stage); `lake env lean Audit.lean` → **`Rowpartition theorems audited:
  2378; declarations using a non-standard axiom: 0`** (2329 before).
  `Rowpartition/CutSearch.lean` is still out of the root import list; no `require` was added
  and `lake exe cache get` was never run.
* **The two comment-only edits, verified.**  `sbt -batch core/compile` on the final tree:
  clean, 7 s.  The recompiled `Constraints*.class` files are not byte-identical to the
  measured ones — adding comment lines moves the debug line-number tables — so the class set
  was re-checked instead of assumed: on the RECOMPILED classes the `G7` seed is again SOLVED
  100/100 with `drawn` 1 ×100 under `D` and 0 ×100 under `E`, and the 66-file corpus is again
  23 LOADED / 43 REJECTED on both sides, **byte-identical to the measured `D` run**
  (`corpus-verdicts.py <measured D> <recompiled D>`: `0 of 66 files differ`).  Incidentally
  the recompiled `D` vs `E` batch pair shows **0 of 66 differ**, where the measured pair
  showed one message drift — which is the third independent confirmation of B7-2.
* `git status`: the modified/untracked set of the table below and nothing else.  **No default
  flipped, nothing committed.**

---

## Files touched

| file | what | state |
|---|---|---|
| `core/src/main/scala/com/clarifi/reporting/ermine/Constraints.scala` | `SplitEmpty` / `ResolutionEmpty` tags; `GenRules.emptyRow`, **default OFF**; `splitConcrete`'s fifth branch and its `emptyRow` parameter; `resolution`'s fourth branch and the same parameter; `learnPartitions`' `envEmptyRow` / `findEmptyRow` and the `implicit hm: SubstEnv`; the correspondence comments at both rules and at the lookup | modified, **+203 / −16**, LF preserved, NOT committed |
| `tracker/lean/Rowpartition/KeyedEmptyScala.lean` | the transcription lemmas, 749 lines, **39 theorems**, 10 definitions | new, NOT committed |
| `tracker/lean/Rowpartition.lean` | the root import and its module note | modified |
| `tracker/lean/README.md` | the `KeyedEmptyScala` build-table row and module-map row, the recounted headline (36 files, 1888 source theorems), the audit/build figures and a dated bullet | modified |
| `tracker/satterm/KEYED-EMPTY-STAGE7.md` | this report | new |
| `tracker/TICKET-sat-termination.md` | §3j, the §4 item-0 update, the §5 file rows | modified |
| `tracker/ROW-CONSTRAINT-STATE.md` | the Stage 7 paragraph after Stage 6's | modified |
| `tracker/tools/keptdef-mints.py` | the `SplitEmpty` reuse bucket (recognised by the GROUP being covered, since this branch emits no name) and the two new whole-trace counters | modified, **+34 / −9** |
| `tracker/repro/satterm/seeds/G7.json` | the new tracked seed | new |

Everything else lives in the scratch directory `/home/dmitry/.claude/jobs/880c725d/tmp/stage7/`
(drivers `b0.sh`, `b1b5.sh`, `b2.sh`, `b2f.sh`, `b3.sh`, `b4.sh`, `b6.sh`, `b6f.sh`,
`keptdef-sweep-flag.sh`; analysers `pre-empty.py`, `agg7.py`; the scratch seeds
`G7bare.json`, `G7queued.json`, `W4e.json`; raw outputs under `b0/`, `b1/`, `b2/`, `b2f/`,
`b3/`, `b4/`, `b6f/`).
