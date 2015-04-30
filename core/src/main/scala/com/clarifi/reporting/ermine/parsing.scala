package com.clarifi.reporting
package ermine

import scalaz.Free.{ Return, suspend }
import scalaz.Scalaz._
import scala.collection.immutable.List
import scalaparsers.{Assoc, AssocL}
import scalaparsers.Document.{ text }
import java.lang.Character._

import com.clarifi.reporting.util.YMDTriple.ymdPivotTimeZone

package object parsing extends scalaparsers.Parsing[parsing.ErParseState] {
  def dist[A](xs: List[Localized[A]]): Localized[List[A]] = Localized(xs.map(_.extract), xs.flatMap(_.names), xs.traverse_[Parser](_.unbind))

  def leftLet      = left(keyword("let"),"let", rawKeyword("in"), "in")
  def leftCase     = left(keyword("case"),"case", rawKeyword("of"), "of")

  def isOpChar(c: Char) =
    existsIn(opChars, c) ||
    (!existsIn(nonopChars, c) && punctClasses(c.getType.asInstanceOf[Byte]))

  def opChar: Parser[Char] = satisfy(isOpChar(_))
  def keyword(s: String): Parser[Unit] = token((letter >> identTail).slice.filter(_ == s).skip.attempt(s))
  def rawKeyword(s: String): Parser[Unit] = (stillOnside >> rawLetter >> rawIdentTail).slice.filter(_ == s).skip.attempt("raw " + s)

  // keywords which cannot be used as identifiers
  val unusedKeywords   = Set("subtype")
  val otherKeywords    = Set("exists", "constructor", "do", "forall", "phi", "φ", "prj#", "rho", "ρ", "constraint", "Γ", "table", "where", "infixr", "infixl", "infix", "postfix", "prefix", "case", "let", "in", "of", "esac", "subtype", "hole", "Eval")
  val startingKeywords = Set("private", "abstract", "field", "data", "foreign", "type", "import", "export", "database","class","instance")
  val keywords = startingKeywords ++ otherKeywords ++ unusedKeywords
  val field      = keyword("φ") | keyword("phi")
  val constraint = keyword("Γ") | keyword("constraint")
  val rhoS       = keyword("ρ") | keyword("rho")

  private val punctClasses = Set(
    START_PUNCTUATION, END_PUNCTUATION, DASH_PUNCTUATION,
    INITIAL_QUOTE_PUNCTUATION, FINAL_QUOTE_PUNCTUATION,
    MATH_SYMBOL, CURRENCY_SYMBOL, MODIFIER_SYMBOL, OTHER_SYMBOL
  )

  /** token parser that consumes a key operator */
  def keyOp(s: String): Parser[Unit] = token((opChar.skipSome).slice.filter(_ == s).skip.attempt("'" + s + "'"))

  // key operators which cannot be used by users
  val keyOps = Set(":", "=","..","->","=>","~","<-") // "!" handled specially
  val star   = keyOp("*") // NB: we permit star to be bound by users, so it isn't in keyOps

  val doubleArrow = keyOp("=>")
  val ellipsis    = keyOp("..")
  val colon       = keyOp(":")
  val dot         = keyOp(".")
  val backslash   = keyOp("\\")
  val bang        = keyOp("!")
  val comma       = token(ch(',')) as ","
  def prec: Parser[Int] = nat.filter(_ <= 10L).map(_.toInt) scope "precedence between 0 and 10"
  def underscore: Parser[Unit] = token((ch('_') >> notFollowedBy(tailChar)) attempt "underscore")

  // kinds
  def prefix (n: String, p: Int = 10) = Local(n, Prefix(p))
  def postfix(n: String, p: Int = 10) = Local(n, Postfix(p))
  def infix  (n: String, p: Int = 9, a: Assoc = AssocL) = Local(n, Infix(p,a))
}
