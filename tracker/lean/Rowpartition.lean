/-
# Rowpartition -- library root

Formalisation of Ermine's single row constraint, PARTITION (`a <- (b, c, (|Foo|))`).

* `Rowpartition.Basic`      -- syntax, semantics, label decomposition
* `Rowpartition.Rules`      -- the inference rules of the solver, audited
* `Rowpartition.Canonical`  -- the non-generative canonicalisation calculus
* `Rowpartition.Divergence` -- the generative CSE rule and its non-termination
* `Rowpartition.Cut`        -- cutting CSE's minting branch: what survives, what does not
* `Rowpartition.SplitNecessary` -- `splitConcrete` is load-bearing: the `nongen` regression
* `Rowpartition.CutConcrete` -- the minting branch introduces no concrete label
* `Rowpartition.Compare`    -- clean calculus vs. the five-line cut, side by side
* `Rowpartition.Fragment`   -- the definitional fragment and a decision procedure
* `Rowpartition.Berthomieu` -- Berthomieu's `=_L`, and an expressiveness separation
* `Rowpartition.Pottier`    -- the bridge to Pottier's LICS 2003 constraint language
* `Rowpartition.LabelClass` -- label signature classes: per-label reasoning at schema scale
* `Rowpartition.LabelProp`  -- per-label unit propagation: the refutation rule, proved safe
NOT IMPORTED: `Rowpartition.CutSearch`.  It is a bounded exhaustive counterexample hunt
by `decide`, and elaborating it exhausts memory on this machine -- `lake build
Rowpartition.CutSearch` is killed by the OOM killer (`Lean exited with code 137`) at 15 GB,
both with default parallelism and with `LEAN_NUM_THREADS=1`.  Importing it here would make
`lake build` and `Audit.lean` unrunnable, so it stays out and its 125 theorems stay OUTSIDE
the axiom audit.  README.md records this; do not "fix" it by adding the import without
first getting the module to build.

* `Rowpartition.ResGuard`   -- guarding `resolution` with the resolvent lookup: it is sound
* `Rowpartition.ResGuardTerm`    -- ...and it terminates on every SATISFIABLE system
* `Rowpartition.ResGuardDiverge` -- ...and not in general: an unsatisfiable divergent seed
* `Rowpartition.Saturate`   -- the saturation preserves satisfiability: the licence to run
                               the per-label refutation on the saturated set (ticket 8a)
* `Rowpartition.Splice`     -- `Subst.reduce`'s second case: sound, exactly conservative for
                               one splice, and a counterexample where the residual is WEAKER
                               than the input (ticket 8b)
* `Rowpartition.LabelAlgo`  -- the SCALA `checkLabel` fixpoint, not just the rule: every bit
                               it writes is `Forced`, so every clash it reports is genuine
* `Rowpartition.SpliceGuard` -- the licence for the 8b REPAIR: guarding the splice on the
                               three conditions of `splice_entails_iff` makes it conservative,
                               and repairs the `DroppedPartition` counterexample
* `Rowpartition.NameLoss`   -- the substitution gap (2026-09-02): `makeConcrete` deletes the
                               name `splitConcrete` minted, and under the cut the later fold
                               needs it; the race, on the three-constraint instance
* `Rowpartition.NameLossClosed` -- ...concretise first, and no non-generative rule ever
                               recovers the fact: the solver's saturated set is closed
* `Rowpartition.NameLossDerivation` -- ...fold first, and `SatSteps` reach `t <- (|c, d|)`
* `Rowpartition.DefaultDiverge` -- the SHIPPED rule set (`cut` + guarded resolution) as a step
                               relation, and the "complementary defences" claim refuted: an
                               unsatisfiable eight-constraint input on which it diverges and
                               which the per-label check does not refute (`not_CRule`)
* `Rowpartition.KeepInert`  -- can `destructiveSub`'s kept definitions mint?  Guarded
                               resolution: never.  `splitConcrete`: yes, when the kept
                               definition carries a concrete part -- and that mint was already
                               enabled on the input
* `Rowpartition.DefaultTerm` -- does the shipped rule set terminate on every SATISFIABLE input?
                               The question stated (`TerminatesOnSat`) and the structural chain
                               proved: mint-free runs are bounded, every mint strictly lowers the
                               model rank, resolution branching is bounded; split branching per
                               parent is the one open gap
* `Rowpartition.DefaultSatDiverge` -- ...and the answer is NO: `not_TerminatesOnSat`.  The
                               satisfiable two-constraint `SatDiverge.W2` admits productive runs
                               of every length (an empty-row variable recurs in every group);
                               a saturating run escapes because names travel with their groups
                               (`subst_names_travel`), and the real loop unifies the link instead
* `Rowpartition.KeyedSplit` -- ...and the repair: key `splitConcrete`'s guard on (lhs, concrete
                               part), as resolution's already is, and the whole calculus
                               TERMINATES on every satisfiable input (`terminatesOnSatKeyed`,
                               `keyed_vs_syntactic`), by `ResGuardTerm`'s measure unchanged
* `Rowpartition.KeyedSplitScala` -- ...and the SHIPPED `splitConcrete` is that rule: both of
                               its reverse lookups give the same answers on the system minus
                               the dequeued premise as on the whole system (`resolved_erase_iff`,
                               `named_erase_iff`), and every branch it takes is a `KDefaultStep`
                               (`scalaSplit_step`, `scalaSplitOf_step`)
* `Rowpartition.KeyedLoop`  -- ...and it does NOT survive the LOOP layer.  `KLoopStep` adds
                               `makeConcrete`/`destructiveSub` (`NameLoss.concretizeKeep`,
                               which DELETES and REWRITES) to the additive `KDefaultStep`,
                               and a three-constraint satisfiable system admits productive
                               runs of every length, minting without bound
                               (`not_TerminatesOnSatKeyedLoop`, `W3_mints_unbounded`): a key
                               witness dies either as a deleted definition
                               (`notMem_lone_lhs`) or, and this is the engine, as an
                               `absorbC`-rewritten mention (`notMem_lone_mention`)
* `Rowpartition.KeyedRow`   -- ...and Stage 4: the CONCRETE-ROW reuse.  `splitConcrete`'s
                               keyed lookup widened to `Carried` (a lone witness `v <- (z, K)`
                               OR a pair of concrete definitions `v <- ((|C|))`,
                               `z <- ((|C \ K|))`), and `makeConcrete` made faithful to the
                               Scala's `srs` re-expression (`concretizeSrs`).  `Carried` is
                               PRESERVED by the deletion (`carried_concretizeSrs`), so the
                               budget survives and minting is BOUNDED on satisfiable input
                               (`mintsBoundedOnSatKeyed2Star`, `mintsBoundedOnSat_splitFragment`);
                               with guarded `resolution` left as shipped it is NOT
                               (`not_MintsBoundedOnSatKeyed2`, the split-free witness `W4`)
* `Rowpartition.KeyedRowScala` -- ...and Stage 5: the SHIPPED `splitConcrete` and
                               `resolution` WITH the concrete-row branch (`-Dermine.splitRow`,
                               `-Dermine.resRow`, adopted as defaults later that day) are steps of that
                               relation.  The Scala's lookup is a single `Option[Fields]` for
                               `v`'s own row plus an explicit `k ⊆ C`, not `∃ C, mk v ∅ C ∈ G`;
                               `MyRowSpec` / `ConcRowSpec` are what it really meets, and
                               `scalaRowSplit_step` / `scalaRowRes_step` prove adequacy for
                               THAT, on a MODELLED system -- which is where the difference
                               costs something (`concRow_none_uncarried`)
* `Rowpartition.KeyedEmpty` -- ...and Stage 6: the SECOND deleting step.  `makeEmpty` added
                               faithfully (`makeEmptyD`; `v <- ()` goes to the SubstEnv, NOT
                               back into the system).  `Carried` is NOT an invariant of it
                               (`carried_not_invariant`) and Stage 4's potential strictly
                               INCREASES (`hmeas_increases`); the missing piece is a carrier
                               of the EMPTY row.  (T2): the Stage 4 bound survives verbatim
                               under the order hypothesis that each `makeEmpty` leaves one
                               behind (`mintsBoundedOnSat_emptyPersisting`), and
                               unconditionally if `v <- ()` is retained
                               (`mintsBoundedOnSatKeyed3E`).  `G7_mints` is the 74-of-157
                               population as a theorem
* `Rowpartition.KeyedEmptyScala` -- ...and Stage 7, the repair IMPLEMENTED: the Scala rules
                               with the EMPTY-ROW branch (`-Dermine.emptyRow`, default off)
                               transcribed.  The lookup reads the retained facts as well as
                               the queues (`EmptyRowSpec`, a `ConcRowSpec` at `C \ K = ∅`);
                               what the branch EMITS is the propagation, and
                               `emptyReuse_compose` proves that is the Lean reuse composed
                               with its forced `makeEmptyE` step, so every firing is TWO
                               steps of `K3ELoopStep` (`splitEmpty_two_steps`,
                               `resEmpty_two_steps`) and the Stage 4 bound applies
                               (`scalaEmptySplit_bounded`, `scalaEmptyRes_bounded`)
* `Rowpartition.Sanity`     -- a standalone toolchain smoke test
* `Rowpartition.Loop`       -- L1 of `tracker/LOOP-MODEL-PLAN.md`: `Constraints.incorporateAll`
                               itself as an executable FUNCTION -- the real queue order (the
                               priority-search key `(rhs.hashCode, lhs.hashCode)` and the
                               reverse-topological priority), the `SubstEnv`, the id supply,
                               every dispatch branch and rule under the shipped flags, with an
                               explicit fuel and no `partial`.  The `looptrace` executable
                               prints the compiler's `-Dermine.rowTrace` TSV, and
                               `tracker/tools/looptrace-diff.py` diffs the two: 240/240
                               comparisons agree (`tracker/loopmodel/L1-MODEL.md`)
-/
import Rowpartition.Basic
import Rowpartition.Rules
import Rowpartition.Canonical
import Rowpartition.Divergence
import Rowpartition.Cut
import Rowpartition.SplitNecessary
import Rowpartition.CutConcrete
import Rowpartition.Compare
import Rowpartition.Fragment
import Rowpartition.Berthomieu
import Rowpartition.Pottier
import Rowpartition.LabelClass
import Rowpartition.Sanity
import Rowpartition.LabelProp
import Rowpartition.ResGuard
import Rowpartition.ResGuardTerm
import Rowpartition.ResGuardDiverge
import Rowpartition.Saturate
import Rowpartition.Splice
import Rowpartition.LabelAlgo
import Rowpartition.SpliceGuard
import Rowpartition.DerivedColumn
import Rowpartition.NameLoss
import Rowpartition.NameLossClosed
import Rowpartition.NameLossDerivation
import Rowpartition.DefaultDiverge
import Rowpartition.KeepInert
import Rowpartition.DefaultTerm
import Rowpartition.DefaultSatDiverge
import Rowpartition.KeyedSplit
import Rowpartition.KeyedSplitScala
import Rowpartition.KeyedLoop
import Rowpartition.KeyedRow
import Rowpartition.KeyedRowScala
import Rowpartition.KeyedEmpty
import Rowpartition.KeyedEmptyScala
import Rowpartition.Loop
import Rowpartition.Loop.Wf
import Rowpartition.Loop.Refine
import Rowpartition.Loop.RefineConcrete
import Rowpartition.Loop.RefineLearn
import Rowpartition.Loop.Order
import Rowpartition.Loop.Strict
import Rowpartition.Loop.StrictStep
import Rowpartition.Loop.StrictBound
import Rowpartition.Loop.Carried
import Rowpartition.Loop.Hygiene
import Rowpartition.Loop.Factor
import Rowpartition.Loop.Draws
import Rowpartition.Loop.Residual
import Rowpartition.Loop.Refuted
import Rowpartition.Loop.Supply
import Rowpartition.Loop.Mints
import Rowpartition.Loop.Pump
import Rowpartition.Loop.Dequeue
import Rowpartition.Loop.Fragment
