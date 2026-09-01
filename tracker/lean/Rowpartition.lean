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
