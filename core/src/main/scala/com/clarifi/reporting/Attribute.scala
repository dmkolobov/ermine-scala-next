package com.clarifi.reporting

import scalaz._
import scalaz.Equal._

final case class Attribute(name: String, t: PrimT) {
  def tuple: (String, PrimT) = (name, t)
  def toHeader: Header = Map(name -> t)
  def toOp: Op = Op.ColumnValue(name, t)
}

object Attribute {
  implicit val attribEq: Equal[Attribute] = equalA
}


