# Stage 5 — `-Dermine.splitRow` and `-Dermine.resRow`: the CONCRETE-ROW reuse in `Constraints.scala`, measured

Date 2026-09-03, branch `scala3-migration`, clean tree at `98e7bf2`.  **Both flags are
DEFAULT OFF, no default was flipped, and nothing was committed.**  Stage 4 (the Lean that
licenses them) is `tracker/satterm/KEYED-ROW-STAGE4.md` / `Rowpartition/KeyedRow.lean`; this
stage is its §9 implemented and measured, in the method of
`tracker/satterm/KEYED-SPLIT-STAGE2.md`.

Toolchain for every command below:

```
export PATH=~/.local/ermine-toolchain/jdk-21.0.12.1+1/bin:~/.local/ermine-toolchain/bin:$PATH
cd /home/dmitry/research/ermine/ermine-scala
export PATH=$HOME/.elan/bin:$PATH          # Lean, in tracker/lean
```

Scratch (raw outputs, drivers): `/home/dmitry/.claude/jobs/880c725d/tmp/stage5/`.

Configurations, throughout:

| tag | properties | `GenRules.toString` (the banner every `repro/*/run.sh` prints) |
|---|---|---|
| `D` | none — the shipped default (`splitKey` ON, both new flags off) | `cut+label-early+resguard+splitkey` |
| `S` | `-Dermine.splitRow=true` | `cut+label-early+resguard+splitkey+splitrow` |
| `R` | `-Dermine.resRow=true` | `cut+label-early+resguard+splitkey+resrow` |
| `B` | both | `cut+label-early+resguard+splitkey+splitrow+resrow` |

---

## Part A — the implementation

### A.1 The change (`core/src/main/scala/com/clarifi/reporting/ermine/Constraints.scala`, LF preserved)

`+215 / −13` lines, comment-heavy; six edits, and the existing ADOPTED comments are
untouched.

1. **`case object SplitRow extends Inference`** and **`case object ResolutionRow extends
   Inference`** (after `SplitKeyed`, ~line 705) — provenance for the two new reuse branches,
   so `-Dermine.rowTrace` can count them.  `Inference` is never inspected and
   `Partition.equals`/`hashCode` ignore it, so both tags are behaviour-neutral.
2. **`GenRules.splitRow`** and **`GenRules.resRow`**, read once at class-init like every
   other flag:

   ```scala
   val splitRow: Boolean = System.getProperty("ermine.splitRow", "false") == "true"
   val resRow:   Boolean = System.getProperty("ermine.resRow",   "false") == "true"
   ```

   each documented with the Lean that licenses it (`K2SplitStep.row` / `K2RowApp`,
   `concRow_reuse_sat`, `K2RowApp.models_iff`, `K2MintApp.toSplitApp`,
   `mintsBoundedOnSat_splitFragment`; `K2ResStep.row`, `K2ResStep.row_models_iff`,
   `K2ResStep.mint_toGRes`, `mintsBoundedOnSatKeyed2Star`,
   `keyed2_star_vs_shipped_res`) and with the scope limit (the split fragment alone is not
   enough — `not_MintsBoundedOnSatKeyed2`; nothing about ill-typed input).
   `toString` gains `+splitrow` / `+resrow`.
3. **`splitConcrete`** gains a sixth parameter `concRow: Fields => Option[TypeVar] = _ =>
   none` and a FOURTH branch, between the keyed reuse and the mint.  The order of the match
   is unchanged, so behaviour is unchanged when either earlier lookup hits, when
   `!GenRules.splitMints`, and when the flag is off:

   ```scala
   case None =>
     (if (GenRules.splitKey) resolvent(concr) else none) match {
       case Some(w) => Set(Partition(w, RHSAbstr(abstr), SplitKeyed))
       case None    =>
         (if (GenRules.splitRow) concRow(concr) else none) match {
           case Some(w) => Set(Partition(w, RHSAbstr(abstr), SplitRow))   // NEW
           case None    => val u = fresh(...); Set(Partition(u, RHSAbstr(abstr), SplitConcrete),
                                                  Partition(v, RHS(Set(u), concr), SplitConcrete))
         }
     }
   ```

   `fresh` is still called only in the mint branch, so a `SplitRow` reuse draws no id from
   the `Supply` — it shifts the id sequence relative to flag-off exactly as `splitKey` did.
4. **`resolution`** gains the same parameter and a THIRD branch, taken when `findResolvent`
   misses:

   ```scala
   (if (GenRules.resGuard) resolvent(all) else none) match {
     case Some(w) => Set(Partition(x, RHS(Set(w), bots), Resolution),
                         Partition(y, RHS(Set(w), tops), Resolution))
     case None =>
       (if (GenRules.resRow) concRow(all) else none) match {
         case Some(w) => Set(Partition(x, RHS(Set(w), bots), ResolutionRow),      // NEW
                             Partition(y, RHS(Set(w), tops), ResolutionRow))
         case None    => Set(Partition(v, RHS(Set(z), all), Resolution), ...)     // the mint
       }
   }
   ```

   with `all = concr1 ++ concr2`, `tops = concr1 -- int`, `bots = concr2 -- int` — read off
   the source and checked against `ResGuard.resReuseResult G x y C D z = insert (mk x {z}
   (D \ C)) (insert (mk y {z} (C \ D)) G)`: `bots` **is** `D \ C` and `tops` **is** `C \ D`,
   so the new branch emits exactly what the shipped `resGuard` reuse emits, with the carrier
   in place of the fresh name.  The lookup row is `F \ (C ∪ D)` — `K2ResStep.row`'s
   `mk z ∅ (F \ (C ∪ D)) ∈ G` — not `C \ concr`, which is the split's.
5. **`learnPartitions`** builds the lookup, lazily, alongside `resolvents`:

   ```scala
   lazy val concRows: (Map[Fields, TypeVar], Option[Fields]) = {
     def add(m, p) = p match {
       case Partition(u, RHS(abs, con), _) if abs.isEmpty =>
         (m._1 + (con -> u), if (u == v) some(con) else m._2)
       case _ => m
     }
     incm.foldLeft(proc.foldLeft((Map[Fields, TypeVar](), none[Fields]))(add))(add)
   }
   def findConcRow(k: Fields): Option[TypeVar] = {
     val (rows, myRow) = concRows
     myRow.filter(k subsetOf _).flatMap(c => rows.get(c -- k))
   }
   val concRow: Fields => Option[TypeVar] =
     if (GenRules.splitRow || GenRules.resRow) findConcRow else noConcRow
   ```

   — one pass, the same shape as `resolvents`, producing BOTH the map of bare concrete
   partitions and `concreteOf(v)`.  `noConcRow` is a module-level shared constant, so with
   both flags off nothing is allocated and the `lazy val` is never forced.
6. The correspondence comments at `def splitConcrete`, at `def resolution` and at
   `learnPartitions`' `concRows`, and the flag comments in `GenRules`.

### A.2 Correspondence with `K2SplitStep` / `K2ResStep`, and the ONE deliberate difference

Writing `c` for the split premise `v <- (abstr, concr)`:

| Scala branch | Lean |
|---|---|
| `rhss(RHSAbstr(abstr)) = Some(u)` → `v <- (u, concr)` | `K2SplitStep.syn` / `SplitReuseApp` — kept verbatim |
| `splitKey` ∧ `resolvent(concr) = Some(w)` → `w <- (abstr)` | `K2SplitStep.key` / `K2KeyApp`, `kSplitReuseResult` |
| **`splitRow` ∧ `concRow(concr) = Some(w)` → `w <- (abstr)`** | **`K2SplitStep.row` / `K2RowApp G c w C`**, `kSplitReuseResult` |
| otherwise → mint | `K2SplitStep.mint` / `K2MintApp`, guard `¬ Carried` |

| Scala branch | Lean |
|---|---|
| `resGuard` ∧ `resolvent(all) = Some(w)` → `x <- (w, bots)`, `y <- (w, tops)` | `K2ResStep.reuse`, `resReuseResult` |
| **`resRow` ∧ `concRow(all) = Some(w)` → the same two** | **`K2ResStep.row`**, `resReuseResult` |
| otherwise → mint `z`, three conclusions | `K2ResStep.mint`, guard `¬ Carried` |

**The one deliberate difference, in the safe direction.**  `K2RowApp` / `K2ResStep.row` have
no `K ⊆ C` premise — their soundness proofs derive it from the model (`concRow_reuse_sat`,
`row_models_iff`).  `findConcRow` ASKS for it (`myRow.filter(k subsetOf _)`).  On satisfiable
input the two agree (`makeConcrete`'s `ensureSuperset` enforces it); on unsatisfiable input
the Scala refuses a reuse the Lean would take, so no refutation can be lost to it.  Every
firing of the Scala branch is therefore a `K2RowApp` / a `K2ResStep.row` — proved, not
argued, in §D.

**A second difference, also in the safe direction:** `findResolvent(s)` consults the current
BATCH `s` as well as `proc ++ incm`; `findConcRow` consults only `proc ++ incm`.  Fewer
reuses, never a wrong one.

### A.3 **The faithfulness note the brief asks for: where the compiler keeps a concrete row**

Traced with `-Dermine.rowTrace` on `W3` and `W4` **before** the lookup was written
(`stage5/w3-trace-b3.tsv`, `stage5/w4-trace-b5.tsv`), and confirmed by reading
`makeConcrete` / `makeEmpty` / `unify`:

* **A NONEMPTY concrete row of `v` is a bare partition `Partition(v, RHS(Set(), C))` in the
  `proc` queue, and nowhere else.**  `makeConcrete` does **not** call `instantiateType` — its
  last line is `(nincm ++! can, nproc + Partition(v, RHSConcr(fs)))`, so the dequeued
  concrete partition **is** returned to `proc`.  The `W3` base-3 trace shows this directly:
  after `step concrete ^free3 <- (,l1 l2)` and `step concrete Cancellation: ^free4 <- (,l2)`
  the next dequeue reports `proc=2`, and those two partitions are exactly the two bare
  concrete rows.  So the substitution environment `hm : SubstEnv` is **not** where a concrete
  row lives, and `concRows`/`concreteOf` are built from the queues, which is what
  `KeyedRow`'s `mk v ∅ C ∈ G` means.
* **The EMPTY row is the exception.**  `makeEmpty v` writes `instantiateType(v,
  ConcreteRho(Loc.builtin, Set()))` into the `SubstEnv` **and deletes every partition
  mentioning `v`** (`proc partition ruleInvolves(v)`, and neither half is returned).  So a
  variable already made empty is invisible to `concRows` and can never be the carrier `w`;
  a `w <- ()` still sitting in `incm`, not yet dequeued, IS visible (`RHS(abs, con)` with
  `abs.isEmpty` matches `RHS(∅, ∅)` too).
* **`unify(v, u)`** likewise moves `v := VarT(u)` into the `SubstEnv` and removes `v`'s
  partitions.

**Consequence, stated as the Lean cannot:** the Scala lookup is a **lower bound** on the
Lean's `mk u ∅ R ∈ G`.  It can MISS where the Lean would hit (an emptied or unified-away
carrier), never hit where the Lean would miss.  For the REUSE branches that is harmless — a
miss is a mint, the shipped behaviour.  For the MINT branch's guard `¬ Carried` it is not
free, because the guard quantifies over all `C`, and the fold keeps ONE row per variable; the
Lean module below therefore states the spec the Scala actually meets (`MyRowSpec`,
`ConcRowSpec`) and proves adequacy for THAT, on a MODELLED system, where
`conc_unique_of_model` closes the "one row" gap and `conc_key_subset_of_model` closes the
`K ⊆ C` gap.  That is the only place a model is needed.

### A.4 Compile, and the flags are really read

```
$ sbt -batch core/compile                       # ONCE; every measurement below is this class set
[success] Total time: 11 s, completed Sep 3, 2026, 5:06:02 PM
$ sbt -batch -J-Xmx3g core/Test/compile
[success] Total time: 7 s, completed Sep 3, 2026, 5:06:22 PM

$ CP=$(cat target/ermine-classpath)
$ echo 'System.out.println(com.clarifi.reporting.ermine.Constraints.GenRules$.MODULE$.toString());' \
    | jshell -q --class-path "$CP" [-R-Dermine.splitRow=true] [-R-Dermine.resRow=true] -
   <none>                     -> cut+label-early+resguard+splitkey
   -R-Dermine.splitRow=true   -> cut+label-early+resguard+splitkey+splitrow
   -R-Dermine.resRow=true     -> cut+label-early+resguard+splitkey+resrow
   both                       -> cut+label-early+resguard+splitkey+splitrow+resrow

$ _JAVA_OPTIONS="-Dermine.splitRow=true -Dermine.resRow=true" \
    sbt -batch 'eval "splitRow=" + System.getProperty("ermine.splitRow") + " resRow=" + System.getProperty("ermine.resRow")'
Picked up _JAVA_OPTIONS: -Dermine.splitRow=true -Dermine.resRow=true
[info] ans: String = splitRow=true resRow=true            (and `splitRow=null resRow=null` with no _JAVA_OPTIONS)
```

`core/test` (`Test / fork := false`, so `_JAVA_OPTIONS` is the way in), same classes:

```
$ sbt -batch -J-Xmx3g core/test                                             # D
[info] Failed: Total 904, Failed 1, Errors 0, Passed 903
[info] ! Constraints.disjunction sound: Gave up after only 0 passed tests. 501 tests were discarded.
$ _JAVA_OPTIONS="-Dermine.splitRow=true -Dermine.resRow=true" sbt -batch -J-Xmx3g core/test   # B
[info] Failed: Total 904, Failed 1, Errors 0, Passed 903
[info] ! Constraints.disjunction sound: Gave up after only 0 passed tests. 501 tests were discarded.
```

**903/904 on both sides, the same single failure — the known `Constraints.disjunction sound`
generator starvation.**  Note that `Constraints.split concrete sound` and
`Constraints.resolution sound` call the rules through their SHORT signatures, i.e. with the
default `concRow = _ => none`, so they exercise the mint path; the new branches' soundness
evidence is the Lean plus the gates below, not those properties.

### A.5 Instrument change (documented, as the brief requires)

`tracker/tools/keptdef-mints.py` (`+36/−1`): a fourth reuse bucket `SplitRow` in the
kept-definition classification (recognised exactly as `SplitKeyed` is — the branch emits the
same shape `w <- (abs,)`), and a new WHOLE-TRACE tally block printed per run, over the same
solve segments:

```
  whole-trace branch tallies (learn records, same segments):
      SplitConcrete bare (a MINT) / non-bare:  <mints> / <syntactic+mint conclusions>
      SplitKeyed / SplitRow:                   <keyed reuses> / <row reuses>
      Resolution / ResolutionRow:              <resolution conclusions> / <row reuses>
```

so one line per configuration says how often each new branch fired.  With the flags off the
new counters are simply zero, and every pre-existing number the script printed is unchanged.

---

## Part D — the Lean (`Rowpartition/KeyedRowScala.lean`, NEW, 616 lines, 33 theorems)

`lake build Rowpartition` — **Build completed successfully (818 jobs)**, 817 before.
`lake env lean Audit.lean` — **`Rowpartition theorems audited: 2255; declarations using a
non-standard axiom: 0`** (2216 before).  `#print axioms` was run in scratch only.

The module is the Stage 5 counterpart of `KeyedSplitScala.lean`, written the same way.

**§1, the specifications the Scala actually meets.**  Not `mk v ∅ C ∈ G`:

```lean
def MyRowSpec (H : System) (v : Var) : Option Row → Prop        -- concRows._2
  | some C => mk v ∅ C ∈ H
  | none   => ∀ C : Row, mk v ∅ C ∉ H

def ConcRowSpec (H : System) (K : Row) : Option Row → Option Var → Prop   -- findConcRow
  | C?, some w => ∃ C, C? = some C ∧ K ⊆ C ∧ mk w ∅ (C \ K) ∈ H
  | C?, none   => ∀ C, C? = some C → K ⊆ C → ∀ w, mk w ∅ (C \ K) ∉ H
```

The two differences from `ConcCarried` are in the spec, not in a comment: the fold keeps ONE
row per variable (an `Option`, not an existential), and `K ⊆ C` is asked explicitly.
`myRowLookup` / `concRowLookup` with `myRowLookup_spec` / `concRowLookup_spec` exhibit
results meeting them (existentials bounded by `H` so the `if` is decidable, exactly as
`ConcCarried`'s are), so nothing downstream is vacuous.

**§2, the dequeued premise is invisible to the new lookup** — and for a THIRD reason, which
neither of `KeyedSplitScala`'s covers: `bare_erase_iff` (a witness is a BARE partition,
`vset = ∅`, and both rules reach the lookup with a nonempty variable set —
`2 ≤ |vset c|` for the split, `vset c = {x}` for resolution), with `myRowSpec_erase_iff` and
`concRowSpec_erase_iff` in the specs' own vocabulary.

**§3, the four-branch split.**  `scalaRowSplit G c u rhss resolvent concRow` mirrors the
source branch for branch and in order; `scalaRowSplit_eq_none_iff` pins the only no-op to the
early return `concr.isEmpty || abstr.size < 2`; `scalaRowSplit_syntactic` / `_keyed` / `_row`
/ `_mint` are the four branches.  **Adequacy: `scalaRowSplit_step`** — with the lookups
computed on `G.erase c`, every system it returns is a `K2SplitStep G G'`; hence
`scalaRowSplit_defaultStep : K2DefaultStep G G'` and `scalaRowSplit_starStep : K2StarStep
G G'`, plus `scalaRowSplit_subset` and `scalaRowSplit_extend`.

**§3.1, where the model is used, isolated in two lemmas.**
`conc_key_subset_of_model : SModels rho G → c ∈ G → mk c.lhs ∅ C ∈ G → c.conc ⊆ C` and
**`concRow_none_uncarried`** : under a model, `ConcRowSpec … none` really is
`¬ ConcCarried G c.lhs c.conc`, the two gaps closed by `conc_unique_of_model` and
`conc_key_subset_of_model`.  Without a model the Scala's mint is NOT provably a `K2MintApp`,
and the module says so in its header rather than hiding it.  (The scope costs nothing: every
termination statement of Stage 4 is about satisfiable input anyway.)

**§4, the three-branch resolution.**  `scalaRowRes G v x y C D z resolvent concRow`,
`scalaRowRes_eq_none_iff` (the only no-op is the `tops`/`bots` early return),
`scalaRowRes_reuse` / `_row` / `_mint`, and **adequacy `scalaRowRes_step` : `K2ResStep G G'`**
(hence `scalaRowRes_starStep`, `scalaRowRes_subset`, `scalaRowRes_extend`).  Its erase lemma
is new too — `resolved_erase_iff_row`: `KeyedSplitScala.resolved_erase_iff` needs
`2 ≤ |vset c|` and resolution's premise has card 1, so the argument is about the ROW instead
(`C ∪ D ≠ C`, from `D \ C ≠ ∅`, `union_ne_left`).

**§5**, the closed functions `scalaRowSplitOf` / `scalaRowResOf` with
`scalaRowSplitOf_step` / `scalaRowResOf_step`, and `scalaRow_starStep`, the two together:
every step either extended rule takes from a modelled system is a step of `K2StarStep`, whose
loop extension `mintsBoundedOnSatKeyed2Star` bounds minting on every satisfiable input in
every run order.

Lemma names, in one list: `MyRowSpec`, `ConcRowSpec`, `myRowLookup(_spec)`,
`concRowLookup(_spec)`, `bare_erase_iff`, `myRowSpec_erase_iff`, `concRowSpec_erase_iff`,
`scalaRowSplit`, `scalaRowSplit_eq_none_iff`, `scalaRowSplit_syntactic`, `scalaRowSplit_keyed`,
`scalaRowSplit_row`, `scalaRowSplit_mint`, `conc_key_subset_of_model`,
`concRow_none_uncarried`, `scalaRowSplit_step`, `scalaRowSplit_defaultStep`,
`scalaRowSplit_starStep`, `scalaRowSplit_subset`, `scalaRowSplit_extend`, `scalaRowRes`,
`scalaRowRes_eq_none_iff`, `scalaRowRes_reuse`, `scalaRowRes_row`, `scalaRowRes_mint`,
`resolved_erase_iff_row`, `union_ne_left`, `scalaRowRes_step`, `scalaRowRes_starStep`,
`scalaRowRes_subset`, `scalaRowRes_extend`, `scalaRowSplitOf(_step)`,
`scalaRowResOf(_step)`, `scalaRow_starStep`.

---

## Part B — the gates

Every gate below uses the SAME class files (`sbt -batch core/compile` at 17:06:02; no
recompile between configurations).

### B0. Seed replays — the positive controls

```
$ [ERMINE_JAVA_OPTS="<flags>"] tracker/repro/satterm/sweep.sh <seed> 0 99
$ [ERMINE_JAVA_OPTS="<flags>"] tracker/repro/crule/sweep.sh   <sys>  0 99
```

`W3.json` and `W4.json` were copied into `tracker/repro/satterm/seeds/` so the seeds are
tracked next to `W2`/`H2`/`NE6`.  `drawn` is the number of ids the run's `Supply` handed
out (an over-count: `resolution` draws one per same-lhs pair and discards it when it emits
nothing).

| seed | `D` | `S` | `R` | `B` |
|---|---|---|---|---|
| `W2` | SOLVED 100, draws 0 ×100 | same | same | same |
| `H2` | SOLVED 100, draws 2 ×38, 3 ×62 | same | same | same |
| `NE6` | SOLVED 100, draws 1 ×22, 2 ×19, 3 ×14, 4 ×20, 5 ×11, 6 ×2, 7 ×4, 10–18 ×8 | SOLVED 100, **1 ×24, 2 ×20, 3 ×15, 4 ×21, 5 ×7, 6 ×3, 7 ×2**, 10–18 ×8 | = `D` | = `S` |
| **`W3`** | SOLVED 100, **draws 0 ×45, 1 ×55** | SOLVED 100, **draws 0 ×100** | = `D` | = `S` |
| `W4` | SOLVED 100, draws 0 ×95, 1 ×2, 3 ×3 | same | **same** | same |
| **`W4c`** (the `resRow` control, scratch seed) | SOLVED 100, draws 0 ×95, 1 ×4, **3 ×1** | — | SOLVED 100, draws 0 ×95, **1 ×5** | — |
| crule `W` (unsat) | REJECTED 100 | REJECTED 100 | REJECTED 100 | REJECTED 100 |
| crule `gseed` (unsat) | REJECTED 100 | REJECTED 100 | REJECTED 100 | REJECTED 100 |

The two unsatisfiable systems are **byte-identical in every configuration apart from the
banner** (`diff` after stripping `in N ms`: exactly 2 differing lines, both `genRules=`).

**`SplitRow` firing, traced (`W3` base 3, the base at which the shipped loop re-mints).**
`D` mints and then throws the mint away; `S` never mints:

```
D  genRules=cut+label-early+resguard+splitkey                  records=34 learn=11 drawn=1
     step  learn      ^free3 <- (^free4,l1)
     step  concrete   ^free3 <- (,l1 l2)                       <- makeConcrete v0 = {l1,l2}
     step  concrete   Cancellation: ^free4 <- (,l2)            <- and v1 = {l2}
     step  learn      ^free3 <- (^free5 ^free6,l1)             <- the KEPT split premise
     learn new  SplitConcrete: ^ambiguous(free)7 <- (^free5 ^free6,)   <- MINT
     learn new  SplitConcrete: ^free3 <- (^ambiguous(free)7,l1)
     ...  step common:4  Cancellation: ^ambiguous(free)7 <- (,l2)      <- `common` unifies 7 with v1

S  genRules=cut+label-early+resguard+splitkey+splitrow          records=26 learn=6 drawn=0
     step  learn      ^free3 <- (^free4,l1)
     step  concrete   ^free3 <- (,l1 l2)
     step  concrete   Cancellation: ^free4 <- (,l2)
     step  learn      ^free3 <- (^free5 ^free6,l1)
     learn new  SplitRow: ^free4 <- (^free5 ^free6,)            <- CONCRETE-ROW REUSE
     step  learn      SplitRow: ^free4 <- (^free5 ^free6,)
     learn new  CommonSubexpression: ^free3 <- (^free4,l1)
```

This is `KeyedRow.lean` §10 executed.  `myRow(v0) = {l1,l2}`, `concr = {l1}`,
`{l1,l2} -- {l1} = {l2}`, and `v1 <- ((|l2|))` carries it — `W3_row_reuse` emits
`z <- (x, y)`, which here is `^free4 <- (^free5 ^free6,)`.  The saturated sets have the same
5 partitions on both sides; `D` reaches it by minting a name and then `common`-unifying it
with `v1` (the 55-of-55 mechanism Stage 3 measured), `S` reaches it in one step, in every
order.  **The rule does in every order what `common` does in some.**

**`ResolutionRow` firing, traced.**  `W4` itself does NOT exercise it — see B7 — so the
positive control is `W4c`, `W4` with the carrier that `W4Inv.round`'s step 2 would create:

```
W4c :  v <- ((|l1,l2,l3|)),  v <- (x, (|l1|)),  v <- (y, (|l2|)),  w <- ((|l3|))
       model  v = {l1,l2,l3}, x = {l2,l3}, y = {l1,l3}, w = {l3}
```

(scratch file `stage5/W4c.json`; not added to the repo, the brief authorises only `W3.json`
and `W4.json`.)  At base 37:

```
D   records=34 steps=10 learn=7 drawn=3   byRule: Cancellation=2 Resolution=3 Substitution=2
      step  learn  ^free37 <- (^free38,l1)
      step  learn  ^free37 <- (^free39,l2)
      learn new  Resolution: ^free37 <- (^ambiguous(free)41,l2 l1)    <- MINT the resolvent
      learn new  Resolution: ^free39 <- (^ambiguous(free)41,l1)
      learn new  Resolution: ^free38 <- (^ambiguous(free)41,l2)
      ...  step unify:41  CommonPartition: ^free40 <- (^ambiguous(free)41,)  <- `common` unifies 41 with w

R   records=25 steps=6  learn=2 drawn=1   byRule: ResolutionRow=2
      step  learn  ^free37 <- (^free38,l1)
      step  learn  ^free37 <- (^free39,l2)
      learn new  ResolutionRow: ^free39 <- (^free40,l1)               <- CONCRETE-ROW REUSE
      learn new  ResolutionRow: ^free38 <- (^free40,l2)
      step  concrete  ^free40 <- (,l3)
```

Exactly `K2ResStep.row`: `myRow(v) = {l1,l2,l3}`, `all = {l1,l2}`, `F \ all = {l3}`, carrier
`w = ^free40`.  Both partitions found in `incm`, not `proc` — the lookup ranges over both,
as `resolvents` does.  Again the flag-off side reaches the same answer by minting and then
`common`-unifying the mint with the carrier.  Same solved result on both sides
(`v = {l1,l2,l3}, x = {l2,l3}, y = {l1,l3}, w = {l3}`), 4 bound variables instead of 5.

**KeepMint control** (`tracker/repro/keepmint/run.sh`, the `KeepInert.lean` instance
`u <- (x, y, (|k|))`, `u <- ((|k,c|))`, `R <- (u, z)` at 8 id bases × 4 input orders; the
script invokes `java` directly, so the flags went in through `_JAVA_OPTIONS`):

```
D  -> splitConcrete MINTED a fresh name:   16  (strict 16)
B  -> splitConcrete MINTED a fresh name:   16  (strict 16)
```

**16 of 32 configurations still mint, identically, with both flags on** — the branch is not a
blanket mint-suppressor.  Here `C = {k,c}` and `K = {k}`, so the carrier would have to be a
bare `w <- ((|c|))`, and this system has no one-abstract definition of `u` for `makeConcrete`
to derive one from.  The lookup misses and the shipped mint stands, which is the same answer
Stage 2 got for `splitKey` on this instance (its key is open too).

### B1. Stdlib boot

```
$ ERMINE_JAVA_OPTS="-Xmx2g -Dermine.useInterface=false [flags]" bin/ermine </dev/null
```

| run | `D` wall / program's own `Loaded 129 modules (s)` | `B` wall / same |
|---|---|---|
| 1 | 12.24 s / 11.39 s | 12.27 s / 11.40 s |
| 2 | 12.24 s / 11.39 s | 12.14 s / 11.23 s |
| 3 | 12.36 s / 11.49 s | 12.28 s / 11.43 s |

**129 modules on both sides, all six runs; boot time identical within noise.**  Traced
(`-Dermine.rowTrace`, `-Dermine.loadInSeries=true`, one run per side):

| | `D` | `B` |
|---|---|---|
| trace records | 60,088 | 60,088 |
| `learn` records | 1,631 | 1,631 |
| by rule | Cancellation 424, CSE 785, DeDuplication 3, SelfSubstitution 2, Substitution 417 | identical |
| `SplitConcrete` / `SplitKeyed` / **`SplitRow`** / `Resolution` / **`ResolutionRow`** | 0 / 0 / **0** / 0 / **0** | 0 / 0 / **0** / 0 / **0** |

**The two trace files are byte-identical (`cmp`).**  The stdlib boot cannot see either flag:
neither `splitConcrete` nor `resolution` fires in it at all — the same population fact
`KEYED-SPLIT-STAGE2.md` B1 and `TICKET-substitution-gap.md` §7.9 record.

### B5. REPL and LSP smoke

`repl-smoke.sh` and `lsp-smoke.sh` invoke `java` directly and do not read
`ERMINE_JAVA_OPTS`, so the flags went in through `_JAVA_OPTIONS` (visible in the LSP log's
own `Picked up _JAVA_OPTIONS: -Dermine.splitRow=true -Dermine.resRow=true`).

| | `D` | `B` |
|---|---|---|
| `repl-smoke.sh` | PASS aliasing (2), relations (6), scoping (4), smoke (23) — **4/4 suites, 35 checks** | **identical, 4/4, 35 checks** |
| `lsp-smoke.sh` | **PASS lsp (98 checks)** | **PASS lsp (98 checks)** |

### B2. Corpus verdicts

```
$ ERMINE_JAVA_OPTS="-Xmx2g [flags]" tracker/tools/corpus-run.sh              <out>     # 66 files
$ ERMINE_JAVA_OPTS="-Xmx2g [flags]" tracker/tools/corpus-run.sh --incomplete <out>     # 34 files
$ tracker/tools/corpus-verdicts.py <outD> <outX>
```

Six passes, **run strictly sequentially**, never alongside `ei-diff.sh`.  (`corpus-run.sh`
deletes `core/examples/**/*.ei` before each run and passes `-Dermine.useInterface=false`,
which is what makes each side re-run the solver.)

| corpus | configuration | LOADED | REJECTED | UNKNOWN | total |
|---|---|---|---|---|---|
| examples + `Ai/` + `shouldfail/` | `D` | **23** | **43** | 0 | 66 |
| examples + `Ai/` + `shouldfail/` | `S` | **23** | **43** | 0 | 66 |
| examples + `Ai/` + `shouldfail/` | `B` | **23** | **43** | 0 | 66 |
| `incomplete/` | `D` | **18** | **16** | 0 | 34 |
| `incomplete/` | `S` | **18** | **16** | 0 | 34 |
| `incomplete/` | `B` | **18** | **16** | 0 | 34 |

* `shouldfail/`: **40 of 40 REJECTED in all three configurations**, 0 modules loading.
* `corpus-verdicts.py`: **`0 of 66 files differ`** and **`0 of 34 files differ`**, both for
  `D` vs `S` and for `D` vs `B` — verdicts AND messages identical.
* Whole-output text diff, with the loader progress bar and the `(N.NN seconds)` timings
  normalised (the normalisation `ROW-CONSTRAINT-STATE.md` requires): **0 of 66** and
  **0 of 34**, for `D` vs `S` and for `D` vs `B`.

**No `shouldfail/der01` message flip this time** (the parallel-loader nondeterminism Stage 2
had to chase in its B7); all six passes agree on every byte that is not a clock.  Two
`shouldfail/` modules — `inc08_project_absent_from_join_result.e` and
`mis02_join_result_annotation.e` — actually EXERCISE the new resolution branch (B6) and stay
rejected with the same message, which is the refutation-safety check that matters most for
`resRow`.

### B6. Trace-based population: do the new branches fire on real code?

```
$ KEPTDEF_EXTRA="[flags]" <scratch>/keptdef-sweep-flag.sh <out>      # 110 modules, one JVM each
$ <scratch>/agg.py <out>                                            # sums the per-file .kept reports
```

110 `core/examples/**/*.e`, one serialized (`-Dermine.loadInSeries=true`)
`-Dermine.rowTrace` run per module, `-Dermine.useInterface=false` (so no `.ei` is written or
read and the sweep could share the machine with B2's corpus passes — Stage 2 B6's
justification, and nothing here is a timing figure), counts attributed to solves under
`core/examples` by the extended `keptdef-mints.py`.

| | `D` | `S` | `B` |
|---|---|---|---|
| modules analysed | 110 | 110 | 110 |
| solve segments | 55,338 | 55,338 | 55,338 |
| `makeConcrete` steps | 3,617 | 3,614 | 3,613 |
| kept-definition dequeues | 748 (336 strict) | 745 (337) | 738 (337) |
| ...with a nonempty concrete part | 308 | 304 | 298 |
| **kept-definition MINTS** | **157** (23 strict) **in 27 modules** | **154** in 27 | **154** in 27 |
| ...syntactically reused | 147 | 141 | 136 |
| ...KEYED-reused | 4 | 5 | 4 |
| **...ROW-reused (`SplitRow`)** | — | **4** | **4** |
| **whole-trace split MINTS** | **637** | **626** | **626** |
| whole-trace `SplitKeyed` | 77 in 18 modules | 77 in 18 | 76 in 18 |
| **whole-trace `SplitRow`** | 0 | **4 in 3 modules** | **4 in 3 modules** |
| whole-trace `Resolution` conclusions | 1,748 | 1,696 | **1,644** |
| **whole-trace `ResolutionRow`** | 0 | 0 | **19 in 5 modules** |

A FOURTH pass, `R` (`-Dermine.resRow=true` alone), was added to attribute the resolution
figures: **157 kept-definition mints (unchanged from `D`), 637 whole-trace split mints
(unchanged), `SplitRow` 0, `Resolution` 1,696, `ResolutionRow` 19 in the same 5 modules.**
So the 19 row-reuses are `resRow`'s alone — `splitRow` does not enable any of them — and
`resRow` changes no split mint (the `SplitKeyed` count moves 77 → 76, a knock-on of the
derivations it removes).  Symmetrically, `S` leaves `ResolutionRow` at 0.

**The `D` baseline reproduces the tracker's figure exactly: 157 kept-definition mints in 27
modules, 748 kept-definition dequeues.**

**The brief's three questions about the 157.**

1. *How many of the 157 become `SplitRow` reuses?*  **Four kept-definition dequeues take the
   row branch, and the kept-definition mint count falls by three, 157 → 154** (the fourth is
   offset because the extra name changes what a later dequeue sees — the `DefaultStep` /
   `K2SplitStep` incomparability again; `keyed` also moves 4 → 5 under `S`).  Corpus-wide the
   split mints fall 637 → 626 (−1.7 %).
2. *Do the consumers still find a name?*  **Yes, all of them.**
   `<scratch>/keptmint-consumers.py` over the 110 gzipped traces:

   ```
   D: {'mints': 157, 'consumer': 133, 'concretised': 79, 'unified': 68, 'in-sat': 72, 'none': 16}
   S: {'mints': 154, 'consumer': 133, 'concretised': 78, 'unified': 65, 'in-sat': 73, 'none': 15}
   ```

   **`consumer` is 133 on both sides** — the documented baseline — so the three mints the
   flag removes are three that NOTHING later used as a name (`none` 16 → 15,
   `unified` 68 → 65: they were mints that `common` was going to unify away anyway, which is
   exactly the mechanism the W3 trace shows).  The design rule ("a name, never silence") is
   respected in the measurement as well as in the rule.
3. *Total mint count per configuration:* 637 (`D`) / 626 (`S`) / 626 (`B`) whole-trace split
   mints under the serialized loader, and 157 / 154 / 154 kept-definition mints.

**Which modules move** (only these; every other module is identical in all three
configurations, and the LOADED/REJECTED verdict is identical on all 110):

| module | split mints `D`→`B` | `SplitKeyed` `D`→`B` | **`SplitRow`** | `Resolution` `D`→`B` | **`ResolutionRow`** |
|---|---|---|---|---|---|
| `Ai/GridTelemetry.e` | 44 → 42 | 6 → 6 | **1** | 87 → 81 | 0 |
| `incomplete/gu05_star_join_4dim_concrete_signature.e` | 14 → 14 | 2 → 1 | 0 | 158 → **125** | **6** |
| `incomplete/np01_add_or_recompute.e` | 108 → 100 | 13 → 13 | **2** | 401 → **345** | **7** |
| `incomplete/np02_which_table_supplies_the_measure.e` | 16 → 16 | 2 → 2 | 0 | 34 → 31 | **2** |
| `incomplete/np05_label_column_no_escape.e` | 25 → 24 | 5 → 5 | **1** | 93 → 93 | 0 |
| `shouldfail/inc08_project_absent_from_join_result.e` | 3 → 3 | 0 | 0 | 6 → 3 | **2** |
| `shouldfail/mis02_join_result_annotation.e` | 3 → 3 | 0 | 0 | 6 → 3 | **2** |

**Neither branch is dead code, and both are RARE.**  `SplitRow` fires 4 times over 3 of 110
modules (against `SplitKeyed`'s 77 over 18); `ResolutionRow` fires 19 times over 5 of 110.
Both are zero in the stdlib boot (B1), as every split/resolution count there is.

### B3. Published types (`.ei`)

```
$ tracker/tools/ei-diff.sh <out> "<flags for side B>"     # 2 x 110 example modules,
                                                         # interfaces ENABLED (else nothing is written)
$ tracker/tools/ei-classify.py <out>/A <out>/B
```

Three invocations, each running BOTH sides itself, **strictly sequential and with nothing
else touching `.ei`**.  Each sweep covers all 110 `core/examples/**/*.e` and snapshots BOTH
trees — the example interfaces and the 129-module stdlib under
`core/target/scala-3.3.8/classes/modules` — **188 interfaces, 1,933 bindings, none missing
on either side** (`only-in-A -  only-in-B -` in all three).

| comparison | interfaces differing | bindings: identical / order-only / alpha-eq / **weaker** / other |
|---|---|---|
| **`D` vs `D′`** (same configuration, control) | **1** of 188 | 1930 / 2 / 1 / **0** / 0 |
| `D` vs `B` | 3 of 188 | 1909 / 21 / 2 / **0** / 1 (`Relation.lookbackJoin`) |
| `D` vs `S` | 5 of 188 | 1917 / 11 / 3 / **0** / 2 (`Relation.lookbackJoin`, `np01.inferredRestate`) |

**No signature became weaker anywhere: `concrete->polymorphic` is 0 in every comparison.**

*(A note on the control's invocation: `ei-diff.sh`'s `flagsB="${2:--Dermine.spliceGuard=true}"`
treats an EMPTY second argument as unset, so the `D` vs `D′` control's side B ran with
`-Dermine.spliceGuard=true`.  That property was REMOVED from the compiler on 2026-09-02 and
survives only in a comment — `grep -rn spliceGuard core/src/main/scala` returns one comment
line and no code — so both sides really are the default configuration and the control is
valid.)*

**Every stdlib interface that moves is churn, and this time that is a THEOREM about the
population, not just a control.**  The three interfaces in `D` vs `B` (`Relation`,
`Relation/Op`, `Relation/Predicate`) and three of the five in `D` vs `S` (`Relation`,
`Layout/Chart`, `Layout/Report`) are stdlib.  B1 already shows the stdlib boot's trace is
byte-identical `D` vs `B` under the serialized loader; under the SHIPPED parallel loader,
which is what `ei-diff.sh` uses, three runs of `D` and one of `B` give

| run | records | learn | Cancellation | CSE | Substitution | `SplitConcrete` / `SplitKeyed` / **`SplitRow`** / `Resolution` / **`ResolutionRow`** |
|---|---|---|---|---|---|---|
| `D` #1 | 60,109 | 1,647 | 425 | 796 | 421 | 0 / 0 / **0** / 0 / **0** |
| `D` #2 | 60,103 | 1,647 | 426 | 797 | 419 | 0 / 0 / **0** / 0 / **0** |
| `D` #3 | 60,110 | 1,648 | 425 | 797 | 421 | 0 / 0 / **0** / 0 / **0** |
| `B` | 60,102 | 1,646 | 426 | 796 | 419 | 0 / 0 / **0** / 0 / **0** |

— the `B` run is inside the spread of the three `D` runs, and **`splitConcrete` and
`resolution` fire ZERO times in a stdlib boot in either configuration**, so no stdlib
interface CAN be attributable to either flag.  That is the churn `ROW-CONSTRAINT-STATE.md`
and `g1-diff.sh` document ("thread timing otherwise reaches `.ei` bytes through the solver's
id-hash queue — measured on `lookbackJoin`"), and `Relation.lookbackJoin` is precisely the
binding Stage 2's own same-configuration control produced as its single `other`.

**So exactly two bindings are attributable to a flag, both in `D` vs `S`, both in
`incomplete/`:**

| interface / binding | verdict |
|---|---|
| `incomplete/TargetList.restrictTo` | **alpha-equivalent** (the classifier's own verdict: a bijection of the existentials) |
| `incomplete/np01_add_or_recompute.inferredRestate` | **7 existentials -> 6, same 8 constraints. Not weaker; equivalent, and STRICTLY more economical.**  Hand-classified below. |

**`np01.inferredRestate`, by hand.**  Write `K3 = (|unitCost, qty, unitPrice|)` and
`K4 = K3 ⊎ (|revenue|)`; rename `S`'s `so`/`so1` to match `D`'s.

```
D (7 existentials so, rs, a, b, rs1, t1, so1; 8 constraints)
    (|revenue|) <- (rs1, so1)      t  <- (K4, rs, so, a)       t1 <- (K3, rs1, so1, b)
    r  <- (K3, rs1, b)             (|margin|) <- (rs, so)      r  <- (K3, b, rs1)
    RelationalComb rel             t1 <- (K4, rs, a)

S (6 existentials t1, rs, a, so, rs1, so1; 8 constraints)
    (|revenue|) <- (rs1, so1)      t  <- (K4, rs, so, a)       t1 <- (K3, rs1, so1, a, rs)
    r  <- (K3, a, rs, rs1)         (|margin|) <- (rs, so)      r  <- (K3, rs1, a, rs)
    RelationalComb rel             t1 <- (K4, rs, a)
```

Five of the eight are identical (including each side's redundant order-only duplicate of
`r <- (K3, …)`, the one `TICKET-substitution-gap.md` §4 already saw on this corpus).  The
other three are `D`'s with `b` replaced by the pair `(a, rs)` — and **`b = a ⊎ rs` is FORCED
in `D`**: from `t1 <- (K4, rs, a)` we get `t1 = K4 ⊎ rs ⊎ a`, and from
`t1 <- (K3, rs1, so1, b)` with `(|revenue|) <- (rs1, so1)` and `K4 = K3 ⊎ (|revenue|)` we get
`t1 = K4 ⊎ b`; hence `b = rs ⊎ a`.  Substituting turns `D` into `S` and instantiating `b`
turns `S` into `D`, so the two published contexts are equivalent on `(rel, r, t)` —
a conservative extension at a name, in the direction that REMOVES the name.

**This is the opposite direction from Stage 2**, where the same binding gained an existential
(7 -> 8) under `splitKey`.  Under `splitRow` it loses one (7 -> 6), which is exactly what a
rule that replaces a mint by an existing name should do, and `np01` is again the module where
the branch fires most (B6: 2 `SplitRow`, 7 `ResolutionRow`, 108 -> 100 split mints).

### B4. Timing — one JVM at a time, machine idle

```
$ ERMINE_JAVA_OPTS="-Xmx2g -Dermine.useInterface=false [flags]" bin/ermine <instance> </dev/null
```

Three passes, drivers `stage5/b4.sh` (pass 1), `b4b.sh` (pass 2, the four configurations
INTERLEAVED per instance), `b4c.sh` (pass 3, `gu05` three runs in each configuration plus a
third point for the two big `ResStar`s).  Each timed run waits (`ps -eo comm=`, polling) until
NO other `java` process exists and is marked `[NOT IDLE]` if it gives up; the figure quoted is
the program's own `Importing module 'X' (N seconds)`, which excludes the ~12 s stdlib boot.
**Pass 1 ran while another agent's JVMs were on the machine** (one run, `ResStar9-B`, carries
the `NOT IDLE` note); passes 2 and 3 ran on an idle machine and are the numbers to read.
Pass 1 is kept in the table because the honest conclusion below is exactly that the spread
BETWEEN passes of one configuration is larger than any gap between configurations.

Module time, seconds (`p1` / `p2` / `p3`; `—` = not measured in that pass):

| instance | `D` | `S` | `R` | `B` | `B/D` (idle passes) |
|---|---|---|---|---|---|
| ResStar5 | 0.22 / 0.19 | — / 0.35 | — / 0.20 | 0.79 / 0.21 | 1.11 |
| ResStar6 | 0.51 / 0.50 | — / 0.44 | — / 0.48 | 0.47 / 0.54 | 1.08 |
| ResStar7 | 1.97 / 2.23 | — / 1.95 | — / 2.22 | 2.64 / 1.96 | 0.88 |
| ResStar8 | 14.49 / 13.22 / 13.03 | 13.08 / 14.65 / 13.59 | 13.12 / 13.53 / 13.64 | 17.55 / 12.98 / 13.31 | 1.00 |
| **ResStar9** | 106.47 / **89.75** / **85.42** | 87.39 / **84.22** / **85.91** | 89.16 / **82.75** / **87.86** | 124.54\* / **83.45** / **89.06** | 0.99 |
| RowStress10 | 0.20 / 0.19 | — | — | 0.23 / 0.18 | 0.95 |
| RowStress14 | 0.49 / 0.45 | — | — | 0.42 / 0.44 | 0.98 |
| CoStar8 | 0.06 / 0.05 | — | — | 0.06 / 0.06 | (0.01 s) |

\* the one run with the `NOT IDLE` note.

`gu05` (`core/examples/incomplete/gu05_star_join_4dim_concrete_signature.e`), three runs in
each configuration in each of two passes:

| pass | `D` | `S` | `R` | `B` |
|---|---|---|---|---|
| p1 | 1.22 / 1.27 / 1.25 | 1.25 / 1.42 / 1.24 | 1.24 / 1.31 / 1.26 | 1.23 / 1.32 / 1.24 |
| p3 (idle) | 1.29 / 1.29 / 1.65 | 1.28 / 1.27 / 1.34 | 1.23 / 1.23 / 1.33 | 1.29 / 1.37 / 1.28 |

**Did `resRow` move ResStar — resolution's own family — in either direction?  NO, in neither.**
Stated as honestly as the numbers allow:

* The largest `R/D` and `B/D` gaps on the two instances big enough to measure are
  ResStar8 `R/D` = 1.04 and ResStar9 `B/D` = 0.99 (idle passes).  `D`'s OWN spread on
  ResStar9 is 85.42 → 106.47 s across the three passes and 85.42 → 89.75 s across the two
  idle ones — i.e. **the within-configuration spread (5 % idle, 25 % overall) is larger than
  every between-configuration gap**.  Nothing here is a signal.
* The sub-second instances (ResStar5/6/7, RowStress, CoStar8) are JIT warm-up, not solver
  work: ResStar5's worst-looking ratio, `S/D` = 1.84, is 0.35 s against 0.19 s.
* The mechanism, checked rather than assumed (`stage5/b7/tr-*.tsv`): **neither branch fires
  anywhere in this family.**  Traced under `B`, ResStar5, ResStar7, RowStress14 and CoStar8
  emit `SplitRow` 0 times and `ResolutionRow` 0 times.  `ResStar`'s premises are
  `a <- (x, (|fi|))` — the left-hand side `a` never becomes concrete, so `myRow(a)` is
  `None` and the concrete-row lookup cannot even be attempted; `RowStress`/`CoStar` have no
  concrete labels at all.  The `ResStar` exponential is untouched because the flag is not
  reachable there, not because it is reachable and cheap.  (`ResStar8`/`ResStar9` were NOT
  traced — their traces would be enormous and the trace itself would dominate the time —
  but they are the same generator with two and three more `r_i` clauses, and the property
  that decides reachability, "no left-hand side is ever concrete", is a property of the
  generator, not of the size.)
* `gu05` is the interesting case, because it IS a module where `resRow` fires (6
  `ResolutionRow`, resolution conclusions 158 → 125, B6) and because it is the module that
  carried `splitKey`'s 5× win.  Its module time does not move: medians 1.29 (`D`), 1.28
  (`S`), 1.23 (`R`), 1.29 (`B`) in the idle pass, against a run-to-run spread of
  1.29–1.65 s within `D` itself.  After `splitKey` the file's solve is small enough that
  removing a third of its resolution conclusions is invisible in the wall clock.
* Cost when the flags are OFF: nothing measurable, as designed — `noConcRow` is a shared
  constant and the `lazy val` is never forced.  The `D` columns of passes 2 and 3 are the
  same class set that produced Stage 2's post-flip figures (`gu05` 1.21/1.25 s there,
  1.29 s here).

**Conclusion for the gate: PASS, with no benefit.**  Both flags are performance-neutral on
every instance measured — they are insurance, not an optimisation.

### B7. Every gate that differed from expectation, with its mechanism

Six did.  None is a blocker; two are population facts that Part C's recommendation rests on.

**B7-1. `W4` is NOT changed by `resRow` (expected: mints at a few bases under `D`, 0 under
`R`).**  Measured: the draw distribution is identical in all four configurations —
`0 ×95, 1 ×2, 3 ×3` — and so is every solved system.

Mechanism.  `K2ResStep.row` needs a carrier for the RESOLVENT row, `F \ (C ∪ D)`.  In
`W4 = {v <- ((|l1,l2,l3|)), v <- (x, (|l1|)), v <- (y, (|l2|))}` that row is `{l3}`, and
**no variable of `W4` denotes `{l3}` at the input.**  In the Lean divergence the carrier
appears only in ROUND 2: round 1 mints the resolvent `w`, cancellation gives `w <- ((|l3|))`,
and it is the NEXT round that could reuse it.  The real loop never reaches round 2 — §3f of
`TICKET-sat-termination.md` measured exactly that: at 95 of 100 bases `makeConcrete v` is
dequeued first and absorbs both premises, and at the other 5 the mint happens once and then
every variable is made concrete.  So on this seed the branch has nothing to find, in every
run order.  This is the reason the brief's expectation was wrong, and the reason the positive
control had to be **`W4c`** (`W4` plus the carrier `w <- ((|l3|))` that round 1 would create,
`stage5/W4c.json`), where `R` does fire: base 37, 3 draws and 3 `Resolution` conclusions
under `D`, **1 draw and 2 `ResolutionRow`** under `R`, same solved system with one bound
variable fewer.

**B7-2. The `SplitRow` population is tiny: 4 firings against 157 kept-definition mints.  WHY
the carrier is almost never there.**  Classified mechanically over the 110 `D` traces
(`stage5/b7-carrier.py`, which replays, per solve segment and in record order, the two things
`findConcRow` consults — `v`'s own bare concrete partition and the map of bare concrete
partitions — and asks which test fails at each kept-definition mint):

```
$ python3 stage5/b7-carrier.py stage5/b6/D/trace-*.tsv.gz
TOTALS {'mints': 157, 'compl-empty': 74, 'uncarried': 82, 'carried': 1}
```

* **0 of 157 fail the first two tests.**  `v` always has a bare concrete partition (that is
  what "kept-definition" means — `makeConcrete v` has just run and returned it to `proc`),
  and `K ⊆ C` always holds (`ensureSuperset`).  The faithfulness note of §A.3 costs nothing
  here.
* **74 of 157 (47 %) have `K = C`, so the complement is the EMPTY row.**  The carrier would
  have to be a variable already known to denote `∅` — and that is precisely the variable
  `makeEmpty` has DELETED from both queues (§A.3).  These mints are unreachable for this
  branch by construction, not by accident.  A typical one, `Ai/ClinicalTrial.e(74:31)`:
  `^305328 <- ((|siteName|))` is concrete, the kept premise is
  `^305328 <- (^305325 ^305329, siteName)`, so the group `{^305325, ^305329}` is FORCED
  empty; the compiler mints `^305330` for it and `common` cleans up two steps later
  (`step common:305328  Cancellation: ^305328 <- (,siteName)`).
* **82 of 157 (52 %) have a nonempty complement that NOTHING names.**  Example,
  `Accumulate.e(32:3)`: `C = {name, nodeId, parentId}`, `K = {nodeId, parentId}`, complement
  `{name}`, and no variable in that solve denotes `{name}`.
* **1 of 157 is carried** (`incomplete/np05_label_column_no_escape.e(128:1)`: `C` five labels,
  `K` three, complement `{displayName, orderId}`, carrier `^304444`).

So on the DEFAULT run's own trajectory the branch would have fired once; with the flag on it
fires four times, because a reuse changes the trajectory (fewer names, different dequeue
order) and creates opportunities the default run never had.  Both numbers say the same thing:
**the carrier exists only where `makeConcrete`'s own cancellation has just built it** — a
ONE-abstract definition `v <- (z, K)` becoming `z <- ((|C \ K|))`, which is exactly Stage 4's
`srsOf` / `carried_of_deleted_def`, and exactly the situation `splitKey` already covers with
the lone witness.  The concrete-row branch adds value only in the window where the witness
has been deleted but its cancellation fact survives — which is what Stage 3 said, and which
is rare in this corpus.

**B7-3. `NE6` moved under `S` (expected: a control seed, unchanged).**  Measured: SOLVED
100/100 as before, but **one fresh id fewer at 17 of the 100 bases** (3, 16, 17, 20, 24, 26,
27, 29, 34, 37, 40, 47, 48, 49, 55, 73, 91), with the SAME final substitution on every base
and `bound` falling 5 → 4 on exactly those bases.  Traced at base 3 (`stage5/b7/ne6-b3-*`),
the two runs are identical for 17 records and then diverge at the same premise:

```
D  ... step concrete  ^free3 <- (,l2 l3 l4 l1)          <- makeConcrete v0
       step concrete  Cancellation: ^free7 <- (,l2 l3)  <- the srs fact for v4
       step learn     ^free3 <- (^free5 ^free6,l1 l4)
       learn new  SplitConcrete: ^ambiguous(free)11 <- (^free5 ^free6,)   <- MINT
       learn new  SplitConcrete: ^free3 <- (^ambiguous(free)11,l1 l4)
       ... step common:7  Cancellation: ^ambiguous(free)11 <- (,l2 l3)    <- common unifies 11 with v4

S  ... same first 17 records ...
       learn new  SplitRow: ^free7 <- (^free5 ^free6,)                    <- REUSE v4
       step learn  SplitRow: ^free7 <- (^free5 ^free6,)
       learn new  CommonSubexpression: ^free3 <- (^free7,l1 l4)
```

`C = {l1,l2,l3,l4}`, `K = {l1,l4}`, `C \ K = {l2,l3}`, carrier `^free7` — and `^free7`'s row
is a `Cancellation` fact `makeConcrete ^free3` derived from the one-abstract input
`v0 <- (v4, (|l1,l4|))`, i.e. `srsOf` in the compiler.  `records` 60 → 52, `drawn` 3 → 2,
`bound` 5 → 4.  **The same mechanism as `W3`: the flag does in every order what `common` does
in some.**  This is a deviation from the brief's expectation only in that `NE6` was listed as
a control; it is the third independent confirmation that the branch is doing what Stage 4
says.

**B7-4. The two flags are NOT additive on published types: `D` vs `S` has TWO attributable
bindings, `D` vs `B` has NONE.**  Expected: `B` ⊇ `S`'s differences.  Measured (§B3):
`incomplete/np01.inferredRestate` publishes a 6-existential context under `S` and D's
7-existential one under `B`, byte for byte; `incomplete/TargetList.restrictTo` likewise
returns to `D`'s form under `B`.  Mechanism: `resRow` removes 56 of `np01`'s resolution
conclusions (B6: 401 → 345), and those conclusions are among the inputs the split rule later
dequeues, so under `B` the `SplitRow` firings happen at different premises and the name that
`S` eliminates is re-introduced.  The incomparability that Stage 2 saw between the shipped
and keyed split rules holds between the two new branches as well; "more reuse" is not
monotone in the published context.  Nothing here is weaker — `0 weaker` in all three
comparisons — but it means the `.ei` gate must be run in the configuration that would ship,
not inferred from one flag at a time.

**B7-5. B4: `resRow` did not move `ResStar` in either direction, and the reason is that it
cannot run there.**  Expected (the brief): "`resRow` touches the rule that carried the
original `gu05` win and the ResStar exponential: report both directions honestly."  Measured:
every ratio inside the run-to-run spread (§B4).  Mechanism, traced under `B`
(`stage5/b7/tr-*.tsv`): `ResStar5` and `ResStar7` emit **`ResolutionRow` 0 times** (110 and
905 ordinary `Resolution` conclusions), `RowStress14` and `CoStar8` emit no resolution
conclusions at all.  `ResStar`'s premises are `a <- (x, (|fi|))`: the left-hand side `a` never
becomes concrete, so `myRow(a) = None` and the lookup cannot be attempted.  The exponential
is untouched because the branch is unreachable there — not because it is reachable and cheap.
Where it IS reachable, `gu05`, it removes a third of the resolution conclusions (158 → 125
whole-trace `learn` records, `ResolutionRow` 6) and the module time still does not move.

**B7-6. `splitRow` removes THREE kept-definition mints while firing FOUR times, and `resRow`
moves `SplitKeyed` 77 → 76.**  Expected: one fewer mint per firing.  Mechanism: the same
incomparability as B7-4 — a reuse changes what the next dequeue sees, so one of the four
firings is offset by a mint that the default run did not make (and `SplitKeyed` gains one,
4 → 5, under `S`).  `resRow` changes no split mint at all in the `R` column (637 whole-trace,
157 kept-definition — identical to `D`), but it does move the KEYED counts: `SplitKeyed`
77 → **76** and kept-definition keyed reuses 4 → **3** in the `R` column alone, so the same
77 → 76 in `B` is `resRow`'s knock-on and not a split-rule effect.  This is `KeyedRow`'s
`K2SplitStep` / `DefaultStep` incomparability on real code, as Stage 2's B7-3 was.

*(A seventh, of method rather than result, unchanged from Stage 2: the population figures of
B6 come from the SERIALIZED loader, which `keptdef-mints.py` needs to segment by `solve`; the
shipped parallel loader derives more.  All of B6's numbers are therefore a lower bound, and
B4's timings — which need no segmentation — were taken under the default parallel loader.)*

---

## Part C — the path to default

### C.1 The gate table, four configurations

`D` = default, `S` = `-Dermine.splitRow=true`, `R` = `-Dermine.resRow=true`, `B` = both.
A dash means the gate was not run in that configuration (with the reason in the row).

| gate | expected | `D` | `S` | `R` | `B` | verdict |
|---|---|---|---|---|---|---|
| `sbt -batch core/compile` | clean | ok, 11 s | — one class set for every column — | | | PASS |
| `core/test` (904) | 903/904, known `disjunction sound` starvation | **903/904** | — | — | **903/904** | PASS |
| B0 `W2` 100 bases | solved, unchanged | 100 SOLVED, draws 0 ×100 | = `D` | = `D` | = `D` | PASS |
| B0 `H2` 100 bases | solved, unchanged | 100 SOLVED, 2 ×38 / 3 ×62 | = `D` | = `D` | = `D` | PASS |
| B0 `NE6` 100 bases | solved, unchanged | 100 SOLVED | 100 SOLVED, **one draw fewer at 17 bases**, same bindings | = `D` | = `S` | PASS (B7-3) |
| **B0 `W3` 100 bases** | mints at ~55/100 under `D`, **0 under `S`** | 100 SOLVED, draws 0 ×45 **1 ×55** | 100 SOLVED, **draws 0 ×100** | = `D` | = `S` | PASS, non-vacuous |
| B0 `W3` base 3 trace | `SplitRow` must fire | `SplitConcrete` mint, then `common` | **`SplitRow: ^free4 <- (^free5 ^free6,)`** | = `D` | = `S` | PASS |
| B0 `W4` 100 bases | mints at a few bases under `D`, **0 under `R`** | draws 0 ×95, 1 ×2, 3 ×3 | = `D` | **= `D` (unchanged)** | = `D` | DEVIATION (B7-1) |
| **B0 `W4c` control** (scratch seed) | `ResolutionRow` must fire | base 37: 3 draws, 3 `Resolution` | — | **1 draw, 2 `ResolutionRow`** | — | PASS, non-vacuous |
| B0 crule `W` (unsat) 100 bases | still rejected | 100 REJECTED | 100 | 100 | 100, byte-identical bar the banner | PASS |
| B0 crule `gseed` (unsat) 100 bases | still rejected | 100 REJECTED | 100 | 100 | 100, byte-identical bar the banner | PASS |
| B0 KeepMint control | mints on both (no carrier exists) | 16 mint / 0 keyed / 0 row | — | — | **16 / 0 / 0**, branch tallies identical | PASS |
| B1 stdlib boot | 129 modules | 129, 11.39–11.49 s | — | — | 129, 11.23–11.43 s | PASS |
| B1 boot firings | (population fact) | `SplitRow` 0 / `ResolutionRow` 0 | — | — | **0 / 0**, traces byte-identical | PASS (flags invisible there) |
| B2 examples corpus (66) | 23 LOADED / 43 REJECTED, 0 differ | 23/43 | 23/43, **0 of 66 differ** | — | 23/43, **0 of 66 differ** | PASS |
| B2 `shouldfail/` (40) | 40/40 rejected | 40/40 | 40/40 | — | 40/40 | PASS |
| B2 `incomplete/` (34) | 18/16, 0 differ | 18/16 | 18/16, **0 of 34 differ** | — | 18/16, **0 of 34 differ** | PASS |
| B3 published types (188 interfaces, 1,933 bindings) | **no signature weaker** | control `D` vs `D′`: 1 interface, 3 bindings churn | `D` vs `S`: 5 interfaces, **0 weaker**, 2 attributable | — | `D` vs `B`: 3 interfaces, **0 weaker**, **0 attributable** | PASS (B7-4) |
| B4 ResStar 5–9 module time | unchanged | see §B4 | 0.87–1.84× | 0.96–1.05× | 0.88–1.11× | PASS (all inside `D`'s own spread, which is 5 % idle / 25 % overall on ResStar9) |
| B4 RowStress 10/14, CoStar8 | unchanged | see §B4 | — | — | 0.95× / 0.98× / (0.05 s → 0.06 s) | PASS |
| B4 `gu05`, three runs each | unchanged (`resRow` fires 6× here) | 1.29 / 1.29 / 1.65 s | 1.28 / 1.27 / 1.34 | 1.23 / 1.23 / 1.33 | 1.29 / 1.37 / 1.28 | PASS |
| B5 `repl-smoke` | 4/4 | 4/4, 35 checks | — | — | 4/4, 35 checks | PASS |
| B5 `lsp-smoke` | 98/98 | PASS 98 | — | — | PASS 98 | PASS |
| B6 firings on real code (110 modules) | non-zero, or say so | 0 / 0 | **`SplitRow` 4 in 3 modules** | **`ResolutionRow` 19 in 5 modules** | 4 and 19 | PASS, non-vacuous but RARE |
| B6 whole-trace split mints | fewer | 637 | **626** | 637 | 626 | PASS |
| B6 kept-definition mints | fewer | 157 in 27 modules | **154** | 157 | 154 | PASS |
| B6 kept-mint consumers | still 133 | 133 of 157 | **133 of 154** | — | — | PASS (design rule holds) |
| B6 `Resolution` conclusions | fewer under `R` | 1,748 | 1,696 | **1,696** | **1,644** | PASS |
| B6 verdicts over 110 modules | unchanged | — | 0 differ | 0 differ | 0 differ | PASS |
| Part D `lake build Rowpartition` | green | **818 jobs** | | | | PASS |
| Part D `lake env lean Audit.lean` | 0 non-standard | **2,255 audited, 0 non-standard** | | | | PASS |

### C.2 The exact unapplied one-line diffs, and the ADOPTED comment each would need

Neither is applied.  Each is one character in one line, plus a comment paragraph.

**`splitRow`** — `core/src/main/scala/com/clarifi/reporting/ermine/Constraints.scala`, line 891:

```diff
-    val splitRow: Boolean = System.getProperty("ermine.splitRow", "false") == "true"
+    val splitRow: Boolean = System.getProperty("ermine.splitRow", "true") == "true"
```

and lines 889–890 would change from

```
     * DEFAULT OFF pending the adoption gates in `tracker/satterm/KEYED-ROW-STAGE5.md`.
     * `-Dermine.splitRow=true` enables it. */
```

to an ADOPTED paragraph in the shape the other five flags use:

```
     * ADOPTED <date>: DEFAULT ON.  `-Dermine.splitRow=false` restores the previous
     * behaviour exactly.  The evidence (`tracker/satterm/KEYED-ROW-STAGE5.md`):
     *   - proved not a semantic change (`KeyedRow.concRow_reuse_sat`,
     *     `K2RowApp.models_iff` -- the model set does not move) and, for the SPLIT
     *     fragment, MINT-BOUNDED under the loop's own deletions on every satisfiable input
     *     in every run order (`mintsBoundedOnSat_splitFragment`), which is exactly the
     *     statement Stage 3 proved FALSE for the keyed guard alone
     *     (`KeyedLoop.not_TerminatesOnSatKeyedLoop`, witness `W3`); and the rule AS WRITTEN
     *     here is a step of that calculus (`KeyedRowScala.scalaRowSplit_step`, for the spec
     *     the lookup really meets, `MyRowSpec`/`ConcRowSpec`, on a modelled system);
     *   - `W3` in the real solver: the re-mint happens at 55 of 100 id bases with the flag
     *     off and at NONE with it on, same solved system -- the rule does in every order
     *     what `common` does in some;
     *   - 66-file example corpus and 34-file incompleteness corpus: 0 files differ,
     *     verdicts identical (23/43 and 18/16), `shouldfail/` 40/40 still rejected;
     *   - 188 published interfaces / 1,933 bindings: NO signature weaker; the one binding
     *     attributable to this flag, `incomplete/np01.inferredRestate`, LOSES a forced
     *     existential (7 -> 6) and is equivalent to the shipped one;
     *   - `core/test` 903/904 with the flag on, the one failure being the pre-existing
     *     `Constraints.disjunction sound` generator; `repl-smoke` 4/4, `lsp-smoke` 98/98;
     *   - population, stated honestly: it is INSURANCE, not a speed-up.  It fires 4 times
     *     over 3 of the 110 example modules and at 17 of 100 `NE6` bases, taking corpus
     *     split mints 637 -> 626 and kept-definition mints 157 -> 154 with all 133
     *     consumers still finding a name; no timing moved (ResStar 5-9, RowStress 10/14,
     *     CoStar8 and `gu05` all inside their own run-to-run spread). */
```

**`resRow`** — same file, line 917:

```diff
-    val resRow: Boolean = System.getProperty("ermine.resRow", "false") == "true"
+    val resRow: Boolean = System.getProperty("ermine.resRow", "true") == "true"
```

with lines 915–916 replaced by:

```
     * ADOPTED <date>: DEFAULT ON.  `-Dermine.resRow=false` restores the previous
     * behaviour exactly.  The evidence (`tracker/satterm/KEYED-ROW-STAGE5.md`):
     *   - proved not a semantic change (`K2ResStep.row_models_iff`; the two conclusions are
     *     the ones `resGuard`'s reuse already emits, with an existing name in place of the
     *     fresh one) and every mint that survives the widened guard is a shipped guarded
     *     mint (`K2ResStep.mint_toGRes`); the rule AS WRITTEN is a step of the calculus
     *     (`KeyedRowScala.scalaRowRes_step`);
     *   - it is the flag that completes the theorem: with BOTH branches the whole
     *     loop-extended calculus mints boundedly on every satisfiable input in every order
     *     (`mintsBoundedOnSatKeyed2Star`, bound `|allVars G0| + hmeas L rho G0`), and
     *     `keyed2_star_vs_shipped_res` says the same statement is FALSE with `resolution`
     *     left as shipped (`not_MintsBoundedOnSatKeyed2`, the split-free witness `W4`);
     *   - 66-file and 34-file corpora: 0 files differ, verdicts identical, `shouldfail/`
     *     40/40 -- including `inc08_project_absent_from_join_result.e` and
     *     `mis02_join_result_annotation.e`, the two modules where this branch actually
     *     fires, which stay REJECTED with the same message (the refutation-safety check);
     *   - 188 published interfaces: NO signature weaker and NO binding attributable to this
     *     flag at all;
     *   - `core/test` 903/904 with the flag on; `repl-smoke` 4/4, `lsp-smoke` 98/98;
     *   - population: 19 firings over 5 of the 110 example modules, taking resolution's
     *     conclusions 1,748 -> 1,696 (and 1,644 with `splitRow` as well); no timing moved,
     *     including the `ResStar` family, which cannot reach the branch because the
     *     resolution premise's left-hand side never becomes concrete there. */
```

`ROW-CONSTRAINT-STATE.md` would gain an ADOPTED entry in the shape `resGuard`'s,
`labelCheckEarly`'s and `splitKey`'s have; `tracker/lean/Rowpartition/KeyedRow.lean`'s and
`KeyedRowScala.lean`'s closing "the flags are DEFAULT OFF" lines and this report's header
would be updated; `TICKET-sat-termination.md` §3g would gain a post-flip subsection in the
shape of §3d.

### C.3 What would be re-run after a flip, and what `toString` prints

The same gates against the NEW default with no properties, which is how `cut`, `labelCheck`,
`resGuard`, `labelCheckEarly` and `splitKey` were each confirmed:

* `sbt -batch core/compile`, then `sbt -batch -J-Xmx3g core/test` (expect 903/904);
* `tracker/tools/corpus-run.sh` and `--incomplete`, against a `-Dermine.splitRow=false`
  (resp. `-Dermine.resRow=false`) side — the flag inverts, so the RESTORE side now needs the
  property — with `corpus-verdicts.py` and the normalised whole-output diff;
* `tracker/tools/ei-diff.sh <out> "-Dermine.splitRow=false -Dermine.resRow=false"`, classified
  with `ei-classify.py`, **with a same-configuration control sweep** (1 of 188 interfaces
  churns between two runs of one build, and 3 more do under the parallel loader);
* `tracker/tools/repl-smoke.sh`, `tracker/tools/lsp-smoke.sh`;
* `tracker/repro/satterm/sweep.sh` for `W2`, `H2`, `NE6`, `seeds/W3.json`, `seeds/W4.json` and
  `tracker/repro/crule/sweep.sh` for `W`, `gseed`; `tracker/repro/keepmint/run.sh`;
* `tracker/tools/keptdef-sweep.sh` + `keptdef-mints.py` (the population, and the check that
  the 133 consumers still find a name);
* the `gu05` and ResStar timings, one JVM at a time.

`GenRules.toString` needs NO edit — it already prints a marker per flag that is on — and the
banner every `tracker/repro/*/run.sh` prints becomes:

```
cut+label-early+resguard+splitkey+splitrow+resrow    (both adopted, no properties)
cut+label-early+resguard+splitkey+resrow             (-Dermine.splitRow=false)
cut+label-early+resguard+splitkey+splitrow           (-Dermine.resRow=false)
cut+label-early+resguard+splitkey                    (both restored: today's default)
```

### C.4 The honest scope

* **What becomes true for the first time, with BOTH flags on.**
  `mintsBoundedOnSatKeyed2Star`: from every satisfiable input, in every run order, the
  loop-extended calculus `K2StarStep` — the keyed-2 additive rules plus the faithful
  concretisation `concretizeSrs`, which is `makeConcrete`/`destructiveSub` with the `srs`
  cancellation kept — enlarges the vocabulary only boundedly, with the explicit bound
  `|allVars G₀| + hmeas (labelsOf G₀) rho G₀`.  `keyed2_star_vs_shipped_res` is the contrast
  in one line: the same statement with `resolution` as shipped is FALSE.
* **What ONE flag buys.**  `splitRow` alone buys the SPLIT fragment
  (`mintsBoundedOnSat_splitFragment`) and kills Stage 3's witness `W3` (`W3_not_mintable`,
  `W3_row_reuse`); it does NOT bound the calculus, because `W4` mints for ever through
  resolution with no split step at all (`not_MintsBoundedOnSatKeyed2`).  `resRow` alone buys
  NO bound — there is no theorem in the development about resolution's fragment on its own —
  only soundness and conservativity (`K2ResStep.row_models_iff`, `mint_toGRes`).  **The
  theorem is a property of the PAIR.**
* **What does not become true.**
  1. **Bounded minting is not termination.**  The bound is on the VOCABULARY, not on run
     length; the any-order relation permits add/delete cycles, and `K2LoopStep.allVars_cases`
     is what licenses reading the bound as "only a mint enlarges it".
  2. **The loop's single pass and `common` are unmodelled.**  `incorporateAll` dequeues in a
     particular order and `common`/`unify`/`dedup` are not steps of any relation here.  Every
     seed measurement in Part B where the flag-off side still reaches the same answer reaches
     it through `common` — that is a property of the real loop that no theorem states.
  3. **Ill-typed input is untouched.**  `hmeas` needs a model; guarded resolution still
     diverges on `ResGuardDiverge.gSeed`, `DefaultDiverge.not_CRule` still exhibits an
     unsatisfiable system the input check does not refute, and the label check plus
     `RHS.merge` remain the only defences.  B0's `W`/`gseed` measure exactly this: byte-
     identical in all four configurations.
  4. **The Scala lookup is a LOWER bound on the Lean's membership**, and the adequacy proof
     says so: `MyRowSpec`/`ConcRowSpec` keep ONE row per variable and ask `k ⊆ C` explicitly,
     an emptied (`makeEmpty`) or unified-away carrier is invisible, and the MINT side of
     adequacy needs a model (`concRow_none_uncarried`, `conc_unique_of_model`,
     `conc_key_subset_of_model`).  On unsatisfiable input the branches can only decline a
     reuse, never take a wrong one — which is why nothing in B0's refutation gates moves.
  5. **The population is SMALL.**  4 `SplitRow` firings in 3 of 110 example modules, 19
     `ResolutionRow` in 5, zero of either in a 129-module stdlib boot.  The corpus and `.ei`
     zeros are therefore much weaker evidence than Stage 2's were (77 `SplitKeyed` firings in
     18 modules): most of the corpus never reaches either branch.  §B7-2 traces WHY — the
     carrier `w <- ((|C \ K|))` exists essentially only where a cancellation has just made it,
     which is the keyed witness's own situation.
  6. **It is a behaviour change, not a refactor.**  Ids shift, one `incomplete/` published
     type changes (equivalently, and in the simplifying direction), and both branches emit an
     EXISTING name where the shipped rule emits a fresh one.

### C.5 Recommendation, per flag

**`-Dermine.splitRow`: ADOPT WITH CAVEATS.**

1. Every adoption gate this project uses is green, each with a positive control first: 903/904
   `core/test`; 0 of 66 and 0 of 34 corpus files differ with `shouldfail/` 40/40; 188
   interfaces with **no signature weaker** and the single attributable binding STRICTLY more
   economical; `repl-smoke` 4/4; `lsp-smoke` 98/98; 129 stdlib modules with a byte-identical
   trace; 300/300 satisfiable seeds solved, 200/200 unsatisfiable seeds rejected.
2. It is proved to be pure entailment (`concRow_reuse_sat`, `K2RowApp.models_iff`) and the
   shipped rule as written is a step of the calculus that has the bound
   (`scalaRowSplit_step`).  It closes, for the split, exactly the hole Stage 3 opened.
3. It is measurably non-vacuous where it matters: `W3`'s re-mint disappears at all 55 bases,
   `NE6` loses a mint at 17 of 100, and the corpus loses 11 split mints.
4. The caveats: **it is rare on real code** (4 firings / 110 modules), so the corpus zeros are
   mostly the branch not running; it **buys no speed** (every B4 figure is inside the noise);
   it is a behaviour change (ids shift, `np01`'s published context changes shape); and the
   bound it buys is for the split fragment only — `W4` still mints for ever without `resRow`.

**`-Dermine.resRow`: ADOPT WITH CAVEATS — and only together with `splitRow`.**

1. The same gates are green in `R` and in `B`, including the one that matters most for a
   resolution change: the two `shouldfail/` modules where the branch actually fires stay
   REJECTED with the identical message, and the unsatisfiable seeds are byte-identical.
2. **It is the flag that turns the fragment result into the theorem**
   (`mintsBoundedOnSatKeyed2Star`, `keyed2_star_vs_shipped_res`).  Adopted alone it buys no
   bound at all; adopted with `splitRow` it buys the whole loop-extended statement.  That is
   the reason to treat the two as one decision.
3. It removes real derivation on real code — 52 resolution conclusions on `np01`, 33 on
   `gu05`, 1,748 -> 1,696 corpus-wide — and **no published binding is attributable to it**.
4. The caveats: its seed control had to be **synthesised** (`W4c`); the shipped seed `W4` never
   reaches the branch, because in the real loop `makeConcrete`'s order absorbs the premises
   before a carrier for the resolvent row exists (§B7-1).  So the positive evidence that it
   fires in the loop is the 19 corpus firings and one constructed seed, not one of the
   tracked witnesses.  And, as with `splitRow`, no timing moved — including the `ResStar`
   family, which cannot reach the branch at all (§B7-6).

**If only one is adopted, adopt `splitRow`** — it has a theorem of its own and the tracked
witness `W3`.  **If the goal is the termination statement, adopt both.**  Nothing was flipped
and nothing was committed; the decision is the user's.

---

## Housekeeping and final state

```
$ find core/examples -name '*.ei' -delete                       # the sweeps' interfaces
$ find core/target/scala-3.3.8/classes/modules -name '*.ei' -delete
$ bin/ermine core/examples/syntaxExample.e </dev/null           # ONE run, no properties
$ find core/examples -name '*.ei' -delete                       # the .ei that run writes
```

* `core/examples`: **0** `.ei` files.
* stdlib interfaces: 138 before (9 of them stale, left by older builds), deleted, and
  **129 regenerated by one DEFAULT run** — one per loaded module — so the next default run
  does not read a flag-on artifact.
* `java` processes left running: **0**.
* `cd tracker/lean && lake build Rowpartition` → **`Build completed successfully (818 jobs)`**
  (817 before this stage); `lake env lean Audit.lean` → **`Rowpartition theorems audited:
  2255; declarations using a non-standard axiom: 0`** (2216 before).  Re-confirmed after all
  the sweeps, from the same tree.  `Rowpartition/CutSearch.lean` is still out of the root
  import list; no `require` was added and `lake exe cache get` was never run.
* `git status`: the modified/untracked set of the table below and nothing else.  **No
  default flipped, nothing committed.**

---

## Files touched

| file | what | state |
|---|---|---|
| `core/src/main/scala/com/clarifi/reporting/ermine/Constraints.scala` | `SplitRow` / `ResolutionRow` tags; `GenRules.splitRow` / `GenRules.resRow`, **both default OFF**; `splitConcrete`'s fourth branch and its `concRow` parameter; `resolution`'s third branch and the same parameter; `learnPartitions`' lazy `concRows` / `findConcRow` and the shared `noConcRow`; the correspondence comments at both rules and at the lookup | modified, **+215 / −13**, LF preserved, NOT committed |
| `tracker/lean/Rowpartition/KeyedRowScala.lean` | the transcription lemmas, 616 lines, **33 theorems** | new, NOT committed |
| `tracker/lean/Rowpartition.lean` | the root import and its module note | modified |
| `tracker/lean/README.md` | the `KeyedRowScala` row, the module-map entry, the recounted headline (35 files, 1,849 source theorems) and the audit/build figures | modified |
| `tracker/satterm/KEYED-ROW-STAGE5.md` | this report | new |
| `tracker/TICKET-sat-termination.md` | §3g, the §4 item-0 update, the §5 file rows | modified |
| `tracker/ROW-CONSTRAINT-STATE.md` | the Stage 5 paragraph after Stage 4's | modified |
| `tracker/tools/keptdef-mints.py` | the `SplitRow` reuse bucket and the whole-trace branch tallies | modified, **+36 / −1** |
| `tracker/repro/satterm/seeds/W3.json`, `seeds/W4.json` | the two `json:` seeds, now tracked next to `W2`/`H2`/`NE6` | new |

Everything else lives in the scratch directory `/home/dmitry/.claude/jobs/880c725d/tmp/stage5/`
(drivers `b0.sh`, `b1b5.sh`, `b2.sh`, `b3.sh`, `b4.sh`, `b4b.sh`, `b4c.sh`, `b6.sh`,
`b7-runs.sh`, `b0k.sh`, `housekeep.sh`; analysers `agg.py`, `b7-carrier.py`,
`keptmint-consumers.py`; raw outputs under `b0/`, `b1/`, `b2/`, `b3/`, `b4/`, `b6/`, `b7/`),
including the `W4c` control seed, which the brief did not authorise adding to the repository.

**No default was flipped.  Nothing was committed.**  The uncommitted Stage 4 work already in
the tree (the Lean modules and their tracker entries) is untouched by this stage except where
the table above says so.
