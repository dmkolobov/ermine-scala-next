package com.clarifi.reporting.ermine

import scalaparsers.{Parser => _, ParseState => _, _}

object Relocatable {
  def preserveLoc[A <: Located, B<:Located:Relocatable](sub: Map[A,B]): PartialFunction[A,B] = {
    case x if sub.contains(x) => setLoc(sub(x),x.loc)
  }
}
