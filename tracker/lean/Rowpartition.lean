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
* `Rowpartition.Sanity`     -- a standalone toolchain smoke test
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
