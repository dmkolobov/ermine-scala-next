package com.clarifi.reporting.ermine

/** A possibly qualified name with its associated fixity, associativity and precedence information
  *
  * @author EAK
  */

sealed abstract class Name {
  def string: String
  def fixity: Fixity
  def qualifier: Option[String]
  def local: Local
}

/** A local name as it occurs in the source file */
case class Local(string: String, fixity: Fixity = Idfix) extends Name {
  override def toString = string
  def qualifier = None
  override def equals(other: Any) = other match {
    case Local(ostring, ofixity) => string == ostring && fixity.con == ofixity.con
    case _ => false
  }
  override def hashCode = (1, string, fixity.con).hashCode
  def local = this
  def global(module: String) = Global(module, string, fixity)
}

/** A global name fully resolved to the module it was defined in */
case class Global(module: String, string: String, fixity: Fixity = Idfix) extends Name {
  override def toString = fixity match {
    case Idfix => module + "." + string
    case _     => module + ".(" + string + ")"
  }
  def qualifier = Some(module)
  override def equals(other: Any) = other match {
    case Global(omodule, ostring, ofixity) => module == omodule && string == ostring && fixity.con == ofixity.con
    case _ => false
  }
  override def hashCode = (2, module, string, fixity.con).hashCode
  def local = Local(string, fixity)
  def localized(affix: Option[String], rename: Option[Local]) = {
    val newString = rename.map(_.string).getOrElse(string)
    Local(newString + affix.map(m => '_' + m).getOrElse(""), fixity)
  }
}

// useful for printf-debugging the parser,
case class NameOrdering() extends Ordering[Name] {
  def compare(n: Name, m:Name) = {
    (n,m) match {
      case (g: Global, g2: Global) => (g.module + g.string) compare (g2.module + g2.string)
      case _ => n.string compare m.string
    }
  }
}

object Name {
  def lib(s: String, f: Fixity = Idfix): Name = Global("Lib", s, f)
  def prelude(s: String, f: Fixity = Idfix): Name = Global("Prelude", s, f)
  implicit lazy val ord = NameOrdering()
  lazy val globalOrd = NameOrdering().asInstanceOf[Ordering[Global]]
  lazy val localOrd = NameOrdering().asInstanceOf[Ordering[Local]]
}

