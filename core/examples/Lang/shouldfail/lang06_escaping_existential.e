module Lang.Shouldfail.Lang06 where

{- NEGATIVE: projecting the seed out of an existential.

   `Data.Nu`'s `data Nu f = forall s. Unfold (s -> f s) s` hides the seed type. A
   function that returns it would have to mention `s` in its result type, and `s` is
   bound by the constructor, so it escapes. `observe` is the only elimination the type
   permits.

   The same shape guards `Field.EField`, `Layout.Report.Fulcrum.Dynamic.PivotColumn`
   and every `ChartSeries`; this is the one-line demonstration of why.

   EXPECTED:

     error: skolem variables escape:
     Type would have been: Nu f -> !s
-}

import Prelude
import Data.Nu as Nu

leakSeed (Unfold_Nu f x) = x
