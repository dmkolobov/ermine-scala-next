/-
# The loop model: `Constraints.incorporateAll` as an executable Lean FUNCTION

Stage L1 of `tracker/LOOP-MODEL-PLAN.md`.  Everything in `Rowpartition/` above this file is
about a RELATION -- the rule set applied in any order.  The compiler applies the rules in ONE
order, with a priority-search queue, a mutable substitution environment, an id supply and four
deleting steps, and the measured behaviour lives in that difference.  This subdirectory is the
loop itself, as a total function, with an executable that prints the compiler's own
`-Dermine.rowTrace` TSV so the two can be diffed record for record.

* `Loop.Hash`        -- `MurmurHash3`, `Hashing.improve`, `String.hashCode`: the JVM functions
                        the QUEUE ORDER is a function of
* `Loop.SSet`        -- `scala.collection.immutable.Set` WITH its iteration order: `SetN` in
                        insertion order up to four, CHAMP order above
* `Loop.State`       -- `RHS`, `Partition`, `Inference`, `SubstEnv`, `GenRules`, and
                        `Partition.toString`
* `Loop.Queue`       -- `Q`: `TypeVarGraph`, `reverseTopSort`, `insert`, `pop`, `findRHS`
* `Loop.Rules`       -- `selfSubstitution`, `splitConcrete`, `cancellation`, `resolution`,
                        `substitution`, `commonSubexpression`, `disjunction`
* `Loop.Step`        -- `learnPartitions`, `makeEmpty`, `makeConcrete`, `destructiveSub`,
                        `unify`, and `step`/`run` with an explicit fuel
* `Loop.Trace`       -- the TSV record formats of `RowTrace`
* `Loop.Json`        -- `Exists.apply`, `RHS.build`, `PQueue.build`, `labelClash`
* `Loop.Seed`        -- the `json:` seed format and the whole of `Subst.solve` around the loop
* `Loop.Replay`      -- (L2) reading a compiler `-Dermine.rowTrace` file back: its `sin` /
                        `slbl` / `svar` / `scon` records reconstruct every solve's input, so
                        the model can be run on the corpus rather than on hand seeds
* `Loop.Conformance` -- the JVM's hash and iteration-order answers as build-time `#guard`s
* `Loop.Bridge`      -- a loop partition IS a `Rowpartition.Constraint`: the conversion both
                        ways, `champSort` proved a permutation, and `LPart.eqv` proved to be
                        equality of the constraints
* `Loop.RejectTerm`  -- (S1b) the REJECTION path: what the draw budget guarantees at the
                        SHIPPED defaults (S2 layer (i) ON), and the whole of `Subst.solve`
                        around the loop -- `budgetSP_terminates`, `solveSeedP_terminates`
* `Loop.EnvBound`    -- (S1b) the `SubstEnv` a refused solve can leave: at most one entry per
                        dequeue, each of ONE node (`envTermSize_eq_len`), the escape walk over
                        it linear (`escWalk_length_le`), the exponential blow-up that H1 needs
                        exhibited for the GENERAL `instantiateType` (`chain_blowup`), and no
                        cyclic binding (`stepP_noAliasChain`, `noAliasChain_no_cycle`)

`Rowpartition/Loop/Main.lean` is the `looptrace` executable and is deliberately NOT imported
here: it is the `lean_exe` root, and keeping it out lets `lake build Rowpartition` stay a
library build.

The differential result, and what is and is not modelled, are in
`tracker/loopmodel/L1-MODEL.md`.
-/
import Rowpartition.Loop.Hash
import Rowpartition.Loop.SSet
import Rowpartition.Loop.State
import Rowpartition.Loop.Queue
import Rowpartition.Loop.Rules
import Rowpartition.Loop.Step
import Rowpartition.Loop.Trace
import Rowpartition.Loop.Json
import Rowpartition.Loop.Seed
import Rowpartition.Loop.Replay
import Rowpartition.Loop.Conformance
import Rowpartition.Loop.Bridge
import Rowpartition.Loop.RejectTerm
import Rowpartition.Loop.EnvBound
