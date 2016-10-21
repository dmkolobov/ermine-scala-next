package com.clarifi.reporting.ermine.syntax

import com.clarifi.reporting.ermine._
import scala.collection.immutable.List

import scalaz.Monad
import scalaparsers.{Located, Pos}

case class Module(
  loc: Pos,
  name: String,
  importExports: List[ImportExportStatement] = List(),
  fields: List[FieldStatement] = List(),
  tables: List[TableStatement] = List(),
  foreignData: List[ForeignDataStatement] = List(),
  types: List[TypeDef] = List(),
  foreigns: List[ForeignTermDef] = List(),
  implicits: List[ImplicitBinding] = List(), // top level binding group
  explicits: List[ExplicitBinding] = List(),
  privateTerms : Set[TermVar] = Set(),
  privateTypes : Set[TypeVar] = Set()
) extends Located {
  def subTerm(m: PartialFunction[TermVar, TermVar]): Module = {
    this copy (implicits = Term.subTerm(m, this.implicits), explicits = Term.subTerm(m, this.explicits))
  }
}
