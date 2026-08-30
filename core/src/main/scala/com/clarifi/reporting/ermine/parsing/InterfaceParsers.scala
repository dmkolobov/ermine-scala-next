package com.clarifi.reporting.ermine
package parsing

import scalaparsers.{++, Located, Pos}
import scalaparsers.Diagnostic.raise

import TypeParsers._

object InterfaceParsers {
  private val logger = org.apache.log4j.Logger.getLogger(this.getClass)

  private def interfaceSig: Parser[(Name, Type)] =
    (TermNameParsers.name[Local]{case x => List(x)} << keyOp(":")) ++ qtyp

  /** The (name, type) pairs of an interface file, as data.  The G1
    * differential oracle reads interfaces back through the language's own
    * parser (tracker/LSP-ROADMAP.md, Stage 1 item 1.1). */
  def interfaceSigs: Parser[List[(Name, Type)]] = laidout("interface", interfaceSig)

  def interfaceFile: Parser[PartialFunction[TermVar, TermVar]] = {
    def remap(tys: Map[Name, Type])(v: TermVar): Option[TermVar] = {
      v.name flatMap {
        n =>
          logger.trace("Remap name: " + n)
          tys.get(n).map(v as _)
      }
    }

    (laidout("interface", interfaceSig) << eof).map(sigs => Function.unlift(remap(sigs.toMap)))
  }
}
