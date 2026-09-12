module SigEntail where

import Field
import Primitive

-- SIG-3 (tracker/SIG-ENTAIL-PLAN.md): the editor half of the signature-entailment
-- check.  `TolerantCheck` calls `typeCheckExplicitBinding` on its own path, so a
-- declared signature whose ROW context is too weak for its body must show the same
-- diagnostic in the editor as `bin/ermine` reports -- at the term that generated the
-- obligation, with "declared at" on the signature.
--
-- `tooWeak` is the defect (`healthOpt` of core/examples/shouldfail/sig01): the
-- signature promises every row and the body reads one column.  `honest` is the
-- control: the same body with the constraint the body needs, and it must draw NO
-- diagnostic, or the check would be reported on every signed binding.
field health : Int

tooWeak : forall r. {..r} -> Int
tooWeak r = r ! health

honest : forall r t. r <- ((|health|), t) => {..r} -> Int
honest r = r ! health
