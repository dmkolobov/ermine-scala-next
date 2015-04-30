package com.clarifi.reporting
package relational

import scalaz.Equal
import scalaz.std.string._
import scalaz.syntax.equal._

import PrimT.{ StringT, DateT }

sealed trait SM {
  def header: Header
}
case class LookupSM(field: String, attr: String) extends SM {
  def header = Map("issueId" -> StringT(0, false), field -> StringT(0, false))
}
case class HistoricalSM(field: String, attr: String) extends SM {
  def header = Map("issueId" -> StringT(0, false), field -> StringT(0, false), "date" -> DateT(false))
}

object SM {
  implicit def smEq: Equal[SM] = new Equal[SM] {
    def equal(sm1: SM, sm2: SM) = (sm1, sm2) match {
      case (LookupSM(f1, a1), LookupSM(f2, a2)) => f1 === f2 && a1 === a2
      case (HistoricalSM(f1, a1), HistoricalSM(f2, a2)) => f1 === f2 && a1 === a2
      case _ => false
    }
  }
}
