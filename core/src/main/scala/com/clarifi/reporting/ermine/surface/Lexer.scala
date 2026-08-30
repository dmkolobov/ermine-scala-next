package com.clarifi.reporting.ermine.surface

/** The operator lexer, ported byte-for-byte from the fused pipeline for
  * the resolution-free parser (tracker/LSP-ROADMAP.md item 2.2).
  *
  * Grammar (NameParsers.op): opStart, then opChar*, then optionally
  * '_' tailChar+ — the `_Module` affix is PART OF THE LEXEME (`++_L` is
  * one token).  Three guards follow: `|` must not precede `]`; key
  * operators are not user operators; three-or-more dashes are a comment.
  * One committed quirk is preserved deliberately: when '_' follows the
  * operator chars but no tail character follows it, the fused parser has
  * committed into the affix group and the WHOLE operator fails
  * (skipOptional cannot rewind consumed input) — this lexer answers None
  * there too, not the shorter lexeme.
  *
  * Character classes verbatim from scalaparsers.ParsingUtil:342-343 and
  * parsing/package.scala isOpChar.
  */
object Lexer {

  private val opCharSet: Set[Char] = ":!#$%&*+./<=>?@\\^|-~'`".toSet
  private val nonopCharSet: Set[Char] = "()[]{};,\"".toSet
  private val punctClasses: Set[Int] = Set(
    Character.START_PUNCTUATION, Character.END_PUNCTUATION,
    Character.DASH_PUNCTUATION, Character.INITIAL_QUOTE_PUNCTUATION,
    Character.FINAL_QUOTE_PUNCTUATION, Character.MATH_SYMBOL,
    Character.CURRENCY_SYMBOL, Character.MODIFIER_SYMBOL,
    Character.OTHER_SYMBOL).map(_.toInt)

  def isOpChar(c: Char): Boolean =
    opCharSet(c) || (!nonopCharSet(c) && punctClasses(c.getType))

  /** ParsingUtil.tailChar. */
  def isTailChar(c: Char): Boolean =
    c.isLetter || c.isDigit || c == '_' || c == '#' || c == '\''

  val keyOps: Set[String] = Set(":", "=", "..", "->", "=>", "~", "<-")

  /** The three op-start disciplines (TermNameParsers.scala:196-210):
    * data constructor operators are exactly the ':'-lexemes, pattern-var
    * operators exclude them — a lexical split, kept lexical. */
  sealed abstract class OpFlavor { def starts(c: Char): Boolean }
  case object TermOp   extends OpFlavor { def starts(c: Char) = isOpChar(c) }
  case object ConOp    extends OpFlavor { def starts(c: Char) = c == ':' }
  case object PatVarOp extends OpFlavor { def starts(c: Char) = c != ':' && isOpChar(c) }

  final case class Lexed(lexeme: String, end: Int)

  /** Lex one operator at `offset`; no whitespace handling (token
    * plumbing is the caller's job). */
  def op(input: String, offset: Int, flavor: OpFlavor = TermOp): Option[Lexed] = {
    val n = input.length
    if (offset >= n || !flavor.starts(input.charAt(offset))) None
    else {
      var i = offset + 1
      while (i < n && isOpChar(input.charAt(i))) i += 1
      var dead = false
      if (i < n && input.charAt(i) == '_') {
        if (i + 1 < n && isTailChar(input.charAt(i + 1))) {
          i += 2
          while (i < n && isTailChar(input.charAt(i))) i += 1
        } else dead = true  // committed into the affix, no tail: whole op fails
      }
      if (dead) None
      else {
        val lex = input.substring(offset, i)
        if (lex == "|" && i < n && input.charAt(i) == ']') None
        else if (keyOps(lex)) None
        else if (lex.length > 2 && lex.forall(_ == '-')) None
        else Some(Lexed(lex, i))
      }
    }
  }
}
