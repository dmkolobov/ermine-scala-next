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
* `Loop.Conformance` -- the JVM's hash and iteration-order answers as build-time `#guard`s
* `Loop.Bridge`      -- a loop partition IS a `Rowpartition.Constraint`: the conversion both
                        ways, `champSort` proved a permutation, and `LPart.eqv` proved to be
                        equality of the constraints

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
import Rowpartition.Loop.Conformance
import Rowpartition.Loop.Bridge
