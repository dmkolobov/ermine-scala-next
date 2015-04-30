module Layout.Report.Atomic where
-- ^ Typically, you only need concern yourself with `data Atomic`.

import Layout.Format
import Native.Function
import Native.NonEmpty
import Prim using type PrimExpr#

-- | A datum to be displayed.
data Atomic a = Atomic (Format a) a

-- | Box the data of an Atomic for Scala consumption.
atomic# : Atomic a -> Atomic# a
atomic# (Atomic fmt val) = funcall2# consAtomic# fmt (toPrimExprNel val)

foreign
  -- | Foreign variant of `Atomic'.
  data "com.clarifi.reporting.writers.Atomic" Atomic# (a: *)
  -- | Existential foreign `Atomic' variant.
  data "com.clarifi.reporting.writers.Atomic" EAtomic#
  subtype AtomicExistentially# : Atomic# a -> EAtomic#
  function "com.clarifi.reporting.writers.Writer" "toPrimExprNel"
      toPrimExprNel : a -> NonEmpty# PrimExpr#

private foreign
  value "com.clarifi.reporting.writers.Atomic$" "MODULE$"
      consAtomic# : Function2 (Format a) (NonEmpty# PrimExpr#) (Atomic# a)
