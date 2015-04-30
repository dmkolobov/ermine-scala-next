package com.clarifi.reporting

import org.scalacheck.Gen
import org.scalacheck.Gen._

import com.clarifi.reporting.PrimT._
import com.clarifi.reporting.AggFunc._

/**
 * Generators for the different kinds of functions for the aggregate
 * relation.
 */
object AggFuncGens {

  private def genCount: Gen[AggFunc] = const(Count)
  private def genOpAgg(s: String, ty: Type, fs: (Op => AggFunc)*) =
    oneOf(fs) map (_ apply Op.ColumnValue(s, ty))

  /**
   * Creates an aggregation function based on the given column name. Note
   * that only certain types are supported for these aggregate functions,
   * so if a type is given that is not supported an exception is thrown.
   */
  def genAggFuncAny(t: Type, s: String): Gen[AggFunc] = {
    t match {
      case IntT(_) =>
        oneOf(genCount, genOpAgg(s, t, Sum, Avg, Min, Max))
      case DoubleT(_) =>
        genOpAgg(s, t, Sum, Avg, Min, Max, Stddev, Variance)
      case _ => sys.error("Cannot perform an aggregation over type: " + t)
    }
  }
}
